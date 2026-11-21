import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/audio/player.dart';
import '../../core/audio/wav.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/voices.dart';
import '../../data/production/production_service.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  Project? _p;
  Uint8List? _master;
  List<double> _peaks = const [];
  final _starts = <String, Duration>{};
  String? _regen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = ref.read(projectsProvider.notifier).byId(widget.projectId)?.copy();
    if (p == null) return;
    var m = p.masterKey == null ? null : LocalDb.readAudio(p.masterKey!);
    if (m == null) {
      final prod = ref.read(productionProvider);
      m = await prod?.remix(p);
      if (m != null) await ref.read(projectsProvider.notifier).save(p);
    }
    _computeStarts(p);
    if (!mounted) return;
    setState(() {
      _p = p;
      _master = m;
      _peaks = m == null ? const [] : Wav.peaks(m, buckets: 56);
    });
    if (m != null) {
      await ref.read(playerProvider.notifier).playBytes('master_${p.id}', m);
    }
  }

  void _computeStarts(Project p) {
    final gap = Duration(milliseconds: LocalDb.settings.get('gapMs', defaultValue: 250) as int);
    var at = Duration.zero;
    _starts.clear();
    for (final s in p.segments.where((s) => s.text.trim().isNotEmpty)) {
      _starts[s.id] = at;
      final b = s.audioKey == null ? null : LocalDb.readAudio(s.audioKey!);
      if (b != null) at += Wav.durationOf(b) + gap;
    }
  }

  Future<void> _regenerate(Segment s) async {
    final prod = ref.read(productionProvider);
    if (prod == null || _p == null) return;
    setState(() => _regen = s.id);
    try {
      await ref.read(playerProvider.notifier).stop();
      await prod.segment(_p!, s, force: true);
      final m = await prod.remix(_p!);
      await ref.read(projectsProvider.notifier).save(_p!);
      _computeStarts(_p!);
      if (m != null) {
        setState(() {
          _master = m;
          _peaks = Wav.peaks(m, buckets: 56);
        });
        final start = _starts[s.id] ?? Duration.zero;
        await ref.read(playerProvider.notifier).playBytes('master_${_p!.id}', m);
        await ref.read(playerProvider.notifier).seek(start);
      }
      if (mounted) showStudioMessage(context, 'اتعملت نسخة جديدة من الجملة.');
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _regen = null);
    }
  }

  Future<void> _share() async {
    if (_master == null || _p == null) return;
    final name = '${_p!.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.wav';
    await Share.shareXFiles(
      [XFile.fromData(_master!, mimeType: 'audio/wav', name: name)],
      text: 'اتعمل بـ Studio-Eldawly',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final pr = _p;
    final st = ref.watch(playerProvider);
    final id = pr == null ? '' : 'master_${pr.id}';
    final isMe = st.id == id;
    final progress = isMe ? st.progress : 0.0;
    final total = pr == null ? Duration.zero : Duration(milliseconds: pr.durationMs);

    String? currentSeg;
    if (isMe) {
      for (final e in _starts.entries) {
        if (st.position >= e.value) currentSeg = e.key;
      }
    }

    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: pr == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(children: [
                      BackSquare(onPressed: () {
                        ref.read(playerProvider.notifier).stop();
                        context.pop();
                      }),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('الأداء جاهز', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            pr.type == ProjectType.podcast
                                ? '${pr.title} · ${pr.speakers.length} متحدثين'
                                : '${VoiceCatalog.byId(pr.voiceId).name} · ${pr.segments.length} جملة',
                            style: t.labelSmall,
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                      decoration: BoxDecoration(gradient: p.hero, borderRadius: BorderRadius.circular(28), boxShadow: p.heroShadow),
                      child: Column(children: [
                        Waveform(
                          peaks: _peaks.isEmpty ? List.filled(56, 0.1) : _peaks,
                          progress: progress,
                          height: 76,
                          played: Colors.white,
                          rest: Colors.white.withValues(alpha: 0.3),
                          onSeek: _master == null
                              ? null
                              : (f) async {
                                  if (!isMe) await ref.read(playerProvider.notifier).playBytes(id, _master!);
                                  await ref.read(playerProvider.notifier).seek(total * f);
                                },
                        ),
                        const SizedBox(height: 10),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(formatDuration(isMe ? st.position : Duration.zero), style: _time),
                            Text(formatDuration(total), style: _time),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _round(Icons.replay_5_rounded, 'رجوع ٥ ثواني', () => ref.read(playerProvider.notifier).skip(-5)),
                          const SizedBox(width: 22),
                          Semantics(
                            button: true,
                            label: isMe && st.playing ? 'إيقاف مؤقت' : 'تشغيل',
                            child: GestureDetector(
                              onTap: _master == null ? null : () => ref.read(playerProvider.notifier).toggle(id, _master!),
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Color(0x59140838), blurRadius: 26, offset: Offset(0, 10))],
                                ),
                                child: Icon(isMe && st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 34, color: p.isDark ? const Color(0xFF4B23C8) : const Color(0xFF6C4DE6)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 22),
                          _round(Icons.forward_5_rounded, 'تقديم ٥ ثواني', () => ref.read(playerProvider.notifier).skip(5)),
                        ]),
                      ]),
                    ),
                  ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.97, 0.97)),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader('الجمل', action: 'تعديل', onAction: () {
                      ref.read(playerProvider.notifier).stop();
                      context.pop();
                    }),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      itemCount: pr.segments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final s = pr.segments[i];
                        final now = s.id == currentSeg;
                        final speaker = s.speakerId == null ? null : pr.speakers.where((x) => x.id == s.speakerId).firstOrNull;
                        return SCard(
                          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                          radius: 18,
                          borderColor: now ? p.accent : null,
                          onTap: _master == null
                              ? null
                              : () async {
                                  if (!isMe) await ref.read(playerProvider.notifier).playBytes(id, _master!);
                                  await ref.read(playerProvider.notifier).seek(_starts[s.id] ?? Duration.zero);
                                },
                          child: Row(children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: s.emotion.bg(p.isDark), borderRadius: BorderRadius.circular(12)),
                              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: s.emotion.dot(p.isDark), shape: BoxShape.circle)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                Text(
                                  '${speaker != null ? '${speaker.name} · ' : ''}${s.emotion.label} · ${formatDuration(_starts[s.id] ?? Duration.zero)}',
                                  style: t.labelSmall,
                                ),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'نسخة جديدة من الجملة',
                              onPressed: _regen != null ? null : () => _regenerate(s),
                              icon: _regen == s.id
                                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                                  : Icon(Icons.autorenew_rounded, color: p.accent),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Row(children: [
                      Expanded(
                        flex: 2,
                        child: GradientButton(label: 'حفظ ومشاركة WAV', icon: Icons.ios_share_rounded, height: 56, onPressed: _master == null ? null : _share),
                      ),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }

  static const _time = TextStyle(fontFamily: Fonts.latin, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white);

  Widget _round(IconData icon, String label, VoidCallback onTap) => IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), fixedSize: const Size(48, 48)),
        icon: Icon(icon, color: Colors.white),
      );
}
