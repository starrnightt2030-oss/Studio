import 'package:flutter/material.dart';

enum Emotion {
  neutral('طبيعي', 'neutral, natural', Color(0xFF8B87A3), Color(0xFFEDEBF5), Color(0xFF3F3B57), Color(0xFFC9C5DB), Color(0xFF1E1C2A)),
  joy('فرح', 'joyful, smiling, delighted', Color(0xFFF59E0B), Color(0xFFFEF3C7), Color(0xFF92400E), Color(0xFFFBBF24), Color(0xFF2A2210)),
  excitement('حماس', 'excited, energetic, enthusiastic', Color(0xFFF97316), Color(0xFFFFEDD5), Color(0xFF9A3412), Color(0xFFFB923C), Color(0xFF2B1B10)),
  sadness('حزن', 'sad, heavy-hearted, softly sorrowful', Color(0xFF3B82F6), Color(0xFFDBEAFE), Color(0xFF1E40AF), Color(0xFF60A5FA), Color(0xFF121D33)),
  anger('غضب', 'angry, intense, frustrated', Color(0xFFEF4444), Color(0xFFFEE2E2), Color(0xFF991B1B), Color(0xFFF87171), Color(0xFF2E1414)),
  calm('هدوء', 'calm, soothing, reassuring', Color(0xFF10B981), Color(0xFFD1FAE5), Color(0xFF065F46), Color(0xFF34D399), Color(0xFF0F261E)),
  fear('خوف', 'fearful, anxious, trembling', Color(0xFF64748B), Color(0xFFE2E8F0), Color(0xFF334155), Color(0xFFCBD5E1), Color(0xFF1E2230)),
  surprise('دهشة', 'surprised, amazed', Color(0xFF06B6D4), Color(0xFFCFFAFE), Color(0xFF155E75), Color(0xFF22D3EE), Color(0xFF0E2429)),
  whisper('همس', 'whispering softly and intimately', Color(0xFF8B5CF6), Color(0xFFEDE9FE), Color(0xFF5B21B6), Color(0xFFC4B5FD), Color(0xFF221B3A));

  const Emotion(this.label, this.prompt, this.dotLight, this.bgLight, this.fgLight, this.dotDark, this.bgDark);

  final String label;
  final String prompt;
  final Color dotLight;
  final Color bgLight;
  final Color fgLight;
  final Color dotDark;
  final Color bgDark;

  Color dot(bool dark) => dark ? dotDark : dotLight;
  Color bg(bool dark) => dark ? bgDark : bgLight;
  Color fg(bool dark) => dark ? dotDark : fgLight;

  static Emotion byName(String? n) => Emotion.values.firstWhere((e) => e.name == n, orElse: () => Emotion.neutral);
}

enum Intensity {
  light('خفيف', 'slightly'),
  medium('متوسط', 'clearly'),
  strong('قوي', 'very strongly');

  const Intensity(this.label, this.prompt);
  final String label;
  final String prompt;

  static Intensity byName(String? n) => Intensity.values.firstWhere((e) => e.name == n, orElse: () => Intensity.medium);
}

enum Age {
  child('طفل', 'a child about 8 years old, high-pitched, playful and innocent'),
  young('شاب', 'a young person in their early twenties, fresh and lively'),
  adult('بالغ', 'an adult in their late thirties, confident and mature'),
  elder('مسن', 'an elderly person around 70, slower, slightly raspy and wise');

  const Age(this.label, this.prompt);
  final String label;
  final String prompt;

  static Age byName(String? n) => Age.values.firstWhere((e) => e.name == n, orElse: () => Age.adult);
}

enum Gender {
  male('رجل'),
  female('سيدة');

  const Gender(this.label);
  final String label;

  static Gender byName(String? n) => Gender.values.firstWhere((e) => e.name == n, orElse: () => Gender.male);
}

/// غرض الأداء (بيأثر على الإلقاء كله).
enum Purpose {
  ad('إعلان', 'a punchy commercial advertisement read'),
  documentary('وثائقي', 'a cinematic documentary narration'),
  story('قصصي', 'warm expressive storytelling'),
  podcast('بودكاست', 'a relaxed, conversational podcast'),
  news('إخباري', 'a neutral, professional news read'),
  education('تعليمي', 'a clear, steady educational explanation'),
  corporate('مؤسسي', 'a polished corporate presentation'),
  cartoon('كرتون', 'an animated cartoon character performance with playful exaggeration');

  const Purpose(this.label, this.prompt);
  final String label;
  final String prompt;

  static Purpose byName(String? n) => Purpose.values.firstWhere((e) => e.name == n, orElse: () => Purpose.story);
}
