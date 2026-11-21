import '../../data/gemini/style_builder.dart';
import '../../data/projects/models.dart';

/// ملف ترجمة SRT متزامن مع الجمل (تحطه على CapCut أو Premiere على طول).
class Subtitles {
  Subtitles._();

  static String _ts(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  /// [starts]: بداية كل جملة في الملف قبل القص، [offset]: اللي اتقص من الأول، [total]: طول الملف قبل القص.
  static String srt(Project p, Map<String, Duration> starts, {Duration offset = Duration.zero, required Duration total, bool speakerNames = true}) {
    final segs = p.segments.where((s) => s.text.trim().isNotEmpty && starts.containsKey(s.id)).toList();
    final b = StringBuffer();
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      final start = starts[s.id]! - offset;
      var end = i + 1 < segs.length ? starts[segs[i + 1].id]! - offset - const Duration(milliseconds: 80) : total - offset;
      if (end <= start) end = start + const Duration(milliseconds: 800);
      var text = PerformanceTags.stripAll(s.text);
      if (speakerNames && s.speakerId != null) {
        final sp = p.speakers.where((x) => x.id == s.speakerId).firstOrNull;
        if (sp != null) text = '${sp.name}: $text';
      }
      b
        ..writeln(i + 1)
        ..writeln('${_ts(start)} --> ${_ts(end)}')
        ..writeln(_wrap(text))
        ..writeln();
    }
    return b.toString();
  }

  /// سطرين بحد أقصى ~42 حرف للسطر (المعيار المريح للترجمة).
  static String _wrap(String t, {int max = 42}) {
    if (t.length <= max) return t;
    final words = t.split(' ');
    final lines = <String>[];
    var cur = '';
    for (final w in words) {
      if (cur.isNotEmpty && (cur.length + w.length + 1) > max && lines.isEmpty) {
        lines.add(cur);
        cur = w;
      } else {
        cur = cur.isEmpty ? w : '$cur $w';
      }
    }
    lines.add(cur);
    return lines.join('\n');
  }
}
