import 'package:flutter/material.dart';

import 'palette.dart';

class Fonts {
  static const display = 'Alexandria';
  static const body = 'Almarai';
  static const latin = 'Sora';
  static const poster = 'BebasNeue';
}

class AppTheme {
  static ThemeData light() => _build(StudioPalette.light, Brightness.light);
  static ThemeData dark() => _build(StudioPalette.dark, Brightness.dark);

  static ThemeData _build(StudioPalette p, Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C4DE6),
      brightness: b,
    ).copyWith(
      primary: p.accent,
      surface: p.surface,
      onSurface: p.text,
      error: p.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      fontFamily: Fonts.body,
      extensions: [p],
      splashFactory: InkRipple.splashFactory,
    );

    TextStyle d(double size, FontWeight w) =>
        TextStyle(fontFamily: Fonts.display, fontSize: size, fontWeight: w, color: p.text, height: 1.35);
    TextStyle t(double size, FontWeight w, [Color? c]) =>
        TextStyle(fontFamily: Fonts.body, fontSize: size, fontWeight: w, color: c ?? p.text, height: 1.6);

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: d(28, FontWeight.w800),
        headlineMedium: d(24, FontWeight.w700),
        headlineSmall: d(21, FontWeight.w700),
        titleLarge: d(18, FontWeight.w700),
        titleMedium: d(16, FontWeight.w600),
        titleSmall: d(14, FontWeight.w600),
        bodyLarge: t(16, FontWeight.w400),
        bodyMedium: t(14, FontWeight.w400),
        bodySmall: t(12, FontWeight.w400, p.muted),
        labelLarge: d(15, FontWeight.w600),
        labelMedium: t(12.5, FontWeight.w700),
        labelSmall: t(11, FontWeight.w400, p.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.muted, fontFamily: Fonts.body),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.accent, width: 1.5)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.track,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.15),
        trackHeight: 5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : p.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.track),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? const Color(0xFF2A2640) : const Color(0xFF1F1A3D),
        contentTextStyle: const TextStyle(fontFamily: Fonts.body, color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.track),
      dividerColor: p.line,
    );
  }
}
