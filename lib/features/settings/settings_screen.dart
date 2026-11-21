import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings.dart';
import '../../core/storage/key_store.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../core/usage.dart';
import '../../data/azure/azure_tts.dart';
import '../../data/gemini/gemini_client.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<GeminiModel>? _models;
  bool _loadingModels = false;

  Future<void> _loadModels() async {
    final c = ref.read(geminiClientProvider);
    if (c == null) return;
    setState(() => _loadingModels = true);
    try {
      final m = await c.listModels();
      setState(() => _models = m);
    } on DioException catch (e) {
      if (mounted) showStudioError(context, GeminiClient.mapError(e));
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _chooseModel({required bool tts}) async {
    if (_models == null) await _loadModels();
    if (!mounted || _models == null) return;
    final list = _models!.where((m) => tts ? m.isTts : (!m.isTts && m.methods.contains('generateContent') && m.id.contains('gemini'))).toList();
    final s = ref.read(settingsProvider);
    final current = tts ? s.ttsModel : s.textModel;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 16), children: [
            ListTile(
              leading: Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_off, color: ctx.palette.accent),
              title: const Text('تلقائي (أحسن موديل متاح)'),
              onTap: () => Navigator.pop(ctx, '__auto__'),
            ),
            for (final m in list)
              ListTile(
                leading: Icon(current == m.id ? Icons.radio_button_checked : Icons.radio_button_off, color: ctx.palette.accent),
                title: Text(m.displayName, textDirection: TextDirection.ltr),
                subtitle: Text(m.id, textDirection: TextDirection.ltr),
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    final n = ref.read(settingsProvider.notifier);
    final value = picked == '__auto__' ? null : picked;
    if (tts) {
      await LocalDb.settings.delete('autoTtsModel');
      await n.setTtsModel(value);
    } else {
      await n.setTextModel(value);
    }
  }

  Widget _usageRow(BuildContext context, String label, String value, double? progress) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: t.bodySmall?.copyWith(color: p.text))),
          Text(value, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: p.accent, fontSize: 12.5)),
        ]),
        if (progress != null) ...[
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress, minHeight: 6)),
        ],
      ]),
    );
  }

  Future<void> _azureDialog(AzureConfig? current) async {
    final keyCtrl = TextEditingController(text: current?.key ?? '');
    var region = current?.region ?? AzureTts.regions.first;
    var busy = false;
    String? status;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final p = ctx.palette;
        final t = Theme.of(ctx).textTheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Azure Speech', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('من بوابة Azure اعمل مورد Speech بالطبقة المجانية (F0)، وانسخ Key والـ Region.', style: t.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'Key'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: region,
              items: [for (final r in AzureTts.regions) DropdownMenuItem(value: r, child: Text(r, textDirection: TextDirection.ltr))],
              onChanged: (v) => set(() => region = v ?? region),
              decoration: const InputDecoration(labelText: 'Region'),
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Text(status!, style: TextStyle(fontWeight: FontWeight.w700, color: status!.startsWith('✓') ? p.ok : p.danger)),
            ],
            const SizedBox(height: 14),
            GradientButton(
              label: 'تأكيد وحفظ',
              loading: busy,
              height: 54,
              onPressed: () async {
                set(() {
                  busy = true;
                  status = null;
                });
                try {
                  final n = await AzureTts(keyCtrl.text.trim(), region).verify();
                  await ref.read(azureConfigProvider.notifier).set(keyCtrl.text.trim(), region);
                  set(() => status = '✓ تمام — لقيت $n صوت عربي');
                } catch (e) {
                  set(() => status = e.toString());
                } finally {
                  set(() => busy = false);
                }
              },
            ),
            if (current != null)
              TextButton(
                onPressed: () async {
                  await ref.read(azureConfigProvider.notifier).clear();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('حذف مفتاح Azure', style: TextStyle(color: p.danger)),
              ),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final key = ref.watch(apiKeyProvider);
    final masked = key == null ? 'مفيش' : '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
    final autoTts = LocalDb.settings.get('autoTtsModel') as String?;
    final azure = ref.watch(azureConfigProvider);

    Widget tile(IconData icon, String title, String? sub, {VoidCallback? onTap, Widget? trailing}) => SCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          radius: 18,
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: p.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (sub != null) Text(sub, style: t.labelSmall),
              ]),
            ),
            trailing ?? Icon(Icons.chevron_left_rounded, color: p.muted),
          ]),
        );

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 130), children: [
        Text('حسابي والإعدادات', style: t.headlineSmall),
        const SizedBox(height: 16),
        Text('المظهر', style: t.labelSmall),
        const SizedBox(height: 6),
        SegmentedPills<ThemeMode>(
          items: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
          selected: s.themeMode,
          label: (m) => switch (m) { ThemeMode.light => 'فاتح', ThemeMode.dark => 'داكن', _ => 'تلقائي' },
          onChanged: (m) => ref.read(settingsProvider.notifier).setTheme(m),
        ),
        const SizedBox(height: 18),
        Text('Gemini', style: t.labelSmall),
        const SizedBox(height: 6),
        tile(Icons.key_rounded, 'مفتاح API', masked, onTap: () => context.push('/key?edit=1')),
        const SizedBox(height: 8),
        tile(Icons.record_voice_over_rounded, 'موديل الصوت', s.ttsModel ?? 'تلقائي${autoTts != null ? ' ($autoTts)' : ''}',
            onTap: () => _chooseModel(tts: true),
            trailing: _loadingModels ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)) : null),
        const SizedBox(height: 8),
        tile(Icons.psychology_rounded, 'موديل النصوص', s.textModel ?? 'تلقائي (${GeminiClient.textFallbacks.first})', onTap: () => _chooseModel(tts: false)),
        const SizedBox(height: 18),
        Text('محرك الصوت', style: t.labelSmall),
        const SizedBox(height: 6),
        SegmentedPills<TtsEngine>(
          items: TtsEngine.values,
          selected: s.engine,
          label: (e) => e.label,
          onChanged: (e) => ref.read(settingsProvider.notifier).setEngine(e),
        ),
        const SizedBox(height: 6),
        Text(s.engine.hint, style: t.labelSmall),
        const SizedBox(height: 8),
        tile(Icons.cloud_rounded, 'مفتاح Azure Speech (اختياري)',
            azure == null ? 'مش متظبط — لأصوات لهجات أصلية وسعة إضافية مجانية' : 'متظبط · منطقة ${azure.region}',
            onTap: () => _azureDialog(azure)),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: Usage.changes,
          builder: (_, __, ___) => SCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الاستهلاك', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _usageRow(context, 'طلبات صوت Gemini النهارده', '${Usage.geminiRequestsToday}', null),
              _usageRow(context, 'طلبات نصوص (إحساس، لهجة، قصص) النهارده', '${Usage.textRequestsToday}', null),
              _usageRow(context, 'حروف Azure الشهر ده', '${Usage.azureCharsMonth} / ${Usage.azureMonthlyFree}',
                  (Usage.azureCharsMonth / Usage.azureMonthlyFree).clamp(0.0, 1.0).toDouble()),
              const SizedBox(height: 4),
              Text('الحصص الفعلية بيحددها Google وMicrosoft لكل مفتاح؛ العداد ده بيحسب اللي اتعمل من جهازك.', style: t.labelSmall),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Text('الإنتاج', style: t.labelSmall),
        const SizedBox(height: 6),
        SCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('المسافة بين الجمل', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text('${s.gapMs}ms', textDirection: TextDirection.ltr, style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: p.accent)),
            ]),
            Slider(
              value: s.gapMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 20,
              onChanged: (v) => ref.read(settingsProvider.notifier).setGap(v.round()),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        SCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.offlineFallback,
            onChanged: (v) => ref.read(settingsProvider.notifier).setOfflineFallback(v),
            title: Text('صوت احتياطي بدون إنترنت', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('لما Gemini مش متاح', style: t.labelSmall),
          ),
        ),
        const SizedBox(height: 8),
        tile(Icons.cleaning_services_rounded, 'تنظيف ملفات الصوت القديمة', 'بيمسح الصوت اللي مش مستخدم في أي مشروع', onTap: () async {
          final n = await ref.read(projectsProvider.notifier).prune();
          if (context.mounted) showStudioMessage(context, 'اتمسح $n ملف.');
        }),
        const SizedBox(height: 24),
        Center(
          child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset('assets/icon/play_store_512.png', width: 120, height: 120)),
            const SizedBox(height: 10),
            Text('الإصدار 1.0.0 · الصوت من Google Gemini', style: t.labelSmall),
            const SizedBox(height: 2),
            Text('الخطوط: Alexandria · Almarai · Sora · Bebas Neue (OFL)', style: t.labelSmall),
            const SizedBox(height: 2),
            Text('موديل الصوت الحالي: ${s.ttsModel ?? autoTts ?? 'هيتحدد أول استخدام'}', style: t.labelSmall, textAlign: TextAlign.center),
          ]),
        ),
      ]),
    );
  }
}
