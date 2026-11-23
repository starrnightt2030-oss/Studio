import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/file_saver.dart';
import '../../core/errors.dart';
import '../../core/audio/mastering.dart';
import '../../core/audio/subtitles.dart';
import '../../core/audio/wav.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/projects/models.dart';
import '../../widgets/ui.dart';

/// لوحة التصدير: MP3 أو WAV، مستوى الصوت حسب مكان النشر، ملف الترجمة،
/// والحفظ في Download/Studio-Eldawly أو المشاركة.
Future<void> showExportSheet(BuildContext context, {required Project project, required Uint8List master, required Map<String, Duration> starts}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExportSheet(project, master, starts),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet(this.project, this.master, this.starts);
  final Project project;
  final Uint8List master;
  final Map<String, Duration> starts;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportFormat _format = ExportFormat.values.firstWhere(
    (f) => f.name == LocalDb.settings.get('exportFormat'),
    orElse: () => ExportFormat.mp3,
  );
  late LoudnessTarget _target = LoudnessTarget.values.firstWhere(
    (t) => t.name == LocalDb.settings.get('exportTarget'),
    orElse: () => LoudnessTarget.video,
  );
  late bool _srt = LocalDb.settings.get('exportSrt', defaultValue: false) as bool;
  String? _busy; // 'save' أو 'share'

  // التحويل بيبدأ أول ما الشاشة تفتح، فلما تدوس «حفظ» يكون خلص أو قرّب
  final _jobs = <String, Future<Uint8List>>{};
  final _startedAt = <String, DateTime>{};
  Timer? _tick;

  String get _jobKey => '${_format.name}|${_target.name}';

  Future<Uint8List> _audio() {
    final key = _jobKey;
    return _jobs.putIfAbsent(key, () {
      _startedAt[key] = DateTime.now();
      final f = Mastering.export(widget.master, format: _format, target: _target).then((r) => r.$1);
      // لو فشل نسمح بمحاولة تانية
      f.catchError((Object _) {
        _jobs.remove(key);
        return Uint8List(0);
      });
      return f;
    });
  }

  /// نسبة تقريبية للتحويل (بالوقت، لأن المشفّر مبيبلّغش بتقدّمه).
  double get _progress {
    final st = _startedAt[_jobKey];
    if (st == null) return 0;
    final est = Mastering.estimate(widget.master, _format).inMilliseconds;
    return (DateTime.now().difference(st).inMilliseconds / est).clamp(0.0, 0.95);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _audio();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<List<OutFile>> _build() async {
    await LocalDb.settings.putAll({'exportFormat': _format.name, 'exportTarget': _target.name, 'exportSrt': _srt});
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    final fmt = _format;
    final est = Mastering.estimate(widget.master, fmt);
    final Uint8List bytes;
    try {
      bytes = await _audio().timeout(est * 4 + const Duration(seconds: 60));
    } on TimeoutException {
      throw const StudioException('التحويل لـ MP3 أخد وقت أطول من المتوقع — جرّب صيغة WAV.', code: 'export_slow');
    } finally {
      _tick?.cancel();
    }
    if (bytes.isEmpty) throw const StudioException('حصلت مشكلة في التحويل — جرّب تاني أو اختار WAV.', code: 'export_failed');
    final base = StudioFiles.fileName(widget.project.title, fmt.ext);
    final files = [OutFile(bytes, base, fmt.mime)];
    if (_srt && widget.starts.isNotEmpty) {
      final srt = Subtitles.srt(
        widget.project,
        widget.starts,
        offset: Mastering.leadingTrim(widget.master),
        total: Wav.durationOf(widget.master),
      );
      final srtName = '${base.substring(0, base.lastIndexOf('.'))}.srt';
      files.add(OutFile(Uint8List.fromList(utf8.encode('﻿$srt')), srtName, 'application/x-subrip'));
    }
    return files;
  }

  Future<void> _save() async {
    setState(() => _busy = 'save');
    try {
      final files = await _build();
      final where = await StudioFiles.saveToDownloads(files);
      if (!mounted) return;
      Navigator.pop(context);
      showStudioMessage(context, 'اتحفظ في $where\n${files.map((f) => f.name).join('\n')}');
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = 'share');
    try {
      await StudioFiles.share(await _build(), text: 'اتعمل بـ Studio-Eldawly');
      if (mounted) Navigator.pop(context);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('حفظ وتصدير', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('قص الصمت وتوحيد مستوى الصوت بيتعملوا تلقائياً.', style: t.bodySmall),
          const SizedBox(height: 16),
          Text('الصيغة', style: t.labelSmall),
          const SizedBox(height: 6),
          Row(children: [
            for (final f in ExportFormat.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: SCard(
                    padding: const EdgeInsets.all(12),
                    radius: 18,
                    borderColor: f == _format ? p.accent : null,
                    onTap: () {
                      setState(() => _format = f);
                      _audio();
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(f == _format ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: p.accent),
                        const SizedBox(width: 6),
                        Text(f.label, style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: p.text)),
                      ]),
                      const SizedBox(height: 4),
                      Text(f.hint, style: t.labelSmall),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Text('مستوى الصوت حسب مكان النشر', style: t.labelSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final lt in LoudnessTarget.values)
              ChoiceChipPill(
                label: lt == LoudnessTarget.off ? lt.label : '${lt.label} (${lt.lufs.round()} LUFS)',
                selected: lt == _target,
                onTap: () {
                  setState(() => _target = lt);
                  _audio();
                },
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _srt,
            onChanged: (v) => setState(() => _srt = v),
            title: Text('ملف ترجمة SRT معاه', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('متزامن مع الجمل — للمونتاج على CapCut وPremiere', style: t.labelSmall),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.folder_rounded, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text('بيتحفظ في: Download/${StudioFiles.folder}', style: t.labelSmall)),
          ]),
          if (_busy != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(_format == ExportFormat.mp3 ? 'بيحوّل لـ MP3…' : 'بيجهّز الملف…', style: t.labelSmall)),
              Text('${(_progress * 100).round()}%', textDirection: TextDirection.ltr, style: t.labelSmall?.copyWith(color: p.accent)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: _progress < 0.02 ? null : _progress, minHeight: 6, color: p.accent, backgroundColor: p.surface2),
            ),
          ],
          const SizedBox(height: 12),
          GradientButton(
            label: 'حفظ في التنزيلات',
            icon: Icons.download_rounded,
            loading: _busy == 'save',
            onPressed: _busy == null ? _save : null,
          ),
          const SizedBox(height: 8),
          GhostButton(label: _busy == 'share' ? 'جاري التجهيز…' : 'مشاركة', icon: Icons.ios_share_rounded, onPressed: _busy == null ? _share : null),
        ]),
      ),
    );
  }
}
