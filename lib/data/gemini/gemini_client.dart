import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/usage.dart';
import '../../core/settings/settings.dart';
import '../../core/storage/key_store.dart';

class GeminiModel {
  const GeminiModel(this.id, this.displayName, this.methods);
  final String id;
  final String displayName;
  final List<String> methods;

  bool get isTts => id.contains('tts');
}

/// اتصال مباشر بـ Gemini API بمفتاح المستخدم (مفيش سيرفر وسيط).
class GeminiClient {
  GeminiClient(this.apiKey, {Dio? dio, this.preferredTextModel})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://generativelanguage.googleapis.com/v1beta/',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ));

  final String apiKey;
  final Dio dio;
  final String? preferredTextModel;

  static const textFallbacks = ['gemini-flash-latest', 'gemini-2.5-flash', 'gemini-flash-lite-latest', 'gemini-2.5-flash-lite'];

  Options get _auth => Options(headers: {'x-goog-api-key': apiKey});

  /// POST مع إعادة محاولة تلقائية:
  /// - حد الطلبات في الدقيقة: نستنى المدة اللي السيرفر قالها ونكمّل (ونبلّغ الواجهة عن طريق onWait).
  /// - مشاكل الشبكة والسيرفر: محاولات بتأخير متزايد.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int attempts = 3,
    void Function(Duration wait)? onWait,
  }) async {
    var delay = const Duration(seconds: 2);
    var minuteWaits = 0;
    for (var i = 0;; i++) {
      try {
        final res = await dio.post<dynamic>(path, data: jsonEncode(body), options: _auth);
        final data = res.data;
        if (data is Map<String, dynamic>) return data;
        if (data is String) return jsonDecode(data) as Map<String, dynamic>;
        return <String, dynamic>{};
      } on DioException catch (e) {
        final err = mapError(e);
        if (err.code == 'quota_minute' && minuteWaits < 4) {
          minuteWaits++;
          final wait = err.retryAfter ?? const Duration(seconds: 30);
          onWait?.call(wait);
          await Future<void>.delayed(wait + const Duration(seconds: 1));
          i--; // انتظار الحصة مش محسوب من المحاولات
          continue;
        }
        final last = i >= attempts - 1;
        if (!err.retryable || err.code == 'quota_minute' || last) throw err;
        await Future<void>.delayed(delay + Duration(milliseconds: math.Random().nextInt(600)));
        delay *= 2;
      }
    }
  }

  /// يحوّل أخطاء الشبكة/الـ API لرسالة عربية مفهومة.
  static StudioException mapError(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final msg = (body is Map ? (body['error']?['message'] ?? '') : body?.toString() ?? '').toString();
    final lower = msg.toLowerCase();
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return StudioException.network;
    }
    if (code == 429 || lower.contains('resource_exhausted') || lower.contains('exceeded your current quota')) {
      return _quotaError(body, lower);
    }
    if (lower.contains('api key not valid') || lower.contains('api_key_invalid') || code == 401) return StudioException.badKey;
    if (code == 403) {
      return const StudioException('المفتاح مالوش صلاحية على الموديل ده. فعّل Gemini API في حسابك أو غيّر الموديل.', code: 'forbidden');
    }
    if (code == 404) return StudioException('الموديل مش متاح: $msg', code: 'not_found');
    if (code == 400) return StudioException('طلب غير مقبول: $msg', code: 'bad_request');
    if (code != null && code >= 500) {
      return const StudioException('سيرفر Gemini مشغول دلوقتي. جاري المحاولة تاني…', code: 'server', retryable: true);
    }
    return StudioException(msg.isEmpty ? 'حصل خطأ غير متوقع.' : msg);
  }

  /// بيفرّق بين حد الدقيقة (نستنى ونكمّل) والحد اليومي (نجرّب موديل تاني أو نوقف).
  static StudioException _quotaError(dynamic body, String lowerMsg) {
    Duration? retry;
    var perDay = lowerMsg.contains('per day') || lowerMsg.contains('perday') || lowerMsg.contains('limit: 0');
    var perMinute = lowerMsg.contains('per minute') || lowerMsg.contains('perminute');
    final dynamic details = body is Map ? (body['error']?['details']) : null;
    if (details is List) {
      for (final d in details) {
        if (d is! Map) continue;
        final type = (d['@type'] ?? '').toString();
        if (type.endsWith('RetryInfo')) {
          final m = RegExp(r'([\d.]+)s').firstMatch((d['retryDelay'] ?? '').toString());
          if (m != null) retry = Duration(milliseconds: (double.parse(m.group(1)!) * 1000).round());
        }
        if (type.endsWith('QuotaFailure')) {
          for (final v in (d['violations'] as List? ?? const [])) {
            final id = '${v['quotaId'] ?? ''} ${v['quotaMetric'] ?? ''}'.toLowerCase();
            if (id.contains('perday')) perDay = true;
            if (id.contains('perminute')) perMinute = true;
          }
        }
      }
    }
    if (perDay && !perMinute) return StudioException.quotaDay;
    final wait = retry ?? const Duration(seconds: 30);
    // لو السيرفر طالب نستنى أكتر من دقيقتين، غالباً ده حد يومي
    if (wait > const Duration(minutes: 2)) return StudioException.quotaDay;
    return StudioException.quotaMinute(wait);
  }

  // ───────────────────────── الموديلات

  Future<List<GeminiModel>> listModels() async {
    final out = <GeminiModel>[];
    String? token;
    do {
      final res = await dio.get<dynamic>('models',
          queryParameters: {'pageSize': 200, if (token != null) 'pageToken': token}, options: _auth);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      for (final m in (data['models'] as List? ?? const [])) {
        final id = (m['name'] as String).replaceFirst('models/', '');
        out.add(GeminiModel(id, (m['displayName'] ?? id).toString(),
            List<String>.from(m['supportedGenerationMethods'] as List? ?? const [])));
      }
      token = data['nextPageToken'] as String?;
    } while (token != null && token.isNotEmpty);
    return out;
  }

  /// تحقق سريع إن المفتاح شغال.
  Future<int> verifyKey() async {
    try {
      final models = await listModels();
      return models.length;
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  // ───────────────────────── النصوص

  Future<String> generateText(
    String prompt, {
    String? system,
    Map<String, dynamic>? jsonSchema,
    List<Map<String, dynamic>> inlineParts = const [],
    double temperature = 0.7,
  }) async {
    final models = [if (preferredTextModel != null) preferredTextModel!, ...textFallbacks];
    StudioException? lastErr;
    for (final m in models.toSet()) {
      try {
        final data = await post('models/$m:generateContent', {
          if (system != null) 'systemInstruction': {'parts': [{'text': system}]},
          'contents': [
            {
              'role': 'user',
              'parts': [...inlineParts, {'text': prompt}],
            }
          ],
          'generationConfig': {
            'temperature': temperature,
            if (jsonSchema != null) 'responseMimeType': 'application/json',
            if (jsonSchema != null) 'responseSchema': jsonSchema,
          },
        });
        final cands = data['candidates'] as List?;
        if (cands == null || cands.isEmpty) {
          if (data['promptFeedback']?['blockReason'] != null) throw StudioException.blocked;
          throw StudioException.noAudio;
        }
        final parts = (cands.first['content']?['parts'] as List?) ?? const [];
        final text = parts.map((p) => p['text'] ?? '').join();
        if (text.trim().isEmpty) throw const StudioException('الموديل رجّع رد فاضي.');
        await Usage.text();
        return text.trim();
      } on StudioException catch (e) {
        lastErr = e;
        if (e.code == 'not_found' || e.code == 'forbidden') continue;
        rethrow;
      }
    }
    throw lastErr ?? const StudioException('مفيش موديل نص متاح للمفتاح ده.');
  }

  Future<dynamic> generateJson(String prompt, {String? system, required Map<String, dynamic> schema}) async {
    final raw = await generateText(prompt, system: system, jsonSchema: schema, temperature: 0.8);
    final cleaned = raw.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
    return jsonDecode(cleaned);
  }

  static Map<String, dynamic> inlineData(Uint8List bytes, String mime) =>
      {'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)}};
}

final geminiClientProvider = Provider<GeminiClient?>((ref) {
  final key = ref.watch(apiKeyProvider);
  if (key == null) return null;
  final textModel = ref.watch(settingsProvider.select((s) => s.textModel));
  return GeminiClient(key, preferredTextModel: textModel);
});

void logDebug(Object o) {
  if (kDebugMode) debugPrint('[gemini] $o');
}
