import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String teacherId;
  final List<String> subjectIds;

  const GroupModel({
    required this.id,
    required this.name,
    required this.teacherId,
    required this.subjectIds,
  });

  factory GroupModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return GroupModel(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      teacherId: (data['teacherId'] as String?) ?? '',
      subjectIds: List<String>.from((data['subjectIds'] as List?) ?? const []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'teacherId': teacherId,
      'subjectIds': subjectIds,
    };
  }
}