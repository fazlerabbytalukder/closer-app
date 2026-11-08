import 'dart:convert';

/// Repairs UTF-8 text that was decoded as Windows-1252 and re-encoded
/// ("ðŸ’•" → "💕"). An early build saved some demo data this way.
///
/// Returns the repaired string, or null when [s] is not mojibake (contains
/// real non-Latin characters, or the bytes aren't valid UTF-8, e.g. a
/// genuine "Fiancé").
String? repairMojibake(String s) {
  var suspicious = false;
  final bytes = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      bytes.add(r);
    } else if (r <= 0xFF) {
      bytes.add(r);
      suspicious = true;
    } else if (_cp1252[r] case final b?) {
      bytes.add(b);
      suspicious = true;
    } else {
      return null; // A real character outside cp1252: not mojibake.
    }
  }
  if (!suspicious) return null;
  try {
    final fixed = utf8.decode(bytes);
    return fixed == s ? null : fixed;
  } on FormatException {
    return null;
  }
}

/// Walks decoded JSON and repairs strings in place. Returns how many strings
/// were changed.
int repairJsonTree(Object? node) {
  var changed = 0;
  if (node is Map) {
    for (final key in node.keys.toList()) {
      final v = node[key];
      if (v is String) {
        final f = repairMojibake(v);
        if (f != null) {
          node[key] = f;
          changed++;
        }
      } else {
        changed += repairJsonTree(v);
      }
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      final v = node[i];
      if (v is String) {
        final f = repairMojibake(v);
        if (f != null) {
          node[i] = f;
          changed++;
        }
      } else {
        changed += repairJsonTree(v);
      }
    }
  }
  return changed;
}

/// Unicode → byte for the Windows-1252 range 0x80–0x9F.
const _cp1252 = <int, int>{
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};
