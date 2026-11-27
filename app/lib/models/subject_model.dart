import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectModel {
  final String id;
  final String code;
  final String name;
  final String teacherId;
  final bool isArchived;

  const SubjectModel({
    required this.id,
    required this.code,
    required this.name,
    required this.teacherId,
    this.isArchived = false,
  });

  factory SubjectModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SubjectModel(
      id: doc.id,
      code: (data['code'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      teacherId: (data['teacherId'] as String?) ?? '',
      isArchived: (data['isArchived'] as bool?) ?? false,
    );
  }

  SubjectModel copyWith({
    String? id,
    String? code,
    String? name,
    String? teacherId,
    bool? isArchived,
  }) {
    return SubjectModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      teacherId: teacherId ?? this.teacherId,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'teacherId': teacherId,
      'isArchived': isArchived,
    };
  }
}