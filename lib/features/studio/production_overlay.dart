import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/production/production_service.dart';
import '../../data/projects/models.dart';

class ProductionOutcome {
  const ProductionOutcome({this.error, this.cancelled = false});
  final Object? error;
  final bool cancelled;
}

typedef ProductionTask = Future<dynamic> Function(void Function(ProductionProgress) onProgress, bool Function() cancelled);

/// ينتج المشروع بـ Gemini. لو الحصة اليومية خلصت وAzure متظبط، بنسأل:
/// نستنى (الجمل اللي اتولدت محفوظة وبتكمّل من مكانها) ولا نكمّل بـ Azure (جودة أقل).
Future<ProductionOutcome> produceProject(BuildContext context, ProductionService prod, Project p) async {
  final out = await runProduction(context, (onProgress, cancelled) => prod.produce(p, onProgress: onProgress, cancelled: cancelled));
  final e = out.error;
  if (e is! StudioException || !prod.canOfferAzure(e) || !context.mounted) return out;
  final azure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حصة Gemini النهارده خلصت'),
      content: const Text(
        'الجمل اللي اتولدت محفوظة، ولما الحصة ترجع بكرة هتكمّل من مكانك بنفس الجودة.\n\n'
        'تقدر تكمّل دلوقتي بـ Azure، بس جودته أقل وممكن يغلط في النطق — ماننصحش بيه للآيات والأحاديث.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('هستنى Gemini')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('كمّل بـ Azure')),
      ],
    ),
  );
  if (azure != true || !context.mounted) return const ProductionOutcome(cancelled: true);
  return runProduction(context, (onProgress, cancelled) => prod.produce(p, engine: 'azure', onProgress: onProgress, cancelled: cancelled));
}

/// نافذة الإنتاج: تقدّم حقيقي جملة بجملة + إلغاء.
Future<ProductionOutcome> runProduction(BuildContext context, ProductionTask task) async {
  final res = await showDialog<ProductionOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductionDialog(task),
  );
  return res ?? const ProductionOutcome(cancelled: true);
}

class _ProductionDialog extends StatefulWidget {
  const _ProductionDialog(this.task);
  final ProductionTask task;

  @override
  State<_ProductionDialog> createState() => _ProductionDialogState();
}

class _ProductionDialogState extends State<_ProductionDialog> {
  ProductionProgress _p = const ProductionProgress(0, 1, 'جاري التجهيز…');
  bool _cancel = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.task((p) {
        if (mounted) setState(() => _p = p);
      }, () => _cancel);
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.pop(context, const ProductionOutcome());
    } on StudioException catch (e) {
      if (mounted) Navigator.pop(context, ProductionOutcome(error: e, cancelled: e.code == 'cancelled'));
    } catch (e) {
      if (mounted) Navigator.pop(context, ProductionOutcome(error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: p.orb, boxShadow: p.orbGlow),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 36),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(0.94, 0.94), end: const Offset(1.04, 1.04), duration: 900.ms, curve: Curves.easeInOut),
            const SizedBox(height: 18),
            Text('جاري الإنتاج', style: t.titleLarge),
            const SizedBox(height: 6),
            Text(_p.message, textAlign: TextAlign.center, style: t.bodySmall),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: _p.fraction == 0 ? null : _p.fraction, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text('${(_p.fraction * 100).round()}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: p.accent)),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _cancel ? null : () => setState(() => _cancel = true),
              child: Text(_cancel ? 'بيتلغي بعد الجملة الحالية…' : 'إلغاء', style: TextStyle(color: p.muted)),
            ),
          ]),
        ),
      ),
    );
  }
}
