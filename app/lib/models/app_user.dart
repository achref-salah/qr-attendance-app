import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  teacher,
  student;

  static UserRole fromString(String value) {
    return switch (value) {
      'teacher' => UserRole.teacher,
      'student' => UserRole.student,
      _ => throw ArgumentError('Invalid role: $value'),
    };
  }
}

class AppUser {
  final String uid;
  final String name;
  final UserRole role;
  final String? groupId;
  final String? registrationNumber;

  const AppUser({
    required this.uid,
    required this.name,
    required this.role,
    this.groupId,
    this.registrationNumber,
  });

  bool get isTeacher => role == UserRole.teacher;
  bool get isStudent => role == UserRole.student;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('User document ${doc.id} does not exist');
    }
    return AppUser(
      uid: doc.id,
      name: (data['name'] as String?) ?? '',
      role: UserRole.fromString((data['role'] as String?) ?? 'student'),
      groupId: data['groupId'] as String?,
      registrationNumber: data['registrationNumber'] as String?,
    );
  }

  Map<String, dynamic> toStudentCreateMap() {
    return {
      'name': name.trim(),
      'role': UserRole.student.name,
      'groupId': groupId,
      'registrationNumber': registrationNumber?.trim() ?? '',
    };
  }
}