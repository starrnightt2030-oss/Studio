import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/emotions.dart';
import '../../data/gemini/style_builder.dart';
import '../../widgets/ui.dart';

class EmotionSheetResult {
  const EmotionSheetResult(this.emotion, this.intensity, this.controls, {this.applyToAll = false});
  final Emotion emotion;
  final Intensity intensity;
  final VoiceControls controls;
  final bool applyToAll;
}

/// لوحة الإحساس وضبط الصوت (زي التصميم: دايرة فوق، شبكة مشاعر، شدة، عمر، سلايدرات).
Future<EmotionSheetResult?> showEmotionSheet(
  BuildContext context, {
  required String sentence,
  required Emotion emotion,
  required Intensity intensity,
  required VoiceControls controls,
  required Future<void> Function(Emotion, Intensity, VoiceControls) onTry,
}) {
  return showModalBottomSheet<EmotionSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.palette.isDark ? const Color(0xB307060C) : const Color(0x995C4FA0),
    builder: (_) => _EmotionSheet(sentence, emotion, intensity, controls, onTry),
  );
}

class _EmotionSheet extends StatefulWidget {
  const _EmotionSheet(this.sentence, this.emotion, this.intensity, this.controls, this.onTry);
  final String sentence;
  final Emotion emotion;
  final Intensity intensity;
  final VoiceControls controls;
  final Future<void> Function(Emotion, Intensity, VoiceControls) onTry;

  @override
  State<_EmotionSheet> createState() => _EmotionSheetState();
}

class _EmotionSheetState extends State<_EmotionSheet> {
  late Emotion _emo = widget.emotion;
  late Intensity _int = widget.intensity;
  late VoiceControls _c = widget.controls;
  bool _trying = false;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final dark = p.isDark;

    return Padding(
      padding: EdgeInsets.only(top: 60, bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          margin: const EdgeInsets.only(top: 34),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            boxShadow: const [BoxShadow(color: Color(0x2E28146E), blurRadius: 40, offset: Offset(0, -16))],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 46, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('إحساس الجملة', textAlign: TextAlign.center, style: t.titleLarge),
                const SizedBox(height: 4),
                Text('«${widget.sentence}»',
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.75,
                  children: [
                    for (final e in Emotion.values)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _emo = e);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: e == _emo ? e.bg(dark) : (dark ? const Color(0xFF1B1828) : const Color(0xFFF7F5FF)),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: e == _emo ? e.dot(dark) : Colors.transparent, width: 2),
                            boxShadow: e == _emo ? [BoxShadow(color: e.dot(dark).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8))] : null,
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Container(width: 13, height: 13, decoration: BoxDecoration(color: e.dot(dark), shape: BoxShape.circle)),
                            const SizedBox(height: 6),
                            Text(e.label,
                                style: TextStyle(
                                    fontFamily: Fonts.display,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                    color: e == _emo ? e.fg(dark) : p.text)),
                          ]),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('شدة الإحساس', style: t.labelSmall),
                const SizedBox(height: 6),
                SegmentedPills<Intensity>(
                  items: Intensity.values,
                  selected: _int,
                  label: (i) => i.label,
                  onChanged: (i) => setState(() => _int = i),
                  height: 36,
                ),
                const SizedBox(height: 12),
                Text('عمر الصوت', style: t.labelSmall),
                const SizedBox(height: 6),
                SegmentedPills<Age?>(
                  items: const [null, Age.child, Age.young, Age.adult, Age.elder],
                  selected: _c.age,
                  label: (a) => a?.label ?? 'تلقائي',
                  onChanged: (a) => setState(() => _c = VoiceControls(speed: _c.speed, pitch: _c.pitch, warmth: _c.warmth, age: a, purpose: _c.purpose)),
                  height: 36,
                ),
                const SizedBox(height: 10),
                _slider('السرعة', _c.speedLabel, _c.speed, (v) => setState(() => _c = _c.copyWith(speed: v))),
                _slider('طبقة الصوت', _c.pitchLabel, _c.pitch, (v) => setState(() => _c = _c.copyWith(pitch: v))),
                _slider('عمق ودفء الصوت', _c.warmthLabel, _c.warmth, (v) => setState(() => _c = _c.copyWith(warmth: v))),
                CheckboxListTile(
                  value: _all,
                  onChanged: (v) => setState(() => _all = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: p.accent,
                  title: Text('طبّق الإحساس ده على كل الجمل', style: t.bodyMedium),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GhostButton(
                      label: _trying ? 'جاري…' : 'جرّب الجملة',
                      icon: Icons.play_arrow_rounded,
                      onPressed: _trying
                          ? null
                          : () async {
                              setState(() => _trying = true);
                              try {
                                await widget.onTry(_emo, _int, _c);
                              } finally {
                                if (mounted) setState(() => _trying = false);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'تطبيق',
                      height: 54,
                      onPressed: () => Navigator.pop(context, EmotionSheetResult(_emo, _int, _c, applyToAll: _all)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: p.orb,
              boxShadow: p.orbGlow,
              border: Border.all(color: p.surface, width: 5),
            ),
            child: const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white, size: 28),
          ),
        ),
      ]),
    );
  }

  Widget _slider(String label, String value, double v, ValueChanged<double> onChanged) {
    final p = context.palette;
    return Column(children: [
      Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
        Text(value,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, fontSize: 12.5, color: p.accent)),
      ]),
      Slider(value: v, onChanged: onChanged, divisions: 20),
    ]);
  }
}
