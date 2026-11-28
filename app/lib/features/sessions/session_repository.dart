import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/app_user.dart';
import '../../models/presence_model.dart';
import '../../models/session_model.dart';

class SessionException implements Exception {
  final String message;
  final String? existingOpenSessionId;

  const SessionException(this.message, {this.existingOpenSessionId});

  @override
  String toString() => message;
}

class SessionRepository {
  final FirebaseFirestore _firestore;
  final Random _random = Random.secure();

  SessionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  String generateToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return List.generate(24, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  static String encodeQrPayload({
    required String sessionId,
    required String token,
  }) {
    return jsonEncode({'sid': sessionId, 't': token});
  }

  Stream<List<SessionModel>> watchTeacherSessions(String teacherId) {
    return _firestore
        .collection(AppConstants.sessionsCollection)
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(SessionModel.fromFirestore).toList();
      list.sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final aTime = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  Stream<SessionModel?> watchSession(String sessionId) {
    return _firestore
        .collection(AppConstants.sessionsCollection)
        .doc(sessionId)
        .snapshots()
        .map((doc) => doc.exists ? SessionModel.fromFirestore(doc) : null);
  }

  Stream<SessionSecretModel?> watchSessionSecret(String sessionId) {
    return _firestore
        .collection(AppConstants.sessionsCollection)
        .doc(sessionId)
        .collection(AppConstants.secretSubcollection)
        .doc(AppConstants.secretDocId)
        .snapshots()
        .map((doc) => doc.exists ? SessionSecretModel.fromFirestore(doc) : null);
  }

  Stream<List<PresenceModel>> watchSessionPresences(String sessionId) {
    return _firestore
        .collection(AppConstants.sessionsCollection)
        .doc(sessionId)
        .collection(AppConstants.presencesSubcollection)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(PresenceModel.fromFirestore).toList();
      list.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.now();
        final bTime = b.createdAt ?? DateTime.now();
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  Stream<List<AppUser>> watchGroupStudents(String groupId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: UserRole.student.name)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(AppUser.fromFirestore).toList();
      list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return list;
    });
  }

  Future<String> openSession({
    required String teacherId,
    required String groupId,
    required String subjectId,
    required String room,
    required double refLat,
    required double refLng,
  }) async {
    final trimmedRoom = room.trim();
    if (trimmedRoom.isEmpty) {
      throw const SessionException('Room name is required.');
    }

    try {
      // Enforce single open session per teacher.
      final existingOpen = await _firestore
          .collection(AppConstants.sessionsCollection)
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: SessionStatus.open.name)
          .limit(1)
          .get();

      if (existingOpen.docs.isNotEmpty) {
        throw SessionException(
          'You already have an open session. Close it before starting a new one.',
          existingOpenSessionId: existingOpen.docs.first.id,
        );
      }

      // Create session first so secret/current rule ownsSession(sid) succeeds.
      final sessionRef =
      _firestore.collection(AppConstants.sessionsCollection).doc();
      await sessionRef.set({
        'teacherId': teacherId,
        'groupId': groupId,
        'subjectId': subjectId,
        'room': trimmedRoom,
        'refLat': refLat,
        'refLng': refLng,
        'status': SessionStatus.open.name,
        'openedAt': FieldValue.serverTimestamp(),
      });

      final token = generateToken();
      await sessionRef
          .collection(AppConstants.secretSubcollection)
          .doc(AppConstants.secretDocId)
          .set({
        'token': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      return sessionRef.id;
    } on SessionException {
      rethrow;
    } on FirebaseException catch (e) {
      throw SessionException(_mapFirebaseError(e));
    }
  }

  Future<void> rotateSessionToken({
    required String sessionId,
    String? previousToken,
  }) async {
    try {
      final nextToken = generateToken();
      final payload = <String, dynamic>{
        'token': nextToken,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (previousToken != null && previousToken.isNotEmpty) {
        payload['prevToken'] = previousToken;
      }

      await _firestore
          .collection(AppConstants.sessionsCollection)
          .doc(sessionId)
          .collection(AppConstants.secretSubcollection)
          .doc(AppConstants.secretDocId)
          .set(payload);
    } on FirebaseException catch (e) {
      throw SessionException(_mapFirebaseError(e));
    }
  }

  Future<void> addManualPresence({
    required String sessionId,
    required String teacherId,
    required String studentId,
    String? reason,
  }) async {
    try {
      final presenceRef = _firestore
          .collection(AppConstants.sessionsCollection)
          .doc(sessionId)
          .collection(AppConstants.presencesSubcollection)
          .doc(studentId);

      final existing = await presenceRef.get();
      if (existing.exists) {
        throw const SessionException(
          'This student is already marked present for this session.',
        );
      }

      final payload = <String, dynamic>{
        'studentId': studentId,
        'isManual': true,
        'teacherId': teacherId,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final trimmedReason = reason?.trim() ?? '';
      if (trimmedReason.isNotEmpty) {
        if (trimmedReason.length > 200) {
          throw const SessionException(
            'Reason must be 200 characters or fewer.',
          );
        }
        payload['reason'] = trimmedReason;
      }

      await presenceRef.set(payload);
    } on SessionException {
      rethrow;
    } on FirebaseException catch (e) {
      throw SessionException(_mapFirebaseError(e));
    }
  }

  Future<void> closeSession(String sessionId) async {
    try {
      await _firestore
          .collection(AppConstants.sessionsCollection)
          .doc(sessionId)
          .update({
        'status': SessionStatus.closed.name,
        'closedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw SessionException(_mapFirebaseError(e));
    }
  }

  String _mapFirebaseError(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
      'Permission denied by security rules. Ensure the group and subject are active and linked.',
      'unavailable' =>
      'Network unavailable. Please check your internet connection.',
      _ => e.message ?? 'Unexpected Firestore error (${e.code}).',
    };
  }
}