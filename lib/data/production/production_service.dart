import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/settings/settings.dart';
import '../../core/storage/local_db.dart';
import '../catalog/voices.dart';
import '../gemini/style_builder.dart';
import '../gemini/tts_service.dart';
import '../projects/models.dart';

class ProductionProgress {
  const ProductionProgress(this.done, this.total, this.message);
  final int done;
  final int total;
  final String message;
  double get fraction => total == 0 ? 0 : done / total;
}

/// بيحوّل مشروع كامل لصوت: جملة جملة، مع كاش، وبعدين يدمجهم في ملف واحد.
class ProductionService {
  ProductionService(this.tts, this.settings);
  final TtsService tts;
  final AppSettings settings;

  VoicePersona personaFor(Project p, Segment s) {
    if (s.speakerId != null) {
      for (final sp in p.speakers) {
        if (sp.id == s.speakerId) return VoiceCatalog.byId(sp.voiceId);
      }
    }
    return VoiceCatalog.byId(p.voiceId);
  }

  TtsRequest requestFor(Project p, Segment s) {
    final persona = personaFor(p, s);
    final controls = p.type == ProjectType.podcast ? VoiceControls(speed: p.controls.speed, warmth: p.controls.warmth) : p.controls;
    return TtsRequest(
      text: s.text,
      voice: persona.baseVoice,
      locale: persona.dialect.locale,
      style: StyleBuilder.build(
        persona: persona,
        emotion: s.emotion,
        intensity: s.intensity,
        controls: controls,
        dialectId: p.dialectId,
      ),
    );
  }

  Future<Uint8List> segment(Project p, Segment s, {bool force = false}) async {
    final wav = await tts.synthesize(requestFor(p, s), useCache: !force);
    s.audioKey = TtsService.cacheKey(await tts.resolveModel(), requestFor(p, s));
    return wav;
  }

  /// ينتج المشروع كله. الجمل اللي اتولدت قبل كده بنفس الإعدادات بتيجي من الكاش فوراً.
  Future<Uint8List> produce(Project p, {void Function(ProductionProgress)? onProgress, bool Function()? cancelled}) async {
    final segs = p.segments.where((s) => s.text.trim().isNotEmpty).toList();
    if (segs.isEmpty) throw const StudioException('اكتب نص الأول.');
    final parts = <Uint8List>[];
    for (var i = 0; i < segs.length; i++) {
      if (cancelled?.call() ?? false) throw const StudioException('اتلغى الإنتاج.', code: 'cancelled');
      onProgress?.call(ProductionProgress(i, segs.length, 'جاري توليد الجملة ${i + 1} من ${segs.length}…'));
      parts.add(await segment(p, segs[i]));
    }
    onProgress?.call(ProductionProgress(segs.length, segs.length, 'جاري دمج الملف النهائي…'));
    final master = Wav.concat(parts, gapMs: settings.gapMs);
    final key = 'master_${p.id}';
    await LocalDb.writeAudio(key, master);
    p.masterKey = key;
    p.durationMs = Wav.durationOf(master).inMilliseconds;
    return master;
  }

  /// بعد إعادة توليد جملة واحدة: نعيد الدمج من الكاش بس.
  Future<Uint8List?> remix(Project p) async {
    final parts = <Uint8List>[];
    for (final s in p.segments.where((s) => s.text.trim().isNotEmpty)) {
      final b = s.audioKey == null ? null : LocalDb.readAudio(s.audioKey!);
      if (b == null) return null;
      parts.add(b);
    }
    if (parts.isEmpty) return null;
    final master = Wav.concat(parts, gapMs: settings.gapMs);
    final key = 'master_${p.id}';
    await LocalDb.writeAudio(key, master);
    p.masterKey = key;
    p.durationMs = Wav.durationOf(master).inMilliseconds;
    return master;
  }
}

final productionProvider = Provider<ProductionService?>((ref) {
  final tts = ref.watch(ttsServiceProvider);
  if (tts == null) return null;
  return ProductionService(tts, ref.watch(settingsProvider));
});
