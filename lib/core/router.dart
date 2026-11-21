import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/intro/intro_screen.dart';
import '../features/onboarding/api_key_screen.dart';
import '../features/podcast/podcast_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/result/result_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/studio/studio_screen.dart';
import '../features/transcribe/transcribe_screen.dart';
import '../features/voices/voices_screen.dart';
import 'storage/key_store.dart';

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, a, _, c) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
      ),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(apiKeyProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/intro',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (state.matchedLocation == '/intro') return null;
      final hasKey = ref.read(apiKeyProvider) != null;
      final atKey = state.matchedLocation == '/key';
      if (!hasKey && !atKey) return '/key';
      if (hasKey && atKey && state.uri.queryParameters['edit'] != '1') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/intro', builder: (c, s) => const IntroScreen()),
      GoRoute(path: '/key', pageBuilder: (c, s) => _fade(s, ApiKeyScreen(editing: s.uri.queryParameters['edit'] == '1'))),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/voices', builder: (c, s) => const VoicesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/projects', builder: (c, s) => const ProjectsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen())]),
        ],
      ),
      GoRoute(path: '/studio/:id', pageBuilder: (c, s) => _fade(s, StudioScreen(projectId: s.pathParameters['id']!))),
      GoRoute(path: '/result/:id', pageBuilder: (c, s) => _fade(s, ResultScreen(projectId: s.pathParameters['id']!))),
      GoRoute(path: '/podcast/:id', pageBuilder: (c, s) => _fade(s, PodcastScreen(projectId: s.pathParameters['id']!))),
      GoRoute(path: '/transcribe', pageBuilder: (c, s) => _fade(s, const TranscribeScreen())),
      GoRoute(
        path: '/pick/:id',
        pageBuilder: (c, s) => _fade(
          s,
          VoicesScreen(pickForProject: s.pathParameters['id'], pickForSpeaker: s.uri.queryParameters['speaker']),
        ),
      ),
    ],
  );
});
