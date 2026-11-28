import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_user.dart';
import '../../models/presence_model.dart';
import '../../models/session_model.dart';
import '../auth/auth_provider.dart';
import 'session_repository.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository();
});

final teacherSessionsProvider = StreamProvider<List<SessionModel>>((ref) {
  final authUser = ref.watch(firebaseAuthStateProvider).value;
  if (authUser == null) return Stream.value(const []);
  return ref.watch(sessionRepositoryProvider).watchTeacherSessions(authUser.uid);
});

final openTeacherSessionProvider = Provider<SessionModel?>((ref) {
  final sessions = ref.watch(teacherSessionsProvider).value ?? const [];
  for (final session in sessions) {
    if (session.isOpen) return session;
  }
  return null;
});

final sessionByIdProvider = StreamProvider.family<SessionModel?, String>((
    ref,
    sessionId,
    ) {
  return ref.watch(sessionRepositoryProvider).watchSession(sessionId);
});

final sessionSecretProvider =
StreamProvider.family<SessionSecretModel?, String>((ref, sessionId) {
  return ref.watch(sessionRepositoryProvider).watchSessionSecret(sessionId);
});

final sessionPresencesProvider =
StreamProvider.family<List<PresenceModel>, String>((ref, sessionId) {
  return ref.watch(sessionRepositoryProvider).watchSessionPresences(sessionId);
});

final groupStudentsProvider = StreamProvider.family<List<AppUser>, String>((
    ref,
    groupId,
    ) {
  return ref.watch(sessionRepositoryProvider).watchGroupStudents(groupId);
});