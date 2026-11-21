import 'dialects.dart';
import 'emotions.dart';

/// شخصية صوتية: اسم عربي + لهجة + نوع + عمر + غرض، مربوطة بصوت Gemini حقيقي مختلف.
class VoicePersona {
  const VoicePersona({
    required this.id,
    required this.name,
    required this.dialectId,
    required this.gender,
    required this.age,
    required this.purpose,
    required this.baseVoice,
    required this.description,
    required this.character,
  });

  final String id;
  final String name;
  final String dialectId;
  final Gender gender;
  final Age age;
  final Purpose purpose;

  /// اسم صوت Gemini المسبق (Puck, Kore, ...).
  final String baseVoice;
  final String description;

  /// وصف الشخصية بالإنجليزي للموديل.
  final String character;

  Dialect get dialect => Dialects.byId(dialectId);
  String get initial {
    final n = name.startsWith('عم ') || name.startsWith('أبو ') || name.startsWith('أم ') ? name.split(' ').last : name;
    return String.fromCharCode(n.runes.first);
  }
}

class _Archetype {
  const _Archetype(this.key, this.gender, this.age, this.purpose, this.voices, this.description, this.character);
  final String key;
  final Gender gender;
  final Age age;
  final Purpose purpose;

  /// بدائل للصوت الأساسي؛ بنختار منها حسب اللهجة عشان نزود التنوع.
  final List<String> voices;
  final String description;
  final String character;
}

class VoiceCatalog {
  VoiceCatalog._();

  /// أصوات Gemini الـ30 مع وصفها الرسمي.
  static const geminiVoices = <String, String>{
    'Zephyr': 'Bright', 'Puck': 'Upbeat', 'Charon': 'Informative', 'Kore': 'Firm', 'Fenrir': 'Excitable',
    'Leda': 'Youthful', 'Orus': 'Firm', 'Aoede': 'Breezy', 'Callirrhoe': 'Easy-going', 'Autonoe': 'Bright',
    'Enceladus': 'Breathy', 'Iapetus': 'Clear', 'Umbriel': 'Easy-going', 'Algieba': 'Smooth', 'Despina': 'Smooth',
    'Erinome': 'Clear', 'Algenib': 'Gravelly', 'Rasalgethi': 'Informative', 'Laomedeia': 'Upbeat', 'Achernar': 'Soft',
    'Alnilam': 'Firm', 'Schedar': 'Even', 'Gacrux': 'Mature', 'Pulcherrima': 'Forward', 'Achird': 'Friendly',
    'Zubenelgenubi': 'Casual', 'Vindemiatrix': 'Gentle', 'Sadachbia': 'Lively', 'Sadaltager': 'Knowledgeable', 'Sulafat': 'Warm',
  };

