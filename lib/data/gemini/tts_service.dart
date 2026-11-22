import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/settings/settings.dart';
import '../../core/storage/local_db.dart';
import '../../core/usage.dart';
import '../azure/azure_tts.dart';
import '../catalog/emotions.dart';
import 'gemini_client.dart';
import 'style_builder.dart';

/// جزء من النص بإحساس خاص بيه (جملة).
class TtsSpan {
  const TtsSpan(this.text, this.direction, {this.emotion = Emotion.neutral, this.intensity = Intensity.medium});
  final String text;
  final Emotion emotion;
  final Intensity intensity;

  /// وصف الإحساس للجزء ده (مثلاً "very strongly excited").
  final String direction;
}

/// طلب توليد صوت. ممكن يكون جملة واحدة أو مقطع فيه كذا جملة كل واحدة بإحساسها —
/// ده اللي بيخلي 30 جملة تبقى 3-4 طلبات بس بدل 30 (توفير كبير للحصة المجانية).
class TtsRequest {
  TtsRequest({
    required this.voice,
    required this.baseStyle,
    required List<TtsSpan> spans,
    this.locale,
    this.dialectId,
    this.gender,
    this.age,
    this.speed = 0.5,
    this.pitch = 0.5,
    this.azureVoice,
  }) : spans = spans.where((s) => s.text.trim().isNotEmpty).toList();

  /// معلومات لمحرك Azure (مش بتأثر على Gemini).
  final String? dialectId;
  final Gender? gender;
  final Age? age;
  final double speed;
  final double pitch;

  /// صوت Azure محدد (لو null بنختار حسب اللهجة والنوع).
  final String? azureVoice;

  /// طلب لجملة واحدة.
  factory TtsRequest.single({
    required String text,
    required String voice,
    required String style,
    String? locale,
    String? dialectId,
    Gender? gender,
    Age? age,
    Emotion emotion = Emotion.neutral,
    String? azureVoice,
  }) =>
      TtsRequest(
        voice: voice,
        baseStyle: style,
        spans: [TtsSpan(text, '', emotion: emotion)],
        locale: locale,
        dialectId: dialectId,
        gender: gender,
        age: age,
        azureVoice: azureVoice,
      );

  final String voice;
  final String baseStyle;
  final List<TtsSpan> spans;
  final String? locale;

  bool get isMulti => spans.length > 1 || spans.any((s) => s.direction.isNotEmpty);
  String get plainText => spans.map((s) => s.text.trim()).join('\n');
}

/// الطريقة اللي بنكلّم بيها الموديل. الـ API بيتغير، فبنجرب الأشكال المعروفة
/// ونفتكر اللي اشتغل لكل موديل.
enum TtsWire { generateContent, interactionsRef, interactionsGuide }

class TtsService {
  TtsService(this.client, this.settings, {this.azure});

  final GeminiClient client;
  final AppSettings settings;
  final AzureTts? azure;

  /// المحرك الأساسي حسب الإعدادات.
  String get primaryEngine => settings.engine == TtsEngine.azure && azure != null ? 'azure' : 'gemini';

  /// هل نقدر نكمّل بـ Azure لو Gemini خلص؟
  bool get canFallbackToAzure => settings.engine == TtsEngine.auto && azure != null;

  Future<Uint8List> _synthAzure(TtsRequest r, String key) async {
    final az = azure;
    if (az == null) throw const StudioException('ضيف مفتاح Azure من الإعدادات الأول.', code: 'azure_key');
    final voice = r.azureVoice != null ? await az.voiceByName(r.azureVoice!) : await az.pickVoice(r.dialectId ?? 'saudi', r.gender ?? Gender.male);
    final body = AzureTts.ssml(
      voice: voice,
      lines: [for (final s in r.spans) (s.text, s.emotion, s.intensity)],
      speed: r.speed,
      pitch: r.pitch,
      age: r.age,
    );
    final wav = await az.synthesize(body);
    await Usage.azure(r.plainText.length);
    await LocalDb.writeAudio(key, wav);
    return wav;
  }

  /// لو مقدرناش نجيب قايمة الموديلات.
  static const candidates = [
    'gemini-2.5-flash-preview-tts',
    'gemini-3.1-flash-tts-preview',
    'gemini-3.8-flash-tts',
    'gemini-3.8-flash-lite-tts',
    'gemini-2.5-pro-preview-tts',
  ];

  List<String>? _models;

  static String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  static bool _exhausted(String model) => LocalDb.settings.get('exhausted:$model') == _today();
  static Future<void> _markExhausted(String model) => LocalDb.settings.put('exhausted:$model', _today());

