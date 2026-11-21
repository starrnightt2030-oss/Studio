import 'catalog/emotions.dart';
import 'projects/models.dart';

class TemplateLine {
  const TemplateLine(this.text, [this.emotion = Emotion.neutral, this.intensity = Intensity.medium, this.sfx]);
  final String text;
  final Emotion emotion;
  final Intensity intensity;
  final String? sfx;
}

/// قوالب جاهزة: نص مكتوب بإحساس كل جملة + صوت + موسيقى مناسبين. المستخدم يعدّل الكلمات بس.
class ScriptTemplate {
  const ScriptTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.voiceId,
    this.musicId,
    this.lines = const [],
    this.story,
    this.targetSeconds,
  });

  final String id;
  final String title;
  final String subtitle;
  final ProjectType type;
  final String voiceId;
  final String? musicId;
  final List<TemplateLine> lines;

  /// للقصص: النص بيروح لشاشة توزيع الأدوار.
  final String? story;
  final int? targetSeconds;

  Project toProject() {
    final p = Project(title: title, type: type, dialectId: voiceId.split('_').first, voiceId: voiceId, musicId: musicId, targetSeconds: targetSeconds);
    p.segments = [for (final l in lines) Segment(text: l.text, emotion: l.emotion, intensity: l.intensity, sfx: l.sfx)];
    if (story != null) p.sourceText = story!;
    return p;
  }
}

class Templates {
  Templates._();

