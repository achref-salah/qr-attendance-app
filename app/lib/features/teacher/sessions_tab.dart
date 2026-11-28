import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../models/group_model.dart';
import '../../models/session_model.dart';
import '../../models/subject_model.dart';
import '../academics/academics_provider.dart';
import '../auth/auth_provider.dart';
import '../sessions/session_provider.dart';

Future<void> showStartSessionFlow(
    BuildContext context,
    WidgetRef ref,
    ) async {
  final teacherId = ref.read(firebaseAuthStateProvider).value?.uid;
  if (teacherId == null) return;

  final existingOpen = ref.read(openTeacherSessionProvider);
  if (existingOpen != null) {
    final openExisting = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Session Already Open'),
        content: Text(
          'You already have an active session in ${existingOpen.room}. '
              'Only one open session is allowed at a time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Go to Session'),
          ),
        ],
      ),
    );
    if (openExisting == true && context.mounted) {
      context.push('/teacher/session/${existingOpen.id}');
    }
    return;
  }

  final allGroups = ref.read(teacherGroupsProvider).value ?? const <GroupModel>[];
  final allSubjects =
      ref.read(teacherSubjectsProvider).value ?? const <SubjectModel>[];

  final createdSessionId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StartSessionSheet(
      teacherId: teacherId,
      groups: allGroups.where((g) => !g.isArchived).toList(),
      subjects: allSubjects.where((s) => !s.isArchived).toList(),
    ),
  );

  if (createdSessionId != null && context.mounted) {
    context.push('/teacher/session/$createdSessionId');
  }
}