  /// ترتيب موديلات الصوت اللي هنجربها (المختار يدوياً لوحده، أو تلقائي مع بدائل).
  Future<List<String>> modelOrder() async {
    if (settings.ttsModel != null) return [settings.ttsModel!];
    if (_models == null) {
      try {
        final ids = (await client.listModels()).where((m) => m.isTts).map((m) => m.id).toList();
        ids.sort((a, b) => _score(b).compareTo(_score(a)));
        _models = ids.isEmpty ? candidates : ids;
      } on DioException catch (e) {
        final err = GeminiClient.mapError(e);
        if (err.code == 'bad_key') throw err;
        _models = candidates;
      }
    }
    final last = LocalDb.settings.get('autoTtsModel') as String?;
    final order = [if (last != null && _models!.contains(last)) last, ..._models!.where((m) => m != last)];
    final fresh = order.where((m) => !_exhausted(m)).toList();
    return fresh.isEmpty ? order : fresh;
  }

  /// الموديل المستخدم حالياً (للعرض).
  Future<String> resolveModel() async => (await modelOrder()).first;

  /// الأحسن الأول: الأحدث، flash قبل pro، والعادي قبل lite.
  static int _score(String id) {
    final v = RegExp(r'(\d+)\.(\d+)').firstMatch(id);
    var s = v == null ? 0 : int.parse(v.group(1)!) * 100 + int.parse(v.group(2)!) * 10;
    if (id.contains('flash')) s += 5;
    if (id.contains('lite')) s -= 3;
    if (id.contains('pro')) s -= 1;
    if (!id.contains('preview')) s += 2;
    return s;
  }

  /// مفتاح الكاش مش مربوط بالموديل، عشان لو اتغير الموديل ما نعيدش توليد الجاهز.
  static String cacheKey(TtsRequest r, {String engine = 'gemini'}) {
    final body = sha1
        .convert(utf8.encode('${r.voice}|${r.locale}|${r.baseStyle}|${r.spans.map((s) => '${s.direction}»${s.text}').join('¦')}'))
        .toString();
    if (engine == 'gemini') return body;
    if (engine != 'azure') return '$engine|$body';
    final v = r.azureVoice ?? 'auto-${r.dialectId}-${r.gender?.name}';
    return 'azure|$v|$body';
  }

  /// يولّد (أو يجيب من الكاش) ملف WAV.
  Future<Uint8List> synthesize(TtsRequest r, {bool useCache = true, void Function(String status)? onStatus, String? engine}) async {
    if (r.spans.isEmpty) throw const StudioException('النص فاضي.');
    final eng = engine ?? primaryEngine;
    final key = cacheKey(r, engine: eng);
    if (useCache) {
      final hit = LocalDb.readAudio(key);
      if (hit != null) return hit;
    }
    if (eng == 'azure') return _synthAzure(r, key);

    final models = await modelOrder();
    StudioException? last;
    for (final model in models) {
      try {
        final wav = await _withWires(model, r, onStatus);
        if (settings.ttsModel == null) await LocalDb.settings.put('autoTtsModel', model);
        await Usage.gemini(r.plainText.length);
        await LocalDb.writeAudio(key, wav);
        return wav;
      } on StudioException catch (e) {
        last = e;
        final tryNext = e.code == 'quota_day' || e.code == 'not_found' || e.code == 'forbidden' || e.code == 'bad_request';
        if (!tryNext || settings.ttsModel != null) rethrow;
        if (e.code == 'quota_day') await _markExhausted(model);
        logDebug('model $model failed (${e.code}), trying next');
        onStatus?.call('بنجرّب موديل صوت تاني…');
      }
    }
    if (last?.code == 'quota_day') throw StudioException.quotaDay;
    throw StudioException.noTtsModel;
  }

  Future<Uint8List> _withWires(String model, TtsRequest r, void Function(String)? onStatus) async {
    final saved = LocalDb.settings.get('wire:$model') as String?;
    final order = <TtsWire>[
      if (saved != null && TtsWire.values.any((w) => w.name == saved)) TtsWire.values.byName(saved),
      ...TtsWire.values.where((w) => w.name != saved),
    ];
    StudioException? last;
    for (final wire in order) {
      try {
        final wav = await _call(wire, model, r, onStatus);
        if (saved != wire.name) await LocalDb.settings.put('wire:$model', wire.name);
        return wav;
      } on StudioException catch (e) {
        last = e;
        // نجرب الشكل التاني بس لو الخطأ في شكل الطلب، مش في الحصة أو المفتاح.
        final shapeError = e.code == 'bad_request' || e.code == 'not_found' || e.code == 'no_audio';
        if (!shapeError) rethrow;
        logDebug('wire ${wire.name} on $model failed: ${e.message}');
      }
    }
    throw last ?? StudioException.noAudio;
  }

