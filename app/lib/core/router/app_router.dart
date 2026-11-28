import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/student/student_shell_screen.dart';
import '../../features/teacher/live_session_screen.dart';
import '../../features/teacher/teacher_shell_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier();

  ref.listen(firebaseAuthStateProvider, (_, _) => notifier.refresh());
  ref.listen(currentUserProfileProvider, (_, _) => notifier.refresh());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/loading',
    refreshListenable: notifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final authState = ref.read(firebaseAuthStateProvider);
      final profileState = ref.read(currentUserProfileProvider);

      if (authState.isLoading) {
        return location == '/loading' ? null : '/loading';
      }

      final firebaseUser = authState.value;
      if (firebaseUser == null) {
        if (location == '/login' || location == '/register') return null;
        return '/login';
      }

      if (profileState.isLoading) {
        return location == '/loading' ? null : '/loading';
      }

      if (profileState.hasError || profileState.value == null) {
        return location == '/profile-error' ? null : '/profile-error';
      }

      final profile = profileState.value!;
      if (profile.isTeacher) {
        return location.startsWith('/teacher') ? null : '/teacher';
      }
      return location.startsWith('/student') ? null : '/student';
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/profile-error',
        builder: (_, _) => const _ProfileErrorScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/teacher',
        builder: (_, _) => const TeacherShellScreen(),
      ),
      GoRoute(
        path: '/teacher/session/:id',
        builder: (_, state) => LiveSessionScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/student',
        builder: (_, _) => const StudentShellScreen(),
      ),
    ],
  );
});

class _ProfileErrorScreen extends ConsumerWidget {
  const _ProfileErrorScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Could not load your user profile. Please sign out and try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}