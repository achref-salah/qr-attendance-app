import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

  Stream<AppUser?> watchUserProfile(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Stream<List<GroupModel>> watchAvailableGroups() {
    return _firestore
        .collection(AppConstants.groupsCollection)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(GroupModel.fromFirestore).toList());
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Registers a student in Auth + Firestore /users/{uid} (BR-2, BR-3, BR-4, FR-3).
  Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
    required String registrationNumber,
    required String groupId,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-creation-failed',
        message: 'Could not create user account.',
      );
    }

    try {
      final profile = AppUser(
        uid: user.uid,
        name: name.trim(),
        role: UserRole.student,
        groupId: groupId,
        registrationNumber: registrationNumber.trim(),
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(profile.toStudentCreateMap());
    } catch (e) {
      // Clean up orphan Auth user if Firestore write fails
      await user.delete();
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}