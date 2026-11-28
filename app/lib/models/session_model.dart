import 'package:cloud_firestore/cloud_firestore.dart';

enum SessionStatus {
  open,
  closed;

  static SessionStatus fromString(String value) {
    return switch (value) {
      'open' => SessionStatus.open,
      'closed' => SessionStatus.closed,
      _ => SessionStatus.closed,
    };
  }
}

class SessionModel {
  final String id;
  final String teacherId;
  final String groupId;
  final String subjectId;
  final String room;
  final double refLat;
  final double refLng;
  final SessionStatus status;
  final DateTime? openedAt;
  final DateTime? closedAt;

  const SessionModel({
    required this.id,
    required this.teacherId,
    required this.groupId,
    required this.subjectId,
    required this.room,
    required this.refLat,
    required this.refLng,
    required this.status,
    this.openedAt,
    this.closedAt,
  });

  bool get isOpen => status == SessionStatus.open;

  factory SessionModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SessionModel(
      id: doc.id,
      teacherId: (data['teacherId'] as String?) ?? '',
      groupId: (data['groupId'] as String?) ?? '',
      subjectId: (data['subjectId'] as String?) ?? '',
      room: (data['room'] as String?) ?? '',
      refLat: ((data['refLat'] as num?) ?? 0).toDouble(),
      refLng: ((data['refLng'] as num?) ?? 0).toDouble(),
      status: SessionStatus.fromString((data['status'] as String?) ?? 'closed'),
      openedAt: (data['openedAt'] as Timestamp?)?.toDate(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class SessionSecretModel {
  final String token;
  final String? prevToken;
  final DateTime? tokenUpdatedAt;

  const SessionSecretModel({
    required this.token,
    this.prevToken,
    this.tokenUpdatedAt,
  });

  factory SessionSecretModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SessionSecretModel(
      token: (data['token'] as String?) ?? '',
      prevToken: data['prevToken'] as String?,
      tokenUpdatedAt: (data['tokenUpdatedAt'] as Timestamp?)?.toDate(),
    );
  }
}