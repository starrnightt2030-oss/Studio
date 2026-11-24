import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/dialects.dart';
import '../../data/catalog/emotions.dart';
import '../../data/catalog/voices.dart';
import '../../data/gemini/text_service.dart';
import '../../data/production/production_service.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';
import '../studio/production_overlay.dart';

class PodcastScreen extends ConsumerStatefulWidget {
  const PodcastScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends ConsumerState<PodcastScreen> with WidgetsBindingObserver {
  Project? _p;
  final _source = TextEditingController();
  int _count = 2;
  bool _writing = false;

  static const _speakerColors = [Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF97316), Color(0xFFEC4899)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = ref.read(projectsProvider.notifier);
    _reload();
    _source.addListener(() {
      final p = _p;
      if (p == null || p.sourceText == _source.text) return;
      p.sourceText = _source.text;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _save);
    });
  }

  Timer? _debounce;
  late final ProjectsNotifier _repo;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _debounce?.cancel();
      _save();
    }
  }

  void _reload() {
    final p = ref.read(projectsProvider.notifier).byId(widget.projectId)?.copy();
    setState(() => _p = p);
    if (p != null && _source.text.isEmpty) _source.text = p.sourceText;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    final last = _p;
    final repo = _repo;
    if (last != null) Future.microtask(() => repo.save(last));
    _source.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p != null) await ref.read(projectsProvider.notifier).save(_p!);
  }

  Future<void> _write() async {
    final src = _source.text.trim();
    if (src.length < 20) return showStudioMessage(context, 'اكتب الموضوع أو الصق محتوى أطول شوية.');
    final svc = ref.read(textServiceProvider);
    if (svc == null) return showStudioError(context, StudioException.noKey);
    setState(() => _writing = true);
    try {
      final story = _p!.type == ProjectType.story;
      final draft = story
          ? await svc.castStory(story: src, dialectId: _p!.dialectId)
          : await svc.writePodcast(source: src, dialectId: _p!.dialectId, speakers: _count);
      if (draft.turns.isEmpty) throw const StudioException('ما قدرش يكتب حوار. جرّب تاني.');
      final used = <String>{};
      final speakers = <Speaker>[];
      final idMap = <String, String>{};
      for (final s in draft.speakers) {
        final purpose = !story
            ? Purpose.podcast
            : s.id == 'narrator'
                ? Purpose.story
                : (s.cartoon || s.age == Age.child)
                    ? Purpose.cartoon
                    : null;
        final v = VoiceCatalog.bestMatch(dialectId: _p!.dialectId, gender: s.gender, age: s.age, purpose: purpose, avoid: used);
        used.add(v.id);
        final sp = Speaker(name: s.name, role: s.role, voiceId: v.id);
        idMap[s.id] = sp.id;
        speakers.add(sp);
      }
      setState(() {
        _p!
          ..sourceText = src
          ..speakers = speakers
          ..segments = [
            for (final t in draft.turns) Segment(text: t.text, emotion: t.emotion, speakerId: idMap[t.speakerId]),
          ]
          ..masterKey = null;
        if (_p!.title.endsWith('جديد') || _p!.title.endsWith('جديدة')) {
          _p!.title = '${story ? 'قصة' : 'حلقة'}: ${src.split(RegExp(r'\s+')).take(4).join(' ')}';
        }
        if (story && _p!.musicId == null) _p!.musicId = 'kids_playful';
      });
      await _save();
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _editTurn(Segment s) async {
    final c = TextEditingController(text: s.text);
    var emo = s.emotion;
    var speaker = s.speakerId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final p = ctx.palette;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تعديل الدور', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final sp in _p!.speakers) ChoiceChipPill(label: sp.name, selected: sp.id == speaker, onTap: () => set(() => speaker = sp.id)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: c, maxLines: null, minLines: 2),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in Emotion.values)
                ChoiceChip(
                  label: Text(e.label),
                  selected: e == emo,
                  selectedColor: e.bg(p.isDark),
                  avatar: CircleAvatar(backgroundColor: e.dot(p.isDark), radius: 5),
                  onSelected: (_) => set(() => emo = e),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: GhostButton(
                  label: 'حذف',
                  icon: Icons.delete_outline_rounded,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: GradientButton(label: 'حفظ', height: 54, onPressed: () => Navigator.pop(ctx, true))),
            ]),
          ]),
        );
      }),
    );
    if (ok == null) return;
    setState(() {
      if (ok) {
        s
          ..text = c.text.trim()
          ..emotion = emo
          ..speakerId = speaker
          ..audioKey = null;
      } else {
        _p!.segments.removeWhere((e) => e.id == s.id);
      }
      _p!.masterKey = null;
    });
    await _save();
  }

  Future<void> _produce() async {
    final prod = ref.read(productionProvider);
    if (prod == null) return showStudioError(context, StudioException.noKey);
    await _save();
    if (!mounted) return;
    final out = await produceProject(context, prod, _p!);
    await _save();
    if (!mounted || out.cancelled) return;
    if (out.error != null) return showStudioError(context, out.error!);
    context.push('/result/${_p!.id}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final pr = _p;
    if (pr == null) return const Scaffold(body: Center(child: Text('المشروع مش موجود')));
    final hasScript = pr.segments.isNotEmpty;
    final isStory = pr.type == ProjectType.story;

    Color colorOf(String? id) {
      final i = pr.speakers.indexWhere((s) => s.id == id);
      return _speakerColors[(i < 0 ? 0 : i) % _speakerColors.length];
    }

    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(children: [
                BackSquare(onPressed: () => context.pop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pr.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${pr.type.label} · ${Dialects.byId(pr.dialectId).short} · ${pr.speakers.isEmpty ? (isStory ? 'أدوار تلقائية' : '$_count متحدثين') : '${pr.speakers.length} أدوار'}',
                        style: t.labelSmall),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), children: [
                if (!hasScript) ...[
                  Text('اللهجة', style: t.labelSmall),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: Dialects.all.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = Dialects.all[i];
                        return ChoiceChipPill(
                          label: d.short,
                          selected: d.id == pr.dialectId,
                          onTap: () => setState(() => pr.dialectId = d.id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!isStory) ...[
                    Text('عدد المتحدثين', style: t.labelSmall),
                    const SizedBox(height: 6),
                    SegmentedPills<int>(items: const [2, 3, 4], selected: _count, label: (n) => '$n', onChanged: (n) => setState(() => _count = n)),
                  ],
                  const SizedBox(height: 14),
                  SCard(
                    child: TextField(
                      controller: _source,
                      minLines: 8,
                      maxLines: null,
                      style: TextStyle(fontFamily: Fonts.body, fontSize: 15.5, height: 1.8, color: p.text),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: isStory
                            ? 'الصق القصة هنا…\nوالذكاء الاصطناعي هيوزّع الأدوار: الراوي وكل شخصية بصوت وعمر مناسبين.'
                            : 'اكتب موضوع الحلقة أو الصق مقال/ملاحظات…\nوالذكاء الاصطناعي هيحوّله لحوار طبيعي بين المتحدثين.',
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    height: 124,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (i, s) in pr.speakers.indexed)
                      SizedBox(
                        width: pr.speakers.length <= 2 ? (MediaQuery.of(context).size.width - 48) / 2 : 120,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: SCard(
                            padding: const EdgeInsets.all(10),
                            radius: 20,
                            onTap: () async {
                              await _save();
                              if (!context.mounted) return;
                              await context.push('/pick/${pr.id}?speaker=${s.id}');
                              if (mounted) _reload();
                            },
                            child: Column(children: [
                              VoiceAvatar(letter: VoiceCatalog.byId(s.voiceId).initial, seed: i, size: 40),
                              const SizedBox(height: 6),
                              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                              Text('صوت: ${s.azureVoice != null ? 'Azure ${s.azureVoice!.split('-').skip(2).join('-').replaceAll('Neural', '')}' : VoiceCatalog.byId(s.voiceId).name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  for (final (i, s) in pr.segments.indexed) _bubble(context, pr, s, colorOf(s.speakerId), i),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: hasScript
                  ? Row(children: [
                      GhostButton(
                        label: 'أعد الكتابة',
                        icon: Icons.auto_awesome_rounded,
                        onPressed: _writing
                            ? null
                            : () => setState(() {
                                  pr.segments = [];
                                  pr.speakers = [];
                                }),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: GradientButton(label: isStory ? 'ولّد القصة' : 'ولّد الحلقة', icon: Icons.graphic_eq_rounded, onPressed: _produce)),
                    ])
                  : GradientButton(label: isStory ? 'وزّع الأدوار' : 'اكتب السيناريو', icon: Icons.auto_awesome_rounded, loading: _writing, onPressed: _write),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, Project pr, Segment s, Color color, int i) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final idx = pr.speakers.indexWhere((x) => x.id == s.speakerId);
    final first = idx <= 0;
    final name = idx < 0 ? '؟' : pr.speakers[idx].name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: first ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(crossAxisAlignment: first ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('$name · ${s.emotion.label}', style: t.labelSmall),
            ]),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _editTurn(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  gradient: first ? p.hero : null,
                  color: first ? null : p.surface,
                  border: first ? null : Border.all(color: p.line),
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: const Radius.circular(20),
                    topEnd: const Radius.circular(20),
                    bottomStart: Radius.circular(first ? 6 : 20),
                    bottomEnd: Radius.circular(first ? 20 : 6),
                  ),
                  boxShadow: p.cardShadow,
                ),
                child: Text(s.text, style: TextStyle(fontSize: 14.5, height: 1.7, color: first ? Colors.white : p.text)),
              ),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(delay: (40 * i).ms).slideY(begin: 0.08);
  }
}
