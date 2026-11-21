import '../catalog/dialects.dart';
import '../catalog/emotions.dart';
import '../catalog/voices.dart';

/// إعدادات الأداء اللي المستخدم بيتحكم فيها.
class VoiceControls {
  const VoiceControls({
    this.speed = 0.5,
    this.pitch = 0.5,
    this.warmth = 0.5,
    this.age,
    this.purpose,
  });

  /// 0..1 (0.5 = طبيعي)
  final double speed;
  final double pitch;
  final double warmth;

  /// لو null بناخد عمر/غرض الشخصية نفسها.
  final Age? age;
  final Purpose? purpose;

  VoiceControls copyWith({double? speed, double? pitch, double? warmth, Age? age, Purpose? purpose}) => VoiceControls(
        speed: speed ?? this.speed,
        pitch: pitch ?? this.pitch,
        warmth: warmth ?? this.warmth,
        age: age ?? this.age,
        purpose: purpose ?? this.purpose,
      );

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'pitch': pitch,
        'warmth': warmth,
        'age': age?.name,
        'purpose': purpose?.name,
      };

  factory VoiceControls.fromJson(Map? j) => j == null
      ? const VoiceControls()
      : VoiceControls(
          speed: (j['speed'] as num?)?.toDouble() ?? 0.5,
          pitch: (j['pitch'] as num?)?.toDouble() ?? 0.5,
          warmth: (j['warmth'] as num?)?.toDouble() ?? 0.5,
          age: j['age'] == null ? null : Age.byName(j['age'] as String),
          purpose: j['purpose'] == null ? null : Purpose.byName(j['purpose'] as String),
        );

  String get speedLabel => '${(0.75 + speed * 0.5).toStringAsFixed(2)}×';
  String get pitchLabel {
    final v = ((pitch - 0.5) * 6).round();
    return v > 0 ? '+$v' : '$v';
  }

  String get warmthLabel => '${(warmth * 100).round()}%';
}

/// بيبني "توجيه الأداء" اللي بيتبعت للموديل جنب النص (مش جوّه النص).
class StyleBuilder {
  StyleBuilder._();

  static String _band(double v, List<String> words) {
    if (v < 0.2) return words[0];
    if (v < 0.42) return words[1];
    if (v <= 0.58) return words[2];
    if (v <= 0.8) return words[3];
    return words[4];
  }

  /// وصف الإحساس بكلمات قصيرة للموديل.
  static String emotionDirection(Emotion emotion, Intensity intensity) {
    if (emotion == Emotion.neutral) return 'neutral and natural';
    if (emotion == Emotion.whisper) return 'whispering ${intensity == Intensity.strong ? 'very quietly' : 'softly'}';
    return '${intensity.prompt} ${emotion.prompt}';
  }

  /// التوجيه الثابت للصوت (الشخصية، العمر، الغرض، السرعة، الطبقة، اللهجة) من غير الإحساس.
  static String base({required VoicePersona persona, required VoiceControls controls, String? dialectId}) {
    final d = Dialects.byId(dialectId ?? persona.dialectId);
    final age = controls.age ?? persona.age;
    final purpose = controls.purpose ?? persona.purpose;
    final who = persona.gender == Gender.male ? 'male' : 'female';
    final pace = _band(controls.speed, ['very slow', 'slightly slow', 'natural', 'slightly fast', 'fast']);
    final pitch = _band(controls.pitch, ['much lower', 'slightly lower', 'natural', 'slightly higher', 'much higher']);
    final warmth = _band(controls.warmth, ['crisp and bright', 'clean', 'balanced', 'warm', 'deep, rich and warm']);
    return [
      'Voice: $who, ${age.prompt}; ${persona.character}.',
      'Delivery: ${purpose.prompt}.',
      'Pace: $pace. Pitch: $pitch. Timbre: $warmth.',
      d.ttsHint,
    ].join(' ');
  }

  static String build({
    required VoicePersona persona,
    required Emotion emotion,
    required Intensity intensity,
    required VoiceControls controls,
    String? dialectId,
    String? extra,
  }) {
    return [
      base(persona: persona, controls: controls, dialectId: dialectId),
      'Emotion: ${emotionDirection(emotion, intensity)}.',
      if (extra != null && extra.trim().isNotEmpty) extra.trim(),
    ].join(' ');
  }
}

/// تاجات الأداء اللي المستخدم بيدخلها في النص.
class PerformanceTags {
  PerformanceTags._();

  static const map = <String, String>{
    '⟨وقفة⟩': '<short pause>',
    '⟨وقفة طويلة⟩': '<long pause>',
    '⟨ضحكة⟩': '<laugh>',
    '⟨تنهيدة⟩': '<sigh>',
    '⟨كحة⟩': '<cough>',
  };

  /// للـ API الجديد (Interactions) اللي بيفهم التاجات.
  static String toApi(String text) {
    var t = text;
    map.forEach((k, v) => t = t.replaceAll(k, ' $v '));
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// للـ API القديم: الوقفات تبقى نقط، والباقي يتشال عشان ما يتقريش بصوت عالي.
  static String toPlain(String text) {
    var t = text
        .replaceAll('⟨وقفة طويلة⟩', ' … … ')
        .replaceAll('⟨وقفة⟩', ' … ');
    t = t.replaceAll(RegExp(r'⟨[^⟩]*⟩'), ' ');
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String stripAll(String text) => text.replaceAll(RegExp(r'⟨[^⟩]*⟩'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}
