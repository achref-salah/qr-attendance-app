import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/group_model.dart';
import '../../models/subject_model.dart';

class AcademicsException implements Exception {
  final String message;
  const AcademicsException(this.message);

  @override
  String toString() => message;
}

class GroupUsageReport {
  final bool hasStudents;
  final bool hasSessions;

  const GroupUsageReport({
    required this.hasStudents,
    required this.hasSessions,
  });

  bool get hasAny => hasStudents || hasSessions;

  String describeReason() {
    if (hasStudents && hasSessions) {
      return 'This group has enrolled students and attendance sessions.';
    }
    if (hasStudents) {
      return 'This group has enrolled students.';
    }
    if (hasSessions) {
      return 'This group has attendance sessions.';
    }
    return '';
  }
}

class SubjectUsageReport {
  final bool hasLinkedGroups;
  final bool hasSessions;

  const SubjectUsageReport({
    required this.hasLinkedGroups,
    required this.hasSessions,
  });

  bool get hasAny => hasLinkedGroups || hasSessions;

  String describeReason() {
    if (hasLinkedGroups && hasSessions) {
      return 'This subject is linked to one or more groups and has attendance sessions.';
    }
    if (hasLinkedGroups) {
      return 'This subject is currently linked to one or more groups. Unlink it from all groups first to delete it permanently.';
    }
    if (hasSessions) {
      return 'This subject has existing attendance sessions.';
    }
    return '';
  }
}

enum SafeDeleteOutcome { deleted, archivedInstead }

class SafeDeleteResult {
  final SafeDeleteOutcome outcome;
  final String message;

  const SafeDeleteResult._({
    required this.outcome,
    required this.message,
  });

  const SafeDeleteResult.deleted(String message)
      : this._(outcome: SafeDeleteOutcome.deleted, message: message);

  const SafeDeleteResult.archivedInstead(String message)
      : this._(outcome: SafeDeleteOutcome.archivedInstead, message: message);
}

class AcademicsRepository {
  final FirebaseFirestore _firestore;

  AcademicsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection(AppConstants.groupsCollection);

  CollectionReference<Map<String, dynamic>> get _subjects =>
      _firestore.collection(AppConstants.subjectsCollection);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(AppConstants.sessionsCollection);

  CollectionReference<Map<String, dynamic>> get _uniqueKeys =>
      _firestore.collection(AppConstants.uniqueKeysCollection);

  // ---------- Normalization & Deterministic Lock IDs (Matches firestore.rules) ----------

