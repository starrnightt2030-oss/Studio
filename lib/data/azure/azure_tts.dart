import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/storage/local_db.dart';
import '../catalog/emotions.dart';

class AzureVoice {
  const AzureVoice(this.shortName, this.locale, this.gender, this.displayName);
  final String shortName;
  final String locale;
  final String gender;
  final String displayName;
}

/// محرك تاني: Azure Speech (الطبقة المجانية F0 فيها نصف مليون حرف في الشهر)،
/// وفيه أصوات أصلية لكل لهجة عربية تقريباً.
class AzureTts {
  AzureTts(this.key, this.region, {Dio? dio})
      : dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 90)));

  final String key;
  final String region;
  final Dio dio;

  String? _token;
  DateTime? _tokenAt;

  static const regions = ['eastus', 'westeurope', 'uaenorth', 'qatarcentral', 'northeurope', 'westus2', 'southeastasia', 'centralindia'];

  /// أقرب لغة Azure لكل لهجة في التطبيق.
  static const dialectLocales = <String, List<String>>{
    'egyptian': ['ar-EG'],
    'saudi': ['ar-SA'],
    'khaleeji': ['ar-AE', 'ar-KW', 'ar-QA', 'ar-BH', 'ar-OM'],
    'levantine': ['ar-SY', 'ar-JO'],
    'lebanese': ['ar-LB'],
    'iraqi': ['ar-IQ'],
    'sudanese': ['ar-SD', 'ar-EG'],
    'yemeni': ['ar-YE'],
    'moroccan': ['ar-MA'],
    'algerian': ['ar-DZ'],
    'tunisian': ['ar-TN'],
    'fusha': ['ar-SA', 'ar-EG'],
  };

  String get _ttsHost => 'https://$region.tts.speech.microsoft.com';

  static StudioException _map(DioException e) {
    final c = e.response?.statusCode;
    if (c == 401 || c == 403) return const StudioException('مفتاح Azure أو المنطقة (Region) غلط.', code: 'azure_key');
    if (c == 429) return const StudioException('حصة Azure المجانية خلصت أو الطلبات كتير ورا بعض.', code: 'azure_quota', retryable: true);
    if (c == 400) return StudioException('Azure رفض الطلب: ${e.response?.data}', code: 'azure_bad_request');
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      return StudioException.network;
    }
    return StudioException('خطأ من Azure (${c ?? e.type.name}).', code: 'azure');
  }

  Future<String> _bearer() async {
    if (_token != null && _tokenAt != null && DateTime.now().difference(_tokenAt!) < const Duration(minutes: 9)) return _token!;
    final res = await dio.post<String>(
      'https://$region.api.cognitive.microsoft.com/sts/v1.0/issueToken',
      options: Options(headers: {'Ocp-Apim-Subscription-Key': key, 'Content-Length': '0'}, responseType: ResponseType.plain),
    );
    _token = res.data;
    _tokenAt = DateTime.now();
    return _token!;
  }

  Future<List<AzureVoice>> listVoices() async {
    final cached = LocalDb.settings.get('azureVoices:$region') as String?;
    if (cached != null) return _parseVoices(jsonDecode(cached) as List);
    try {
      final res = await dio.get<dynamic>('$_ttsHost/cognitiveservices/voices/list',
          options: Options(headers: {'Ocp-Apim-Subscription-Key': key}));
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final arabic = (data as List).where((v) => (v['Locale'] ?? '').toString().startsWith('ar-')).toList();
      await LocalDb.settings.put('azureVoices:$region', jsonEncode(arabic));
      return _parseVoices(arabic);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static List<AzureVoice> _parseVoices(List l) => [
        for (final v in l)
          AzureVoice(v['ShortName'].toString(), v['Locale'].toString(), v['Gender'].toString(),
              (v['LocalName'] ?? v['DisplayName'] ?? v['ShortName']).toString()),
      ];

  /// يختار صوت Azure للهجة والنوع.
  Future<AzureVoice> pickVoice(String dialectId, Gender gender) async {
    final voices = await listVoices();
    final g = gender == Gender.male ? 'Male' : 'Female';
    for (final loc in dialectLocales[dialectId] ?? const ['ar-SA']) {
      final hit = voices.where((v) => v.locale == loc && v.gender == g).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    final any = voices.where((v) => v.gender == g).toList();
    if (any.isNotEmpty) return any.first;
    if (voices.isNotEmpty) return voices.first;
    throw const StudioException('مفيش أصوات عربي متاحة في منطقة Azure دي.', code: 'azure_no_voice');
  }

  /// الإحساس بيتقرّب بالسرعة والطبقة والعلو (أصوات Azure العربي مفيهاش أنماط مشاعر).
  static ({int rate, int pitch, String volume}) _prosody(Emotion e, Intensity i) {
    final k = switch (i) { Intensity.light => 0.5, Intensity.medium => 1.0, Intensity.strong => 1.5 };
    final (r, p, v) = switch (e) {
      Emotion.neutral => (0, 0, 'medium'),
      Emotion.joy => (6, 6, 'medium'),
      Emotion.excitement => (12, 9, 'loud'),
      Emotion.sadness => (-12, -6, 'soft'),
      Emotion.anger => (6, -3, 'x-loud'),
      Emotion.calm => (-8, -2, 'soft'),
      Emotion.fear => (10, 8, 'soft'),
      Emotion.surprise => (4, 12, 'loud'),
      Emotion.whisper => (-8, -2, 'x-soft'),
    };
    return (rate: (r * k).round(), pitch: (p * k).round(), volume: v);
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  static String _text(String t) {
    var s = _esc(t);
    s = s.replaceAll(_esc('⟨وقفة طويلة⟩'), '<break time="900ms"/>').replaceAll(_esc('⟨وقفة⟩'), '<break time="400ms"/>');
    return s.replaceAll(RegExp(r'⟨[^⟩]*⟩'), ' ');
  }

  /// بيبني SSML: كل جملة بإحساسها (سرعة/طبقة/علو)، مع إعدادات العمر والسرعة العامة.
  static String ssml({
    required AzureVoice voice,
    required List<(String, Emotion, Intensity)> lines,
    double speed = 0.5,
    double pitch = 0.5,
    Age? age,
  }) {
    final baseRate = ((speed - 0.5) * 50).round();
    var basePitch = ((pitch - 0.5) * 30).round();
    var ageRate = 0;
    if (age == Age.child) basePitch += 22;
    if (age == Age.elder) {
      basePitch -= 8;
      ageRate = -10;
    }
    final b = StringBuffer("<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='${voice.locale}'>")
      ..write("<voice name='${voice.shortName}'>");
    for (final (t, e, i) in lines) {
      final pr = _prosody(e, i);
      final rate = baseRate + ageRate + pr.rate;
      final p = basePitch + pr.pitch;
      b.write("<prosody rate='${rate >= 0 ? '+' : ''}$rate%' pitch='${p >= 0 ? '+' : ''}$p%' volume='${pr.volume}'>${_text(t)}</prosody>");
      b.write('<break time="250ms"/>');
    }
    b.write('</voice></speak>');
    return b.toString();
  }

  Future<Uint8List> synthesize(String ssmlBody) async {
    Future<Response<List<int>>> send(Map<String, String> auth) => dio.post<List<int>>(
          '$_ttsHost/cognitiveservices/v1',
          data: ssmlBody,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              ...auth,
              'Content-Type': 'application/ssml+xml',
              'X-Microsoft-OutputFormat': 'riff-24khz-16bit-mono-pcm',
            },
          ),
        );
    try {
      Response<List<int>> res;
      try {
        res = await send({'Authorization': 'Bearer ${await _bearer()}'});
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        res = await send({'Ocp-Apim-Subscription-Key': key});
      }
      final bytes = Uint8List.fromList(res.data ?? const []);
      if (bytes.isEmpty) throw StudioException.noAudio;
      return Wav.isWav(bytes) ? bytes : Wav.fromPcm16(bytes);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<int> verify() async {
    await LocalDb.settings.delete('azureVoices:$region');
    return (await listVoices()).length;
  }
}

/// إعدادات Azure: المفتاح مشفّر، والمنطقة في الإعدادات.
class AzureConfig {
  const AzureConfig(this.key, this.region);
  final String key;
  final String region;
}

class AzureConfigNotifier extends Notifier<AzureConfig?> {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  @override
  AzureConfig? build() => null;

  Future<void> load() async {
    final k = await _storage.read(key: 'azure_key');
    final r = LocalDb.settings.get('azureRegion') as String?;
    state = (k == null || k.isEmpty || r == null) ? null : AzureConfig(k, r);
  }

  Future<void> set(String key, String region) async {
    await _storage.write(key: 'azure_key', value: key.trim());
    await LocalDb.settings.put('azureRegion', region);
    state = AzureConfig(key.trim(), region);
  }

  Future<void> clear() async {
    await _storage.delete(key: 'azure_key');
    await LocalDb.settings.delete('azureRegion');
    state = null;
  }
}

final azureConfigProvider = NotifierProvider<AzureConfigNotifier, AzureConfig?>(AzureConfigNotifier.new);

final azureTtsProvider = Provider<AzureTts?>((ref) {
  final c = ref.watch(azureConfigProvider);
  return c == null ? null : AzureTts(c.key, c.region);
});
