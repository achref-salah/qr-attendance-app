import 'package:cloud_firestore/cloud_firestore.dart';

class PresenceModel {
  final String studentId;
  final bool isManual;
  final String? token;
  final double? distance;
  final String? teacherId;
  final String? reason;
  final DateTime? createdAt;

  const PresenceModel({
    required this.studentId,
    required this.isManual,
    this.token,
    this.distance,
    this.teacherId,
    this.reason,
    this.createdAt,
  });

  factory PresenceModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};
    return PresenceModel(
      studentId: (data['studentId'] as String?) ?? doc.id,
      isManual: (data['isManual'] as bool?) ?? false,
      token: data['token'] as String?,
      distance: (data['distance'] as num?)?.toDouble(),
      teacherId: data['teacherId'] as String?,
      reason: data['reason'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}