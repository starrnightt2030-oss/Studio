/// اللهجات المدعومة. `ttsHint` بيتبعت للموديل كتوجيه نطق، و`rewriteGuide` بيتستخدم
/// لما المستخدم يطلب "حوّل النص للهجة".
class Dialect {
  const Dialect({
    required this.id,
    required this.title,
    required this.short,
    required this.locale,
    required this.ttsHint,
    required this.rewriteGuide,
  });

  final String id;
  final String title;
  final String short;
  final String locale;
  final String ttsHint;
  final String rewriteGuide;
}

class Dialects {
  Dialects._();

  static const all = <Dialect>[
    Dialect(
      id: 'egyptian',
      title: 'اللهجة المصرية',
      short: 'مصري',
      locale: 'ar-EG',
      ttsHint: 'Speak in natural Cairene Egyptian Arabic. Pronounce ج as a hard "g" and ق mostly as a glottal stop, with relaxed Egyptian rhythm and intonation.',
      rewriteGuide: 'العامية المصرية القاهرية الدارجة (عشان، كده، إيه، مفيش، دلوقتي).',
    ),
    Dialect(
      id: 'saudi',
      title: 'اللهجة السعودية',
      short: 'سعودي',
      locale: 'ar-SA',
      ttsHint: 'Speak in natural Saudi Arabic (Najdi/Hejazi urban), clear and composed, with authentic Saudi prosody.',
      rewriteGuide: 'اللهجة السعودية البيضاء المفهومة (وش، ليش، الحين، زين، مرة).',
    ),
    Dialect(
      id: 'khaleeji',
      title: 'اللهجة الخليجية',
      short: 'خليجي',
      locale: 'ar-AE',
      ttsHint: 'Speak in neutral Gulf (Khaleeji) Arabic as spoken in the UAE and Kuwait, warm and clear.',
      rewriteGuide: 'الخليجي الأبيض (شلونك، وايد، الحين، زين، يالله).',
    ),
    Dialect(
      id: 'levantine',
      title: 'اللهجة الشامية',
      short: 'شامي',
      locale: 'ar-SY',
      ttsHint: 'Speak in Syrian/Levantine Arabic with soft melodic Damascene intonation.',
      rewriteGuide: 'الشامي الدمشقي (شو، هيك، كتير، هلق، منيح، كرمال).',
    ),
    Dialect(
      id: 'lebanese',
      title: 'اللهجة اللبنانية',
      short: 'لبناني',
      locale: 'ar-LB',
      ttsHint: 'Speak in urban Beirut Lebanese Arabic, light, elegant and musical.',
      rewriteGuide: 'اللبناني البيروتي (هلق، كتير، شو، كيفك، أكيد، ميرسي).',
    ),
    Dialect(
      id: 'iraqi',
      title: 'اللهجة العراقية',
      short: 'عراقي',
      locale: 'ar-IQ',
      ttsHint: 'Speak in Baghdadi Iraqi Arabic, deep and expressive, with authentic Iraqi intonation (ك often as "ch").',
      rewriteGuide: 'العراقي البغدادي (شلونك، هواية، هسه، شكو، زين).',
    ),
    Dialect(
      id: 'sudanese',
      title: 'اللهجة السودانية',
      short: 'سوداني',
      locale: 'ar-SD',
      ttsHint: 'Speak in Sudanese Arabic (Khartoum), calm and warm, with Sudanese qaf as "g".',
      rewriteGuide: 'السوداني الدارج الخفيف (هسه، زول، شديد، ياخي، تمام).',
    ),
    Dialect(
      id: 'yemeni',
      title: 'اللهجة اليمنية',
      short: 'يمني',
      locale: 'ar-YE',
      ttsHint: 'Speak in urban Sanaani Yemeni Arabic, clear and friendly, without Gulf elongation.',
      rewriteGuide: 'اليمني المدني الأبيض (الحين، كذا، عاد، نشوف، تمام).',
    ),
    Dialect(
      id: 'moroccan',
      title: 'اللهجة المغربية',
      short: 'مغربي',
      locale: 'ar-MA',
      ttsHint: 'Speak in Moroccan Darija (Casablanca/Rabat), natural fast-flowing rhythm.',
      rewriteGuide: 'الدارجة المغربية المفهومة (واش، بزاف، دابا، مزيان، شنو).',
    ),
    Dialect(
      id: 'algerian',
      title: 'اللهجة الجزائرية',
      short: 'جزائري',
      locale: 'ar-DZ',
      ttsHint: 'Speak in Algerian Darja (Algiers), lively and natural.',
      rewriteGuide: 'الدارجة الجزائرية العاصمية (واش، بزاف، دروك، مليح، كيفاش).',
    ),
    Dialect(
      id: 'tunisian',
      title: 'اللهجة التونسية',
      short: 'تونسي',
      locale: 'ar-TN',
      ttsHint: 'Speak in Tunisian Arabic (Tunis), light and rhythmic.',
      rewriteGuide: 'الدارجة التونسية (برشا، توا، باهي، شنوة، علاش).',
    ),
    Dialect(
      id: 'fusha',
      title: 'الفصحى',
      short: 'فصحى',
      locale: 'ar',
      ttsHint: 'Speak in Modern Standard Arabic with correct, clear pronunciation and natural case endings where appropriate.',
      rewriteGuide: 'العربية الفصحى المعاصرة السليمة.',
    ),
  ];

  static Dialect byId(String id) => all.firstWhere((d) => d.id == id, orElse: () => all.first);
}