  static String normalizeDisplayText(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String normalizeSubjectCode(String input) {
    return normalizeDisplayText(input).toUpperCase();
  }

  static String normalizeLockValue(String input) {
    return normalizeDisplayText(input).toLowerCase();
  }

  static String escapeLockKeyPart(String input) {
    return normalizeLockValue(input)
        .replaceAll('_', '__')
        .replaceAll('/', '_s')
        .replaceAll(' ', '_p');
  }

  static String groupNameLockId(String teacherId, String name) =>
      '${teacherId}_g_name_${escapeLockKeyPart(name)}';

  static String subjectNameLockId(String teacherId, String name) =>
      '${teacherId}_s_name_${escapeLockKeyPart(name)}';

  static String subjectCodeLockId(String teacherId, String code) =>
      '${teacherId}_s_code_${escapeLockKeyPart(code)}';

  // ---------- Streams ----------

  Stream<List<GroupModel>> watchTeacherGroups(String teacherId) {
    return _groups
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(GroupModel.fromFirestore).toList();
      list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return list;
    });
  }

  Stream<List<SubjectModel>> watchTeacherSubjects(String teacherId) {
    return _subjects
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(SubjectModel.fromFirestore).toList();
      list.sort(
            (a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()),
      );
      return list;
    });
  }

  // ---------- Group CRUD ----------

  Future<void> createGroup({
    required String teacherId,
    required String name,
    List<String> subjectIds = const [],
  }) async {
    final displayName = normalizeDisplayText(name);
    if (displayName.isEmpty || displayName.length > 100) {
      throw const AcademicsException(
        'Group name must be between 1 and 100 characters.',
      );
    }

    final cleanSubjectIds = subjectIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final normName = normalizeLockValue(displayName);
    final groupRef = _groups.doc();
    final lockRef = _uniqueKeys.doc(groupNameLockId(teacherId, displayName));

    await _firestore.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        throw AcademicsException(
          'A group named "$displayName" already exists.',
        );
      }

      tx.set(groupRef, {
        'name': displayName,
        'teacherId': teacherId,
        'subjectIds': cleanSubjectIds,
        'isArchived': false,
      });

      tx.set(lockRef, {
        'teacherId': teacherId,
        'entityType': 'group',
        'entityId': groupRef.id,
        'field': 'name',
        'normalizedValue': normName,
      });
    });
  }

  Future<void> updateGroupName({
    required String teacherId,
    required String groupId,
    required String newName,
  }) async {
    final displayName = normalizeDisplayText(newName);
    if (displayName.isEmpty || displayName.length > 100) {
      throw const AcademicsException(
        'Group name must be between 1 and 100 characters.',
      );
    }

    final groupRef = _groups.doc(groupId);
    final newNorm = normalizeLockValue(displayName);

    await _firestore.runTransaction((tx) async {
      final groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists || groupSnap.data() == null) {
        throw const AcademicsException('Group not found.');
      }

      final data = groupSnap.data()!;
      if (data['teacherId'] != teacherId) {
        throw const AcademicsException(
          'You do not have permission to edit this group.',
        );
      }

      final oldName = (data['name'] as String?) ?? '';
      final oldNorm = normalizeLockValue(oldName);

      if (oldNorm == newNorm) {
        if (oldName != displayName) {
          tx.update(groupRef, {'name': displayName});
        }
        return;
      }

      final oldLockRef = _uniqueKeys.doc(groupNameLockId(teacherId, oldName));
      final newLockRef = _uniqueKeys.doc(
        groupNameLockId(teacherId, displayName),
      );

      final newLockSnap = await tx.get(newLockRef);
      final oldLockSnap = await tx.get(oldLockRef);

      if (newLockSnap.exists) {
        throw AcademicsException(
          'A group named "$displayName" already exists.',
        );
      }

      tx.update(groupRef, {'name': displayName});
      if (oldLockSnap.exists) {
        tx.delete(oldLockRef);
      }
      tx.set(newLockRef, {
        'teacherId': teacherId,
        'entityType': 'group',
        'entityId': groupId,
        'field': 'name',
        'normalizedValue': newNorm,
      });
    });
  }

  Future<void> updateGroupSubjects({
    required String groupId,
    required List<String> subjectIds,
  }) async {
    final cleanIds = subjectIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    await _groups.doc(groupId).update({'subjectIds': cleanIds});
  }

  Future<void> setGroupArchived({
    required String groupId,
    required bool isArchived,
  }) async {
    await _groups.doc(groupId).update({'isArchived': isArchived});
  }

  // ---------- Subject CRUD ----------

  Future<void> createSubject({
    required String teacherId,
    required String code,
    required String name,
  }) async {
    final displayCode = normalizeSubjectCode(code);
    final displayName = normalizeDisplayText(name);

    if (displayCode.isEmpty || displayCode.length > 30) {
      throw const AcademicsException(
        'Subject code must be between 1 and 30 characters.',
      );
    }
    if (displayName.isEmpty || displayName.length > 100) {
      throw const AcademicsException(
        'Subject name must be between 1 and 100 characters.',
      );
    }

    final normCode = normalizeLockValue(displayCode);
    final normName = normalizeLockValue(displayName);

    final subjectRef = _subjects.doc();
    final nameLockRef = _uniqueKeys.doc(
      subjectNameLockId(teacherId, displayName),
    );
    final codeLockRef = _uniqueKeys.doc(
      subjectCodeLockId(teacherId, displayCode),
    );

    await _firestore.runTransaction((tx) async {
      final nameLockSnap = await tx.get(nameLockRef);
      final codeLockSnap = await tx.get(codeLockRef);

      if (nameLockSnap.exists) {
        throw AcademicsException(
          'A subject named "$displayName" already exists.',
        );
      }
      if (codeLockSnap.exists) {
        throw AcademicsException(
          'A subject with code "$displayCode" already exists.',
        );
      }

      tx.set(subjectRef, {
        'code': displayCode,
        'name': displayName,
        'teacherId': teacherId,
        'isArchived': false,
      });

      tx.set(nameLockRef, {
        'teacherId': teacherId,
        'entityType': 'subject',
        'entityId': subjectRef.id,
        'field': 'name',
        'normalizedValue': normName,
      });

      tx.set(codeLockRef, {
        'teacherId': teacherId,
        'entityType': 'subject',
        'entityId': subjectRef.id,
        'field': 'code',
        'normalizedValue': normCode,
      });
    });
  }

  Future<void> updateSubject({
    required String teacherId,
    required String subjectId,
    required String newCode,
    required String newName,
  }) async {
    final displayCode = normalizeSubjectCode(newCode);
    final displayName = normalizeDisplayText(newName);

    if (displayCode.isEmpty || displayCode.length > 30) {
      throw const AcademicsException(
        'Subject code must be between 1 and 30 characters.',
      );
    }
    if (displayName.isEmpty || displayName.length > 100) {
      throw const AcademicsException(
        'Subject name must be between 1 and 100 characters.',
      );
    }

    final subjectRef = _subjects.doc(subjectId);
    final newCodeNorm = normalizeLockValue(displayCode);
    final newNameNorm = normalizeLockValue(displayName);

    await _firestore.runTransaction((tx) async {
      final subjectSnap = await tx.get(subjectRef);
      if (!subjectSnap.exists || subjectSnap.data() == null) {
        throw const AcademicsException('Subject not found.');
      }

      final data = subjectSnap.data()!;
      if (data['teacherId'] != teacherId) {
        throw const AcademicsException(
          'You do not have permission to edit this subject.',
        );
      }

      final oldName = (data['name'] as String?) ?? '';
      final oldCode = (data['code'] as String?) ?? '';
      final nameChanged = normalizeLockValue(oldName) != newNameNorm;
      final codeChanged = normalizeLockValue(oldCode) != newCodeNorm;

      if (!nameChanged && !codeChanged) {
        if (oldName != displayName || oldCode != displayCode) {
          tx.update(subjectRef, {'code': displayCode, 'name': displayName});
        }
        return;
      }

      final oldNameLockRef = _uniqueKeys.doc(
        subjectNameLockId(teacherId, oldName),
      );
      final newNameLockRef = _uniqueKeys.doc(
        subjectNameLockId(teacherId, displayName),
      );
      final oldCodeLockRef = _uniqueKeys.doc(
        subjectCodeLockId(teacherId, oldCode),
      );
      final newCodeLockRef = _uniqueKeys.doc(
        subjectCodeLockId(teacherId, displayCode),
      );

      DocumentSnapshot<Map<String, dynamic>>? newNameSnap;
      DocumentSnapshot<Map<String, dynamic>>? oldNameSnap;
      DocumentSnapshot<Map<String, dynamic>>? newCodeSnap;
      DocumentSnapshot<Map<String, dynamic>>? oldCodeSnap;

      if (nameChanged) {
        newNameSnap = await tx.get(newNameLockRef);
        oldNameSnap = await tx.get(oldNameLockRef);
      }
      if (codeChanged) {
        newCodeSnap = await tx.get(newCodeLockRef);
        oldCodeSnap = await tx.get(oldCodeLockRef);
      }

      if (nameChanged && (newNameSnap?.exists ?? false)) {
        throw AcademicsException(
          'A subject named "$displayName" already exists.',
        );
      }
      if (codeChanged && (newCodeSnap?.exists ?? false)) {
        throw AcademicsException(
          'A subject with code "$displayCode" already exists.',
        );
      }

      tx.update(subjectRef, {'code': displayCode, 'name': displayName});

      if (nameChanged) {
        if (oldNameSnap?.exists ?? false) {
          tx.delete(oldNameLockRef);
        }
        tx.set(newNameLockRef, {
          'teacherId': teacherId,
          'entityType': 'subject',
          'entityId': subjectId,
          'field': 'name',
          'normalizedValue': newNameNorm,
        });
      }

      if (codeChanged) {
        if (oldCodeSnap?.exists ?? false) {
          tx.delete(oldCodeLockRef);
        }
        tx.set(newCodeLockRef, {
          'teacherId': teacherId,
          'entityType': 'subject',
          'entityId': subjectId,
          'field': 'code',
          'normalizedValue': newCodeNorm,
        });
      }
    });
  }

  Future<void> setSubjectArchived({
    required String subjectId,
    required bool isArchived,
  }) async {
    await _subjects.doc(subjectId).update({'isArchived': isArchived});
  }

  // ---------- Reference Checks & Two-Phase Safe Delete ----------

  Future<GroupUsageReport> checkGroupUsage({
    required String teacherId,
    required String groupId,
  }) async {
    final studentsSnap = await _users
        .where('role', isEqualTo: 'student')
        .where('groupId', isEqualTo: groupId)
        .limit(1)
        .get();

    final sessionsSnap = await _sessions
        .where('teacherId', isEqualTo: teacherId)
        .where('groupId', isEqualTo: groupId)
        .limit(1)
        .get();

    return GroupUsageReport(
      hasStudents: studentsSnap.docs.isNotEmpty,
      hasSessions: sessionsSnap.docs.isNotEmpty,
    );
  }

  Future<SafeDeleteResult> deleteGroupSafely({
    required String teacherId,
    required String groupId,
  }) async {
    final groupRef = _groups.doc(groupId);

    // Stage 1: Atomic soft-lock (blocks new registrations & sessions via Rules)
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(groupRef);
      if (!snap.exists || snap.data() == null) {
        throw const AcademicsException('Group not found.');
      }
      if (snap.data()!['teacherId'] != teacherId) {
        throw const AcademicsException(
          'You do not have permission to delete this group.',
        );
      }
      tx.update(groupRef, {'isArchived': true});
    });

    // Stage 2: Post-lock collection reference re-check
    final usage = await checkGroupUsage(teacherId: teacherId, groupId: groupId);
    if (usage.hasAny) {
      return SafeDeleteResult.archivedInstead(
        '${usage.describeReason()} The group was archived instead to preserve existing records.',
      );
    }

    // Stage 3: Atomic permanent delete of entity + uniqueness lock
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(groupRef);
      if (!snap.exists || snap.data() == null) return;

      final data = snap.data()!;
      if (data['isArchived'] != true) {
        throw const AcademicsException(
          'Group state changed during deletion. Please retry.',
        );
      }

      final name = (data['name'] as String?) ?? '';
      final lockRef = _uniqueKeys.doc(groupNameLockId(teacherId, name));
      final lockSnap = await tx.get(lockRef);

      tx.delete(groupRef);
      if (lockSnap.exists) {
        tx.delete(lockRef);
      }
    });

    return const SafeDeleteResult.deleted('Group permanently deleted.');
  }

  Future<SubjectUsageReport> checkSubjectUsage({
    required String teacherId,
    required String subjectId,
  }) async {
    final groupsSnap = await _groups
        .where('teacherId', isEqualTo: teacherId)
        .where('subjectIds', arrayContains: subjectId)
        .limit(1)
        .get();

    final sessionsSnap = await _sessions
        .where('teacherId', isEqualTo: teacherId)
        .where('subjectId', isEqualTo: subjectId)
        .limit(1)
        .get();

    return SubjectUsageReport(
      hasLinkedGroups: groupsSnap.docs.isNotEmpty,
      hasSessions: sessionsSnap.docs.isNotEmpty,
    );
  }

  Future<SafeDeleteResult> deleteSubjectSafely({
    required String teacherId,
    required String subjectId,
  }) async {
    final subjectRef = _subjects.doc(subjectId);

    // Stage 1: Atomic soft-lock (blocks new sessions via Rules)
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(subjectRef);
      if (!snap.exists || snap.data() == null) {
        throw const AcademicsException('Subject not found.');
      }
      if (snap.data()!['teacherId'] != teacherId) {
        throw const AcademicsException(
          'You do not have permission to delete this subject.',
        );
      }
      tx.update(subjectRef, {'isArchived': true});
    });

    // Stage 2: Post-lock collection reference re-check
    final usage = await checkSubjectUsage(
      teacherId: teacherId,
      subjectId: subjectId,
    );
    if (usage.hasAny) {
      return SafeDeleteResult.archivedInstead(
        '${usage.describeReason()} The subject was archived instead to preserve existing records.',
      );
    }

    // Stage 3: Atomic permanent delete of entity + both uniqueness locks
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(subjectRef);
      if (!snap.exists || snap.data() == null) return;

      final data = snap.data()!;
      if (data['isArchived'] != true) {
        throw const AcademicsException(
          'Subject state changed during deletion. Please retry.',
        );
      }

      final name = (data['name'] as String?) ?? '';
      final code = (data['code'] as String?) ?? '';
      final nameLockRef = _uniqueKeys.doc(subjectNameLockId(teacherId, name));
      final codeLockRef = _uniqueKeys.doc(subjectCodeLockId(teacherId, code));

      final nameLockSnap = await tx.get(nameLockRef);
      final codeLockSnap = await tx.get(codeLockRef);

      tx.delete(subjectRef);
      if (nameLockSnap.exists) {
        tx.delete(nameLockRef);
      }
      if (codeLockSnap.exists) {
        tx.delete(codeLockRef);
      }
    });

    return const SafeDeleteResult.deleted('Subject permanently deleted.');
  }
}