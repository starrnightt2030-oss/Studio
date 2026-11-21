import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/mixer.dart';
import '../core/audio/player.dart';
import '../core/theme/palette.dart';
import 'ui.dart';

class MusicChoice {
  const MusicChoice(this.musicId, this.volume, this.duck);
  final String? musicId;
  final double volume;
  final bool duck;
}

/// اختيار موسيقى الخلفية: معاينة، مستوى الصوت، والتوطية التلقائية تحت الكلام.
Future<MusicChoice?> showMusicSheet(BuildContext context, {String? musicId, double volume = 0.25, bool duck = true}) {
  return showModalBottomSheet<MusicChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MusicSheet(musicId, volume, duck),
  );
}

class _MusicSheet extends ConsumerStatefulWidget {
  const _MusicSheet(this.musicId, this.volume, this.duck);
  final String? musicId;
  final double volume;
  final bool duck;

  @override
  ConsumerState<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends ConsumerState<_MusicSheet> {
  late String? _id = widget.musicId;
  late double _vol = widget.volume;
  late bool _duck = widget.duck;

  Future<void> _preview(MusicTrack m) async {
    final st = ref.read(playerProvider);
    if (st.id == 'music_${m.id}' && st.playing) return ref.read(playerProvider.notifier).stop();
    await ref.read(playerProvider.notifier).playBytes('music_${m.id}', await AudioLibrary.load(m.asset));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final st = ref.watch(playerProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), children: [
          Text('موسيقى الخلفية', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('ألحان أصلية للتطبيق، مسموح تستخدمها في أي فيديو.', style: t.bodySmall),
          const SizedBox(height: 12),
          SCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            radius: 18,
            borderColor: _id == null ? p.accent : null,
            onTap: () => setState(() => _id = null),
            child: Row(children: [
              Icon(Icons.music_off_rounded, color: p.muted),
              const SizedBox(width: 12),
              Expanded(child: Text('من غير موسيقى', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (_id == null) Icon(Icons.check_circle_rounded, color: p.accent),
            ]),
          ),
          const SizedBox(height: 8),
          for (final m in AudioLibrary.music)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SCard(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                radius: 18,
                borderColor: _id == m.id ? p.accent : null,
                onTap: () => setState(() => _id = m.id),
                child: Row(children: [
                  IconButton.filledTonal(
                    tooltip: 'معاينة',
                    style: IconButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.accent),
                    onPressed: () => _preview(m),
                    icon: Icon(st.id == 'music_${m.id}' && st.playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.title, style: t.titleSmall),
                      Text(m.mood, style: t.labelSmall),
                    ]),
                  ),
                  if (_id == m.id) Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.check_circle_rounded, color: p.accent)),
                ]),
              ),
            ),
          if (_id != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('مستوى الموسيقى', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text('${(_vol * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
            ]),
            Slider(value: _vol, min: 0.05, max: 0.6, divisions: 11, onChanged: (v) => setState(() => _vol = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _duck,
              onChanged: (v) => setState(() => _duck = v),
              title: Text('توطية تلقائية تحت الكلام', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text('الموسيقى توطى وقت الكلام وتعلى في الوقفات', style: t.labelSmall),
            ),
          ],
          const SizedBox(height: 10),
          GradientButton(label: 'تطبيق', height: 54, onPressed: () {
            ref.read(playerProvider.notifier).stop();
            Navigator.pop(context, MusicChoice(_id, _vol, _duck));
          }),
        ]),
      ),
    );
  }
}

/// اختيار مؤثر صوتي قبل جملة. بيرجّع '' لو اختار "من غير".
Future<String?> showSfxPicker(BuildContext context, WidgetRef ref, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('مؤثر قبل الجملة', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChipPill(label: 'من غير', selected: current == null, onTap: () => Navigator.pop(ctx, '')),
              for (final s in AudioLibrary.sfx)
                GestureDetector(
                  onLongPress: () async => ref.read(playerProvider.notifier).playBytes('sfx_${s.id}', await AudioLibrary.load(s.asset)),
                  child: ChoiceChipPill(
                    label: s.title,
                    selected: current == s.id,
                    onTap: () async {
                      await ref.read(playerProvider.notifier).playBytes('sfx_${s.id}', await AudioLibrary.load(s.asset));
                      if (ctx.mounted) Navigator.pop(ctx, s.id);
                    },
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Text('بتسمع المؤثر لما تختاره.', style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      );
    },
  );
}
