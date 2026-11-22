import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/storage/local_db.dart';
import 'gemini_client.dart';

/// تشكيل النص العربي بموديل نصوص Gemini (حصته منفصلة عن حصة الصوت).
/// بيتعمل تلقائياً قبل Azure، ومتاح كأداة في الاستوديو عشان تراجعه قبل التوليد.
class Tashkeel {
  Tashkeel._();

  static final _harakat = RegExp('[ً-ْٰ]');
  static final _letters = RegExp('[ء-ي]');
  static final _tags = RegExp(r'⟨[^⟩]*⟩|\[[^\]]*\]');

  /// يشيل الحركات والتطويل.
  static String strip(String s) => s.replaceAll(_harakat, '').replaceAll('ـ', '');

  /// الحروف بس (للتأكد إن الموديل ما غيّرش ولا كلمة).
  static String skeleton(String s) => strip(s.replaceAll(_tags, '')).replaceAll(RegExp('[^ء-ي]'), '').replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');

  /// النص محتاج تشكيل لو أقل من ربع حروفه عليها حركات.
  static bool needs(String s) {
    final letters = _letters.allMatches(s).length;
    if (letters < 3) return false;
    return _harakat.allMatches(s).length / letters < 0.25;
  }

  static const _system = 'أنت مدقق لغوي متخصص في تشكيل النصوص العربية للإلقاء الصوتي. '
      'شكّل كل سطر تشكيلاً كاملاً دقيقاً حسب المعنى والإعراب (وحسب نطق اللهجة لو السطر عامي). '
      'ممنوع تغيّر أو تحذف أو تزوّد أي كلمة أو حرف أو علامة ترقيم، وسيب أي نص بين ⟨ ⟩ أو [ ] زي ما هو. '
      'لو فيه آية قرآنية أو حديث، شكّلها بالتشكيل المعروف المضبوط. '
      'رجّع مصفوفة JSON فيها نفس عدد السطور بنفس الترتيب.';

  /// بيرجع السطور متشكّلة. أي سطر الموديل غيّر فيه كلمة بيرجع زي ما كان.
  static Future<List<String>> apply(GeminiClient client, List<String> lines) async {
    final out = List<String>.of(lines);
    final todo = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (!needs(lines[i])) continue;
      final hit = LocalDb.settings.get(_key(lines[i]));
      if (hit is String) {
        out[i] = hit;
      } else {
        todo.add(i);
      }
    }
    // دفعات صغيرة عشان الرد يفضل دقيق
    for (var b = 0; b < todo.length; b += 25) {
      final batch = todo.sublist(b, (b + 25).clamp(0, todo.length));
      final res = await client.generateText(
        jsonEncode([for (final i in batch) lines[i]]),
        system: _system,
        jsonSchema: const {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        temperature: 0.1,
      );
      final cleaned = res.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
      final list = (jsonDecode(cleaned) as List).map((e) => '$e').toList();
      for (var k = 0; k < batch.length && k < list.length; k++) {
        final i = batch[k];
        if (skeleton(list[k]) == skeleton(lines[i])) {
          out[i] = list[k];
          await LocalDb.settings.put(_key(lines[i]), list[k]);
        }
      }
    }
    return out;
  }

  static String _key(String s) => 'tashkeel:${sha1.convert(utf8.encode(s))}';
}
