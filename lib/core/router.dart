import 'package:go_router/go_router.dart';

import '../data/settings_repository.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/result/result_cubit.dart';
import '../features/result/result_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/main_shell.dart';

GoRouter buildRouter(SettingsRepository settings) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      // /result is exempt: links tapped before onboarding must still be checked.
      if (!settings.onboardingDone && path != '/onboarding' && path != '/result') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/result',
        builder: (_, state) => ResultScreen(args: state.extra! as ResultArgs),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          ]),
        ],
      ),
    ],
  );
}