  static const all = <ScriptTemplate>[
    ScriptTemplate(
      id: 'ad30_eg',
      title: 'إعلان 30 ثانية (مصري)',
      subtitle: 'منتج أو مطعم · حماسي',
      type: ProjectType.voiceover,
      voiceId: 'egyptian_m_ad',
      musicId: 'ad_upbeat',
      targetSeconds: 30,
      lines: [
        TemplateLine('زهقت من [المشكلة] كل يوم؟', Emotion.surprise, Intensity.medium, 'whoosh'),
        TemplateLine('خلاص، [اسم المنتج] وصل!', Emotion.excitement, Intensity.strong, 'impact'),
        TemplateLine('[الميزة الأولى]، و[الميزة التانية]، وبسعر يفرّحك.', Emotion.joy),
        TemplateLine('وبيني وبينك… أول طلب عليه خصم ⟨وقفة⟩ [النسبة].', Emotion.whisper, Intensity.light),
        TemplateLine('اطلب دلوقتي من [المكان]. [اسم المنتج]… [الشعار].', Emotion.calm, Intensity.medium, 'ding'),
      ],
    ),
    ScriptTemplate(
      id: 'ad15_sa',
      title: 'إعلان 15 ثانية (خليجي)',
      subtitle: 'عرض سريع · سوشيال',
      type: ProjectType.voiceover,
      voiceId: 'saudi_f_ad',
      musicId: 'ad_upbeat',
      targetSeconds: 15,
      lines: [
        TemplateLine('عرض ما يتفوّت!', Emotion.excitement, Intensity.strong, 'riser'),
        TemplateLine('[اسم المنتج] الحين بخصم [النسبة] لفترة محدودة.', Emotion.joy),
        TemplateLine('حمّل التطبيق واطلب الحين.', Emotion.excitement, Intensity.medium, 'pop'),
      ],
    ),
    ScriptTemplate(
      id: 'app_promo',
      title: 'شرح تطبيق (فصحى)',
      subtitle: 'تعريف بالمزايا · مؤسسي',
      type: ProjectType.voiceover,
      voiceId: 'fusha_f_edu',
      musicId: 'corporate_inspire',
      targetSeconds: 45,
      lines: [
        TemplateLine('هل تبحث عن طريقة أسهل لـ[الهدف]؟', Emotion.calm),
        TemplateLine('نقدّم لك تطبيق [الاسم].', Emotion.joy, Intensity.light, 'ding'),
        TemplateLine('مع [الاسم] يمكنك [الميزة الأولى] بضغطة واحدة.', Emotion.neutral),
        TemplateLine('ومتابعة [الميزة الثانية] في أي وقت ومن أي مكان.', Emotion.neutral),
        TemplateLine('حمّل [الاسم] الآن مجاناً، وابدأ رحلتك اليوم.', Emotion.excitement, Intensity.light, 'success'),
      ],
    ),
    ScriptTemplate(
      id: 'yt_intro',
      title: 'مقدمة يوتيوب',
      subtitle: 'ترحيب بالقناة · مصري',
      type: ProjectType.voiceover,
      voiceId: 'egyptian_m_pod',
      musicId: 'corporate_inspire',
      lines: [
        TemplateLine('أهلاً بيكم في قناة [اسم القناة]!', Emotion.excitement, Intensity.medium, 'whoosh'),
        TemplateLine('النهارده هنتكلم عن حاجة مهمة جداً: [الموضوع].', Emotion.surprise, Intensity.light),
        TemplateLine('ما تنساش تعمل اشتراك وتفعّل الجرس ⟨وقفة⟩ وياللا بينا.', Emotion.joy),
      ],
    ),
    ScriptTemplate(
      id: 'doc_open',
      title: 'افتتاحية وثائقي',
      subtitle: 'سينمائي · فصحى',
      type: ProjectType.voiceover,
      voiceId: 'fusha_m_doc',
      musicId: 'drama_cinematic',
      lines: [
        TemplateLine('في قلب [المكان]… ⟨وقفة طويلة⟩ تبدأ حكاية لم يروها أحد من قبل.', Emotion.calm, Intensity.strong, 'riser'),
        TemplateLine('حكاية [الموضوع]، التي غيّرت كل شيء.', Emotion.sadness, Intensity.light),
        TemplateLine('هذه هي القصة الكاملة.', Emotion.calm, Intensity.medium, 'impact'),
      ],
    ),
    ScriptTemplate(
      id: 'kids_bedtime',
      title: 'قصة قبل النوم',
      subtitle: 'راوي وشخصيات · طفولي',
      type: ProjectType.story,
      voiceId: 'egyptian_f_story',
      musicId: 'calm_story',
      story: 'كان يا ما كان، في غابة خضرا جميلة، كان فيه أرنب صغير اسمه بندق.\n'
          'بندق كان بيحب يجري ويلعب طول اليوم.\n'
          'وفي يوم قابل السلحفاة العجوز وقال لها: "يا جدّة، تعالي نتسابق!"\n'
          'ضحكت السلحفاة وقالت: "ماشي يا بندق، بس الصبر مفتاح الفرج."\n'
          'جري بندق بسرعة، وبعدين نام تحت الشجرة.\n'
          'والسلحفاة فضلت ماشية بالراحة… لحد ما وصلت قبله!\n'
          'صحي بندق مستغرب وقال: "إزاي ده حصل؟!"\n'
          'ومن يومها، بندق اتعلم إن الشطارة مش بالسرعة بس، لكن بالصبر والاجتهاد.',
    ),
    ScriptTemplate(
      id: 'kids_cartoon',
      title: 'مشهد كرتوني',
      subtitle: 'شخصيات مرحة · مغامرة',
      type: ProjectType.story,
      voiceId: 'egyptian_m_cartoon',
      musicId: 'kids_playful',
      story: 'الراوي: في مدينة الألوان، صحي القط زعتر على صوت غريب.\n'
          'زعتر: "مين اللي بيعمل الدوشة دي الصبح بدري؟!"\n'
          'العصفورة لولو: "أنا يا زعتر! لقيت خريطة كنز!"\n'
          'زعتر: "كنز؟! ياللا بينا بسرعة!"\n'
          'الراوي: وبدأت أجمل مغامرة في حياتهم.',
    ),
  ];
}
