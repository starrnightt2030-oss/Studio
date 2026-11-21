import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/audio/mastering.dart';
import '../../core/audio/subtitles.dart';
import '../../core/audio/wav.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/projects/models.dart';
import '../../widgets/ui.dart';

/// لوحة التصدير: الصيغة، مستوى الصوت حسب مكان النشر، وملف الترجمة.
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
    orElse: () => Mastering.canEncodeM4a ? ExportFormat.m4a : ExportFormat.wav,
  );
  late LoudnessTarget _target = LoudnessTarget.values.firstWhere(
    (t) => t.name == LocalDb.settings.get('exportTarget'),
    orElse: () => LoudnessTarget.video,
  );
  late bool _srt = LocalDb.settings.get('exportSrt', defaultValue: true) as bool;
  bool _busy = false;

  String get _baseName => widget.project.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> _export() async {
    setState(() => _busy = true);
    await LocalDb.settings.putAll({'exportFormat': _format.name, 'exportTarget': _target.name, 'exportSrt': _srt});
    try {
      // نسيب الواجهة ترسم مؤشر التحميل قبل الحسابات التقيلة
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final (bytes, fmt) = await Mastering.export(widget.master, format: _format, target: _target);
      final files = <XFile>[XFile.fromData(bytes, mimeType: fmt.mime, name: '$_baseName.${fmt.ext}')];
      if (_srt && widget.starts.isNotEmpty) {
        final srt = Subtitles.srt(
          widget.project,
          widget.starts,
          offset: Mastering.leadingTrim(widget.master),
          total: Wav.durationOf(widget.master),
        );
        files.add(XFile.fromData(Uint8List.fromList(utf8.encode('﻿$srt')), mimeType: 'application/x-subrip', name: '$_baseName.srt'));
      }
      if (_format == ExportFormat.m4a && fmt != ExportFormat.m4a && mounted) {
        showStudioMessage(context, 'M4A مش متاح على الجهاز ده، فاتصدّر WAV بجودة عالية.');
      }
      await Share.shareXFiles(files, text: 'اتعمل بـ Studio-Eldawly');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
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
          Text('تصدير احترافي', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('قص الصمت وتوحيد مستوى الصوت وتحويله لـ 48kHz بيتعملوا تلقائياً.', style: t.bodySmall),
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
                    onTap: () => setState(() => _format = f),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(f == _format ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: p.accent),
                        const SizedBox(width: 6),
                        Text(f.label, style: TextStyle(fontFamily: Fonts.latin, fontWeight: FontWeight.w700, color: p.text)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        f == ExportFormat.m4a && !Mastering.canEncodeM4a ? 'متاح على أندرويد' : f.hint,
                        style: t.labelSmall,
                      ),
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
                onTap: () => setState(() => _target = lt),
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _srt,
            onChanged: (v) => setState(() => _srt = v),
            title: Text('ملف ترجمة SRT', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('متزامن مع الجمل — للمونتاج على CapCut وPremiere', style: t.labelSmall),
          ),
          const SizedBox(height: 10),
          GradientButton(label: 'تصدير ومشاركة', icon: Icons.ios_share_rounded, loading: _busy, onPressed: _export),
        ]),
      ),
    );
  }
}
