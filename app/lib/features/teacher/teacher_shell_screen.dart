import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../academics/academics_provider.dart';
import '../auth/auth_provider.dart';
import 'groups_tab.dart';
import 'sessions_tab.dart';

class TeacherShellScreen extends ConsumerStatefulWidget {
  const TeacherShellScreen({super.key});

  @override
  ConsumerState<TeacherShellScreen> createState() => _TeacherShellScreenState();
}

class _TeacherShellScreenState extends ConsumerState<TeacherShellScreen> {
  int _selectedIndex = 0;

  static const _titles = [
    'Sessions',
    'Subjects & Groups',
    'Statistics',
    'AI Summary',
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider).value;
    final colorScheme = Theme.of(context).colorScheme;
    final segment = ref.watch(academicsSegmentProvider);

    Widget body;
    if (_selectedIndex == 0) {
      body = const SessionsTab();
    } else if (_selectedIndex == 1) {
      body = const GroupsTab();
    } else {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.school),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Teacher',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Teacher Account',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${_titles[_selectedIndex]} view will be built in upcoming steps.',
                ),
              ],
            ),
          ),
        ),
      );
    }

    FloatingActionButton? fab;
    if (_selectedIndex == 0) {
      fab = FloatingActionButton(
        tooltip: 'Start Session',
        onPressed: () => showStartSessionFlow(context, ref),
        child: const Icon(Icons.add),
      );
    } else if (_selectedIndex == 1) {
      fab = FloatingActionButton(
        tooltip: segment == AcademicsSegment.groups
            ? 'Create Group'
            : 'Create Subject',
        onPressed: () => showCreateAcademicsSheet(context, ref),
        child: const Icon(Icons.add),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
        ],
      ),
    );
  }
}