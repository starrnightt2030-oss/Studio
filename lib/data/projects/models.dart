import 'package:uuid/uuid.dart';

import '../catalog/emotions.dart';
import '../gemini/style_builder.dart';

const _uuid = Uuid();
String newId() => _uuid.v4().substring(0, 12);

enum ProjectType {
  voiceover('تعليق صوتي'),
  audiobook('كتاب صوتي'),
  podcast('بودكاست'),
  story('قصة أطفال');

  /// أنواع فيها أكتر من متحدث (شاشة الأدوار).
  bool get multiVoice => this == podcast || this == story;

  const ProjectType(this.label);
  final String label;
}

class Segment {
  Segment({
    String? id,
    required this.text,
    this.emotion = Emotion.neutral,
    this.intensity = Intensity.medium,
    this.speakerId,
    this.audioKey,
    this.sfx,
  }) : id = id ?? newId();

  final String id;
  String text;
  Emotion emotion;
  Intensity intensity;

  /// في البودكاست: مين اللي بيتكلم.
  String? speakerId;

  /// مفتاح الصوت المتولّد في الكاش (null = لسه ما اتولدش أو اتعدّل).
  String? audioKey;

  /// مؤثر صوتي قبل الجملة (id من مكتبة المؤثرات).
  String? sfx;

  Segment copy() => Segment(id: id, text: text, emotion: emotion, intensity: intensity, speakerId: speakerId, audioKey: audioKey, sfx: sfx);

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'emotion': emotion.name,
        'intensity': intensity.name,
        'speakerId': speakerId,
        'audioKey': audioKey,
        'sfx': sfx,
      };

  factory Segment.fromJson(Map j) => Segment(
        id: j['id'] as String?,
        text: (j['text'] ?? '') as String,
        emotion: Emotion.byName(j['emotion'] as String?),
        intensity: Intensity.byName(j['intensity'] as String?),
        speakerId: j['speakerId'] as String?,
        audioKey: j['audioKey'] as String?,
        sfx: j['sfx'] as String?,
      );
}

class Speaker {
  Speaker({String? id, required this.name, required this.role, required this.voiceId}) : id = id ?? newId();
  final String id;
  String name;
  String role;
  String voiceId;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role, 'voiceId': voiceId};
  factory Speaker.fromJson(Map j) =>
      Speaker(id: j['id'] as String?, name: j['name'] as String, role: (j['role'] ?? '') as String, voiceId: j['voiceId'] as String);
}

class Project {
  Project({
    String? id,
    required this.title,
    required this.type,
    required this.dialectId,
    required this.voiceId,
    this.controls = const VoiceControls(),
    List<Segment>? segments,
    List<Speaker>? speakers,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.masterKey,
    this.durationMs = 0,
    this.sourceText = '',
    this.musicId,
    this.musicVolume = 0.25,
    this.duck = true,
    this.voiceKey,
    this.targetSeconds,
  })  : id = id ?? newId(),
        segments = segments ?? [],
        speakers = speakers ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  ProjectType type;
  String dialectId;
  String voiceId;
  VoiceControls controls;
  List<Segment> segments;
  List<Speaker> speakers;
  final DateTime createdAt;
  DateTime updatedAt;

  /// مفتاح الملف النهائي المدموج.
  String? masterKey;
  int durationMs;

  /// النص الأصلي (للبودكاست).
  String sourceText;

  /// موسيقى الخلفية (null = من غير موسيقى).
  String? musicId;
  double musicVolume;

  /// الموسيقى توطى لوحدها وقت الكلام.
  bool duck;

  /// الصوت لوحده قبل الموسيقى والمؤثرات.
  String? voiceKey;

  /// المدة المطلوبة بالثواني (للإعلانات).
  int? targetSeconds;

  bool get hasMix => musicId != null || segments.any((s) => s.sfx != null);

  bool get isGenerated => masterKey != null && segments.every((s) => s.audioKey != null);

  Project copy() => Project.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'dialectId': dialectId,
        'voiceId': voiceId,
        'controls': controls.toJson(),
        'segments': segments.map((s) => s.toJson()).toList(),
        'speakers': speakers.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'masterKey': masterKey,
        'durationMs': durationMs,
        'sourceText': sourceText,
        'musicId': musicId,
        'musicVolume': musicVolume,
        'duck': duck,
        'voiceKey': voiceKey,
        'targetSeconds': targetSeconds,
      };

  factory Project.fromJson(Map j) => Project(
        id: j['id'] as String,
        title: (j['title'] ?? 'مشروع') as String,
        type: ProjectType.values.firstWhere((t) => t.name == j['type'], orElse: () => ProjectType.voiceover),
        dialectId: (j['dialectId'] ?? 'egyptian') as String,
        voiceId: (j['voiceId'] ?? 'egyptian_m_ad') as String,
        controls: VoiceControls.fromJson(j['controls'] as Map?),
        segments: [for (final s in (j['segments'] as List? ?? const [])) Segment.fromJson(s as Map)],
        speakers: [for (final s in (j['speakers'] as List? ?? const [])) Speaker.fromJson(s as Map)],
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] ?? 0) as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((j['updatedAt'] ?? 0) as int),
        masterKey: j['masterKey'] as String?,
        durationMs: (j['durationMs'] ?? 0) as int,
        sourceText: (j['sourceText'] ?? '') as String,
        musicId: j['musicId'] as String?,
        musicVolume: (j['musicVolume'] as num?)?.toDouble() ?? 0.25,
        duck: (j['duck'] ?? true) as bool,
        voiceKey: j['voiceKey'] as String?,
        targetSeconds: j['targetSeconds'] as int?,
      );
}
