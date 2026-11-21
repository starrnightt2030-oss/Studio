import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/player.dart';
import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/dialects.dart';
import '../../data/catalog/emotions.dart';
import '../../data/catalog/voices.dart';
import '../../data/gemini/style_builder.dart';
import '../../data/gemini/tts_service.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

const _samples = <String, String>{
  'egyptian': 'أهلاً بيك! أنا {n}، وده صوتي في ستوديو الدولي.',
  'saudi': 'هلا والله! أنا {n}، وهذا صوتي في ستوديو الدولي.',
  'khaleeji': 'هلا وغلا! أنا {n}، وهذا صوتي في ستوديو الدولي.',
  'levantine': 'أهلين فيك! أنا {n}، وهيدا صوتي بستوديو الدولي.',
  'lebanese': 'أهلا وسهلا! أنا {n}، وهيدا صوتي بستوديو الدولي.',
  'iraqi': 'هلا بيك! آني {n}، وهذا صوتي بستوديو الدولي.',
  'sudanese': 'مرحب بيك! أنا {n}، ودا صوتي في ستوديو الدولي.',
  'yemeni': 'أهلاً وسهلاً! أنا {n}، وهذا صوتي في ستوديو الدولي.',
  'moroccan': 'مرحبا بيك! أنا {n}، وهادا صوتي فستوديو الدولي.',
  'algerian': 'مرحبا بيك! أنا {n}، وهذا صوتي في ستوديو الدولي.',
  'tunisian': 'أهلا بيك! أنا {n}، وهذا صوتي في ستوديو الدولي.',
  'fusha': 'مرحباً بك! أنا {n}، وهذا صوتي في استوديو الدولي.',
};

class VoicesScreen extends ConsumerStatefulWidget {
  const VoicesScreen({super.key, this.pickForProject, this.pickForSpeaker});

  /// لو مش null: الشاشة بتشتغل كمختار صوت لمشروع.
  final String? pickForProject;
  final String? pickForSpeaker;

