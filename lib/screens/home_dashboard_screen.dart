import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../widgets/app_logo.dart';
import 'link_studio_screen.dart';
import 'practice_mode_screen.dart';

enum SelectionMode { none, group, delete }

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key, required this.library});

  final RoutineLibrary library;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _tabIndex = 0;

  void _openLinkStudio() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkStudioScreen(library: widget.library),
      ),
    );
  }

  void _startRoutine(SavedRoutine routine) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeModeScreen(routine: routine),
      ),
    );
  }

  void _onTabSelected(int index) {
    if (index == 2) {
      _openLinkStudio();
      return;
    }
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 16,
        title: const Align(
          alignment: Alignment.centerLeft,
          child: AppLogo(height: 30),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: '알림',
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            onPressed: () => setState(() => _tabIndex = 3),
            tooltip: '프로필',
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tabIndex == 2 ? 0 : _tabIndex,
          children: [
            _HomeTab(
              library: widget.library,
              onCreateRoutine: _openLinkStudio,
              onStartRoutine: _startRoutine,
            ),
            _LibraryTab(
              library: widget.library,
              onCreateRoutine: _openLinkStudio,
              onStartRoutine: _startRoutine,
            ),
            const SizedBox.shrink(),
            const _SettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex == 2 ? 0 : _tabIndex,
        onDestinationSelected: _onTabSelected,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        destinations: [
          NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'home.tab_home'.tr(), //
        ),
        NavigationDestination(
          icon: const Icon(Icons.bookmark_outline),
          selectedIcon: const Icon(Icons.bookmark),
          label: 'library.title'.tr(),
        ),
        NavigationDestination(
          icon: Icon(Icons.movie_creation_outlined),
          selectedIcon: Icon(Icons.movie_creation),
          label: 'home.tab_studio'.tr(), 
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'home.tab_settings'.tr(), 
        ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.library,
    required this.onCreateRoutine,
    required this.onStartRoutine,
  });

  final RoutineLibrary library;
  final VoidCallback onCreateRoutine;
  final ValueChanged<SavedRoutine> onStartRoutine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.62);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Text('home.greeting'.tr(), style: TextStyle(color: muted, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          'home.subtitle'.tr(),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: library,
          builder: (context, _) => _WeeklyStatsCard(routineCount: library.routines.length),
        ),
        const SizedBox(height: 20),
        _QuickActionCard(onTap: onCreateRoutine),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'home.recent_routines'.tr(),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(onPressed: () {}, child: Text('home.view_all'.tr())),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: library,
          builder: (context, _) {
            if (library.routines.isEmpty) {
              return _EmptyRoutineCard(onTap: onCreateRoutine);
            }
            return Column(
              children: [
                for (final routine in library.routines.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RoutineCard(
                      routine: routine,
                      onStart: () => onStartRoutine(routine),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WeeklyStatsCard extends StatelessWidget {
  const _WeeklyStatsCard({required this.routineCount});

  final int routineCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'home.weekly_stats'.tr(),
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  icon: Icons.local_fire_department_rounded,
                  label: 'home.continuous_learning'.tr(),
                  value: '5${'common.days'.tr()}',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.timer_outlined,
                  label: 'home.this_week'.tr(),
                  value: '42${'common.minutes'.tr()}',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.library_music_outlined,
                  label: 'home.saved_routines'.tr(),
                  value: '$routineCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: LoopiColors.purple),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: LoopiColors.purple,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'home.quick_action'.tr(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'home.quick_action_subtitle'.tr(),
                    style: TextStyle(color: Color(0xFFE8E0FF), fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoutineCard extends StatelessWidget {
  const _EmptyRoutineCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded, color: LoopiColors.purple, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'home.no_routines'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.onStart,
    this.isSelected = false,
    this.onTap,
  });

  final SavedRoutine routine;
  final VoidCallback onStart;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = routine.segments.first;
    final last = routine.segments.last;
    final rangeLabel =
        '${formatMmSs(first.startSec)} – ${formatMmSs(last.endSec)} · ${routine.segments.length}개 구간';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: LoopiColors.purple, width: 2)
              : null,
        ),
        child: Row(
          children: [
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle, color: LoopiColors.purple),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                'https://img.youtube.com/vi/${routine.videoId}/mqdefault.jpg',
                width: 72,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 72,
                  height: 52,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Icon(Icons.play_circle_fill_rounded, color: LoopiColors.purple),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    rangeLabel,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onTap == null)
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: LoopiColors.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('home.start_practice'.tr()),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    required this.library,
    required this.onCreateRoutine,
    required this.onStartRoutine,
  });

  final RoutineLibrary library;
  final VoidCallback onCreateRoutine;
  final ValueChanged<SavedRoutine> onStartRoutine;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  SelectionMode _selectionMode = SelectionMode.none;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(SelectionMode mode) {
    setState(() {
      _selectionMode = mode;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = SelectionMode.none;
      _selectedIds.clear();
    });
  }

  Future<void> _handleGroupConfirm() async {
    if (_selectedIds.isEmpty) return;
    
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('library.create_group'.tr()),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: 'library.group_name_hint'.tr()),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('library.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text('library.confirm'.tr()),
          ),
        ],
      ),
    );
    
    if (name?.isNotEmpty == true) {
      widget.library.createGroup(name: name!, routineIds: _selectedIds.toList());
    }
    _exitSelectionMode();
  }

  Future<void> _handleDeleteConfirm() async {
    if (_selectedIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('library.delete_confirm_title'.tr()),
        content: Text('library.delete_confirm_message'.tr().replaceAll('N', '${_selectedIds.length}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('library.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('library.delete'.tr()),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      widget.library.deleteMany(_selectedIds);
    }
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        if (widget.library.routines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _EmptyRoutineCard(onTap: widget.onCreateRoutine),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  Text(
                    'library.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (_selectionMode == SelectionMode.none) ...[
                    IconButton(
                      onPressed: () => _enterSelectionMode(SelectionMode.group),
                      icon: const Icon(Icons.folder_shared),
                      tooltip: '루틴 묶어서 저장',
                    ),
                    IconButton(
                      onPressed: () => _enterSelectionMode(SelectionMode.delete),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '삭제',
                    ),
                  ] else ...[
                    if (_selectionMode == SelectionMode.group)
                      IconButton(
                        onPressed: _handleGroupConfirm,
                        icon: const Icon(Icons.check),
                        tooltip: '확인',
                      )
                    else
                      IconButton(
                        onPressed: _handleDeleteConfirm,
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: '삭제',
                      ),
                    IconButton(
                      onPressed: _exitSelectionMode,
                      icon: const Icon(Icons.close),
                      tooltip: '취소',
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  for (final routine in widget.library.routines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RoutineCard(
                        routine: routine,
                        onStart: () => widget.onStartRoutine(routine),
                        isSelected: _selectedIds.contains(routine.id),
                        onTap: _selectionMode != SelectionMode.none
                            ? () => _toggleSelection(routine.id)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text('settings.notifications'.tr()),
          subtitle: Text('settings.notifications_subtitle'.tr()),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text('settings.theme'.tr()),
          subtitle: Text('settings.theme_subtitle'.tr()),
        ),
        Builder(
          builder: (context) => ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr()),
            subtitle: Text('settings.language_subtitle'.tr()),
            trailing: DropdownButton<Locale>(
              value: context.locale,
              items: const [
                DropdownMenuItem(value: Locale('en'), child: Text('English')),
                DropdownMenuItem(value: Locale('ko'), child: Text('한국어')),
              ],
              onChanged: (locale) {
                if (locale != null) {
                  context.setLocale(locale);
                }
              },
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('settings.app_info'.tr()),
          subtitle: Text('settings.app_info_subtitle'.tr()),
        ),
      ],
    );
  }
}
