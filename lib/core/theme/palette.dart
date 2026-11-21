import 'package:flutter/material.dart';

/// ألوان الثيمين (Lavender الفاتح و Neon الداكن) كـ ThemeExtension،
/// عشان كل ويدجت تاخد ألوانها من `context.palette` بدل ما نكتب ألوان ثابتة.
@immutable
class StudioPalette extends ThemeExtension<StudioPalette> {
  const StudioPalette({
    required this.isDark,
    required this.bgTop,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.hero,
    required this.heroShadow,
    required this.heroButton,
    required this.heroButtonText,
    required this.cta,
    required this.ctaText,
    required this.ctaShadow,
    required this.segment,
    required this.ghostLine,
    required this.track,
    required this.played,
    required this.ok,
    required this.okBg,
    required this.danger,
    required this.orb,
    required this.orbGlow,
    required this.cardShadow,
  });

  final bool isDark;
  final Color bgTop;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Gradient hero;
  final List<BoxShadow> heroShadow;
  final Gradient heroButton;
  final Color heroButtonText;
  final Gradient cta;
  final Color ctaText;
  final List<BoxShadow> ctaShadow;
  final Gradient segment;
  final Color ghostLine;
  final Color track;
  final Color played;
  final Color ok;
  final Color okBg;
  final Color danger;
  final Gradient orb;
  final List<BoxShadow> orbGlow;
  final List<BoxShadow> cardShadow;

  /// خلفية الشاشات: توهج من فوق وبعدين اللون الأساسي.
  Gradient get background => RadialGradient(
        center: const Alignment(0, -1.25),
        radius: 1.35,
        colors: [bgTop, bg],
        stops: const [0, 0.62],
      );

  static const light = StudioPalette(
    isDark: false,
    bgTop: Color(0xFFDCD1FF),
    bg: Color(0xFFF1EEFE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1EDFF),
    line: Color(0xFFECE7FB),
    text: Color(0xFF1F1A3D),
    muted: Color(0xFF6B6489),
    accent: Color(0xFF6C4DE6),
    hero: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF6C4DE6), Color(0xFF9B7BFF)],
    ),
    heroShadow: [BoxShadow(color: Color(0x526C4DE6), blurRadius: 40, offset: Offset(0, 18))],
    heroButton: LinearGradient(colors: [Color(0xFF2FD6B5), Color(0xFF66E8CF)]),
    heroButtonText: Color(0xFF0B3A31),
    cta: LinearGradient(colors: [Color(0xFF2FD6B5), Color(0xFF66E8CF)]),
    ctaText: Color(0xFF0B3A31),
    ctaShadow: [BoxShadow(color: Color(0x612FD6B5), blurRadius: 24, offset: Offset(0, 10))],
    segment: LinearGradient(colors: [Color(0xFF6C4DE6), Color(0xFF9B7BFF)]),
    ghostLine: Color(0xFFDCD4F7),
    track: Color(0xFFE4DEF7),
    played: Color(0xFF6C4DE6),
    ok: Color(0xFF047857),
    okBg: Color(0xFFE7F8F1),
    danger: Color(0xFFB91C1C),
    orb: RadialGradient(
      center: Alignment(0, -0.3),
      colors: [Color(0xFFE9DDFF), Color(0xFFA47BFF), Color(0xFF6C4DE6), Color(0xFF4B2FC0)],
      stops: [0, 0.32, 0.7, 1],
    ),
    orbGlow: [BoxShadow(color: Color(0x806C4DE6), blurRadius: 26, offset: Offset(0, 10))],
    cardShadow: [BoxShadow(color: Color(0x1A6C4DE6), blurRadius: 28, offset: Offset(0, 10))],
  );

  static const dark = StudioPalette(
    isDark: true,
    bgTop: Color(0xFF2B1866),
    bg: Color(0xFF0A0912),
    surface: Color(0xFF15131F),
    surface2: Color(0xFF221E33),
    line: Color(0xFF2A2640),
    text: Color(0xFFF3F1FA),
    muted: Color(0xFFA19CBB),
    accent: Color(0xFFB794FF),
    hero: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF3A1D8A), Color(0xFF6D3FE8), Color(0xFFA77BFF)],
      stops: [0, 0.55, 1],
    ),
    heroShadow: [BoxShadow(color: Color(0x597C4DFF), blurRadius: 44, offset: Offset(0, 18))],
    heroButton: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF1EAFF)]),
    heroButtonText: Color(0xFF3B1E9E),
    cta: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFA66BFF)]),
    ctaText: Color(0xFFFFFFFF),
    ctaShadow: [BoxShadow(color: Color(0x737C4DFF), blurRadius: 28, offset: Offset(0, 10))],
    segment: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFA66BFF)]),
    ghostLine: Color(0xFF3A3554),
    track: Color(0xFF2E2A44),
    played: Color(0xFFB794FF),
    ok: Color(0xFF34D399),
    okBg: Color(0xFF0F261E),
    danger: Color(0xFFF87171),
    orb: RadialGradient(
      center: Alignment(0, -0.3),
      colors: [Color(0xFFE9DDFF), Color(0xFFA47BFF), Color(0xFF6A3DF0), Color(0xFF2B1670)],
      stops: [0, 0.32, 0.66, 1],
    ),
    orbGlow: [BoxShadow(color: Color(0xD9966EFF), blurRadius: 30)],
    cardShadow: [],
  );

  @override
  StudioPalette copyWith() => this;

  @override
  StudioPalette lerp(ThemeExtension<StudioPalette>? other, double t) {
    if (other is! StudioPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension PaletteX on BuildContext {
  StudioPalette get palette => Theme.of(this).extension<StudioPalette>()!;
}
