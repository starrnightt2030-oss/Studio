import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/palette.dart';
import '../data/catalog/emotions.dart';

/// خلفية الشاشات بالتوهج العلوي.
class StudioBackground extends StatelessWidget {
  const StudioBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.bg, gradient: p.background),
      child: child,
    );
  }
}

/// كارت أساسي.
class SCard extends StatelessWidget {
  const SCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.radius = 22, this.borderColor, this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? p.line, width: borderColor == null ? 1 : 1.5),
        boxShadow: p.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

/// زرار مربع صغير (رجوع، بحث، …).
class SquareButton extends StatelessWidget {
  const SquareButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.size = 44});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 20, color: p.text)),
        ),
      ),
    );
  }
}

class BackSquare extends StatelessWidget {
  const BackSquare({super.key, this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SquareButton(
        icon: Icons.arrow_forward_ios_rounded,
        tooltip: 'رجوع',
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      );
}

/// زرار بتدرّج لوني (الأساسي).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 58,
    this.trailing,
    this.hero = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;
  final String? trailing;

  /// زرار على الكارت البنفسجي (أبيض في الداكن، نعناعي في الفاتح).
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;
    final fg = hero ? p.heroButtonText : p.ctaText;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || loading ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: hero ? p.heroButton : p.cta,
          borderRadius: BorderRadius.circular(height / 2.9),
          boxShadow: enabled ? p.ctaShadow : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2.9),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  }
                : null,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                    else if (icon != null)
                      Icon(icon, color: fg, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: 15.5, color: fg)),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      Text(trailing!,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontFamily: Fonts.latin, fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زرار بإطار بس.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.onPressed, this.icon, this.height = 54});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18, color: p.accent),
        label: Text(label, style: TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w600, color: p.text, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          backgroundColor: p.surface,
          side: BorderSide(color: p.ghostLine, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}

/// اختيارات متجاورة (رجل/سيدة، العمر، الشدة…).
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({super.key, required this.items, required this.selected, required this.label, required this.onChanged, this.height = 40});
  final List<T> items;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF100E18) : p.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
        boxShadow: p.cardShadow,
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: Semantics(
                selected: it == selected,
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(it);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: it == selected ? p.segment : null,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: it == selected ? p.ctaShadow.map((s) => BoxShadow(color: s.color, blurRadius: 14, offset: s.offset)).toList() : null,
                    ),
                    child: Text(
                      label(it),
                      style: TextStyle(
                        fontFamily: Fonts.display,
                        fontSize: 13,
                        fontWeight: it == selected ? FontWeight.w600 : FontWeight.w400,
                        color: it == selected ? Colors.white : p.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// شريحة اختيار (لهجة مثلاً).
class ChoiceChipPill extends StatelessWidget {
  const ChoiceChipPill({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.accent : p.surface,
          gradient: selected ? p.segment : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.transparent : p.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 12.5, color: selected ? Colors.white : p.text)),
      ),
    );
  }
}

/// موجة صوت مرسومة.
class Waveform extends StatelessWidget {
  const Waveform({super.key, required this.peaks, this.progress = 0, this.height = 40, this.played, this.rest, this.onSeek});
  final List<double> peaks;
  final double progress;
  final double height;
  final Color? played;
  final Color? rest;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = CustomPaint(
      size: Size(double.infinity, height),
      painter: _WavePainter(peaks, progress, played ?? p.played, rest ?? p.track),
    );
    if (onSeek == null) return SizedBox(height: height, child: w);
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onSeek!(_frac(d.localPosition.dx, c.maxWidth, context)),
        onHorizontalDragUpdate: (d) => onSeek!(_frac(d.localPosition.dx, c.maxWidth, context)),
        child: SizedBox(height: height, child: w),
      ),
    );
  }

  double _frac(double x, double width, BuildContext context) {
    // الموجة دايماً من الشمال لليمين زي الوقت
    return (x / width).clamp(0.0, 1.0);
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.peaks, this.progress, this.played, this.rest);
  final List<double> peaks;
  final double progress;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final n = peaks.length;
    final gap = 2.0;
    final bw = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final h = (peaks[i] * size.height).clamp(3.0, size.height);
      final x = i * (bw + gap);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bw, h), Radius.circular(bw / 2));
      canvas.drawRRect(r, Paint()..color = (i + 0.5) / n <= progress ? played : rest);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.progress != progress || old.peaks != peaks || old.played != played;
}

/// أفاتار الشخصية بتدرّج ملون.
class VoiceAvatar extends StatelessWidget {
  const VoiceAvatar({super.key, required this.letter, required this.seed, this.size = 46});
  final String letter;
  final int seed;
  final double size;

  static const gradients = [
    [Color(0xFFF472B6), Color(0xFFC026D3)],
    [Color(0xFF7DD3FC), Color(0xFF3B82F6)],
    [Color(0xFFFDBA74), Color(0xFFF97316)],
    [Color(0xFF5EEAD4), Color(0xFF14B8A6)],
    [Color(0xFFA47BFF), Color(0xFF6C4DE6)],
    [Color(0xFFFCD34D), Color(0xFFD97706)],
  ];

  @override
  Widget build(BuildContext context) {
    final g = gradients[seed.abs() % gradients.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: g),
        boxShadow: [BoxShadow(color: g.last.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Text(letter,
          style: TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: size * 0.4, color: Colors.white)),
    );
  }
}

/// شارة الإحساس.
class EmotionTag extends StatelessWidget {
  const EmotionTag({super.key, required this.emotion, this.intensity, this.onTap});
  final Emotion emotion;
  final Intensity? intensity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: emotion.bg(dark), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: emotion.dot(dark), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            intensity == null || emotion == Emotion.neutral ? emotion.label : '${emotion.label} · ${intensity!.label}',
            style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 11.5, color: emotion.fg(dark)),
          ),
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(action!, style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 12.5, color: p.accent)),
        ),
    ]);
  }
}

/// شعار التطبيق: المايك + الاسم.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 42, this.showSubtitle = true});
  final double size;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.asset('assets/images/mic.jpg', width: size, height: size, fit: BoxFit.cover),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Studio', style: TextStyle(color: p.text)),
            TextSpan(text: '-', style: TextStyle(color: p.accent)),
            TextSpan(text: 'Eldawly', style: TextStyle(color: p.text)),
          ]), style: const TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.2)),
        ),
        if (showSubtitle) Text('استوديو الصوت العربي', style: TextStyle(fontSize: 11.5, color: p.muted)),
      ]),
    ]);
  }
}

void showStudioError(BuildContext context, Object e) {
  final msg = e is StudioException ? e.message : 'حصل خطأ: $e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showStudioMessage(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
