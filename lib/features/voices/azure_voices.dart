import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/player.dart';
import '../../core/audio/wav.dart';
import '../../core/errors.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/azure/azure_tts.dart';
import '../../data/catalog/emotions.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

/// جملة العينة حسب البلد.
String azureSample(String locale, String name) {
  final s = switch (locale) {
    'ar-EG' => 'أهلاً بيك! أنا {n}، وده صوتي في ستوديو الدولي. تحب نبدأ؟',
    'ar-SA' || 'ar-KW' || 'ar-QA' || 'ar-BH' || 'ar-OM' || 'ar-AE' => 'هلا والله! أنا {n}، وهذا صوتي في ستوديو الدولي.',
    'ar-SY' || 'ar-LB' || 'ar-JO' => 'أهلين فيك! أنا {n}، وهيدا صوتي بستوديو الدولي.',
    'ar-IQ' => 'هلا بيك! آني {n}، وهذا صوتي بستوديو الدولي.',
    'ar-MA' => 'مرحبا بيك! أنا {n}، وهادا صوتي فستوديو الدولي.',
    _ => 'مرحباً بك! أنا {n}، وهذا صوتي في استوديو الدولي.',
  };
  return s.replaceAll('{n}', name);
}

/// مكتبة أصوات Azure: كل الأصوات العربي في منطقتك، مقسّمة حسب البلد والنوع،
/// مع معاينة واختيار للمشروع أو لمتحدث.
class AzureVoiceLibrary extends ConsumerStatefulWidget {
  const AzureVoiceLibrary({super.key, required this.header, this.pickForProject, this.pickForSpeaker});

  final List<Widget> header;
  final String? pickForProject;
  final String? pickForSpeaker;

  @override
  ConsumerState<AzureVoiceLibrary> createState() => _AzureVoiceLibraryState();
}

class _AzureVoiceLibraryState extends ConsumerState<AzureVoiceLibrary> {
  Future<List<AzureVoice>>? _future;
  AzureTts? _forAz;
  String? _locale; // null = الكل
  Gender? _gender;
  String? _loading;
  final _peaks = <String, List<double>>{};

  bool get _picking => widget.pickForProject != null;

  void _load(AzureTts az, {bool refresh = false}) {
    _forAz = az;
    _future = () async {
      if (refresh) await LocalDb.settings.delete('azureVoices:${az.region}');
      final l = await az.listVoices();
      l.sort((a, b) {
        final c = _order(a.locale).compareTo(_order(b.locale));
        return c != 0 ? c : a.shortLabel.compareTo(b.shortLabel);
      });
      return l;
    }();
  }

  static int _order(String loc) {
    final i = AzureTts.localeNames.keys.toList().indexOf(loc);
    return i < 0 ? 99 : i;
  }