  Future<Uint8List> _call(TtsWire wire, String model, TtsRequest r, void Function(String)? onStatus) async {
    void onWait(Duration d) => onStatus?.call('حد الطلبات في الدقيقة… هنكمّل بعد ${d.inSeconds} ثانية');
    final Map<String, dynamic> data;
    switch (wire) {
      case TtsWire.generateContent:
        data = await client.post(
          'models/$model:generateContent',
          {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': _directorScript(r)}
                ],
              }
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': r.voice}
                }
              },
            },
          },
          onWait: onWait,
        );
      case TtsWire.interactionsRef:
        final (refText, refAnn) = _annotated(r);
        data = await client.post(
          'interactions',
          {
            'model': model,
            'input': [
              {'type': 'text', 'text': refText, 'annotations': refAnn}
            ],
            'generation_config': {
              'structured_speech_config': [
                {'voice': r.voice}
              ],
            },
          },
          onWait: onWait,
        );
      case TtsWire.interactionsGuide:
        final (text, annotations) = _annotated(r);
        data = await client.post(
          'interactions',
          {
            'model': model,
            'input': [
              {
                'type': 'user_input',
                'content': [
                  {'type': 'text', 'text': text, 'annotations': annotations}
                ],
              }
            ],
            'response_format': {'type': 'audio'},
            'generation_config': {
              'speech_config': [
                {'voice': r.voice}
              ],
            },
          },
          onWait: onWait,
        );
    }
    final audio = _findAudio(data);
    if (audio == null) {
      final reason = data['candidates']?[0]?['finishReason'] ?? data['promptFeedback']?['blockReason'];
      if (reason == 'SAFETY' || reason == 'PROHIBITED_CONTENT') throw StudioException.blocked;
      throw StudioException.noAudio;
    }
    return audio;
  }

  /// للـ generateContent: سكريبت إخراج — كل سطر قبله إحساسه بين أقواس، والموديل يأديه من غير ما يقرا الأقواس.
  static String _directorScript(TtsRequest r) {
    if (r.spans.length == 1) {
      final dir = r.spans.first.direction;
      return '${r.baseStyle}${dir.isEmpty ? '' : ' Emotion: $dir.'}\n'
          'Read the following Arabic text exactly as written:\n${PerformanceTags.toPlain(r.spans.first.text)}';
    }
    final b = StringBuffer(r.baseStyle);
    if (r.spans.every((s) => s.direction.isEmpty)) {
      b.write('\nRead the following Arabic text exactly as written:\n');
      b.write(PerformanceTags.toPlain(r.plainText));
      return b.toString();
    }
    b.write('\nPerform the following Arabic script line by line, in one continuous natural take. '
        'Each line begins with a performance direction in square brackets: follow that emotion for that line only, '
        'and NEVER read the brackets or the direction aloud. Read the Arabic words exactly as written.\n\n');
    for (final s in r.spans) {
      b.write('[${s.direction.isEmpty ? 'neutral' : s.direction}] ${PerformanceTags.toPlain(s.text)}\n');
    }
    return b.toString();
  }

  /// للـ Interactions API: النص كله مع ملاحظة أداء لكل جملة (مواضعها بالبايت).
  static (String, List<Map<String, dynamic>>) _annotated(TtsRequest r) {
    final buf = StringBuffer();
    final ann = <Map<String, dynamic>>[];
    var offset = 0;
    for (var i = 0; i < r.spans.length; i++) {
      final s = r.spans[i];
      final piece = PerformanceTags.toApi(s.text) + (i < r.spans.length - 1 ? '\n' : '');
      final len = utf8.encode(piece).length;
      ann.add({
        'type': 'speech_metadata',
        'style': s.direction.isEmpty ? r.baseStyle : '${r.baseStyle} Emotion: ${s.direction}.',
        'start_index': offset,
        'end_index': offset + len,
      });
      buf.write(piece);
      offset += len;
    }
    return (buf.toString(), ann);
  }

  /// بيدوّر على الصوت في أي شكل للرد (القديم أو الجديد).
  static Uint8List? _findAudio(dynamic node) {
    if (node is Map) {
      final inline = node['inlineData'] ?? node['inline_data'];
      if (inline is Map && inline['data'] is String) {
        return _toWav(inline['data'] as String, (inline['mimeType'] ?? inline['mime_type'] ?? '').toString());
      }
      final type = node['type'];
      final mime = (node['mime_type'] ?? node['mimeType'] ?? '').toString();
      if (node['data'] is String && (type == 'audio' || mime.startsWith('audio'))) {
        return _toWav(node['data'] as String, mime, rate: node['sample_rate'] as int?);
      }
      for (final v in node.values) {
        final res = _findAudio(v);
        if (res != null) return res;
      }
    } else if (node is List) {
      for (final v in node.reversed) {
        final res = _findAudio(v);
        if (res != null) return res;
      }
    }
    return null;
  }

  static Uint8List _toWav(String b64, String mime, {int? rate}) {
    final bytes = base64Decode(b64);
    if (Wav.isWav(bytes)) return bytes;
    final m = RegExp(r'rate=(\d+)').firstMatch(mime);
    final sr = rate ?? (m != null ? int.parse(m.group(1)!) : 24000);
    return Wav.fromPcm16(bytes, sampleRate: sr);
  }
}

final ttsServiceProvider = Provider<TtsService?>((ref) {
  final c = ref.watch(geminiClientProvider);
  if (c == null) return null;
  return TtsService(c, ref.watch(settingsProvider), azure: ref.watch(azureTtsProvider));
});
