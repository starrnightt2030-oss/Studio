import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/palette.dart';
import '../../data/catalog/dialects.dart';
import '../../data/catalog/voices.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';
import '../home/home_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final list = ref.watch(projectsProvider);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 130),
        children: [
          Text('مشاريعي', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('${list.length} مشروع محفوظ على جهازك', style: t.bodySmall),
          const SizedBox(height: 16),
          if (list.isEmpty)
            SCard(child: Text('مفيش مشاريع لسه. اضغط على المايك عشان تبدأ.', style: t.bodyMedium))
          else
            for (final p in list)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: ProjectTile(project: p, showMenu: true)),
        ],
      ),
    );
  }
}

class ProjectTile extends ConsumerWidget {
  const ProjectTile({super.key, required this.project, this.showMenu = false});
  final Project project;
  final bool showMenu;

  static const _typeColors = {
    ProjectType.voiceover: [Color(0xFFFCE7F3), Color(0xFFBE185D), Color(0xFF2E1A2A), Color(0xFFF472B6)],
    ProjectType.audiobook: [Color(0xFFFFEDD5), Color(0xFFC2410C), Color(0xFF2B2010), Color(0xFFFDBA74)],
    ProjectType.podcast: [Color(0xFFDBEAFE), Color(0xFF1D4ED8), Color(0xFF121D33), Color(0xFF7DD3FC)],
    ProjectType.story: [Color(0xFFD1FAE5), Color(0xFF047857), Color(0xFF0F261E), Color(0xFF5EEAD4)],
  };
  static const _typeIcons = {
    ProjectType.voiceover: Icons.mic_rounded,
    ProjectType.audiobook: Icons.menu_book_rounded,
    ProjectType.podcast: Icons.groups_rounded,
    ProjectType.story: Icons.auto_stories_rounded,
  };

  void _open(BuildContext context) =>
      context.push(project.type.multiVoice ? '/podcast/${project.id}' : '/studio/${project.id}');

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: project.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم المشروع'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      final p = project.copy()..title = v;
      await ref.read(projectsProvider.notifier).save(p);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final c = _typeColors[project.type]!;
    final voice = VoiceCatalog.byId(project.voiceId);
    final dur = project.durationMs > 0 ? ' · ${formatDuration(Duration(milliseconds: project.durationMs))}' : '';
    final meta = project.type.multiVoice
        ? '${Dialects.byId(project.dialectId).short} · ${project.speakers.length} أدوار$dur'
        : '${voice.dialect.short} · ${voice.name} · ${project.segments.length} جملة$dur';

    return SCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      radius: 18,
      onTap: () => _open(context),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: p.isDark ? c[2] : c[0], borderRadius: BorderRadius.circular(13)),
          child: Icon(_typeIcons[project.type], color: p.isDark ? c[3] : c[1], size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall),
          ]),
        ),
        RecentPlayButton(project: project),
        if (showMenu)
          PopupMenuButton<String>(
            tooltip: 'خيارات',
            icon: Icon(Icons.more_vert_rounded, color: p.muted),
            onSelected: (v) async {
              if (v == 'rename') await _rename(context, ref);
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('حذف المشروع؟'),
                    content: Text('هيتمسح "${project.title}" والصوت بتاعه من جهازك.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حذف', style: TextStyle(color: p.danger))),
                    ],
                  ),
                );
                if (ok == true) await ref.read(projectsProvider.notifier).delete(project.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('تغيير الاسم')),
              PopupMenuItem(value: 'delete', child: Text('حذف')),
            ],
          ),
      ]),
    );
  }
}