  static const _archetypes = <_Archetype>[
    // رجالة
    _Archetype('m_ad', Gender.male, Age.young, Purpose.ad, ['Puck', 'Fenrir', 'Sadachbia'], 'إعلاني سريع · طاقة عالية', 'an upbeat, charismatic commercial voice'),
    _Archetype('m_doc', Gender.male, Age.adult, Purpose.documentary, ['Charon', 'Rasalgethi', 'Orus'], 'وثائقي عميق · مؤثر', 'a deep, authoritative documentary narrator'),
    _Archetype('m_pod', Gender.male, Age.adult, Purpose.podcast, ['Iapetus', 'Achird', 'Umbriel'], 'بودكاست هادئ · قريب', 'a friendly, relaxed podcast host'),
    _Archetype('m_drama', Gender.male, Age.adult, Purpose.story, ['Orus', 'Algieba', 'Enceladus'], 'درامي عاطفي · عميق', 'an emotional dramatic actor'),
    _Archetype('m_corp', Gender.male, Age.adult, Purpose.corporate, ['Alnilam', 'Schedar', 'Sadaltager'], 'مؤسسي رسمي · واثق', 'a polished corporate presenter'),
    _Archetype('m_cartoon', Gender.male, Age.young, Purpose.cartoon, ['Fenrir', 'Puck', 'Zubenelgenubi'], 'كرتوني فكاهي · مبالغ', 'a funny, exaggerated cartoon character'),
    _Archetype('m_elder', Gender.male, Age.elder, Purpose.story, ['Algenib', 'Rasalgethi', 'Charon'], 'حكّاء كبير · حكيم', 'a wise old grandfather storyteller'),
    _Archetype('m_child', Gender.male, Age.child, Purpose.cartoon, ['Sadachbia', 'Puck', 'Fenrir'], 'طفل مرح · شقي', 'a playful little boy'),
    // ستات
    _Archetype('f_ad', Gender.female, Age.young, Purpose.ad, ['Zephyr', 'Autonoe', 'Laomedeia'], 'إعلانية مشرقة · نشيطة', 'a bright, energetic commercial voice'),
    _Archetype('f_story', Gender.female, Age.adult, Purpose.story, ['Sulafat', 'Aoede', 'Vindemiatrix'], 'راوية دافئة · قصصية', 'a warm, expressive storyteller'),
    _Archetype('f_pod', Gender.female, Age.young, Purpose.podcast, ['Despina', 'Callirrhoe', 'Aoede'], 'بودكاست طبيعي · ودود', 'a natural, friendly podcast co-host'),
    _Archetype('f_news', Gender.female, Age.adult, Purpose.news, ['Erinome', 'Kore', 'Pulcherrima'], 'إخبارية واضحة · رصينة', 'a clear, composed news anchor'),
    _Archetype('f_edu', Gender.female, Age.adult, Purpose.education, ['Kore', 'Achernar', 'Erinome'], 'تعليمية مفهومة · هادئة', 'a patient, clear teacher'),
    _Archetype('f_cartoon', Gender.female, Age.young, Purpose.cartoon, ['Laomedeia', 'Leda', 'Zephyr'], 'كرتونية خفيفة · لطيفة', 'a cute, bubbly cartoon character'),
    _Archetype('f_elder', Gender.female, Age.elder, Purpose.story, ['Gacrux', 'Vindemiatrix', 'Sulafat'], 'جدّة حنونة · حكيمة', 'a loving old grandmother'),
    _Archetype('f_child', Gender.female, Age.child, Purpose.cartoon, ['Leda', 'Laomedeia', 'Autonoe'], 'طفلة بريئة · مرحة', 'a sweet little girl'),
  ];

