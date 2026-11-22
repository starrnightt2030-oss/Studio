import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_db.dart';

/// محرك الصوت.
enum TtsEngine {
  auto('تلقائي', 'Gemini، ولو الحصة خلصت يسألك تكمّل بـ Azure'),
  gemini('Gemini', 'أحسن مشاعر وتحكم'),
  azure('Azure', 'أصوات لهجات أصلية · نصف مليون حرف مجاناً شهرياً');

  const TtsEngine(this.label, this.hint);
  final String label;
  final String hint;
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.offlineFallback = true,
    this.ttsModel,
    this.textModel,
    this.gapMs = 250,
    this.engine = TtsEngine.auto,
  });

  final TtsEngine engine;

  final ThemeMode themeMode;

  /// لو Gemini فشل (حصة خلصت أو مفيش نت) نكمّل بصوت الجهاز.
  final bool offlineFallback;

  /// موديل الصوت المختار يدوياً (null = اختيار تلقائي لأحسن موديل متاح).
  final String? ttsModel;

  /// موديل النص (تحويل اللهجة، البودكاست، التفريغ).
  final String? textModel;

  /// المسافة بين الجمل في الملف النهائي.
  final int gapMs;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? offlineFallback,
    String? ttsModel,
    bool clearTtsModel = false,
    String? textModel,
    bool clearTextModel = false,
    int? gapMs,
    TtsEngine? engine,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        offlineFallback: offlineFallback ?? this.offlineFallback,
        ttsModel: clearTtsModel ? null : (ttsModel ?? this.ttsModel),
        textModel: clearTextModel ? null : (textModel ?? this.textModel),
        gapMs: gapMs ?? this.gapMs,
        engine: engine ?? this.engine,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = LocalDb.settings;
    return AppSettings(
      themeMode: ThemeMode.values[(s.get('themeMode', defaultValue: 0) as int).clamp(0, 2)],
      offlineFallback: s.get('offlineFallback', defaultValue: true) as bool,
      ttsModel: s.get('ttsModel') as String?,
      textModel: s.get('textModel') as String?,
      gapMs: s.get('gapMs', defaultValue: 250) as int,
      engine: TtsEngine.values.firstWhere((e) => e.name == s.get('engine'), orElse: () => TtsEngine.auto),
    );
  }

  Future<void> _save() async {
    final s = LocalDb.settings;
    await s.put('themeMode', state.themeMode.index);
    await s.put('offlineFallback', state.offlineFallback);
    await s.put('ttsModel', state.ttsModel);
    await s.put('textModel', state.textModel);
    await s.put('gapMs', state.gapMs);
    await s.put('engine', state.engine.name);
  }

  Future<void> setTheme(ThemeMode m) async {
    state = state.copyWith(themeMode: m);
    await _save();
  }

  Future<void> setOfflineFallback(bool v) async {
    state = state.copyWith(offlineFallback: v);
    await _save();
  }

  Future<void> setTtsModel(String? m) async {
    state = m == null ? state.copyWith(clearTtsModel: true) : state.copyWith(ttsModel: m);
    await _save();
  }

  Future<void> setTextModel(String? m) async {
    state = m == null ? state.copyWith(clearTextModel: true) : state.copyWith(textModel: m);
    await _save();
  }

  Future<void> setEngine(TtsEngine e) async {
    state = state.copyWith(engine: e);
    await _save();
  }

  Future<void> setGap(int ms) async {
    state = state.copyWith(gapMs: ms);
    await _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
