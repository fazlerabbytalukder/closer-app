import 'dart:io';

import 'package:closer_app/core/data/firebase/send_queue.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late File image;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('send_queue_test');
    image = await File('${tmp.path}/render.png').writeAsBytes([1, 2, 3]);
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<SendQueue> newQueue() async => SendQueue(prefs: await SharedPreferences.getInstance(), dir: () async => tmp);

  SendRequest note(String text) => SendRequest(
    type: ItemType.note,
    imagePath: image.path,
    text: text,
    noteStyle: const NoteStyle(bg: 'pink', font: 'rounded'),
    secret: true,
  );

  test('keeps sends in order with their own image copy', () async {
    final q = await newQueue();
    await q.add(itemId: 'a', pairId: 'p', uid: 'me', request: note('one'));
    await q.add(itemId: 'b', pairId: 'p', uid: 'me', request: note('two'));
    await image.delete(); // the screen's temp render can disappear

    final items = await q.items();
    expect(items.map((e) => e.itemId), ['a', 'b']);
    expect(File(items.first.file).existsSync(), isTrue);
    expect(items.first.request.imagePath, items.first.file);
  });

  test('survives an app restart with every field intact', () async {
    await (await newQueue()).add(itemId: 'a', pairId: 'p', uid: 'me', request: note('hello'));

    final e = (await (await newQueue()).items()).single;
    expect(e.pairId, 'p');
    expect(e.uid, 'me');
    expect(e.request.type, ItemType.note);
    expect(e.request.text, 'hello');
    expect(e.request.noteStyle?.bg, 'pink');
    expect(e.request.secret, isTrue);
    expect(e.request.saveToMemories, isTrue);
  });

  test('counts only the signed-in user and updates on change', () async {
    final q = await newQueue();
    await q.add(itemId: 'a', pairId: 'p', uid: 'me', request: note('x'));
    await q.add(itemId: 'b', pairId: 'p', uid: 'someone-else', request: note('y'));

    final counts = <int>[];
    final sub = q.watchCount('me').listen(counts.add);
    await pumpEventQueue();
    await q.remove('a');
    await pumpEventQueue();
    await sub.cancel();

    expect(counts, [1, 0]);
    expect(await q.watchCount(null).first, 0);
  });

  test('remove deletes the image copy', () async {
    final q = await newQueue();
    final e = await q.add(itemId: 'a', pairId: 'p', uid: 'me', request: note('x'));
    await q.remove('a');
    expect(await q.items(), isEmpty);
    expect(File(e.file).existsSync(), isFalse);
  });

  test('skips an unreadable saved entry instead of failing', () async {
    SharedPreferences.setMockInitialValues({
      'send_queue_v1': ['not json'],
    });
    expect(await (await newQueue()).items(), isEmpty);
  });
}
