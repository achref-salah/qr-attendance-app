import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../models/group_model.dart';
import '../../models/subject_model.dart';
import '../academics/academics_provider.dart';
import '../academics/academics_repository.dart';
import '../auth/auth_provider.dart';

Future<void> showCreateAcademicsSheet(
    BuildContext context,
    WidgetRef ref,
    ) async {
  final teacherId = ref.read(firebaseAuthStateProvider).value?.uid;
  if (teacherId == null) return;

  final segment = ref.read(academicsSegmentProvider);
  if (segment == AcademicsSegment.groups) {
    await _showGroupFormSheet(context: context, teacherId: teacherId);
  } else {
    await _showSubjectFormSheet(context: context, teacherId: teacherId);
  }
}

class GroupsTab extends ConsumerWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(academicsSegmentProvider);
    final showArchived = ref.watch(showArchivedAcademicsProvider);
    final groupsAsync = ref.watch(teacherGroupsProvider);
    final subjectsAsync = ref.watch(teacherSubjectsProvider);
    final teacherId = ref.watch(firebaseAuthStateProvider).value?.uid;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<AcademicsSegment>(
                segments: const [
                  ButtonSegment<AcademicsSegment>(
                    value: AcademicsSegment.groups,
                    icon: Icon(Icons.groups_outlined),
                    label: Text('Groups'),
                  ),
                  ButtonSegment<AcademicsSegment>(
                    value: AcademicsSegment.subjects,
                    icon: Icon(Icons.menu_book_outlined),
                    label: Text('Subjects'),
                  ),
                ],
                selected: {segment},
                onSelectionChanged: (selection) {
                  ref
                      .read(academicsSegmentProvider.notifier)
                      .select(selection.first);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Show archived'),
                  selected: showArchived,
                  onSelected: (selected) {
                    ref
                        .read(showArchivedAcademicsProvider.notifier)
                        .toggle(selected);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: segment == AcademicsSegment.groups
              ? _GroupsListView(
            groupsAsync: groupsAsync,
            subjectsAsync: subjectsAsync,
            showArchived: showArchived,
            teacherId: teacherId,
          )
              : _SubjectsListView(
            subjectsAsync: subjectsAsync,
            showArchived: showArchived,
            teacherId: teacherId,
          ),
        ),
      ],
    );
  }
}

class _GroupsListView extends ConsumerWidget {
  final AsyncValue<List<GroupModel>> groupsAsync;
  final AsyncValue<List<SubjectModel>> subjectsAsync;
  final bool showArchived;
  final String? teacherId;

  const _GroupsListView({
    required this.groupsAsync,
    required this.subjectsAsync,
    required this.showArchived,
    required this.teacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorState(message: err.toString()),
      data: (allGroups) {
        final groups = showArchived
            ? allGroups
            : allGroups.where((g) => !g.isArchived).toList();

        if (groups.isEmpty) {
          return _EmptyState(
            icon: Icons.groups_outlined,
            title: showArchived ? 'No groups found' : 'No active groups yet',
            subtitle: showArchived
                ? 'Tap + to create your first student group.'
                : 'Tap + to create a group, or enable "Show archived".',
          );
        }

        final subjectList = subjectsAsync.value ?? const <SubjectModel>[];
        final subjectMap = {for (final s in subjectList) s.id: s};

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final group = groups[index];
            return _GroupCard(
              group: group,
              subjectMap: subjectMap,
              allSubjects: subjectList,
              teacherId: teacherId,
            );
          },
        );
      },
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final GroupModel group;
  final Map<String, SubjectModel> subjectMap;
  final List<SubjectModel> allSubjects;
  final String? teacherId;

