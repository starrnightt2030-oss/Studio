import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player.dart';
import '../../core/errors.dart';
import '../../core/theme/palette.dart';
import '../../data/gemini/gemini_client.dart';
import '../../data/projects/models.dart';
import '../../data/quran/quran.dart';
import '../../widgets/ui.dart';

class QuranChoice {
  const QuranChoice({this.ayah, this.reciter, this.text, this.remove = false});
  final String? ayah;
  final String? reciter;
  final String? text;
  final bool remove;
}

/// الجملة دي آية؟ نحدد السورة والآية، نتأكد من النص بالمصحف، ونختار القارئ.
Future<QuranChoice?> showQuranSheet(BuildContext context, Segment s) => showModalBottomSheet<QuranChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _QuranSheet(s),
      ),
    );

class _QuranSheet extends ConsumerStatefulWidget {
  const _QuranSheet(this.s);
  final Segment s;

  @override
  ConsumerState<_QuranSheet> createState() => _QuranSheetState();
}

class _QuranSheetState extends ConsumerState<_QuranSheet> {
  late final _surah = TextEditingController();
  late final _from = TextEditingController();
  late final _to = TextEditingController();
  late String _reciter = widget.s.reciter ?? Quran.defaultReciter;
  VerifiedAyat? _v;
  String? _busy;

  @override
  void initState() {
    super.initState();
    final r = AyahRef.parse(widget.s.ayah);
    if (r != null) {
      _surah.text = '${r.surah}';
      _from.text = '${r.from}';
      if (r.to != r.from) _to.text = '${r.to}';
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  @override
  void dispose() {
    _surah.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  AyahRef? get _ref {
    final s = int.tryParse(_surah.text.trim()), f = int.tryParse(_from.text.trim());
    if (s == null || f == null) return null;
    final r = AyahRef(s, f, int.tryParse(_to.text.trim()));
    return r.valid ? r : null;
  }

  Future<void> _detect() async {
    final client = ref.read(geminiClientProvider);
    if (client == null) return showStudioError(context, StudioException.noKey);
    setState(() => _busy = 'بيتعرّف على الآية…');
    try {
      final found = await Quran.detect(client, [widget.s.text]);
      final r = found[0];
      if (r == null) throw const StudioException('مش لاقي إن الجملة دي آية — اكتب رقم السورة والآية بإيدك.');
      _surah.text = '${r.surah}';
      _from.text = '${r.from}';
      _to.text = r.to == r.from ? '' : '${r.to}';
      await _verify();
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _verify() async {
    final r = _ref;
    if (r == null) return showStudioMessage(context, 'اكتب رقم السورة (1–114) ورقم الآية.');
    setState(() => _busy = 'بنتأكد من النص في المصحف…');
    try {
      final v = await Quran.verify(r, written: widget.s.ayah == null ? widget.s.text : null);
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _listen() async {
    final r = _v?.ref ?? _ref;
    if (r == null) return;
    setState(() => _busy = 'بنحمّل التلاوة…');
    try {
      final wav = await Quran.recitation(r, _reciter, onStatus: (st) {
        if (mounted) setState(() => _busy = st);
      });
      await ref.read(playerProvider.notifier).playBytes('quran_$r$_reciter', wav);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final v = _v;
    Widget num(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() => _v = null),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تلاوة حقيقية للآية', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('الآيات بتتقرا بصوت قارئ معروف بأحكام التجويد — مش بالذكاء الاصطناعي.', style: t.bodySmall),
          const SizedBox(height: 14),
          GhostButton(label: 'اتعرّف على الآية من النص تلقائياً', icon: Icons.auto_awesome_rounded, onPressed: _busy == null ? _detect : null),
          const SizedBox(height: 12),
          Row(children: [
            num(_surah, 'رقم السورة'),
            const SizedBox(width: 8),
            num(_from, 'من آية'),
            const SizedBox(width: 8),
            num(_to, 'لحد آية (اختياري)'),
          ]),
          const SizedBox(height: 10),
          if (v == null) GhostButton(label: 'تأكّد من النص في المصحف', icon: Icons.menu_book_rounded, onPressed: _busy == null ? _verify : null),
          if (_busy != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
                const SizedBox(width: 10),
                Expanded(child: Text(_busy!, style: t.labelSmall)),
              ]),
            ),
          if (v != null) ...[
            SCard(
              padding: const EdgeInsets.all(14),
              radius: 18,
              borderColor: p.accent,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.ref.label(v.surahName), style: t.titleSmall?.copyWith(color: p.accent)),
                const SizedBox(height: 8),
                Text('﴿${v.text}﴾', style: t.bodyLarge?.copyWith(height: 2)),
              ]),
            ),
            if (v.match < 0.6) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFE0A030)),
                const SizedBox(width: 6),
                Expanded(child: Text('النص اللي كاتبه مختلف عن الآية دي — اتأكد من الرقم. لو صح، هنستخدم نص المصحف.', style: t.labelSmall)),
              ]),
            ],
            const SizedBox(height: 14),
            Text('القارئ', style: t.labelSmall),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _reciter,
              isExpanded: true,
              items: [for (final r in Quran.reciters) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (x) => setState(() => _reciter = x ?? _reciter),
            ),
            const SizedBox(height: 10),
            GhostButton(label: 'اسمع التلاوة', icon: Icons.play_arrow_rounded, onPressed: _busy == null ? _listen : null),
            const SizedBox(height: 8),
            GradientButton(
              label: 'استخدم التلاوة دي',
              icon: Icons.check_rounded,
              onPressed: _busy != null
                  ? null
                  : () {
                      Quran.setDefaultReciter(_reciter);
                      Navigator.pop(context, QuranChoice(ayah: '${v.ref}', reciter: _reciter, text: '﴿${v.text}﴾'));
                    },
            ),
          ],
          if (widget.s.ayah != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, const QuranChoice(remove: true)),
              child: Text('مش آية — رجّعها جملة عادية', style: TextStyle(color: p.muted)),
            ),
          ],
        ]),
      ),
    );
  }
}