class SessionsTab extends ConsumerWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(teacherSessionsProvider);
    final groups = ref.watch(teacherGroupsProvider).value ?? const <GroupModel>[];
    final subjects =
        ref.watch(teacherSubjectsProvider).value ?? const <SubjectModel>[];

    final groupMap = {for (final g in groups) g.id: g};
    final subjectMap = {for (final s in subjects) s.id: s};

    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load sessions: $err',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return _EmptySessionsState(
            onStartTap: () => showStartSessionFlow(context, ref),
          );
        }

        final openSession = sessions.where((s) => s.isOpen).firstOrNull;
        final closedSessions = sessions.where((s) => !s.isOpen).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (openSession != null) ...[
              _SectionHeader(
                title: 'Active Session',
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              _ActiveSessionCard(
                session: openSession,
                group: groupMap[openSession.groupId],
                subject: subjectMap[openSession.subjectId],
              ),
              const SizedBox(height: 20),
            ],
            if (closedSessions.isNotEmpty) ...[
              _SectionHeader(
                title: 'Past Sessions (${closedSessions.length})',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              for (final session in closedSessions) ...[
                _ClosedSessionCard(
                  session: session,
                  group: groupMap[session.groupId],
                  subject: subjectMap[session.subjectId],
                ),
                const SizedBox(height: 10),
              ],
            ] else if (openSession != null) ...[
              _SectionHeader(
                title: 'Past Sessions',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Closed sessions will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final SessionModel session;
  final GroupModel? group;
  final SubjectModel? subject;

  const _ActiveSessionCard({
    required this.session,
    required this.group,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subjectLabel = subject == null
        ? session.subjectId
        : '${subject!.code} · ${subject!.name}';
    final groupLabel = group?.name ?? session.groupId;

    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.55),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/teacher/session/${session.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'LIVE',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      groupLabel,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.qr_code_2),
                ],
              ),
              const SizedBox(height: 8),
              Text(subjectLabel, style: textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                'Room ${session.room} · Started ${_formatDateTime(session.openedAt)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          context.push('/teacher/session/${session.id}'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Live QR & Presences'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedSessionCard extends StatelessWidget {
  final SessionModel session;
  final GroupModel? group;
  final SubjectModel? subject;

  const _ClosedSessionCard({
    required this.session,
    required this.group,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subjectLabel = subject == null
        ? session.subjectId
        : '${subject!.code} · ${subject!.name}';
    final groupLabel = group?.name ?? session.groupId;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push('/teacher/session/${session.id}'),
        leading: CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurfaceVariant,
          child: const Icon(Icons.event_available),
        ),
        title: Text(
          '$groupLabel — $subjectLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Room ${session.room} · ${_formatDateTime(session.openedAt)}',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _EmptySessionsState extends StatelessWidget {
  final VoidCallback onStartTap;

  const _EmptySessionsState({required this.onStartTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No attendance sessions yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Start a live session to generate a rotating QR code and track attendance.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
              onPressed: onStartTap,
              icon: const Icon(Icons.add),
              label: const Text('Start Session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartSessionSheet extends ConsumerStatefulWidget {
  final String teacherId;
  final List<GroupModel> groups;
  final List<SubjectModel> subjects;

  const _StartSessionSheet({
    required this.teacherId,
    required this.groups,
    required this.subjects,
  });

  @override
  ConsumerState<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends ConsumerState<_StartSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _roomController = TextEditingController();
  String? _selectedGroupId;
  String? _selectedSubjectId;
  bool _isSubmitting = false;
  bool _needsLocationSettings = false;
  bool _needsAppSettings = false;
  String? _errorMessage;

  late final Map<String, SubjectModel> _activeSubjectMap;

  @override
  void initState() {
    super.initState();
    _activeSubjectMap = {for (final s in widget.subjects) s.id: s};
    if (widget.groups.isNotEmpty) {
      _selectedGroupId = widget.groups.first.id;
      final firstSubjects = _linkedActiveSubjectsFor(_selectedGroupId);
      if (firstSubjects.isNotEmpty) {
        _selectedSubjectId = firstSubjects.first.id;
      }
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  List<SubjectModel> _linkedActiveSubjectsFor(String? groupId) {
    if (groupId == null) return const [];
    final group = widget.groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) return const [];
    return group.subjectIds
        .map((id) => _activeSubjectMap[id])
        .whereType<SubjectModel>()
        .toList();
  }

  Future<Position?> _acquireLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _needsLocationSettings = true;
          _needsAppSettings = false;
          _errorMessage =
          'Location services (GPS) are turned off. Enable GPS to open a session.';
        });
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _needsLocationSettings = false;
          _needsAppSettings = false;
          _errorMessage =
          'Location permission is required to set the classroom geofence.';
        });
      }
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _needsLocationSettings = false;
          _needsAppSettings = true;
          _errorMessage =
          'Location permission is permanently denied. Enable it in App Settings.';
        });
      }
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedGroupId == null || _selectedSubjectId == null) {
      setState(() {
        _errorMessage = 'Please select an active group and a linked subject.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _needsLocationSettings = false;
      _needsAppSettings = false;
    });

    try {
      final position = await _acquireLocation();
      if (position == null) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      final sessionId = await ref.read(sessionRepositoryProvider).openSession(
        teacherId: widget.teacherId,
        groupId: _selectedGroupId!,
        subjectId: _selectedSubjectId!,
        room: _roomController.text,
        refLat: position.latitude,
        refLng: position.longitude,
      );

      if (!mounted) return;
      Navigator.of(context).pop(sessionId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableSubjects = _linkedActiveSubjectsFor(_selectedGroupId);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start Attendance Session',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Captures your current GPS position for the 100 m classroom check-in zone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.groups.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'No active groups available. Create or restore a group first.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('group_$_selectedGroupId'),
                initialValue: _selectedGroupId,
                decoration: const InputDecoration(labelText: 'Group'),
                items: widget.groups
                    .map(
                      (g) => DropdownMenuItem(
                    value: g.id,
                    child: Text(g.name),
                  ),
                )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                  setState(() {
                    _selectedGroupId = val;
                    final linked = _linkedActiveSubjectsFor(val);
                    _selectedSubjectId =
                    linked.isNotEmpty ? linked.first.id : null;
                    _errorMessage = null;
                  });
                },
                validator: (val) =>
                val == null ? 'Please select a group.' : null,
              ),
              const SizedBox(height: 12),
              if (availableSubjects.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'This group has no active linked subjects. Link a subject in the Groups tab first.',
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('sub_${_selectedGroupId}_$_selectedSubjectId'),
                  initialValue: _selectedSubjectId,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: availableSubjects
                      .map(
                        (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.code} · ${s.name}'),
                    ),
                  )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (val) => setState(() => _selectedSubjectId = val),
                  validator: (val) =>
                  val == null ? 'Please select a subject.' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roomController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Room',
                  hintText: 'e.g. Lab 2 / Room B104',
                ),
                validator: (val) {
                  final trimmed = (val ?? '').trim();
                  if (trimmed.isEmpty) return 'Room is required.';
                  if (trimmed.length > 60) {
                    return 'Room must be 60 characters or fewer.';
                  }
                  return null;
                },
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                    if (_needsLocationSettings)
                      TextButton(
                        onPressed: Geolocator.openLocationSettings,
                        child: const Text('Open Location Settings'),
                      ),
                    if (_needsAppSettings)
                      TextButton(
                        onPressed: Geolocator.openAppSettings,
                        child: const Text('Open App Settings'),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_isSubmitting ||
                        widget.groups.isEmpty ||
                        availableSubjects.isEmpty)
                        ? null
                        : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Open Session'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? dt) {
  if (dt == null) return 'Just now';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}