/// خطأ برسالة عربية واضحة للمستخدم.
class StudioException implements Exception {
  const StudioException(this.message, {this.code, this.retryable = false, this.retryAfter});

  final String message;
  final String? code;
  final bool retryable;

  /// لو السيرفر قال نستنى قد إيه قبل المحاولة تاني.
  final Duration? retryAfter;

  static const noKey = StudioException('مفيش مفتاح Gemini. ضيفه من الإعدادات.', code: 'no_key');
  static const badKey = StudioException('المفتاح غلط أو اتلغى. اتأكد منه في الإعدادات.', code: 'bad_key');

  /// الحصة اليومية للموديل خلصت (بترجع تاني يوم).
  static const quotaDay = StudioException(
    'الحصة المجانية اليومية لموديلات الصوت خلصت على المفتاح ده. بترجع بكرة، أو جرّب مفتاح تاني.',
    code: 'quota_day',
  );

  static StudioException quotaMinute(Duration wait) => StudioException(
        'طلبات كتير في دقيقة واحدة. هنستنى ${wait.inSeconds} ثانية ونكمّل.',
        code: 'quota_minute',
        retryable: true,
        retryAfter: wait,
      );

  static const network = StudioException('مفيش اتصال بالإنترنت أو السيرفر مش بيرد.', code: 'network', retryable: true);
  static const noAudio = StudioException('الموديل ما رجّعش صوت. جرّب تاني أو غيّر الموديل من الإعدادات.', code: 'no_audio', retryable: true);
  static const blocked = StudioException('الموديل رفض النص ده. جرّب تعدّل الصياغة.', code: 'blocked');
  static const noTtsModel = StudioException(
    'مفيش موديل صوت متاح للمفتاح ده دلوقتي (يا إما الحصة خلصت يا إما مش مفعّل). جرّب بعد شوية أو من الإعدادات اختار موديل تاني.',
    code: 'no_tts_model',
  );

  bool get isQuota => code == 'quota_day' || code == 'quota_minute';

  @override
  String toString() => message;
}
