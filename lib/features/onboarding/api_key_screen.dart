import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/settings/settings.dart';
import '../../core/storage/key_store.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/gemini/gemini_client.dart';
import '../../widgets/ui.dart';

class ApiKeyScreen extends ConsumerStatefulWidget {
  const ApiKeyScreen({super.key, this.editing = false});
  final bool editing;

  @override
  ConsumerState<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends ConsumerState<ApiKeyScreen> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _status;
  bool _ok = false;

  static final _studioUrl = Uri.parse('https://aistudio.google.com/apikey');

  @override
  void initState() {
    super.initState();
    final k = ref.read(apiKeyProvider);
    if (k != null) {
      _ctrl.text = k;
      _ok = true;
      _status = 'المفتاح محفوظ وشغال';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _ctrl.text = d!.text!.trim());
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.length < 20) {
      setState(() {
        _ok = false;
        _status = 'المفتاح شكله ناقص. انسخه كامل من Google AI Studio.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جاري التأكد من المفتاح…';
    });
    try {
      final n = await GeminiClient(key).verifyKey();
      await LocalDb.settings.delete('autoTtsModel');
      await ref.read(apiKeyProvider.notifier).set(key);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _status = 'تم الاتصال بنجاح ($n موديل متاح)';
      });
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) context.go('/');
    } on StudioException catch (e) {
      setState(() {
        _ok = false;
        _status = e.message;
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = 'تعذّر الاتصال: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Row(children: [
                if (widget.editing) BackSquare(onPressed: () => context.go('/settings')),
                if (widget.editing) const SizedBox(width: 12),
                Text('مفتاح Gemini', style: t.titleLarge),
              ]),
              const SizedBox(height: 22),
              Center(
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surface,
                    border: Border.all(color: p.isDark ? const Color(0xFF8B5CF6) : const Color(0xFFC9BCFF), width: 2),
                    boxShadow: p.isDark
                        ? const [BoxShadow(color: Color(0xB38B5CF6), blurRadius: 36)]
                        : const [BoxShadow(color: Color(0x406C4DE6), blurRadius: 36, offset: Offset(0, 16))],
                  ),
                  child: Icon(Icons.key_rounded, size: 44, color: p.accent),
                ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'مجاني بالكامل، '),
                  TextSpan(text: 'بمفتاحك انت', style: TextStyle(color: p.accent)),
                ]),
                textAlign: TextAlign.center,
                style: t.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text('المفتاح مجاني من Google، وبيديك حصة استخدام خاصة بيك لوحدك.',
                  textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: p.muted)),
              const SizedBox(height: 20),
              SCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (i, s) in const ['ادخل Google AI Studio بحساب جوجل', 'اضغط Create API key وانسخه', 'الصقه هنا واضغط حفظ'].indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(gradient: p.segment, shape: BoxShape.circle),
                          child: Text('${i + 1}',
                              style: const TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(s, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  TextButton.icon(
                    onPressed: () => launchUrl(_studioUrl, mode: LaunchMode.externalApplication),
                    icon: Icon(Icons.open_in_new_rounded, size: 16, color: p.accent),
                    label: Text('افتح Google AI Studio',
                        style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, color: p.accent)),
                  ),
                ]),
              ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.05),
              const SizedBox(height: 18),
              Text('مفتاح API', style: t.labelMedium?.copyWith(color: p.muted)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(fontFamily: Fonts.latin, fontSize: 13.5, color: p.text),
                decoration: InputDecoration(
                  hintText: 'AIza…',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: _ok ? p.ok.withValues(alpha: 0.6) : p.line, width: 1.5),
                  ),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: _obscure ? 'إظهار' : 'إخفاء',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: p.muted),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: TextButton(onPressed: _paste, child: Text('لصق', style: TextStyle(fontWeight: FontWeight.w700, color: p.accent))),
                    ),
                  ]),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(_ok ? Icons.check_circle_rounded : (_busy ? Icons.hourglass_top_rounded : Icons.error_outline_rounded),
                      size: 16, color: _ok ? p.ok : (_busy ? p.muted : p.danger)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_status!,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ok ? p.ok : (_busy ? p.muted : p.danger))),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              SCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.offlineFallback,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setOfflineFallback(v),
                  title: Text('صوت احتياطي بدون إنترنت', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('لو الحصة خلصت، تقدر تسمع النص بصوت الجهاز', style: t.bodySmall),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: p.muted),
                const SizedBox(width: 6),
                Expanded(child: Text('المفتاح بيتحفظ مشفّر على جهازك، ومش بيتبعت لأي سيرفر غير Google.', style: t.bodySmall)),
              ]),
              const SizedBox(height: 22),
              GradientButton(label: 'حفظ والبدء', icon: Icons.arrow_back_rounded, loading: _busy, onPressed: _save),
              if (widget.editing && ref.watch(apiKeyProvider) != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await ref.read(apiKeyProvider.notifier).clear();
                    if (context.mounted) context.go('/key');
                  },
                  child: Text('حذف المفتاح من الجهاز', style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
