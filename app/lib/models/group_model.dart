import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String teacherId;
  final List<String> subjectIds;
  final bool isArchived;

  const GroupModel({
    required this.id,
    required this.name,
    required this.teacherId,
    required this.subjectIds,
    this.isArchived = false,
  });

  factory GroupModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawSubjects = (data['subjectIds'] as List?) ?? const [];
    return GroupModel(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      teacherId: (data['teacherId'] as String?) ?? '',
      subjectIds: rawSubjects
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      isArchived: (data['isArchived'] as bool?) ?? false,
    );
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? teacherId,
    List<String>? subjectIds,
    bool? isArchived,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      teacherId: teacherId ?? this.teacherId,
      subjectIds: subjectIds ?? this.subjectIds,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'teacherId': teacherId,
      'subjectIds': subjectIds,
      'isArchived': isArchived,
    };
  }
}