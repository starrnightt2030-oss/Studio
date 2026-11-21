import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/player.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/catalog/voices.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';
import '../projects/projects_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, ProjectType type) async {
    final p = await ref.read(projectsProvider.notifier).create(type);
    if (!context.mounted) return;
    context.push(type == ProjectType.podcast ? '/podcast/${p.id}' : '/studio/${p.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final recent = ref.watch(projectsProvider).take(3).toList();

    final studios = [
      _Studio('تعليق صوتي', 'إعلان ووثائقي', Icons.mic_rounded, const [Color(0xFFF472B6), Color(0xFFC026D3)],
          () => _create(context, ref, ProjectType.voiceover)),
      _Studio('كتاب صوتي', 'فصول وراوي', Icons.menu_book_rounded, const [Color(0xFFFDBA74), Color(0xFFF97316)],
          () => _create(context, ref, ProjectType.audiobook)),
      _Studio('بودكاست', 'لحد ٤ متحدثين', Icons.groups_rounded, const [Color(0xFF7DD3FC), Color(0xFF3B82F6)],
          () => _create(context, ref, ProjectType.podcast)),
      _Studio('تفريغ لنص', 'من صوت أو فيديو', Icons.subject_rounded, const [Color(0xFF5EEAD4), Color(0xFF14B8A6)],
          () => context.push('/transcribe')),
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 130),
        children: [
          Row(children: [
            const AppLogo(),
            const Spacer(),
            SquareButton(icon: Icons.search_rounded, tooltip: 'ابحث عن صوت', onPressed: () => context.go('/voices')),
          ]),
          const SizedBox(height: 18),
          _Hero(onStart: () => _create(context, ref, ProjectType.voiceover))
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.15,
            children: [
              for (final (i, s) in studios.indexed)
                SCard(
                  padding: const EdgeInsets.all(12),
                  onTap: s.onTap,
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: s.colors),
                        boxShadow: [BoxShadow(color: s.colors.last.withValues(alpha: 0.32), blurRadius: 16, offset: const Offset(0, 8))],
                      ),
                      child: Icon(s.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.title, style: t.titleSmall),
                        Text(s.subtitle, style: t.labelSmall, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ).animate().fadeIn(delay: (80 * i + 150).ms).slideY(begin: 0.1),
            ],
          ),
          const SizedBox(height: 18),
          SectionHeader('آخر المشاريع', action: recent.isEmpty ? null : 'عرض الكل', onAction: () => context.go('/projects')),
          const SizedBox(height: 4),
          if (recent.isEmpty)
            SCard(
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded, color: p.accent),
                const SizedBox(width: 10),
                Expanded(child: Text('لسه مفيش مشاريع. اضغط على المايك تحت وابدأ أول تسجيل.', style: t.bodyMedium)),
              ]),
            )
          else
            for (final pr in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProjectTile(project: pr),
              ),
        ],
      ),
    );
  }
}

class _Studio {
  const _Studio(this.title, this.subtitle, this.icon, this.colors, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: p.hero, borderRadius: BorderRadius.circular(28), boxShadow: p.heroShadow),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('جلسة جديدة',
                style: TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 6),
            const Text('حوّل نصك لصوت احترافي بإحساس حقيقي',
                style: TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: 20, height: 1.4, color: Colors.white)),
            const SizedBox(height: 6),
            Text('${VoiceCatalog.all.length} شخصية · ١٢ لهجة · ٨ مشاعر',
                style: const TextStyle(fontFamily: Fonts.body, fontSize: 12, color: Colors.white)),
            const SizedBox(height: 14),
            SizedBox(width: 160, child: GradientButton(label: 'ابدأ التسجيل', hero: true, height: 46, icon: Icons.arrow_back_rounded, onPressed: onStart)),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x73140838), blurRadius: 30, offset: Offset(0, 14))],
          ),
          child: ClipOval(child: Image.asset('assets/images/mic.jpg', width: 108, height: 108, fit: BoxFit.cover)),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -6, duration: 2400.ms, curve: Curves.easeInOut),
      ]),
    );
  }
}

/// يُستخدم في الرئيسية وشاشة المشاريع.
class RecentPlayButton extends ConsumerWidget {
  const RecentPlayButton({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(playerProvider);
    final playing = st.id == project.id && st.playing;
    final bytes = project.masterKey == null ? null : LocalDb.readAudio(project.masterKey!);
    return IconButton.filledTonal(
      tooltip: playing ? 'إيقاف' : 'تشغيل',
      style: IconButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.accent),
      onPressed: bytes == null ? null : () => ref.read(playerProvider.notifier).toggle(project.id, bytes),
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
  }
}
