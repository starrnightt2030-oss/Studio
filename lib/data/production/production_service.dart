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

/// مقطع = كذا جملة ورا بعض بنفس الصوت، بيتولدوا في طلب واحد وكل جملة بإحساسها.
class Chunk {
  Chunk(this.persona, this.segments, this.request);
  final VoicePersona persona;
  final List<Segment> segments;
  final TtsRequest request;
  String get key => TtsService.cacheKey(request);
}

/// بيحوّل مشروع كامل لصوت: مقطع مقطع، مع كاش، وبعدين يدمجهم في ملف واحد.
class ProductionService {
  ProductionService(this.tts, this.settings);
  final TtsService tts;
  final AppSettings settings;

  /// أقصى حجم للمقطع الواحد. أكبر = طلبات أقل، أصغر = إعادة توليد أرخص لو عدّلت جملة.
  static const maxChunkChars = 700;
  static const maxChunkSentences = 8;

  VoicePersona personaFor(Project p, Segment s) {
    if (s.speakerId != null) {
      for (final sp in p.speakers) {
        if (sp.id == s.speakerId) return VoiceCatalog.byId(sp.voiceId);
      }
    }
    return VoiceCatalog.byId(p.voiceId);
  }

  VoiceControls _controls(Project p) =>
      p.type == ProjectType.podcast ? VoiceControls(speed: p.controls.speed, warmth: p.controls.warmth) : p.controls;

  TtsRequest requestFor(Project p, VoicePersona persona, List<Segment> segs) => TtsRequest(
        voice: persona.baseVoice,
        locale: persona.dialect.locale,
        baseStyle: StyleBuilder.base(persona: persona, controls: _controls(p), dialectId: p.dialectId),
        spans: [for (final s in segs) TtsSpan(s.text, StyleBuilder.emotionDirection(s.emotion, s.intensity))],
      );

  /// يقسّم المشروع لمقاطع.
  List<Chunk> plan(Project p) {
    final segs = p.segments.where((s) => s.text.trim().isNotEmpty).toList();
    final chunks = <Chunk>[];
    var cur = <Segment>[];
    VoicePersona? curPersona;
    var chars = 0;
    void flush() {
      if (cur.isEmpty) return;
      final persona = curPersona!;
      chunks.add(Chunk(persona, cur, requestFor(p, persona, cur)));
      cur = <Segment>[];
      chars = 0;
    }

    for (final s in segs) {
      final persona = personaFor(p, s);
      final len = s.text.length;
      if (cur.isNotEmpty && (persona.id != curPersona!.id || chars + len > maxChunkChars || cur.length >= maxChunkSentences)) {
        flush();
      }
      curPersona = persona;
      cur.add(s);
      chars += len;
    }
    flush();
    return chunks;
  }

  /// معاينة جملة واحدة (طلب لوحده — مش بيأثر على الملف النهائي).
  Future<Uint8List> segment(Project p, Segment s, {bool force = false}) {
    final persona = personaFor(p, s);
    return tts.synthesize(requestFor(p, persona, [s]), useCache: !force);
  }

  /// ينتج المشروع كله. المقاطع اللي اتولدت قبل كده بنفس الإعدادات بتيجي من الكاش فوراً.
  Future<Uint8List> produce(Project p, {void Function(ProductionProgress)? onProgress, bool Function()? cancelled}) async {
    final chunks = plan(p);
    if (chunks.isEmpty) throw const StudioException('اكتب نص الأول.');
    final total = chunks.length;
    final parts = <Uint8List>[];
    var sentence = 0;
    for (var i = 0; i < total; i++) {
      if (cancelled?.call() ?? false) throw const StudioException('اتلغى الإنتاج.', code: 'cancelled');
      final c = chunks[i];
      final from = sentence + 1;
      final to = sentence + c.segments.length;
      final label = 'المقطع ${i + 1} من $total (الجمل $from–$to)';
      onProgress?.call(ProductionProgress(i, total, 'جاري توليد $label…'));
      final wav = await tts.synthesize(
        c.request,
        onStatus: (st) => onProgress?.call(ProductionProgress(i, total, '$label\n$st')),
      );
      for (final s in c.segments) {
        s.audioKey = c.key;
      }
      parts.add(wav);
      sentence = to;
    }
    onProgress?.call(ProductionProgress(total, total, 'جاري دمج الملف النهائي…'));
    return _saveMaster(p, parts);
  }

  Future<Uint8List> _saveMaster(Project p, List<Uint8List> parts) async {
    final master = Wav.concat(parts, gapMs: settings.gapMs);
    final key = 'master_${p.id}';
    await LocalDb.writeAudio(key, master);
    p.masterKey = key;
    p.durationMs = Wav.durationOf(master).inMilliseconds;
    return master;
  }

  /// إعادة الدمج من الكاش بس (من غير أي طلب). بيرجّع null لو فيه مقطع ناقص.
  Future<Uint8List?> remix(Project p) async {
    final parts = <Uint8List>[];
    for (final c in plan(p)) {
      final b = LocalDb.readAudio(c.key);
      if (b == null) return null;
      for (final s in c.segments) {
        s.audioKey = c.key;
      }
      parts.add(b);
    }
    if (parts.isEmpty) return null;
    return _saveMaster(p, parts);
  }

  /// نسخة جديدة من المقطع اللي فيه الجملة دي، وبعدين إعادة دمج.
  Future<Uint8List?> regenerate(Project p, Segment s, {void Function(String)? onStatus}) async {
    for (final c in plan(p)) {
      if (c.segments.any((x) => x.id == s.id)) {
        await tts.synthesize(c.request, useCache: false, onStatus: onStatus);
        break;
      }
    }
    return remix(p);
  }

  /// بداية كل جملة في الملف النهائي (تقريبية جوه المقطع، حسب طول الجملة).
  Map<String, Duration> starts(Project p) {
    final out = <String, Duration>{};
    final gap = Duration(milliseconds: settings.gapMs);
    var at = Duration.zero;
    for (final c in plan(p)) {
      final b = LocalDb.readAudio(c.key);
      if (b == null) break;
      final dur = Wav.durationOf(b);
      final totalChars = c.segments.fold<int>(0, (a, s) => a + s.text.length).clamp(1, 1 << 30);
      var inner = Duration.zero;
      for (final s in c.segments) {
        out[s.id] = at + inner;
        inner += dur * (s.text.length / totalChars);
      }
      at += dur + gap;
    }
    return out;
  }
}

final productionProvider = Provider<ProductionService?>((ref) {
  final tts = ref.watch(ttsServiceProvider);
  if (tts == null) return null;
  return ProductionService(tts, ref.watch(settingsProvider));
});
