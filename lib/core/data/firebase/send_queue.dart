// Offline send queue: sends made without a connection wait here (on disk,
// so they survive the app being killed) and go out when the phone is back
// online. The server's sendItem is idempotent on itemId, so a retry after a
// lost response can't create a duplicate.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:closer_app/core/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One send waiting for a connection. [file] is the queue's own copy of the
/// image, so it outlives the temp file the send screen rendered.
@immutable
class QueuedSend {
  const QueuedSend({
    required this.itemId,
    required this.pairId,
    required this.uid,
    required this.file,
    required this.request,
    required this.queuedAt,
  });

  factory QueuedSend.fromJson(Map<String, dynamic> j) => QueuedSend(
    itemId: j['itemId'] as String,
    pairId: j['pairId'] as String,
    uid: j['uid'] as String,
    file: j['file'] as String,
    queuedAt: DateTime.fromMillisecondsSinceEpoch(j['queuedAt'] as int),
    request: SendRequest(
      type: ItemType.values.byName(j['type'] as String),
      imagePath: j['file'] as String,
      caption: j['caption'] as String? ?? '',
      text: j['text'] as String?,
      noteStyle: j['noteStyle'] == null ? null : NoteStyle.fromJson((j['noteStyle'] as Map).cast<String, dynamic>()),
      geo: j['geo'] == null ? null : GeoTag.fromJson((j['geo'] as Map).cast<String, dynamic>()),
      saveToMemories: j['saveToMemories'] as bool? ?? true,
      secret: j['secret'] as bool? ?? false,
    ),
  );

  final String itemId;
  final String pairId;
  final String uid;
  final String file;
  final SendRequest request;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'pairId': pairId,
    'uid': uid,
    'file': file,
    'queuedAt': queuedAt.millisecondsSinceEpoch,
    'type': request.type.name,
    'caption': request.caption,
    'text': request.text,
    'noteStyle': request.noteStyle?.toJson(),
    'geo': request.geo?.toJson(),
    'saveToMemories': request.saveToMemories,
    'secret': request.secret,
  };
}

/// Persistent FIFO of [QueuedSend]s.
class SendQueue {
  SendQueue({SharedPreferences? prefs, Future<Directory> Function()? dir})
    : _prefsOverride = prefs,
      _dir = dir ?? getApplicationSupportDirectory;

  static const _key = 'send_queue_v1';

  final SharedPreferences? _prefsOverride;
  final Future<Directory> Function() _dir;
  final _changes = StreamController<int>.broadcast();
  List<QueuedSend>? _items;

  Future<SharedPreferences> get _prefs {
    final p = _prefsOverride;
    return p != null ? Future.value(p) : SharedPreferences.getInstance();
  }

  Future<List<QueuedSend>> _load() async {
    if (_items != null) return _items!;
    final raw = (await _prefs).getStringList(_key) ?? const [];
    final items = <QueuedSend>[];
    for (final s in raw) {
      try {
        items.add(QueuedSend.fromJson((jsonDecode(s) as Map).cast<String, dynamic>()));
      } on Object catch (e) {
        debugPrint('SendQueue: dropping unreadable entry: $e');
      }
    }
    return _items = items;
  }

  Future<void> _save() async {
    final items = _items ?? const <QueuedSend>[];
    await (await _prefs).setStringList(_key, [for (final i in items) jsonEncode(i.toJson())]);
    _changes.add(items.length);
  }

  /// Waiting sends, oldest first.
  Future<List<QueuedSend>> items() async => List.unmodifiable(await _load());

  /// Number of waiting sends for [uid]: now, then on every change.
  Stream<int> watchCount(String? uid) {
    int count(List<QueuedSend> l) => uid == null ? 0 : l.where((e) => e.uid == uid).length;
    StreamSubscription<int>? changes;
    late final StreamController<int> out;
    out = StreamController<int>(
      onListen: () async {
        changes = _changes.stream.listen((_) => out.add(count(_items ?? const [])));
        final items = await _load();
        if (!out.isClosed) out.add(count(items));
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  /// Copies the image into the queue's folder and adds the send.
  Future<QueuedSend> add({
    required String itemId,
    required String pairId,
    required String uid,
    required SendRequest request,
  }) async {
    final folder = Directory('${(await _dir()).path}/send_queue');
    await folder.create(recursive: true);
    final dot = request.imagePath.lastIndexOf('.');
    final ext = dot > request.imagePath.lastIndexOf('/') && dot >= 0 ? request.imagePath.substring(dot) : '.jpg';
    final copy = await File(request.imagePath).copy('${folder.path}/$itemId$ext');
    final entry = QueuedSend(
      itemId: itemId,
      pairId: pairId,
      uid: uid,
      file: copy.path,
      // Retries upload the queue's copy, never the screen's temp render.
      request: SendRequest(
        type: request.type,
        imagePath: copy.path,
        caption: request.caption,
        text: request.text,
        noteStyle: request.noteStyle,
        geo: request.geo,
        saveToMemories: request.saveToMemories,
        secret: request.secret,
      ),
      queuedAt: DateTime.now(),
    );
    (await _load()).add(entry);
    await _save();
    return entry;
  }

  /// Drops [itemId] (sent, or failed for good) and deletes its image copy.
  Future<void> remove(String itemId) async {
    final items = await _load();
    final gone = items.where((e) => e.itemId == itemId).toList();
    if (gone.isEmpty) return;
    items.removeWhere((e) => e.itemId == itemId);
    await _save();
    for (final e in gone) {
      try {
        await File(e.file).delete();
      } on Object catch (_) {}
    }
  }
}
