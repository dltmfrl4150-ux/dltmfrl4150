import 'package:flutter/material.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../widgets/app_logo.dart';
import 'link_studio_screen.dart';
import 'practice_mode_screen.dart';

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
        title: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            color: Colors.transparent,
            child: const AppLogo(height: 30),
          ),
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: '내 루틴 보관함',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation),
            label: '스튜디오',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
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
        Text('좋은 하루예요,', style: TextStyle(color: muted, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          '오늘도 리듬을 이어가볼까요?',
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
              '최근 연습한 루틴',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(onPressed: () {}, child: const Text('전체 보기')),
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
            '주간 학습 스트릭',
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
                  label: '연속 학습',
                  value: '5일',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.timer_outlined,
                  label: '이번 주',
                  value: '42분',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.library_music_outlined,
                  label: '저장 루틴',
                  value: '$routineCount개',
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
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '새 루틴 만들기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '유튜브 링크 등록',
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
                '아직 저장한 루틴이 없어요.\n첫 루틴을 만들어볼까요?',
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
  });

  final SavedRoutine routine;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = routine.segments.first;
    final last = routine.segments.last;
    final rangeLabel =
        '${formatMmSs(first.startSec)} – ${formatMmSs(last.endSec)} · ${routine.segments.length}개 구간';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
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
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: LoopiColors.purple,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('바로 시작'),
          ),
        ],
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.library,
    required this.onCreateRoutine,
    required this.onStartRoutine,
  });

  final RoutineLibrary library;
  final VoidCallback onCreateRoutine;
  final ValueChanged<SavedRoutine> onStartRoutine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        if (library.routines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _EmptyRoutineCard(onTap: onCreateRoutine),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Text(
              '내 루틴 보관함',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            for (final routine in library.routines)
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
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: const [
        ListTile(
          leading: Icon(Icons.notifications_outlined),
          title: Text('알림'),
          subtitle: Text('연습 리마인더 설정'),
        ),
        ListTile(
          leading: Icon(Icons.palette_outlined),
          title: Text('테마'),
          subtitle: Text('시스템 라이트/다크 설정을 따릅니다'),
        ),
        ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('앱 정보'),
          subtitle: Text('LOOPI'),
        ),
      ],
    );
  }
}
