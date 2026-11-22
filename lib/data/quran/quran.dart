import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';

import '../../core/audio/mastering.dart';
import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/storage/local_db.dart';
import '../gemini/gemini_client.dart';
import '../gemini/tashkeel.dart';

/// مرجع آية أو آيات متتالية من سورة واحدة.
class AyahRef {
  const AyahRef(this.surah, this.from, [int? to]) : to = to ?? from;
  final int surah;
  final int from;
  final int to;

  /// "2:255" أو "2:255-257"
  static AyahRef? parse(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d{1,3})\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?\s*$').firstMatch(s);
    if (m == null) return null;
    final r = AyahRef(int.parse(m[1]!), int.parse(m[2]!), m[3] == null ? null : int.parse(m[3]!));
    return r.valid ? r : null;
  }

  bool get valid => surah >= 1 && surah <= 114 && from >= 1 && to >= from && to - from < 40;

  @override
  String toString() => from == to ? '$surah:$from' : '$surah:$from-$to';

  String label(String surahName) => from == to ? '$surahName · آية $from' : '$surahName · الآيات $from–$to';

  Iterable<int> get ayat sync* {
    for (var a = from; a <= to; a++) {
      yield a;
    }
  }
}

class Reciter {
  const Reciter(this.id, this.name);
  final String id; // اسم الفولدر على everyayah.com
  final String name;
}

class VerifiedAyat {
  const VerifiedAyat(this.ref, this.surahName, this.text, this.match);
  final AyahRef ref;
  final String surahName;

  /// نص الآيات بالتشكيل (رسم إملائي).
  final String text;

  /// نسبة تطابق النص اللي المستخدم كتبه مع الآيات (1 = مطابق).
  final double match;
}

/// الآيات بتتقرا بصوت قارئ حقيقي، مش بالذكاء الاصطناعي.
/// النص من api.alquran.cloud والتلاوات من everyayah.com.
class Quran {
  Quran._();

  static const reciters = [
    Reciter('Husary_128kbps', 'محمود خليل الحصري (مرتّل)'),
    Reciter('Minshawy_Murattal_128kbps', 'محمد صديق المنشاوي (مرتّل)'),
    Reciter('Abdul_Basit_Murattal_192kbps', 'عبد الباسط عبد الصمد (مرتّل)'),
    Reciter('Alafasy_128kbps', 'مشاري راشد العفاسي'),
    Reciter('MaherAlMuaiqly128kbps', 'ماهر المعيقلي'),
    Reciter('Abdurrahmaan_As-Sudais_192kbps', 'عبد الرحمن السديس'),
  ];

  static Reciter reciterById(String? id) => reciters.firstWhere((r) => r.id == id, orElse: () => reciters.first);

  /// قارئ المستخدم الافتراضي.
  static String get defaultReciter => (LocalDb.settings.get('reciter') as String?) ?? reciters.first.id;
  static Future<void> setDefaultReciter(String id) => LocalDb.settings.put('reciter', id);

