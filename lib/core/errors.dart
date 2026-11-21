/// خطأ برسالة عربية واضحة للمستخدم.
class StudioException implements Exception {
  const StudioException(this.message, {this.code, this.retryable = false});

  final String message;
  final String? code;
  final bool retryable;

  static const noKey = StudioException('مفيش مفتاح Gemini. ضيفه من الإعدادات.', code: 'no_key');
  static const badKey = StudioException('المفتاح غلط أو اتلغى. اتأكد منه في الإعدادات.', code: 'bad_key');
  static const quota = StudioException(
    'حصة اليوم المجانية خلصت أو الطلبات كتير ورا بعض. استنى شوية أو جرّب بكرة.',
    code: 'quota',
    retryable: true,
  );
  static const network = StudioException('مفيش اتصال بالإنترنت أو السيرفر مش بيرد.', code: 'network', retryable: true);
  static const noAudio = StudioException('الموديل ما رجّعش صوت. جرّب تاني أو غيّر الموديل من الإعدادات.', code: 'no_audio', retryable: true);
  static const blocked = StudioException('الموديل رفض النص ده. جرّب تعدّل الصياغة.', code: 'blocked');

  @override
  String toString() => message;
}
