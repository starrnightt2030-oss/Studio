import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../data/projects/models.dart';
import '../../data/projects/project_repository.dart';
import '../../widgets/ui.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  Future<void> _newRecording(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final p = await ref.read(projectsProvider.notifier).create(ProjectType.voiceover);
    if (context.mounted) context.push('/studio/${p.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final items = [
      (Icons.home_rounded, 'الرئيسية'),
      (Icons.graphic_eq_rounded, 'الأصوات'),
      (Icons.folder_rounded, 'مشاريعي'),
      (Icons.person_rounded, 'حسابي'),
    ];

    Widget tab(int i) {
      final active = shell.currentIndex == i;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          label: items[i].$2,
          child: InkResponse(
            onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: active ? 1.08 : 1,
                child: Icon(items[i].$1, size: 23, color: active ? p.accent : p.muted),
              ),
              const SizedBox(height: 4),
              Text(items[i].$2,
                  style: TextStyle(
                      fontFamily: Fonts.body,
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                      color: active ? p.accent : p.muted)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: StudioBackground(child: shell),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: 82,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Container(
              height: 76,
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF13111C) : Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: p.line),
                boxShadow: p.isDark ? const [] : p.cardShadow,
              ),
              child: Row(children: [tab(0), tab(1), const SizedBox(width: 76), tab(2), tab(3)]),
            ),
            Positioned(
              top: -26,
              child: Semantics(
                button: true,
                label: 'تسجيل جديد',
                child: GestureDetector(
                  onTap: () => _newRecording(context, ref),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: p.orb,
                      boxShadow: p.orbGlow,
                      border: Border.all(color: p.bg, width: 4),
                    ),
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