  /// أسماء لكل لهجة بنفس ترتيب الـ archetypes (8 رجالة ثم 8 ستات).
  static const _names = <String, List<String>>{
    'egyptian': ['مالك', 'يوسف', 'رامي', 'سيف', 'كريم', 'فارس', 'عم حسن', 'زياد', 'ليلى', 'مريم', 'سما', 'نورا', 'هبة', 'لوجين', 'تيتة فاطمة', 'جنى'],
    'saudi': ['راكان', 'ناصر', 'عبدالعزيز', 'فهد', 'محسن', 'فواز', 'أبو سعد', 'تركي', 'أفنان', 'هيا', 'منى', 'الجوهرة', 'بدور', 'لولو', 'أم سعد', 'ريم'],
    'khaleeji': ['حمد', 'سالم', 'خليفة', 'راشد', 'سعيد', 'بطي', 'أبو راشد', 'منصور', 'شما', 'موزة', 'عائشة', 'مريم', 'حصة', 'دانة', 'أم خليفة', 'ميثاء'],
    'levantine': ['جاد', 'ربيع', 'يوسف', 'ميلاد', 'سامر', 'بيبو', 'أبو صياح', 'كنان', 'رهف', 'لين', 'نور', 'ديما', 'رنا', 'ليليا', 'تيتا سعاد', 'جوري'],
    'lebanese': ['رالف', 'جورج', 'طوني', 'مارك', 'نبيل', 'شربل', 'أبو نجيب', 'إيلي', 'ريتا', 'نادين', 'كارلا', 'ماريا', 'هلا', 'ميرا', 'تيتا وداد', 'لارا'],
    'iraqi': ['مهند', 'علي', 'حيدر', 'مصطفى', 'عباس', 'ميمو', 'حجي كاظم', 'أمير', 'زهراء', 'سمر', 'نور', 'رسل', 'بتول', 'لولي', 'حجية أم علي', 'ملك'],
    'sudanese': ['محمد', 'الطيب', 'عثمان', 'مجتبى', 'حاتم', 'دودو', 'عم بشير', 'أواب', 'تسنيم', 'مناسك', 'هبة', 'سلمى', 'آمنة', 'سوسو', 'حبوبة نفيسة', 'ريان'],
    'yemeni': ['عمار', 'صالح', 'هشام', 'أصيل', 'فؤاد', 'حمود', 'العم أحمد', 'زكريا', 'سارة', 'أروى', 'بلقيس', 'هند', 'سماح', 'دودي', 'جدة صفية', 'رغد'],
    'moroccan': ['ياسين', 'أنس', 'مهدي', 'حمزة', 'رضا', 'زكرياء', 'با الحاج', 'آدم', 'سلمى', 'هاجر', 'سكينة', 'خديجة', 'إيمان', 'نونو', 'مي فاطنة', 'إسراء'],
    'algerian': ['قيس', 'أنور', 'حكيم', 'رياض', 'سفيان', 'جلول', 'عمي الطاهر', 'رامي', 'إيناس', 'ياسمين', 'أمال', 'ليندة', 'وفاء', 'لولا', 'ماما زهرة', 'ملاك'],
    'tunisian': ['أيمن', 'كريم', 'وليد', 'نزار', 'سامي', 'شوشو', 'عم الهادي', 'آدم', 'مريم', 'أميرة', 'إيمان', 'سيرين', 'ريم', 'بيبة', 'جدة عائشة', 'ياسمين'],
    'fusha': ['عمر', 'خالد', 'طارق', 'مازن', 'وليد', 'نبيل', 'الشيخ إبراهيم', 'سليم', 'رنا', 'ليلى', 'سلمى', 'هدى', 'أسماء', 'لمى', 'الجدة خديجة', 'نور'],
  };

  static final List<VoicePersona> all = _build();

  static List<VoicePersona> _build() {
    final out = <VoicePersona>[];
    for (var di = 0; di < Dialects.all.length; di++) {
      final d = Dialects.all[di];
      final names = _names[d.id]!;
      for (var ai = 0; ai < _archetypes.length; ai++) {
        final a = _archetypes[ai];
        out.add(VoicePersona(
          id: '${d.id}_${a.key}',
          name: names[ai],
          dialectId: d.id,
          gender: a.gender,
          age: a.age,
          purpose: a.purpose,
          baseVoice: a.voices[di % a.voices.length],
          description: a.description,
          character: a.character,
        ));
      }
    }
    return out;
  }

  static VoicePersona byId(String id) => all.firstWhere((v) => v.id == id, orElse: () => all.first);

  static List<VoicePersona> filter({String? dialectId, Gender? gender, Age? age}) => all
      .where((v) =>
          (dialectId == null || v.dialectId == dialectId) &&
          (gender == null || v.gender == gender) &&
          (age == null || v.age == age))
      .toList();

  /// أقرب صوت لمواصفات (بيستخدم في توزيع أصوات البودكاست تلقائياً).
  static VoicePersona bestMatch({required String dialectId, required Gender gender, Age? age, Set<String> avoid = const {}}) {
    final pool = filter(dialectId: dialectId, gender: gender);
    final exact = pool.where((v) => (age == null || v.age == age) && !avoid.contains(v.id)).toList();
    if (exact.isNotEmpty) return exact.first;
    final free = pool.where((v) => !avoid.contains(v.id)).toList();
    return free.isNotEmpty ? free.first : pool.first;
  }
}
