import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../core/utils/text_split.dart';
import '../../data/gemini/text_service.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

class TranscribeScreen extends ConsumerStatefulWidget {
  const TranscribeScreen({super.key});

  @override
  ConsumerState<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends ConsumerState<TranscribeScreen> {
  static const _maxBytes = 18 * 1024 * 1024;
  static const _mimes = {
    'mp3': 'audio/mp3',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'opus': 'audio/ogg',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
  };

  String? _name;
  Uint8List? _bytes;
  String? _mime;
  bool _timestamps = false;
  bool _busy = false;
  final _out = TextEditingController();

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: _mimes.keys.toList(), withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.bytes!.length > _maxBytes) {
      if (mounted) showStudioMessage(context, 'الملف أكبر من 18 ميجا. قصّه لأجزاء أصغر.');
      return;
    }
    setState(() {
      _name = f.name;
      _bytes = f.bytes;
      _mime = _mimes[(f.extension ?? '').toLowerCase()] ?? 'audio/mpeg';
      _out.clear();
    });
  }

  Future<void> _run() async {
    final svc = ref.read(textServiceProvider);
    if (svc == null) return showStudioError(context, StudioException.noKey);
    if (_bytes == null) return;
    setState(() => _busy = true);
    try {
      final text = await svc.transcribe(_bytes!, _mime!, timestamps: _timestamps);
      setState(() => _out.text = text);
    } catch (e) {
      if (mounted) showStudioError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toVoiceover() async {
    final text = _out.text.replaceAll(RegExp(r'\[\d{1,2}:\d{2}\]'), '').trim();
    if (text.isEmpty) return;
    final repo = ref.read(projectsProvider.notifier);
    final p = await repo.create(ProjectType.voiceover, title: 'من تفريغ: ${_name ?? 'ملف'}');
    p.segments = [for (final l in TextSplit.sentences(text)) Segment(text: l)];
    await repo.save(p);
    if (mounted) context.pushReplacement('/studio/${p.id}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            Row(children: [
              BackSquare(onPressed: () => context.pop()),
              const SizedBox(width: 12),
              Text('تفريغ صوت لنص', style: t.titleLarge),
            ]),
            const SizedBox(height: 16),
            SCard(
              onTap: _busy ? null : _pick,
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(colors: [Color(0xFF5EEAD4), Color(0xFF14B8A6)]),
                  ),
                  child: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 10),
                Text(_name ?? 'اختار ملف صوت أو فيديو', style: t.titleSmall, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  _bytes == null ? 'MP3 · WAV · M4A · MP4 — لحد 18 ميجا' : '${(_bytes!.length / 1024 / 1024).toStringAsFixed(1)} ميجا · اضغط للتغيير',
                  style: t.bodySmall,
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SCard(
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _timestamps,
                onChanged: (v) => setState(() => _timestamps = v),
                title: Text('طوابع زمنية [00:00]', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(label: 'ابدأ التفريغ', icon: Icons.subject_rounded, loading: _busy, onPressed: _bytes == null ? null : _run),
            if (_out.text.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionHeader('النص', action: 'نسخ', onAction: () {
                Clipboard.setData(ClipboardData(text: _out.text));
                showStudioMessage(context, 'اتنسخ النص.');
              }),
              SCard(
                child: TextField(
                  controller: _out,
                  maxLines: null,
                  style: TextStyle(fontFamily: Fonts.body, fontSize: 15.5, height: 1.8, color: p.text),
                  decoration: const InputDecoration(filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GhostButton(
                    label: 'مشاركة',
                    icon: Icons.ios_share_rounded,
                    onPressed: () => Share.share(_out.text),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: GradientButton(label: 'حوّله لتعليق', icon: Icons.mic_rounded, height: 54, onPressed: _toVoiceover)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
