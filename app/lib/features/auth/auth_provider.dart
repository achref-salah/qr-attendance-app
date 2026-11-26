import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import 'auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final authUser = ref.watch(firebaseAuthStateProvider).value;
  if (authUser == null) {
    return Stream.value(null);
  }
  return ref.watch(authRepositoryProvider).watchUserProfile(authUser.uid);
});

final availableGroupsProvider = StreamProvider<List<GroupModel>>((ref) {
  return ref.watch(authRepositoryProvider).watchAvailableGroups();
});