  @override
  ConsumerState<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends ConsumerState<VoicesScreen> {
  String _dialect = 'egyptian';
  Gender _gender = Gender.male;
  Age? _age;
  String? _loading;
  final _peaks = <String, List<double>>{};

  bool get _picking => widget.pickForProject != null;

  @override
  void initState() {
    super.initState();
    if (_picking) {
      final p = ref.read(projectsProvider.notifier).byId(widget.pickForProject!);
      if (p != null) {
        _dialect = p.dialectId;
        final current = widget.pickForSpeaker == null
            ? p.voiceId
            : p.speakers.where((s) => s.id == widget.pickForSpeaker).map((s) => s.voiceId).firstOrNull ?? p.voiceId;
        _gender = VoiceCatalog.byId(current).gender;
      }
    }
  }

  Future<void> _preview(VoicePersona v) async {
    final tts = ref.read(ttsServiceProvider);
    if (tts == null) return showStudioError(context, StudioException.noKey);
    setState(() => _loading = v.id);
    try {
      final wav = await tts.synthesize(TtsRequest(
        text: _samples[v.dialectId]!.replaceAll('{n}', v.name),
        voice: v.baseVoice,
        locale: v.dialect.locale,
        style: StyleBuilder.build(persona: v, emotion: Emotion.joy, intensity: Intensity.light, controls: const VoiceControls()),
      ));
      _peaks[v.id] = Wav.peaks(wav, buckets: 30);
      await ref.read(playerProvider.notifier).playBytes('voice_${v.id}', wav);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  Future<void> _pick(VoicePersona v) async {
    final repo = ref.read(projectsProvider.notifier);
    final p = repo.byId(widget.pickForProject!)?.copy();
    if (p == null) return;
    if (widget.pickForSpeaker != null) {
      for (final s in p.speakers) {
        if (s.id == widget.pickForSpeaker) s.voiceId = v.id;
      }
    } else {
      p.voiceId = v.id;
      p.dialectId = v.dialectId;
    }
    for (final s in p.segments) {
      s.audioKey = null;
    }
    p.masterKey = null;
    await repo.save(p);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final list = VoiceCatalog.filter(dialectId: _dialect, gender: _gender, age: _age);
    final player = ref.watch(playerProvider);
    final selectedId = _picking ? _currentId() : null;

    final body = SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverList.list(children: [
            Row(children: [
              if (_picking) const BackSquare(),
              if (_picking) const SizedBox(width: 12),
              Expanded(child: Text(_picking ? 'اختار الصوت' : 'مكتبة الأصوات', style: t.titleLarge)),
              Text('${VoiceCatalog.all.length} شخصية', style: t.bodySmall),
            ]),
            const SizedBox(height: 14),
            SegmentedPills<Gender>(
              items: Gender.values,
              selected: _gender,
              label: (g) => g.label,
              onChanged: (g) => setState(() => _gender = g),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: Dialects.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d = Dialects.all[i];
                  return ChoiceChipPill(label: d.short, selected: d.id == _dialect, onTap: () => setState(() => _dialect = d.id));
                },
              ),
            ),
            const SizedBox(height: 12),
            Text('العمر', style: t.labelSmall),
            const SizedBox(height: 6),
            Row(children: [
              for (final a in [null, ...Age.values])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _AgeTile(age: a, selected: _age == a, onTap: () => setState(() => _age = a)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('أصوات ${Dialects.byId(_dialect).short} · ${_gender.label}', style: t.titleSmall)),
              Text('${list.length} صوت', style: t.bodySmall),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, _picking ? 30 : 130),
          sliver: SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final v = list[i];
              final playing = player.id == 'voice_${v.id}' && player.playing;
              final selected = v.id == selectedId;
              return SCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                radius: 20,
                borderColor: selected || playing ? p.accent : null,
                child: Row(children: [
                  VoiceAvatar(letter: v.initial, seed: v.id.hashCode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(v.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(v.baseVoice, style: TextStyle(fontFamily: Fonts.latin, fontSize: 10.5, color: p.muted)),
                      ]),
                      const SizedBox(height: 4),
                      Waveform(
                        peaks: _peaks[v.id] ?? List.generate(30, (k) => 0.15 + 0.1 * ((k * 7 + v.name.length) % 5)),
                        progress: playing ? player.progress : 0,
                        height: 16,
                      ),
                      const SizedBox(height: 4),
                      Text('${v.description} · ${v.age.label}', style: t.labelSmall),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  _PlayCircle(
                    loading: _loading == v.id,
                    playing: playing,
                    active: selected || playing,
                    onTap: () => playing ? ref.read(playerProvider.notifier).stop() : _preview(v),
                  ),
                  if (_picking) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'اختيار',
                      onPressed: () => _pick(v),
                      icon: Icon(selected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: p.accent),
                    ),
                  ],
                ]),
              ).animate().fadeIn(delay: (30 * i).ms, duration: 250.ms);
            },
          ),
        ),
      ]),
    );

    return _picking ? Scaffold(body: StudioBackground(child: body)) : body;
  }

  String? _currentId() {
    final p = ref.watch(projectsProvider).where((e) => e.id == widget.pickForProject).firstOrNull;
    if (p == null) return null;
    if (widget.pickForSpeaker == null) return p.voiceId;
    for (final s in p.speakers) {
      if (s.id == widget.pickForSpeaker) return s.voiceId;
    }
    return null;
  }
}

class _AgeTile extends StatelessWidget {
  const _AgeTile({required this.age, required this.selected, required this.onTap});
  final Age? age;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = {
    null: Icons.all_inclusive_rounded,
    Age.child: Icons.child_care_rounded,
    Age.young: Icons.person_rounded,
    Age.adult: Icons.person_outline_rounded,
    Age.elder: Icons.elderly_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 62,
        decoration: BoxDecoration(
          gradient: selected ? p.segment : null,
          color: selected ? null : p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.transparent : p.line),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_icons[age], size: 20, color: selected ? Colors.white : p.text),
          const SizedBox(height: 3),
          Text(age?.label ?? 'الكل',
              style: TextStyle(fontFamily: Fonts.display, fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : p.text)),
        ]),
      ),
    );
  }
}

class _PlayCircle extends StatelessWidget {
  const _PlayCircle({required this.loading, required this.playing, required this.active, required this.onTap});
  final bool loading;
  final bool playing;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: playing ? 'إيقاف' : 'استمع للعينة',
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: active ? p.segment : null,
            color: active ? null : p.surface2,
            boxShadow: active ? p.ctaShadow : null,
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: active ? Colors.white : p.accent),
                )
              : Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: active ? Colors.white : p.accent),
        ),
      ),
    );
  }
}
