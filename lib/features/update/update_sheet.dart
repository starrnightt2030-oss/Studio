import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/update/updater.dart';
import '../../core/theme/palette.dart';
import '../../widgets/ui.dart';

bool _sheetOpen = false;

/// شاشة «تحديث جديد»: الجديد في النسخة، تحميل بشريط تقدّم، وبعدين «تثبيت».
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) async {
  if (_sheetOpen) return;
  _sheetOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => _UpdateSheet(info),
    );
  } finally {
    _sheetOpen = false;
  }
}

/// بيفحص التحديثات أول ما الرئيسية تفتح، وكل ما ترجع للتطبيق (مرة كل دقيقة بالكتير).
class UpdateWatcher extends StatefulWidget {
  const UpdateWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> with WidgetsBindingObserver {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (!Updater.supported) return;
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(seconds: 3), _run);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  Future<void> _run() async {
    if (!mounted || _sheetOpen || DateTime.now().difference(_last) < const Duration(minutes: 1)) return;
    _last = DateTime.now();
    try {
      final info = await Updater.check();
      if (info == null || Updater.wasShown(info.latest) || !mounted) return;
      await Updater.markShown(info.latest);
      if (mounted) await showUpdateSheet(context, info);
    } catch (_) {
      // من غير نت أو GitHub مش متاح — نجرّب المرة الجاية
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Stage { ask, down, ready, permission, fail }

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet(this.info);
  final UpdateInfo info;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> with WidgetsBindingObserver {
  _Stage _stage = _Stage.ask;
  int _got = 0, _total = 0;
  String? _file;
  DateTime _lastInstall = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // لما يرجع من شاشة «السماح بالتثبيت» نفتح التثبيت على طول
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.permission) _install();
  }

  static String _mb(int b) => (b / 1048576).toStringAsFixed(b < 104858 ? 2 : 1);

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.down;
      _got = 0;
      _total = widget.info.size;
    });
    try {
      _file = await Updater.download(widget.info, (r, t) {
        if (mounted) {
          setState(() {
            _got = r;
            _total = t;
          });
        }
      });
      if (mounted) setState(() => _stage = _Stage.ready);
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.fail);
    }
  }

  // ضغطة واحدة = شاشة تثبيت واحدة
  Future<void> _install() async {
    if (_file == null || DateTime.now().difference(_lastInstall) < const Duration(seconds: 6)) return;
    _lastInstall = DateTime.now();
    try {
      final ok = await Updater.install(_file!);
      if (mounted) setState(() => _stage = ok ? _Stage.ready : _Stage.permission);
    } catch (_) {
      _lastInstall = DateTime.fromMillisecondsSinceEpoch(0);
      if (mounted) setState(() => _stage = _Stage.fail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final info = widget.info;
    final pct = _total > 0 ? (_got / _total).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: _stage != _Stage.down,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: p.segment, boxShadow: p.ctaShadow),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                ).animate().scale(begin: const Offset(0, 0), curve: Curves.elasticOut, duration: 700.ms).rotate(begin: -0.3),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('تحديث جديد لـ Studio-Eldawly', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('الإصدار ${info.latest} — عندك $appVersion', style: t.labelSmall),
                  ]),
                ),
              ]),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('الجديد في التحديث', style: t.labelSmall),
                const SizedBox(height: 8),
                SCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (i, n) in info.notes.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 7, color: p.accent)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(n, style: t.bodyMedium?.copyWith(height: 1.6))),
                        ]),
                      ).animate().fadeIn(delay: (200 + 70 * i).ms).slideX(begin: 0.15),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              ..._actions(t, p, pct),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(TextTheme t, StudioPalette p, double pct) {
    final info = widget.info;
    switch (_stage) {
      case _Stage.ask:
        return [
          Text(
            'التحديث هيتحمّل جوّه التطبيق${info.size > 0 ? ' (${_mb(info.size)} ميجا)' : ''}، وبعدها تدوس «تثبيت» — مفتاحك ومشاريعك كلها هتفضل زي ما هي.',
            style: t.labelSmall?.copyWith(height: 1.7),
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'حدّث الآن', icon: Icons.download_rounded, onPressed: _download),
          const SizedBox(height: 8),
          GhostButton(label: 'لاحقاً', onPressed: () => Navigator.pop(context)),
        ];
      case _Stage.down:
        return [
          Row(children: [
            Expanded(child: Text('جاري تحميل التحديث…', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text('${(pct * 100).round()}%', textDirection: TextDirection.ltr, style: t.bodyMedium?.copyWith(color: p.accent, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: pct < 0.03 ? 0.03 : pct),
              duration: const Duration(milliseconds: 250),
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, color: p.accent, backgroundColor: p.surface2),
            ),
          ),
          const SizedBox(height: 8),
          Text(_total > 0 ? '${_mb(_got)} من ${_mb(_total)} ميجا — خليك فاتح التطبيق لحد ما يخلص' : 'بيبدأ التحميل…', style: t.labelSmall),
        ];
      case _Stage.ready:
        return [
          Row(children: [
            Icon(Icons.check_circle_rounded, color: p.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('التحديث اتحمّل كامل ✓ — دوس «تثبيت التحديث»', style: t.bodyMedium)),
          ]),
          const SizedBox(height: 12),
          GradientButton(label: 'تثبيت التحديث', icon: Icons.system_update_rounded, onPressed: _install),
        ];
      case _Stage.permission:
        return [
          Text('أندرويد محتاج تسمح لـ Studio-Eldawly بتثبيت التحديثات مرة واحدة بس: فعّل «السماح من هذا المصدر» وارجع، والتثبيت هيفتح لوحده.',
              style: t.bodyMedium?.copyWith(height: 1.7)),
          const SizedBox(height: 12),
          GradientButton(label: 'تثبيت التحديث', icon: Icons.system_update_rounded, onPressed: () {
            _lastInstall = DateTime.fromMillisecondsSinceEpoch(0);
            _install();
          }),
        ];
      case _Stage.fail:
        return [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE0507A)),
            const SizedBox(width: 8),
            Expanded(child: Text('التحميل ما كملش (ممكن النت فصل). جرّب تاني.', style: t.bodyMedium)),
          ]),
          const SizedBox(height: 12),
          GradientButton(label: 'جرّب تاني', icon: Icons.refresh_rounded, onPressed: _download),
          const SizedBox(height: 8),
          GhostButton(label: 'حمّله من المتصفح', icon: Icons.public_rounded, onPressed: () => Updater.openInBrowser(info)),
          const SizedBox(height: 8),
          GhostButton(label: 'لاحقاً', onPressed: () => Navigator.pop(context)),
        ];
    }
  }
}
