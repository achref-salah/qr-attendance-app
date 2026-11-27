import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group_model.dart';
import '../../models/subject_model.dart';
import '../auth/auth_provider.dart';
import 'academics_repository.dart';

enum AcademicsSegment { groups, subjects }

final academicsRepositoryProvider = Provider<AcademicsRepository>(
      (ref) => AcademicsRepository(),
);

class AcademicsSegmentNotifier extends Notifier<AcademicsSegment> {
  @override
  AcademicsSegment build() => AcademicsSegment.groups;

  void select(AcademicsSegment segment) => state = segment;
}

final academicsSegmentProvider =
NotifierProvider<AcademicsSegmentNotifier, AcademicsSegment>(
  AcademicsSegmentNotifier.new,
);

class ShowArchivedAcademicsNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle(bool showArchived) => state = showArchived;
}

final showArchivedAcademicsProvider =
NotifierProvider<ShowArchivedAcademicsNotifier, bool>(
  ShowArchivedAcademicsNotifier.new,
);

final teacherGroupsProvider = StreamProvider<List<GroupModel>>((ref) {
  final user = ref.watch(firebaseAuthStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(academicsRepositoryProvider).watchTeacherGroups(user.uid);
});

final teacherSubjectsProvider = StreamProvider<List<SubjectModel>>((ref) {
  final user = ref.watch(firebaseAuthStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(academicsRepositoryProvider).watchTeacherSubjects(user.uid);
});