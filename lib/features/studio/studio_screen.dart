import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/player.dart';
import '../../core/errors.dart';
import '../../core/settings/settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../core/utils/text_split.dart';
import '../../data/catalog/emotions.dart';
import '../../data/catalog/voices.dart';
import '../../data/gemini/style_builder.dart';
import '../../data/gemini/text_service.dart';
import '../../data/offline/offline_speaker.dart';
import '../../data/production/production_service.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';
import 'emotion_sheet.dart';
import 'production_overlay.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  Project? _p;
  final _ctrls = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _composer = TextEditingController();
  String? _focused;
  String? _busy; // وصف العملية الجارية
  String? _segLoading;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(projectsProvider.notifier);
    _reload();
  }

  void _reload() {
    final p = ref.read(projectsProvider.notifier).byId(widget.projectId)?.copy();
    setState(() => _p = p);
    if (p != null) _syncControllers();
  }

  void _syncControllers() {
    final ids = _p!.segments.map((s) => s.id).toSet();
    for (final id in _ctrls.keys.toList()) {
      if (!ids.contains(id)) {
        _ctrls.remove(id)?.dispose();
        _focus.remove(id)?.dispose();
      }
    }
    for (final s in _p!.segments) {
      _ctrls.putIfAbsent(s.id, () => TextEditingController(text: s.text));
      if (_ctrls[s.id]!.text != s.text) _ctrls[s.id]!.text = s.text;
      _focus.putIfAbsent(s.id, () {
        final node = FocusNode();
        node.addListener(() {
          if (mounted && node.hasFocus) setState(() => _focused = s.id);
        });
        return node;
      });
    }
  }

  late final ProjectsNotifier _repo;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    final last = _p;
    final repo = _repo;
    if (last != null) Future.microtask(() => repo.save(last));
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _composer.dispose();
    super.dispose();
  }

  void _invalidateMaster() => _p!.masterKey = null;

  void _saveSoon() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_p != null) ref.read(projectsProvider.notifier).save(_p!);
    });
  }

  Future<void> _saveNow() async {
    _saveDebounce?.cancel();
    if (_p != null) await ref.read(projectsProvider.notifier).save(_p!);
  }

  // ───────────── تحويل النص لجمل

  void _splitLocal() {
    final lines = TextSplit.sentences(_composer.text);
    if (lines.isEmpty) return showStudioMessage(context, 'اكتب أو الصق نص الأول.');
    setState(() {
      _p!.segments = [for (final l in lines) Segment(text: l)];
      _invalidateMaster();
      _syncControllers();
    });
    _saveSoon();
  }

  Future<void> _autoEmotions({String? fromText}) async {
    final text = fromText ?? (_p!.segments.isEmpty ? _composer.text : _p!.segments.map((s) => s.text).join('\n'));
    if (text.trim().isEmpty) return showStudioMessage(context, 'اكتب أو الصق نص الأول.');
    final svc = ref.read(textServiceProvider);
    if (svc == null) return showStudioError(context, StudioException.noKey);
    setState(() => _busy = 'بيقرا النص ويختار الإحساس المناسب لكل جملة…');
    try {
      final lines = await svc.detectEmotions(text);
      if (lines.isEmpty) throw const StudioException('ما قدرش يقسّم النص. جرّب "قسّم لجمل".');
      setState(() {
        _p!.segments = [for (final l in lines) Segment(text: l.text, emotion: l.emotion, intensity: l.intensity)];
        _invalidateMaster();
        _syncControllers();
      });
      _saveSoon();
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _rewriteDialect() async {
    final text = _p!.segments.isEmpty ? _composer.text : _p!.segments.map((s) => s.text).join('\n');
    if (text.trim().isEmpty) return showStudioMessage(context, 'اكتب أو الصق نص الأول.');
    final svc = ref.read(textServiceProvider);
    if (svc == null) return showStudioError(context, StudioException.noKey);
    final voice = VoiceCatalog.byId(_p!.voiceId);
    setState(() => _busy = 'بيحوّل النص لـ${voice.dialect.title}…');
    try {
      final out = await svc.rewriteToDialect(text, _p!.dialectId);
      if (!mounted) return;
      setState(() => _busy = null);
      await _autoEmotions(fromText: out);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ───────────── تعديل الجمل

  void _insertTag(String tag) {
    final id = _focused;
    if (id == null || !_ctrls.containsKey(id)) {
      return showStudioMessage(context, 'اضغط جوّه الجملة الأول عشان تحط العلامة مكان المؤشر.');
    }
    final c = _ctrls[id]!;
    final sel = c.selection;
    final pos = sel.isValid ? sel.baseOffset : c.text.length;
    final text = '${c.text.substring(0, pos)} $tag ${c.text.substring(pos)}'.replaceAll(RegExp(r'\s{2,}'), ' ');
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: (pos + tag.length + 2).clamp(0, text.length)));
    _onText(id, text);
  }

  Emotion? get _focusedEmotion {
    if (_focused == null || _p == null) return null;
    for (final s in _p!.segments) {
      if (s.id == _focused) return s.emotion;
    }
    return null;
  }

  /// تغيير سريع لإحساس الجملة المحددة من الشريط تحت.
  void _setFocusedEmotion(Emotion e) {
    final target = _p!.segments.where((s) => s.id == _focused).firstOrNull;
    if (target == null) {
      return showStudioMessage(context, 'اضغط على أي جملة الأول، وبعدين اختار إحساسها.');
    }
    HapticFeedback.selectionClick();
    setState(() {
      target.emotion = e;
      target.audioKey = null;
      _invalidateMaster();
    });
    _saveSoon();
  }

  void _onText(String id, String text) {
    final s = _p!.segments.firstWhere((e) => e.id == id);
    s.text = text;
    s.audioKey = null;
    _invalidateMaster();
    _saveSoon();
  }

  void _addSegment([int? after]) {
    setState(() {
      final s = Segment(text: '');
      if (after == null) {
        _p!.segments.add(s);
      } else {
        _p!.segments.insert(after + 1, s);
      }
      _invalidateMaster();
      _syncControllers();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus[_p!.segments.last.id]?.requestFocus());
  }

  void _removeSegment(Segment s) {
    setState(() {
      _p!.segments.removeWhere((e) => e.id == s.id);
      _invalidateMaster();
      _syncControllers();
    });
    _saveSoon();
  }

  Future<void> _openEmotion(Segment s) async {
    final res = await showEmotionSheet(
      context,
      sentence: s.text,
      emotion: s.emotion,
      intensity: s.intensity,
      controls: _p!.controls,
      onTry: (e, i, c) async {
        final prod = ref.read(productionProvider);
        if (prod == null) throw StudioException.noKey;
        final tmp = _p!.copy()..controls = c;
        final seg = Segment(text: s.text, emotion: e, intensity: i);
        try {
          final wav = await prod.segment(tmp, seg);
          await ref.read(playerProvider.notifier).playBytes('try', wav);
        } catch (err) {
          if (mounted) showStudioError(context, err);
        }
      },
    );
    if (res == null) return;
    setState(() {
      final targets = res.applyToAll ? _p!.segments : [s];
      for (final t in targets) {
        t.emotion = res.emotion;
        t.intensity = res.intensity;
        t.audioKey = null;
      }
      if (res.controls.toJson().toString() != _p!.controls.toJson().toString()) {
        _p!.controls = res.controls;
        for (final t in _p!.segments) {
          t.audioKey = null;
        }
      }
      _invalidateMaster();
    });
    _saveSoon();
  }

  Future<void> _playSegment(Segment s) async {
    final prod = ref.read(productionProvider);
    if (prod == null) return showStudioError(context, StudioException.noKey);
    if (s.text.trim().isEmpty) return;
    setState(() => _segLoading = s.id);
    try {
      final wav = await prod.segment(_p!, s);
      _saveSoon();
      await ref.read(playerProvider.notifier).playBytes('seg_${s.id}', wav);
    } catch (e) {
      if (mounted) await _handleFailure(e, [s.text]);
    } finally {
      if (mounted) setState(() => _segLoading = null);
    }
  }

  // ───────────── الإنتاج

  Future<void> _produce() async {
    if (_p!.segments.isEmpty && _composer.text.trim().isNotEmpty) _splitLocal();
    if (_p!.segments.where((s) => s.text.trim().isNotEmpty).isEmpty) {
      return showStudioMessage(context, 'اكتب النص الأول.');
    }
    final prod = ref.read(productionProvider);
    if (prod == null) return showStudioError(context, StudioException.noKey);
    await _saveNow();
    if (!mounted) return;
    final out = await runProduction(context, (onProgress, cancelled) => prod.produce(_p!, onProgress: onProgress, cancelled: cancelled));
    if (!mounted) return;
    await _saveNow();
    if (!mounted || out.cancelled) return;
    if (out.error != null) {
      await _handleFailure(out.error!, _p!.segments.map((s) => s.text).toList());
      return;
    }
    context.push('/result/${_p!.id}');
  }

  Future<void> _handleFailure(Object e, List<String> lines) async {
    showStudioError(context, e);
    final fallback = ref.read(settingsProvider).offlineFallback;
    final retryable = e is StudioException && (e.isQuota || e.code == 'no_tts_model' || e.code == 'network' || e.code == 'server');
    if (!fallback || !retryable) return;
    final listen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسمعه بصوت الجهاز؟'),
        content: const Text('Gemini مش متاح دلوقتي. تقدر تسمع النص بصوت الموبايل لحد ما الحصة ترجع (للاستماع بس، من غير تصدير).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اسمع')),
        ],
      ),
    );
    if (listen == true) {
      await ref.read(offlineSpeakerProvider).speakAll(lines, locale: VoiceCatalog.byId(_p!.voiceId).dialect.locale);
    }
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _p!.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم المشروع'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() => _p!.title = v);
      _saveSoon();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final pr = _p;
    if (pr == null) {
      return Scaffold(body: StudioBackground(child: Center(child: Text('المشروع مش موجود', style: t.bodyLarge))));
    }
    final voice = VoiceCatalog.byId(pr.voiceId);
    final player = ref.watch(playerProvider);
    final words = pr.segments.fold<int>(0, (a, s) => a + s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
    final estSec = (words / 2.3).round();

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
                  child: GestureDetector(
                    onTap: _rename,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pr.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${pr.type.label} · ${pr.segments.length} جملة · تم الحفظ تلقائياً', style: t.labelSmall),
                    ]),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'أدوات الذكاء',
                  icon: Icon(Icons.auto_awesome_rounded, color: p.accent),
                  onSelected: (v) {
                    if (v == 'emo') _autoEmotions();
                    if (v == 'dialect') _rewriteDialect();
                    if (v == 'split') {
                      _composer.text = pr.segments.map((s) => s.text).join('\n');
                      _splitLocal();
                    }
                    if (v == 'clear') {
                      setState(() {
                        _composer.text = pr.segments.map((s) => s.text).join('\n');
                        pr.segments = [];
                        _invalidateMaster();
                        _syncControllers();
                      });
                      _saveSoon();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'emo', child: Text('✦ إحساس تلقائي لكل جملة')),
                    PopupMenuItem(value: 'dialect', child: Text('✦ حوّل النص لـ${voice.dialect.short}')),
                    const PopupMenuItem(value: 'split', child: Text('أعد تقسيم الجمل')),
                    const PopupMenuItem(value: 'clear', child: Text('رجوع لكتابة النص كامل')),
                  ],
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VoiceBanner(
                name: voice.name,
                letter: voice.initial,
                meta: '${voice.dialect.short} · ${voice.gender.label} · ${(pr.controls.age ?? voice.age).label} · ${voice.purpose.label}',
                onTap: () async {
                  await _saveNow();
                  if (!context.mounted) return;
                  await context.push('/pick/${pr.id}');
                  if (mounted) _reload();
                },
              ),
            ),
            if (_busy != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_busy!, style: t.bodySmall)),
                ]),
              ),
            Expanded(
              child: pr.segments.isEmpty
                  ? _Composer(controller: _composer, onSplit: _splitLocal, onAuto: () => _autoEmotions(), onDialect: _rewriteDialect, busy: _busy != null)
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      itemCount: pr.segments.length + 1,
                      buildDefaultDragHandles: false,
                      onReorder: (a, b) {
                        if (a >= pr.segments.length) return;
                        setState(() {
                          if (b > a) b -= 1;
                          b = b.clamp(0, pr.segments.length - 1);
                          final s = pr.segments.removeAt(a);
                          pr.segments.insert(b, s);
                          _invalidateMaster();
                        });
                        _saveSoon();
                      },
                      itemBuilder: (_, i) {
                        if (i == pr.segments.length) {
                          return Padding(
                            key: const ValueKey('add'),
                            padding: const EdgeInsets.only(top: 2),
                            child: TextButton.icon(
                              onPressed: () => _addSegment(),
                              icon: Icon(Icons.add_rounded, color: p.accent),
                              label: Text('إضافة جملة', style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
                            ),
                          );
                        }
                        final s = pr.segments[i];
                        final playing = player.id == 'seg_${s.id}' && player.playing;
                        // المفتاح لازم يكون على أبعد ويدجت، وإلا ReorderableListView بيقع في نسخة الـ release.
                        return KeyedSubtree(
                          key: ValueKey(s.id),
                          child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SCard(
                            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                            borderColor: _focused == s.id ? p.accent.withValues(alpha: 0.6) : null,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                EmotionTag(emotion: s.emotion, intensity: s.intensity, onTap: () => _openEmotion(s)),
                                const Spacer(),
                                if (s.audioKey != null) Icon(Icons.check_circle_rounded, size: 16, color: p.ok),
                                IconButton(
                                  tooltip: playing ? 'إيقاف' : 'اسمع الجملة',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _segLoading != null
                                      ? null
                                      : () => playing ? ref.read(playerProvider.notifier).stop() : _playSegment(s),
                                  icon: _segLoading == s.id
                                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                                      : Icon(playing ? Icons.stop_rounded : Icons.play_circle_fill_rounded, color: p.accent),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'خيارات الجملة',
                                  icon: Icon(Icons.more_horiz_rounded, color: p.muted),
                                  onSelected: (v) {
                                    if (v == 'emo') _openEmotion(s);
                                    if (v == 'add') _addSegment(i);
                                    if (v == 'del') _removeSegment(s);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'emo', child: Text('الإحساس وضبط الصوت')),
                                    PopupMenuItem(value: 'add', child: Text('جملة جديدة بعدها')),
                                    PopupMenuItem(value: 'del', child: Text('حذف الجملة')),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator_rounded, color: p.muted, size: 20)),
                                ),
                              ]),
                              TextField(
                                controller: _ctrls[s.id],
                                focusNode: _focus[s.id],
                                maxLines: null,
                                onChanged: (v) => _onText(s.id, v),
                                style: TextStyle(fontFamily: Fonts.body, fontSize: 16.5, height: 1.8, color: p.text),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(0, 6, 0, 6),
                                  hintText: 'اكتب الجملة…',
                                ),
                              ),
                            ]),
                          ),
                        ).animate().fadeIn(duration: 220.ms),
                        );
                      },
                    ),
            ),
            if (pr.segments.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Text(_focused == null ? 'إحساس الجملة:' : 'إحساس المحددة:', style: t.labelSmall),
                      ),
                    ),
                    for (final e in Emotion.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ActionChip(
                          avatar: CircleAvatar(radius: 5, backgroundColor: e.dot(p.isDark)),
                          label: Text(e.label,
                              style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 12.5, color: e.fg(p.isDark))),
                          backgroundColor: _focusedEmotion == e ? e.bg(p.isDark) : p.surface,
                          side: BorderSide(color: _focusedEmotion == e ? e.dot(p.isDark) : p.line),
                          shape: const StadiumBorder(),
                          onPressed: () => _setFocusedEmotion(e),
                        ),
                      ),
                  ],
                ),
              ),
            if (pr.segments.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final tag in const [
                      ('وقفة', '⟨وقفة⟩', Icons.pause_rounded),
                      ('وقفة طويلة', '⟨وقفة طويلة⟩', Icons.more_time_rounded),
                      ('ضحكة', '⟨ضحكة⟩', Icons.sentiment_very_satisfied_rounded),
                      ('تنهيدة', '⟨تنهيدة⟩', Icons.air_rounded),
                      ('كحة', '⟨كحة⟩', Icons.masks_rounded),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ActionChip(
                          avatar: Icon(tag.$3, size: 16, color: p.accent),
                          label: Text(tag.$1, style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 12.5, color: p.text)),
                          backgroundColor: p.surface,
                          side: BorderSide(color: p.line),
                          shape: const StadiumBorder(),
                          onPressed: () => _insertTag(tag.$2),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(children: [
                Row(children: [
                  for (final q in [
                    ('السرعة', pr.controls.speedLabel),
                    ('الطبقة', pr.controls.pitchLabel),
                    ('الدفء', pr.controls.warmthLabel),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: SCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          radius: 16,
                          onTap: pr.segments.isEmpty ? null : () => _openEmotion(pr.segments.first),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(q.$1, style: t.labelSmall),
                            Text(q.$2,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, fontSize: 14.5, color: p.text)),
                          ]),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                GradientButton(
                  label: pr.isGenerated ? 'اسمع النتيجة' : 'ولّد الأداء',
                  icon: pr.isGenerated ? Icons.headphones_rounded : Icons.auto_awesome_rounded,
                  trailing: estSec > 0 ? '~${formatDuration(Duration(seconds: estSec))}' : null,
                  onPressed: _busy != null
                      ? null
                      : () => pr.isGenerated ? context.push('/result/${pr.id}') : _produce(),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _VoiceBanner extends StatelessWidget {
  const _VoiceBanner({required this.name, required this.letter, required this.meta, required this.onTap});
  final String name;
  final String letter;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(gradient: p.hero, borderRadius: BorderRadius.circular(22), boxShadow: p.heroShadow),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white38),
              ),
              child: Text(letter, style: const TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white)),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
              ]),
            ),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(999)),
              child: const Text('تغيير', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSplit, required this.onAuto, required this.onDialect, required this.busy});
  final TextEditingController controller;
  final VoidCallback onSplit;
  final VoidCallback onAuto;
  final VoidCallback onDialect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), children: [
      SCard(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: controller,
          minLines: 9,
          maxLines: null,
          style: TextStyle(fontFamily: Fonts.body, fontSize: 16.5, height: 1.8, color: p.text),
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'اكتب أو الصق النص هنا…\n\nبعدها اختار: نقسّمه لجمل، أو نخلي الذكاء الاصطناعي يحدد إحساس كل جملة.',
          ),
        ),
      ),
      const SizedBox(height: 12),
      GradientButton(label: 'إحساس تلقائي لكل جملة', icon: Icons.auto_awesome_rounded, height: 52, onPressed: busy ? null : onAuto),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: GhostButton(label: 'قسّم لجمل', icon: Icons.segment_rounded, onPressed: busy ? null : onSplit)),
        const SizedBox(width: 10),
        Expanded(child: GhostButton(label: 'حوّل للهجة', icon: Icons.translate_rounded, onPressed: busy ? null : onDialect)),
      ]),
      const SizedBox(height: 12),
      Text('نصيحة: الصوت بيطلع أطبع لما النص يكون مكتوب باللهجة نفسها. زرار "حوّل للهجة" بيعمل ده.', style: t.bodySmall),
    ]);
  }
}
