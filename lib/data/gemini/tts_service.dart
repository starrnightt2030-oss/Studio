import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/settings/settings.dart';
import '../../core/storage/local_db.dart';
import 'gemini_client.dart';
import 'style_builder.dart';

/// طلب توليد صوت لجملة واحدة.
class TtsRequest {
  const TtsRequest({required this.text, required this.voice, required this.style, this.locale});
  final String text;
  final String voice;
  final String style;
  final String? locale;
}

/// الطريقة اللي بنكلّم بيها الموديل. الـ API بيتغير، فبنجرب الأشكال المعروفة
/// ونفتكر اللي اشتغل لكل موديل — ده اللي بيخلي التطبيق "اعتمادي".
enum TtsWire { interactionsGuide, interactionsRef, generateContent }

class TtsService {
  TtsService(this.client, this.settings);

  final GeminiClient client;
  final AppSettings settings;

  static const candidates = [
    'gemini-3.8-flash-tts',
    'gemini-3.1-flash-tts-preview',
    'gemini-2.5-flash-preview-tts',
    'gemini-3.8-flash-lite-tts',
    'gemini-2.5-pro-preview-tts',
  ];

  String? _resolved;

  /// يختار أحسن موديل صوت متاح للمفتاح (أو اللي المستخدم اختاره).
  Future<String> resolveModel() async {
    if (settings.ttsModel != null) return settings.ttsModel!;
    if (_resolved != null) return _resolved!;
    final cached = LocalDb.settings.get('autoTtsModel') as String?;
    if (cached != null) return _resolved = cached;
    try {
      final models = (await client.listModels()).where((m) => m.isTts).map((m) => m.id).toList();
      if (models.isNotEmpty) {
        models.sort((a, b) => _score(b).compareTo(_score(a)));
        _resolved = models.first;
        await LocalDb.settings.put('autoTtsModel', _resolved);
        return _resolved!;
      }
    } on DioException catch (e) {
      throw GeminiClient.mapError(e);
    }
    return _resolved = candidates.first;
  }

  static int _score(String id) {
    final v = RegExp(r'(\d+)\.(\d+)').firstMatch(id);
    var s = v == null ? 0 : int.parse(v.group(1)!) * 100 + int.parse(v.group(2)!) * 10;
    if (id.contains('flash')) s += 5;
    if (id.contains('lite')) s -= 3;
    if (id.contains('pro')) s -= 1;
    if (!id.contains('preview')) s += 2;
    return s;
  }

  static String cacheKey(String model, TtsRequest r) =>
      sha1.convert(utf8.encode('$model|${r.voice}|${r.locale}|${r.style}|${r.text}')).toString();

  /// يولّد (أو يجيب من الكاش) ملف WAV للجملة.
  Future<Uint8List> synthesize(TtsRequest r, {bool useCache = true}) async {
    final text = r.text.trim();
    if (text.isEmpty) throw const StudioException('الجملة فاضية.');
    final model = await resolveModel();
    final key = cacheKey(model, r);
    if (useCache) {
      final hit = LocalDb.readAudio(key);
      if (hit != null) return hit;
    }

    final saved = LocalDb.settings.get('wire:$model') as String?;
    final order = <TtsWire>[
      if (saved != null) TtsWire.values.byName(saved),
      ...TtsWire.values.where((w) => w.name != saved),
    ];

    StudioException? last;
    for (final wire in order) {
      try {
        final wav = await _call(wire, model, r);
        if (saved != wire.name) await LocalDb.settings.put('wire:$model', wire.name);
        await LocalDb.writeAudio(key, wav);
        return wav;
      } on StudioException catch (e) {
        last = e;
        // نجرب الشكل التاني بس لو الخطأ في شكل الطلب، مش في الحصة أو المفتاح.
        final shapeError = e.code == 'bad_request' || e.code == 'not_found' || e.code == 'no_audio';
        if (!shapeError) rethrow;
        logDebug('wire ${wire.name} failed: ${e.message}');
      }
    }
    throw last ?? StudioException.noAudio;
  }

  Future<Uint8List> _call(TtsWire wire, String model, TtsRequest r) async {
    final Map<String, dynamic> data;
    switch (wire) {
      case TtsWire.interactionsGuide:
        data = await client.post('interactions', {
          'model': model,
          'input': [
            {
              'type': 'user_input',
              'content': [
                {
                  'type': 'text',
                  'text': PerformanceTags.toApi(r.text),
                  'annotations': [
                    {'type': 'speech_metadata', 'style': r.style}
                  ],
                }
              ],
            }
          ],
          'response_format': {'type': 'audio'},
          'generation_config': {
            'speech_config': [
              {'voice': r.voice}
            ],
          },
        });
      case TtsWire.interactionsRef:
        final t = PerformanceTags.toApi(r.text);
        data = await client.post('interactions', {
          'model': model,
          'input': [
            {
              'type': 'text',
              'text': t,
              'annotations': [
                {'type': 'speech_metadata', 'style': r.style, 'start_index': 0, 'end_index': utf8.encode(t).length}
              ],
            }
          ],
          'generation_config': {
            'structured_speech_config': [
              {'voice': r.voice}
            ],
          },
        });
      case TtsWire.generateContent:
        data = await client.post('models/$model:generateContent', {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': '${r.style}\nRead the following Arabic text exactly as written:\n${PerformanceTags.toPlain(r.text)}'}
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
        });
    }
    final audio = _findAudio(data);
    if (audio == null) {
      final reason = data['candidates']?[0]?['finishReason'] ?? data['promptFeedback']?['blockReason'];
      if (reason == 'SAFETY' || reason == 'PROHIBITED_CONTENT') throw StudioException.blocked;
      throw StudioException.noAudio;
    }
    return audio;
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
        final r = _findAudio(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node.reversed) {
        final r = _findAudio(v);
        if (r != null) return r;
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
  return TtsService(c, ref.watch(settingsProvider));
});