  const _GroupCard({
    required this.group,
    required this.subjectMap,
    required this.allSubjects,
    required this.teacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showManageSubjectsSheet(
          context: context,
          group: group,
          allSubjects: allSubjects,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: group.isArchived
                        ? colorScheme.surfaceContainerHighest
                        : colorScheme.primaryContainer,
                    foregroundColor: group.isArchived
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.groups),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.name,
                                style: textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (group.isArchived) ...[
                              const SizedBox(width: 8),
                              const _ArchivedBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.subjectIds.isEmpty
                              ? 'Tap to link subjects'
                              : '${group.subjectIds.length} linked ${group.subjectIds.length == 1 ? 'subject' : 'subjects'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Group options',
                    onSelected: (value) async {
                      if (teacherId == null) return;
                      switch (value) {
                        case 'manage_subjects':
                          await _showManageSubjectsSheet(
                            context: context,
                            group: group,
                            allSubjects: allSubjects,
                          );
                        case 'edit':
                          await _showGroupFormSheet(
                            context: context,
                            teacherId: teacherId!,
                            existingGroup: group,
                          );
                        case 'archive':
                        case 'restore':
                          await _toggleGroupArchive(
                            context: context,
                            ref: ref,
                            group: group,
                          );
                        case 'delete':
                          await _handleDeleteGroup(
                            context: context,
                            ref: ref,
                            teacherId: teacherId!,
                            group: group,
                          );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'manage_subjects',
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('Manage Subjects'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: group.isArchived ? 'restore' : 'archive',
                        child: ListTile(
                          leading: Icon(
                            group.isArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                          ),
                          title: Text(group.isArchived ? 'Restore' : 'Archive'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: colorScheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (group.subjectIds.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: group.subjectIds.map((subId) {
                    final subject = subjectMap[subId];
                    final label = subject == null
                        ? subId
                        : subject.isArchived
                        ? '${subject.code} (Archived)'
                        : '${subject.code} · ${subject.name}';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectsListView extends ConsumerWidget {
  final AsyncValue<List<SubjectModel>> subjectsAsync;
  final bool showArchived;
  final String? teacherId;

  const _SubjectsListView({
    required this.subjectsAsync,
    required this.showArchived,
    required this.teacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return subjectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorState(message: err.toString()),
      data: (allSubjects) {
        final subjects = showArchived
            ? allSubjects
            : allSubjects.where((s) => !s.isArchived).toList();

        if (subjects.isEmpty) {
          return _EmptyState(
            icon: Icons.menu_book_outlined,
            title:
            showArchived ? 'No subjects found' : 'No active subjects yet',
            subtitle: showArchived
                ? 'Tap + to create your first subject.'
                : 'Tap + to create a subject, or enable "Show archived".',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: subjects.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return _SubjectCard(subject: subject, teacherId: teacherId);
          },
        );
      },
    );
  }
}

class _SubjectCard extends ConsumerWidget {
  final SubjectModel subject;
  final String? teacherId;

  const _SubjectCard({
    required this.subject,
    required this.teacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: subject.isArchived
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                subject.code,
                style: textTheme.labelLarge?.copyWith(
                  color: subject.isArchived
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      subject.name,
                      style: textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subject.isArchived) ...[
                    const SizedBox(width: 8),
                    const _ArchivedBadge(),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Subject options',
              onSelected: (value) async {
                if (teacherId == null) return;
                switch (value) {
                  case 'edit':
                    await _showSubjectFormSheet(
                      context: context,
                      teacherId: teacherId!,
                      existingSubject: subject,
                    );
                  case 'archive':
                  case 'restore':
                    await _toggleSubjectArchive(
                      context: context,
                      ref: ref,
                      subject: subject,
                    );
                  case 'delete':
                    await _handleDeleteSubject(
                      context: context,
                      ref: ref,
                      teacherId: teacherId!,
                      subject: subject,
                    );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: subject.isArchived ? 'restore' : 'archive',
                  child: ListTile(
                    leading: Icon(
                      subject.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    title: Text(subject.isArchived ? 'Restore' : 'Archive'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: colorScheme.error,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
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

class _ArchivedBadge extends StatelessWidget {
  const _ArchivedBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Archived',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load data: $message',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

// ---------- Bottom Sheets (StatefulWidgets for safe controller disposal) ----------

Future<void> _showGroupFormSheet({
  required BuildContext context,
  required String teacherId,
  GroupModel? existingGroup,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final resultMessage = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GroupFormSheet(
      teacherId: teacherId,
      existingGroup: existingGroup,
    ),
  );

  if (resultMessage != null) {
    messenger.showSnackBar(SnackBar(content: Text(resultMessage)));
  }
}

class _GroupFormSheet extends ConsumerStatefulWidget {
  final String teacherId;
  final GroupModel? existingGroup;

  const _GroupFormSheet({
    required this.teacherId,
    this.existingGroup,
  });

  @override
  ConsumerState<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends ConsumerState<_GroupFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingGroup?.name ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(academicsRepositoryProvider);
      if (widget.existingGroup == null) {
        await repo.createGroup(
          teacherId: widget.teacherId,
          name: _nameController.text,
        );
      } else {
        await repo.updateGroupName(
          teacherId: widget.teacherId,
          groupId: widget.existingGroup!.id,
          newName: _nameController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        widget.existingGroup == null ? 'Group created.' : 'Group updated.',
      );
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

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existingGroup == null ? 'Create Group' : 'Edit Group',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g. GLSI-3A',
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) return 'Group name is required.';
                if (trimmed.length > 100) {
                  return 'Group name must be 100 characters or fewer.';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 20),
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
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Text(widget.existingGroup == null ? 'Create' : 'Save'),
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

Future<void> _showSubjectFormSheet({
  required BuildContext context,
  required String teacherId,
  SubjectModel? existingSubject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final resultMessage = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SubjectFormSheet(
      teacherId: teacherId,
      existingSubject: existingSubject,
    ),
  );

  if (resultMessage != null) {
    messenger.showSnackBar(SnackBar(content: Text(resultMessage)));
  }
}

class _SubjectFormSheet extends ConsumerStatefulWidget {
  final String teacherId;
  final SubjectModel? existingSubject;

  const _SubjectFormSheet({
    required this.teacherId,
    this.existingSubject,
  });

  @override
  ConsumerState<_SubjectFormSheet> createState() => _SubjectFormSheetState();
}

class _SubjectFormSheetState extends ConsumerState<_SubjectFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.existingSubject?.code ?? '',
    );
    _nameController = TextEditingController(
      text: widget.existingSubject?.name ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(academicsRepositoryProvider);
      if (widget.existingSubject == null) {
        await repo.createSubject(
          teacherId: widget.teacherId,
          code: _codeController.text,
          name: _nameController.text,
        );
      } else {
        await repo.updateSubject(
          teacherId: widget.teacherId,
          subjectId: widget.existingSubject!.id,
          newCode: _codeController.text,
          newName: _nameController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        widget.existingSubject == null
            ? 'Subject created.'
            : 'Subject updated.',
      );
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

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existingSubject == null
                  ? 'Create Subject'
                  : 'Edit Subject',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Subject Code',
                hintText: 'e.g. CS-401',
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) return 'Subject code is required.';
                if (trimmed.length > 30) {
                  return 'Subject code must be 30 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Subject Name',
                hintText: 'e.g. Mobile Development',
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) return 'Subject name is required.';
                if (trimmed.length > 100) {
                  return 'Subject name must be 100 characters or fewer.';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 20),
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
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Text(
                      widget.existingSubject == null ? 'Create' : 'Save',
                    ),
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

Future<void> _showManageSubjectsSheet({
  required BuildContext context,
  required GroupModel group,
  required List<SubjectModel> allSubjects,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final resultMessage = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ManageSubjectsSheet(
      group: group,
      allSubjects: allSubjects,
    ),
  );

  if (resultMessage != null) {
    messenger.showSnackBar(SnackBar(content: Text(resultMessage)));
  }
}

class _ManageSubjectsSheet extends ConsumerStatefulWidget {
  final GroupModel group;
  final List<SubjectModel> allSubjects;

  const _ManageSubjectsSheet({
    required this.group,
    required this.allSubjects,
  });

  @override
  ConsumerState<_ManageSubjectsSheet> createState() =>
      _ManageSubjectsSheetState();
}

class _ManageSubjectsSheetState extends ConsumerState<_ManageSubjectsSheet> {
  late final Set<String> _selectedIds;
  late final List<SubjectModel> _selectableSubjects;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.group.subjectIds.toSet();
    // Show active subjects + any archived subject already linked so it can be unlinked.
    _selectableSubjects = widget.allSubjects
        .where((s) => !s.isArchived || _selectedIds.contains(s.id))
        .toList();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(academicsRepositoryProvider).updateGroupSubjects(
        groupId: widget.group.id,
        subjectIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop('Linked subjects updated.');
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Subjects for ${widget.group.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Select subjects associated with this group.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_selectableSubjects.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No active subjects available. Create a subject first.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _selectableSubjects.length,
                  itemBuilder: (context, index) {
                    final subject = _selectableSubjects[index];
                    final checked = _selectedIds.contains(subject.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: _isSaving
                          ? null
                          : (val) {
                        setState(() {
                          if (val ?? false) {
                            _selectedIds.add(subject.id);
                          } else {
                            _selectedIds.remove(subject.id);
                          }
                        });
                      },
                      title: Text('${subject.code} · ${subject.name}'),
                      subtitle: subject.isArchived
                          ? const Text('Archived — uncheck to unlink')
                          : null,
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
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
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Save'),
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

// ---------- Archive & Delete Actions ----------

Future<void> _toggleGroupArchive({
  required BuildContext context,
  required WidgetRef ref,
  required GroupModel group,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final nextArchived = !group.isArchived;
  try {
    await ref
        .read(academicsRepositoryProvider)
        .setGroupArchived(groupId: group.id, isArchived: nextArchived);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nextArchived
              ? '${group.name} archived.'
              : '${group.name} restored.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

Future<void> _toggleSubjectArchive({
  required BuildContext context,
  required WidgetRef ref,
  required SubjectModel subject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final nextArchived = !subject.isArchived;
  try {
    await ref
        .read(academicsRepositoryProvider)
        .setSubjectArchived(subjectId: subject.id, isArchived: nextArchived);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nextArchived
              ? '${subject.code} archived.'
              : '${subject.code} restored.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

Future<void> _handleDeleteGroup({
  required BuildContext context,
  required WidgetRef ref,
  required String teacherId,
  required GroupModel group,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(academicsRepositoryProvider);

  late final GroupUsageReport usage;
  try {
    usage = await repo.checkGroupUsage(
      teacherId: teacherId,
      groupId: group.id,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return;
  }

  if (!context.mounted) return;

  if (usage.hasAny) {
    final archiveConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cannot Permanently Delete'),
        content: Text(
          '${usage.describeReason()} '
              '${group.isArchived ? 'This group must remain archived to protect historical records.' : 'Would you like to archive "${group.name}" instead?'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(group.isArchived ? 'Close' : 'Cancel'),
          ),
          if (!group.isArchived)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 44),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Archive Instead'),
            ),
        ],
      ),
    );

    if (archiveConfirmed == true) {
      try {
        await repo.setGroupArchived(groupId: group.id, isArchived: true);
        messenger.showSnackBar(
          SnackBar(content: Text('${group.name} archived.')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    return;
  }

  final deleteConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete "${group.name}"?'),
      content: const Text(
        'No students or attendance sessions reference this group. '
            'Permanent deletion cannot be undone.',
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (deleteConfirmed != true) return;

  try {
    final result = await repo.deleteGroupSafely(
      teacherId: teacherId,
      groupId: group.id,
    );
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

Future<void> _handleDeleteSubject({
  required BuildContext context,
  required WidgetRef ref,
  required String teacherId,
  required SubjectModel subject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(academicsRepositoryProvider);

  late final SubjectUsageReport usage;
  try {
    usage = await repo.checkSubjectUsage(
      teacherId: teacherId,
      subjectId: subject.id,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return;
  }

  if (!context.mounted) return;

  if (usage.hasAny) {
    final archiveConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cannot Permanently Delete'),
        content: Text(
          '${usage.describeReason()} '
              '${subject.isArchived ? 'This subject must remain archived to protect existing references.' : 'Would you like to archive "${subject.code}" instead?'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(subject.isArchived ? 'Close' : 'Cancel'),
          ),
          if (!subject.isArchived)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 44),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Archive Instead'),
            ),
        ],
      ),
    );

    if (archiveConfirmed == true) {
      try {
        await repo.setSubjectArchived(subjectId: subject.id, isArchived: true);
        messenger.showSnackBar(
          SnackBar(content: Text('${subject.code} archived.')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    return;
  }

  final deleteConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete "${subject.code}"?'),
      content: const Text(
        'No groups or attendance sessions reference this subject. '
            'Permanent deletion cannot be undone.',
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (deleteConfirmed != true) return;

  try {
    final result = await repo.deleteSubjectSafely(
      teacherId: teacherId,
      subjectId: subject.id,
    );
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}