  Future<void> _preview(AzureTts az, AzureVoice v) async {
    setState(() => _loading = v.shortName);
    try {
      final key = 'azprev|${v.shortName}';
      var wav = LocalDb.readAudio(key);
      if (wav == null) {
        wav = await az.synthesize(AzureTts.ssml(voice: v, lines: [(azureSample(v.locale, v.shortLabel), Emotion.neutral, Intensity.light)]));
        await LocalDb.writeAudio(key, wav);
      }
      _peaks[v.shortName] = Wav.peaks(wav, buckets: 30);
      await ref.read(playerProvider.notifier).playBytes('az_${v.shortName}', wav);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  String? _current() {
    final p = ref.watch(projectsProvider).where((e) => e.id == widget.pickForProject).firstOrNull;
    if (p == null) return null;
    if (widget.pickForSpeaker == null) return p.azureVoice;
    for (final s in p.speakers) {
      if (s.id == widget.pickForSpeaker) return s.azureVoice;
    }
    return null;
  }

  Future<void> _pick(String? shortName) async {
    final repo = ref.read(projectsProvider.notifier);
    final p = repo.byId(widget.pickForProject!)?.copy();
    if (p == null) return;
    if (widget.pickForSpeaker != null) {
      for (final s in p.speakers) {
        if (s.id == widget.pickForSpeaker) s.azureVoice = shortName;
      }
    } else {
      p.azureVoice = shortName;
    }
    for (final s in p.segments) {
      s.audioKey = null;
    }
    p.masterKey = null;
    await repo.save(p);
    if (!mounted) return;
    showStudioMessage(context, shortName == null ? 'رجعنا للاختيار التلقائي' : 'المشروع هيتولد بصوت Azure ده');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final az = ref.watch(azureTtsProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (az == null) {
      return CustomScrollView(slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), sliver: SliverList.list(children: widget.header)),
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('ضيف مفتاح Azure من الإعدادات عشان تشوف أصواته.', style: t.bodyMedium)),
        ),
      ]);
    }
    if (_future == null || _forAz?.key != az.key || _forAz?.region != az.region) _load(az);
    final player = ref.watch(playerProvider);
    final selected = _picking ? _current() : null;

    return FutureBuilder<List<AzureVoice>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? const <AzureVoice>[];
        final locales = {for (final v in all) v.locale}.toList();
        final list = all.where((v) => (_locale == null || v.locale == _locale) && (_gender == null || v.isMale == (_gender == Gender.male))).toList();

        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _load(az, refresh: true));
            await _future;
          },
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverList.list(children: [
                ...widget.header,
                SegmentedPills<Gender?>(
                  items: const [null, Gender.male, Gender.female],
                  selected: _gender,
                  label: (g) => g?.label ?? 'الكل',
                  onChanged: (g) => setState(() => _gender = g),
                ),
                const SizedBox(height: 12),
                if (locales.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: locales.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final loc = i == 0 ? null : locales[i - 1];
                        return ChoiceChipPill(
                          label: loc == null ? 'كل البلاد' : AzureTts.localeLabel(loc),
                          selected: _locale == loc,
                          onTap: () => setState(() => _locale = loc),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                if (_picking)
                  SCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    radius: 18,
                    borderColor: selected == null ? p.accent : null,
                    onTap: () => _pick(null),
                    child: Row(children: [
                      Icon(Icons.auto_awesome_rounded, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('تلقائي', style: t.titleSmall),
                          Text('بنختار صوت Azure حسب لهجة الشخصية ونوعها', style: t.labelSmall),
                        ]),
                      ),
                      Icon(selected == null ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: p.accent),
                    ]),
                  ),
                if (_picking) const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text('أصوات Azure · ${_locale == null ? 'كل البلاد' : AzureTts.localeLabel(_locale!)}', style: t.titleSmall)),
                  Text('${list.length} صوت', style: t.bodySmall),
                ]),
                const SizedBox(height: 8),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (snap.hasError)
                  SCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(snap.error is StudioException ? (snap.error as StudioException).message : 'معرفناش نجيب الأصوات.', style: t.bodyMedium),
                      const SizedBox(height: 10),
                      GhostButton(label: 'حاول تاني', icon: Icons.refresh_rounded, onPressed: () => setState(() => _load(az, refresh: true))),
                    ]),
                  ),
              ]),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, _picking ? 30 : 130),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final v = list[i];
                  final id = 'az_${v.shortName}';
                  final playing = player.id == id && player.playing;
                  final isSel = v.shortName == selected;
                  return SCard(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    radius: 20,
                    borderColor: isSel || playing ? p.accent : null,
                    child: Row(children: [
                      VoiceAvatar(letter: v.shortLabel.isEmpty ? '؟' : v.shortLabel[0], seed: v.shortName.hashCode),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(v.displayName, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(v.shortLabel,
                                  overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Fonts.latin, fontSize: 10.5, color: p.muted)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Waveform(
                            peaks: _peaks[v.shortName] ?? List.generate(30, (k) => 0.15 + 0.1 * ((k * 7 + v.shortName.length) % 5)),
                            progress: playing ? player.progress : 0,
                            height: 16,
                          ),
                          const SizedBox(height: 4),
                          Text('${v.country} · ${v.isMale ? Gender.male.label : Gender.female.label} · ${v.locale}', style: t.labelSmall),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      _AzPlay(
                        loading: _loading == v.shortName,
                        playing: playing,
                        active: isSel || playing,
                        onTap: () => playing ? ref.read(playerProvider.notifier).stop() : _preview(az, v),
                      ),
                      if (_picking) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'اختيار',
                          onPressed: () => _pick(v.shortName),
                          icon: Icon(isSel ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: p.accent),
                        ),
                      ],
                    ]),
                  ).animate().fadeIn(delay: (20 * i.clamp(0, 15)).ms, duration: 220.ms);
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _AzPlay extends StatelessWidget {
  const _AzPlay({required this.loading, required this.playing, required this.active, required this.onTap});
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