  static final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));

  static String cacheKey(AyahRef r, String reciter) => 'quran|$reciter|$r';

  /// يجيب نص الآيات ويقارنه بالنص المكتوب.
  static Future<VerifiedAyat> verify(AyahRef r, {String? written}) async {
    final parts = <String>[];
    var name = '';
    for (final a in r.ayat) {
      try {
        final res = await _dio.get<Map<String, dynamic>>('https://api.alquran.cloud/v1/ayah/${r.surah}:$a/quran-simple');
        final d = res.data!['data'] as Map;
        name = '${d['surah']?['name'] ?? ''}';
        parts.add('${d['text']}');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 || e.response?.statusCode == 400) {
          throw StudioException('الآية ${r.surah}:$a مش موجودة — راجع رقم السورة والآية.', code: 'quran_ref');
        }
        throw StudioException.network;
      }
    }
    final text = parts.join(' ');
    return VerifiedAyat(r, name, text, written == null ? 1 : similarity(written, text));
  }

  /// تطابق تقريبي على مستوى الكلمات (من غير تشكيل)، من 0 لـ 1.
  static double similarity(String written, String ayat) {
    List<String> words(String s) => Tashkeel.strip(s)
        .replaceAll(RegExp('[^ء-ي\\s]'), ' ')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
    final w = words(written), a = words(ayat);
    if (w.isEmpty || a.isEmpty) return 0;
    final pool = <String, int>{};
    for (final x in a) {
      pool[x] = (pool[x] ?? 0) + 1;
    }
    var hit = 0;
    for (final x in w) {
      final n = pool[x] ?? 0;
      if (n > 0) {
        hit++;
        pool[x] = n - 1;
      }
    }
    return hit / (w.length > a.length ? w.length : a.length);
  }

  /// Gemini بيدوّر على الجمل اللي هي آيات (ونرجع نتأكد من كل واحدة بالمصحف).
  static Future<Map<int, AyahRef>> detect(GeminiClient client, List<String> lines) async {
    final numbered = [for (var i = 0; i < lines.length; i++) '$i) ${lines[i]}'].join('\n');
    final raw = await client.generateJson(
      numbered,
      system: 'حدّد أي سطر نصه آية أو آيات قرآنية متتالية (مش مجرد ذكر أو دعاء). '
          'لكل سطر منهم رجّع رقم السطر ورقم السورة ورقم أول وآخر آية. لو مفيش، رجّع مصفوفة فاضية.',
      schema: const {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'line': {'type': 'INTEGER'},
            'surah': {'type': 'INTEGER'},
            'from': {'type': 'INTEGER'},
            'to': {'type': 'INTEGER'},
          },
          'required': ['line', 'surah', 'from', 'to'],
        },
      },
    );
    final out = <int, AyahRef>{};
    for (final e in (raw as List? ?? const []).cast<Map>()) {
      final i = (e['line'] as num?)?.toInt() ?? -1;
      final r = AyahRef((e['surah'] as num?)?.toInt() ?? 0, (e['from'] as num?)?.toInt() ?? 0, (e['to'] as num?)?.toInt());
      if (i >= 0 && i < lines.length && r.valid) out[i] = r;
    }
    return out;
  }

  /// تلاوة الآيات كـ WAV أحادي 24kHz عشان تتدمج مع باقي الصوت. بتتحفظ في الكاش.
  static Future<Uint8List> recitation(AyahRef r, String reciter, {bool useCache = true, void Function(String)? onStatus}) async {
    final key = cacheKey(r, reciter);
    if (useCache) {
      final hit = LocalDb.readAudio(key);
      if (hit != null) return hit;
    }
    final parts = <Uint8List>[];
    for (final a in r.ayat) {
      onStatus?.call('بنحمّل تلاوة ${reciterById(reciter).name} — آية $a');
      final name = '${r.surah.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3';
      final Response<List<int>> res;
      try {
        res = await _dio.get<List<int>>('https://everyayah.com/data/$reciter/$name', options: Options(responseType: ResponseType.bytes));
      } on DioException {
        throw const StudioException('مقدرناش نحمّل التلاوة — اتأكد من النت وجرّب تاني.', code: 'network', retryable: true);
      }
      parts.add(_mp3ToWav(Uint8List.fromList(res.data!)));
    }
    final wav = Wav.concat(parts, gapMs: 350);
    await LocalDb.writeAudio(key, wav);
    return wav;
  }

  static const rate = 24000;

  static Uint8List _mp3ToWav(Uint8List mp3) {
    final d = mp3Decode(mp3);
    final ch = d.channels < 1 ? 1 : d.channels;
    final n = d.samples.length ~/ ch;
    final mono = Float64List(n);
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var c = 0; c < ch; c++) {
        s += d.samples[i * ch + c];
      }
      mono[i] = s / ch;
    }
    final res = Mastering.resample(mono, d.sampleRate, rate);
    final pcm = Int16List(res.length);
    for (var i = 0; i < res.length; i++) {
      pcm[i] = (res[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return Wav.encode(Pcm(pcm, rate));
  }
}
