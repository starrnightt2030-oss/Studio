import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../gemini/style_builder.dart';

/// صوت الجهاز (بدون إنترنت) كخطة احتياطية — للاستماع فقط، مش للتصدير.
class OfflineSpeaker {
  final _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init(String locale) async {
    if (!_ready) {
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    }
    final langs = (await _tts.getLanguages as List?)?.map((e) => e.toString()).toList() ?? const [];
    final pick = langs.contains(locale)
        ? locale
        : langs.firstWhere((l) => l.toLowerCase().startsWith('ar'), orElse: () => 'ar');
    await _tts.setLanguage(pick);
  }

  Future<void> speak(String text, {String locale = 'ar', double rate = 0.5, double pitch = 1.0}) async {
    await _init(locale);
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.speak(PerformanceTags.stripAll(text));
  }

  Future<void> speakAll(List<String> lines, {String locale = 'ar'}) async {
    for (final l in lines) {
      await speak(l, locale: locale);
    }
  }

  Future<void> stop() => _tts.stop();
}

final offlineSpeakerProvider = Provider<OfflineSpeaker>((ref) => OfflineSpeaker());
