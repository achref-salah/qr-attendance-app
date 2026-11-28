import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import '../../models/presence_model.dart';
import '../../models/session_model.dart';
import '../../models/subject_model.dart';
import '../academics/academics_provider.dart';
import '../auth/auth_provider.dart';
import '../sessions/session_provider.dart';
import '../sessions/session_repository.dart';

class LiveSessionScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const LiveSessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  static final int _intervalSeconds =
      AppConstants.qrRotationInterval.inSeconds;

  Timer? _ticker;
  int _secondsLeft = _intervalSeconds;
  bool _isRotating = false;
  bool _isClosing = false;
  bool _initialSyncChecked = false;
  String? _rotationError;
  DateTime? _lastRotationSuccessAt;
  String? _latestKnownToken;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final session = ref.read(sessionByIdProvider(widget.sessionId)).value;
    if (session == null || !session.isOpen) return;

    if (_secondsLeft > 1) {
      setState(() => _secondsLeft--);
    } else if (!_isRotating) {
      _rotateNow();
    }
  }

  Future<void> _rotateNow() async {
    if (_isRotating) return;
    final session = ref.read(sessionByIdProvider(widget.sessionId)).value;
    if (session == null || !session.isOpen) return;

    final currentSecret =
        ref.read(sessionSecretProvider(widget.sessionId)).value;

    setState(() {
      _isRotating = true;
    });

    try {
      await ref.read(sessionRepositoryProvider).rotateSessionToken(
        sessionId: widget.sessionId,
        previousToken: currentSecret?.token ?? _latestKnownToken,
      );
      if (!mounted) return;
      setState(() {
        _isRotating = false;
        _rotationError = null;
        _secondsLeft = _intervalSeconds;
        _lastRotationSuccessAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRotating = false;
        _rotationError = e.toString();
      });
    }
  }

  Future<void> _confirmAndClose(SessionModel session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close Session?'),
        content: const Text(
          'Students will no longer be able to scan QR codes or check in after closing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 44),
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close Session'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClosing = true);
    try {
      await ref.read(sessionRepositoryProvider).closeSession(session.id);
      _ticker?.cancel();
      if (!mounted) return;
      setState(() => _isClosing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClosing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _openManualPresenceSheet({
    required SessionModel session,
    required List<AppUser> students,
    required Set<String> presentIds,
  }) async {
    final teacherId = ref.read(firebaseAuthStateProvider).value?.uid;
    if (teacherId == null) return;

    final absentStudents =
    students.where((s) => !presentIds.contains(s.uid)).toList();

    final messenger = ScaffoldMessenger.of(context);
    final addedName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ManualPresenceSheet(
        sessionId: session.id,
        teacherId: teacherId,
        absentStudents: absentStudents,
      ),
    );

    if (addedName != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('$addedName marked present (manual).')),
      );
    }
  }

  void _openEnlargedQrDialog({
    required String title,
    required String subtitle,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _EnlargedQrDialog(
        sessionId: widget.sessionId,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionByIdProvider(widget.sessionId));
    final groups = ref.watch(teacherGroupsProvider).value ?? const <GroupModel>[];
    final subjects =
        ref.watch(teacherSubjectsProvider).value ?? const <SubjectModel>[];
    final groupMap = {for (final g in groups) g.id: g};
    final subjectMap = {for (final s in subjects) s.id: s};

    return sessionAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading session: $err'),
          ),
        ),
      ),
      data: (session) {
        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Session')),
            body: const Center(child: Text('Session not found.')),
          );
        }

        final group = groupMap[session.groupId];
        final subject = subjectMap[session.subjectId];
        final groupName = group?.name ?? session.groupId;
        final subjectTitle = subject == null
            ? session.subjectId
            : '${subject.code} · ${subject.name}';

        final secretAsync = session.isOpen
            ? ref.watch(sessionSecretProvider(widget.sessionId))
            : const AsyncData<SessionSecretModel?>(null);
        final secret = secretAsync.value;
        if (secret != null && secret.token.isNotEmpty) {
          _latestKnownToken = secret.token;
          _lastRotationSuccessAt ??= secret.tokenUpdatedAt ?? DateTime.now();
        }

        if (session.isOpen && !_initialSyncChecked && !secretAsync.isLoading) {
          _initialSyncChecked = true;
          final updatedAt = secret?.tokenUpdatedAt;
          final isMissingOrStale = secret == null ||
              secret.token.isEmpty ||
              (updatedAt != null &&
                  DateTime.now().difference(updatedAt) >
                      AppConstants.qrRotationInterval);
          if (isMissingOrStale) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _rotateNow();
            });
          }
        }

        if (!session.isOpen && (_ticker?.isActive ?? false)) {
          _ticker?.cancel();
        }

        final presencesAsync =
        ref.watch(sessionPresencesProvider(widget.sessionId));
        final studentsAsync = ref.watch(groupStudentsProvider(session.groupId));
        final students = studentsAsync.value ?? const <AppUser>[];
        final presences = presencesAsync.value ?? const <PresenceModel>[];
        final studentMap = {for (final s in students) s.uid: s};
        final presentIds = {for (final p in presences) p.studentId};

        final isStalled = session.isOpen &&
            (_rotationError != null ||
                (_lastRotationSuccessAt != null &&
                    DateTime.now().difference(_lastRotationSuccessAt!) >=
                        const Duration(seconds: 20)));

        return Scaffold(
          appBar: AppBar(
            title: Text(groupName),
            actions: [
              if (session.isOpen)
                TextButton.icon(
                  onPressed:
                  _isClosing ? null : () => _confirmAndClose(session),
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    _isClosing ? 'Closing...' : 'Close',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SessionHeaderBanner(
                session: session,
                groupName: groupName,
                subjectTitle: subjectTitle,
              ),
              const SizedBox(height: 16),
              if (session.isOpen) ...[
                _QrSectionCard(
                  sessionId: session.id,
                  secretAsync: secretAsync,
                  secondsLeft: _secondsLeft,
                  totalSeconds: _intervalSeconds,
                  isRotating: _isRotating,
                  isStalled: isStalled,
                  stallError: _rotationError,
                  onRetryRotate: _rotateNow,
                  onEnlarge: () => _openEnlargedQrDialog(
                    title: groupName,
                    subtitle: '$subjectTitle · Room ${session.room}',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _PresencesHeaderRow(
                presentCount: presences.length,
                totalStudents: students.length,
                isOpen: session.isOpen,
                onAddManual: () => _openManualPresenceSheet(
                  session: session,
                  students: students,
                  presentIds: presentIds,
                ),
              ),
              const SizedBox(height: 8),
              if (presencesAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (presencesAsync.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load presences: ${presencesAsync.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              else if (presences.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        session.isOpen
                            ? 'No students checked in yet. Presences will appear live as students scan or are added manually.'
                            : 'No students checked in during this session.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ...presences.map(
                        (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PresenceTile(
                        presence: p,
                        student: studentMap[p.studentId],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionHeaderBanner extends StatelessWidget {
  final SessionModel session;
  final String groupName;
  final String subjectTitle;

  const _SessionHeaderBanner({
    required this.session,
    required this.groupName,
    required this.subjectTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subjectTitle,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$groupName · Room ${session.room}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: session.isOpen
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                session.isOpen ? 'OPEN' : 'CLOSED',
                style: textTheme.labelMedium?.copyWith(
                  color: session.isOpen
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrSectionCard extends StatelessWidget {
  final String sessionId;
  final AsyncValue<SessionSecretModel?> secretAsync;
  final int secondsLeft;
  final int totalSeconds;
  final bool isRotating;
  final bool isStalled;
  final String? stallError;
  final VoidCallback onRetryRotate;
  final VoidCallback onEnlarge;

  const _QrSectionCard({
    required this.sessionId,
    required this.secretAsync,
    required this.secondsLeft,
    required this.totalSeconds,
    required this.isRotating,
    required this.isStalled,
    required this.stallError,
    required this.onRetryRotate,
    required this.onEnlarge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secret = secretAsync.value;
    final token = secret?.token ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Live Attendance QR',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Enlarge QR',
                  onPressed: token.isEmpty ? null : onEnlarge,
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isStalled) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QR rotation stalled — check internet connection. Students may get expired-QR errors.',
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                    if (stallError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        stallError!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onRetryRotate,
                      child: const Text('Retry Now'),
                    ),
                  ],
                ),
              ),
            ],
            if (token.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              InkWell(
                onTap: onEnlarge,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                  child: QrImageView(
                    data: SessionRepository.encodeQrPayload(
                      sessionId: sessionId,
                      token: token,
                    ),
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (secondsLeft / totalSeconds).clamp(0.0, 1.0),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    isRotating
                        ? 'Refreshing token...'
                        : 'Rotates in ${secondsLeft}s',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  'Tap QR to enlarge',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
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

class _EnlargedQrDialog extends ConsumerWidget {
  final String sessionId;
  final String title;
  final String subtitle;

  const _EnlargedQrDialog({
    required this.sessionId,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secret = ref.watch(sessionSecretProvider(sessionId)).value;
    final token = secret?.token ?? '';
    final qrSize = (MediaQuery.sizeOf(context).width - 88).clamp(200.0, 340.0);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: token.isEmpty
                      ? SizedBox(
                    width: qrSize,
                    height: qrSize,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                      : QrImageView(
                    data: SessionRepository.encodeQrPayload(
                      sessionId: sessionId,
                      token: token,
                    ),
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'QR code refreshes automatically every 10 seconds',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresencesHeaderRow extends StatelessWidget {
  final int presentCount;
  final int totalStudents;
  final bool isOpen;
  final VoidCallback onAddManual;

  const _PresencesHeaderRow({
    required this.presentCount,
    required this.totalStudents,
    required this.isOpen,
    required this.onAddManual,
  });

  @override
  Widget build(BuildContext context) {
    final countText = totalStudents > 0
        ? 'Presences ($presentCount / $totalStudents)'
        : 'Presences ($presentCount)';

    return Row(
      children: [
        Expanded(
          child: Text(
            countText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isOpen)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: onAddManual,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Manual'),
          ),
      ],
    );
  }
}

class _PresenceTile extends StatelessWidget {
  final PresenceModel presence;
  final AppUser? student;

  const _PresenceTile({
    required this.presence,
    required this.student,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final name = student?.name ?? presence.studentId;
    final reg = student?.registrationNumber;
    final subtitleParts = <String>[
      if (reg != null && reg.isNotEmpty) reg,
      if (presence.isManual &&
          presence.reason != null &&
          presence.reason!.isNotEmpty)
        'Reason: ${presence.reason}'
      else if (!presence.isManual && presence.distance != null)
        '${presence.distance!.round()} m away',
      _formatTime(presence.createdAt),
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: presence.isManual
              ? colorScheme.secondaryContainer
              : colorScheme.primaryContainer,
          foregroundColor: presence.isManual
              ? colorScheme.onSecondaryContainer
              : colorScheme.onPrimaryContainer,
          child: Icon(
            presence.isManual ? Icons.edit_note : Icons.qr_code_scanner,
          ),
        ),
        title: Text(name),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: presence.isManual
                ? colorScheme.secondaryContainer
                : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            presence.isManual ? 'Manual' : 'QR',
            style: textTheme.labelSmall?.copyWith(
              color: presence.isManual
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'Just now';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}

class _ManualPresenceSheet extends ConsumerStatefulWidget {
  final String sessionId;
  final String teacherId;
  final List<AppUser> absentStudents;

  const _ManualPresenceSheet({
    required this.sessionId,
    required this.teacherId,
    required this.absentStudents,
  });

  @override
  ConsumerState<_ManualPresenceSheet> createState() =>
      _ManualPresenceSheetState();
}

class _ManualPresenceSheetState extends ConsumerState<_ManualPresenceSheet> {
  static const _quickReasons = [
    'Phone issue',
    'Camera issue',
    'Late arrival',
  ];

  final _reasonController = TextEditingController();
  AppUser? _selectedStudent;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final student = _selectedStudent;
    if (student == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(sessionRepositoryProvider).addManualPresence(
        sessionId: widget.sessionId,
        teacherId: widget.teacherId,
        studentId: student.uid,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(student.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add Manual Presence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Select an absent student from this group.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.absentStudents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'All registered students in this group are already marked present.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.absentStudents.length,
                  itemBuilder: (context, index) {
                    final student = widget.absentStudents[index];
                    final selected = _selectedStudent?.uid == student.uid;
                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                      colorScheme.primaryContainer.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(student.name),
                      subtitle: student.registrationNumber != null
                          ? Text(student.registrationNumber!)
                          : null,
                      onTap: _isSaving
                          ? null
                          : () => setState(() => _selectedStudent = student),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _quickReasons.map((label) {
                  final active = _reasonController.text.trim() == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: active,
                    onSelected: _isSaving
                        ? null
                        : (selected) {
                      setState(() {
                        _reasonController.text = selected ? label : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonController,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Phone battery died',
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_isSaving || _selectedStudent == null)
                        ? null
                        : _submit,
                    child: _isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Mark Present'),
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