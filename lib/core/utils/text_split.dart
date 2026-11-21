/// تقسيم النص لجمل مناسبة للأداء الصوتي.
class TextSplit {
  TextSplit._();

  static final _sentenceEnd = RegExp(r'(?<=[\.\!\?؟…!])\s+|\n+');

  /// يقسم النص لجمل، ويدمج الجمل القصيرة جداً، ويقسم الطويلة جداً عند الفواصل.
  static List<String> sentences(String text, {int maxChars = 420, int minChars = 12}) {
    final raw = text
        .replaceAll('\r', '')
        .split(_sentenceEnd)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final merged = <String>[];
    for (final s in raw) {
      if (merged.isNotEmpty && merged.last.length < minChars) {
        merged[merged.length - 1] = '${merged.last} $s';
      } else {
        merged.add(s);
      }
    }

    final out = <String>[];
    for (final s in merged) {
      if (s.length <= maxChars) {
        out.add(s);
        continue;
      }
      var buf = StringBuffer();
      for (final part in s.split(RegExp(r'(?<=[،,؛;])\s*'))) {
        if (buf.length + part.length > maxChars && buf.isNotEmpty) {
          out.add(buf.toString().trim());
          buf = StringBuffer();
        }
        buf.write('$part ');
      }
      if (buf.isNotEmpty) out.add(buf.toString().trim());
    }
    return out;
  }
}
