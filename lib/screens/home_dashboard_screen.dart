import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../widgets/app_logo.dart';
import '../widgets/favorite_icon_button.dart';
import 'link_studio_screen.dart';
import 'practice_mode_screen.dart';
import 'practice_screen.dart';

enum SelectionMode { none, group, delete }

class CommunityPost {
  CommunityPost({required this.routine, required this.description})
      : createdAt = DateTime.now();

  final SavedRoutine routine;
  final String description;
  final DateTime createdAt;

  String get authorId => routine.authorId;
  String get authorName => routine.authorName;
}

class CommunityFeedStore extends ChangeNotifier {
  final List<CommunityPost> _posts = [];

  List<CommunityPost> get posts => List.unmodifiable(_posts);

  void add(CommunityPost post) {
    _posts.insert(0, post);
    notifyListeners();
  }

  void toggleFavorite(SavedRoutine routine, bool value, RoutineLibrary library, BuildContext context) async {
    await library.setFavorite(routine.id, value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '즐겨찾기에 추가했습니다.' : '즐겨찾기에서 삭제했습니다.')),
    );
  }
}

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key, required this.library});

  final RoutineLibrary library;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _tabIndex = 0;
  SavedRoutine? _selectedPracticeRoutine;
    Widget? _selectedPracticeView;
  final CommunityFeedStore _communityFeed = CommunityFeedStore();

  Future<void> _shareRoutine(SavedRoutine routine) async {
    final controller = TextEditingController();
    final description = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('커뮤니티에 ${routine.name} 공유'),
        content: TextField(
          controller: controller,
          maxLength: 50,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '루틴을 소개해 주세요',
            counterText: null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('커뮤니티에 게시')),
        ],
      ),
    );
    controller.dispose();
    if (description == null) return;
    _communityFeed.add(CommunityPost(routine: routine, description: description));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('커뮤니티에 게시했습니다.')));
    }
  }

  Future<void> _pickRoutineToShare() async {
    final routines = widget.library.routines;
    if (routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공유할 루틴이 없습니다.')));
      return;
    }
    final routine = await showDialog<SavedRoutine>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공유할 루틴 선택'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: routines.length,
            itemBuilder: (_, index) => ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(routines[index].name),
              onTap: () => Navigator.pop(dialogContext, routines[index]),
            ),
          ),
        ),
      ),
    );
    if (routine != null) await _shareRoutine(routine);
  }

  void _openLinkStudio({
    SourceType sourceType = SourceType.youtube,
    PlatformFile? file,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkStudioScreen(
          library: widget.library,
          sourceType: sourceType,
          file: file,
        ),
      ),
    );
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      _openLinkStudio(sourceType: SourceType.localVideo, file: file);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'mov', 'webm'],
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      _openLinkStudio(sourceType: SourceType.audio, file: file);
    }
  }

  void _startRoutine(SavedRoutine routine) {
    setState(() {
      _selectedPracticeRoutine = routine;
      _selectedPracticeView = null;
      _tabIndex = 3;
    });
  }

  void _openPracticeView(Widget view) {
    setState(() {
      _selectedPracticeRoutine = null;
      _selectedPracticeView = view;
      _tabIndex = 3;
    });
  }

  void _onTabSelected(int index) {
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
            onPressed: () => setState(() => _tabIndex = 4),
            tooltip: '프로필',
            icon: const Icon(Icons.account_circle_outlined),
          ),
          if (_tabIndex == 4)
            IconButton(
              onPressed: _pickRoutineToShare,
              tooltip: '커뮤니티에 루틴 올리기',
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _HomeTab(
              library: widget.library,
              onCreateRoutine: _openLinkStudio,
              onStartRoutine: _startRoutine,
              onCreateVideoRoutine: _pickVideoFile,
              onCreateAudioRoutine: _pickAudioFile,
            ),
            LinkStudioScreen(library: widget.library, embedded: true),
            CommunityFeedScreen(
              feed: _communityFeed,
              library: widget.library,
              onPlay: _startRoutine,
            ),
            PracticeScreen(
              library: widget.library,
              selectedRoutine: _selectedPracticeRoutine,
              selectedView: _selectedPracticeView,
            ),
            _LibraryTab(
              library: widget.library,
              onStartRoutine: _startRoutine,
              onShareRoutine: _shareRoutine,
              onFavorite: (routine, value) => _communityFeed.toggleFavorite(routine, value, widget.library, context),
              onOpenPracticeView: _openPracticeView,
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _onTabSelected,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        destinations: [
          NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'home.tab_home'.tr(), //
        ),
        NavigationDestination(
          icon: const Icon(Icons.movie_creation_outlined),
          selectedIcon: const Icon(Icons.movie_creation),
          label: 'home.tab_studio'.tr(),
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'home.tab_community'.tr(),
        ),
        NavigationDestination(
          icon: Icon(Icons.fitness_center_outlined),
          selectedIcon: Icon(Icons.fitness_center),
          label: '연습',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_outline),
          selectedIcon: Icon(Icons.bookmark),
          label: 'library.title'.tr(),
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
    required this.onCreateVideoRoutine,
    required this.onCreateAudioRoutine,
  });

  final RoutineLibrary library;
  final VoidCallback onCreateRoutine;
  final ValueChanged<SavedRoutine> onStartRoutine;
  final VoidCallback onCreateVideoRoutine;
  final VoidCallback onCreateAudioRoutine;

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
        Text(
          'home.quick_action'.tr(),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _MediaSourceCards(
          onYouTubeTap: onCreateRoutine,
          onVideoTap: onCreateVideoRoutine,
          onAudioTap: onCreateAudioRoutine,
        ),
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

class _MediaSourceCards extends StatelessWidget {
  const _MediaSourceCards({
    required this.onYouTubeTap,
    required this.onVideoTap,
    required this.onAudioTap,
  });

  final VoidCallback onYouTubeTap;
  final VoidCallback onVideoTap;
  final VoidCallback onAudioTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.play_circle_rounded,
            title: 'home.create_routine_youtube'.tr(),
            subtitle: 'home.create_routine_youtube_subtitle'.tr(),
            color: LoopiColors.purple,
            onTap: onYouTubeTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.videocam_rounded,
            title: 'home.create_routine_video'.tr(),
            subtitle: 'home.create_routine_video_subtitle'.tr(),
            color: LoopiColors.deepPurple,
            onTap: onVideoTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.graphic_eq_rounded,
            title: 'home.create_routine_audio'.tr(),
            subtitle: 'home.create_routine_audio_subtitle'.tr(),
            color: LoopiColors.purple.withValues(alpha: 0.8),
            onTap: onAudioTap,
          ),
        ),
        ],
      ),
    );
  }
}

class _MediaSourceCard extends StatelessWidget {
  const _MediaSourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Color(0xFFE8E0FF), fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          ),
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
    this.onShare,
    this.onFavorite,
  });

  final SavedRoutine routine;
  final VoidCallback onStart;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onShare;
  final ValueChanged<bool>? onFavorite;

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
              child: routine.sourceType == SourceType.youtube
                  ? Image.network(
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
                    )
                  : Container(
                      width: 72,
                      height: 52,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        routine.sourceType == SourceType.audio
                            ? Icons.graphic_eq_rounded
                            : Icons.videocam_rounded,
                        color: LoopiColors.purple,
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
            if (onShare != null)
              IconButton(
                onPressed: onShare,
                tooltip: '커뮤니티에 공유',
                icon: const Icon(Icons.share_outlined),
              ),
            if (onFavorite != null)
              FavoriteButton(
                initialValue: routine.isFavorite,
                onChanged: (value) => onFavorite!(value),
              ),
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
    required this.onStartRoutine,
    required this.onShareRoutine,
    required this.onFavorite,
    required this.onOpenPracticeView,
  });

  final RoutineLibrary library;
  final ValueChanged<SavedRoutine> onStartRoutine;
  final ValueChanged<SavedRoutine> onShareRoutine;
  final void Function(SavedRoutine routine, bool value) onFavorite;
  final ValueChanged<Widget> onOpenPracticeView;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  SelectionMode _selectionMode = SelectionMode.none;
  final Set<String> _selectedIds = {};
  int _librarySection = 0;

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
        final groups = widget.library.groups;
        final ungrouped = widget.library.ungroupedRoutines;
        final totalRoutines = widget.library.routines;

        if (totalRoutines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _EmptyRoutineCard(onTap: () {}),
              ],
            ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('내 루틴')),
                  ButtonSegment(value: 1, label: Text('즐겨찾기')),
                  ButtonSegment(value: 2, label: Text('연습 기록')),
                ],
                selected: {_librarySection},
                onSelectionChanged: (selection) => setState(() => _librarySection = selection.first),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  if (_librarySection == 2)
                    for (final result in widget.library.practiceResults)
                      ListTile(
                        leading: const Icon(Icons.video_library_outlined),
                        title: Text(result.name),
                        subtitle: Text('연습 기록 · ${result.createdAt.toLocal()}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final routine = widget.library.byId(result.routineId);
                          if (routine != null) {
                            widget.onOpenPracticeView(
                              PracticeResultViewer(routine: routine, result: result),
                            );
                          }
                        },
                      ),
                  if (_librarySection == 2 && widget.library.practiceResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('저장된 연습 기록이 없습니다.'),
                    ),
                  if (_librarySection == 1)
                    for (final routine in widget.library.favoriteRoutines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RoutineCard(
                          routine: routine,
                          onStart: () => widget.onStartRoutine(routine),
                          onFavorite: (value) => widget.onFavorite(routine, value),
                        ),
                      ),
                  if (_librarySection == 1 && widget.library.favoriteRoutines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('즐겨찾기한 루틴이 없습니다.'),
                    ),
                  if (_librarySection == 0) ...[
                  for (final group in groups)
                    _RoutineGroupCard(
                      group: group,
                      routines: widget.library.routinesForGroup(group),
                      isSelectionMode: _selectionMode != SelectionMode.none,
                      selectedIds: _selectedIds,
                      onToggleSelection: _toggleSelection,
                      onDeleteGroup: () async {
                        final shouldKeep = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('폴더 삭제'),
                            content: const Text('이 폴더를 삭제할까요? 내부 루틴 원본을 유지하시겠습니까?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('원본 유지'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('루틴도 삭제'),
                              ),
                            ],
                          ),
                        );
                        if (shouldKeep == null) return;
                        await widget.library.deleteGroup(group.id, keepRoutines: shouldKeep);
                      },
                      onPlayGroup: () {
                        final playlist = widget.library.routinesForGroup(group);
                        if (playlist.isEmpty) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PracticeModeScreen(
                              library: widget.library,
                              routine: playlist.first,
                              routines: playlist,
                              repeatPlaylist: true,
                            ),
                          ),
                        );
                      },
                      onOpenRoutine: widget.onStartRoutine,
                      onShareRoutine: widget.onShareRoutine,
                    ),
                  if (ungrouped.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '단독 루틴',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final routine in ungrouped)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RoutineCard(
                          routine: routine,
                          onStart: () => widget.onStartRoutine(routine),
                          onShare: () => widget.onShareRoutine(routine),
                          onFavorite: (value) => widget.onFavorite(routine, value),
                          isSelected: _selectedIds.contains(routine.id),
                          onTap: _selectionMode != SelectionMode.none
                              ? () => _toggleSelection(routine.id)
                              : null,
                        ),
                      ),
                  ],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoutineGroupCard extends StatefulWidget {
  const _RoutineGroupCard({
    required this.group,
    required this.routines,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
    required this.onDeleteGroup,
    required this.onPlayGroup,
    required this.onOpenRoutine,
    required this.onShareRoutine,
  });

  final RoutineGroup group;
  final List<SavedRoutine> routines;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onToggleSelection;
  final Future<void> Function() onDeleteGroup;
  final VoidCallback onPlayGroup;
  final ValueChanged<SavedRoutine> onOpenRoutine;
  final ValueChanged<SavedRoutine> onShareRoutine;

  @override
  State<_RoutineGroupCard> createState() => _RoutineGroupCardState();
}

class _RoutineGroupCardState extends State<_RoutineGroupCard> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: false,
          leading: Icon(Icons.folder_rounded, color: LoopiColors.purple),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.group.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: LoopiColors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.routines.length}개',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: widget.onPlayGroup,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: '폴더 전체 재생',
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    widget.onDeleteGroup();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'delete', child: Text('폴더 삭제')),
                ],
              ),
            ],
          ),
          children: [
            if (widget.routines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('폴더에 포함된 루틴이 없습니다.'),
              )
            else
              ...widget.routines.map(
                (routine) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _RoutineCard(
                      routine: routine,
                      onStart: () => widget.onOpenRoutine(routine),
                      onShare: () => widget.onShareRoutine(routine),
                      isSelected: widget.selectedIds.contains(routine.id),
                      onTap: widget.isSelectionMode ? () => widget.onToggleSelection(routine.id) : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CommunityFeedScreen extends StatelessWidget {
  const CommunityFeedScreen({super.key, required this.feed, required this.library, this.onPlay});

  final CommunityFeedStore feed;
  final RoutineLibrary library;
  final ValueChanged<SavedRoutine>? onPlay;

  void _play(BuildContext context, SavedRoutine routine) {
    if (onPlay != null) {
      onPlay!(routine);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticeModeScreen(routine: routine, library: library)));
  }

  void _openProfile(BuildContext context, CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileRoutinesScreen(
          authorId: post.authorId,
          authorName: post.authorName,
          feed: feed,
          library: library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: feed,
      builder: (context, _) {
        if (feed.posts.isEmpty) {
          return const Center(child: Text('아직 공유된 루틴이 없습니다.'));
        }
        return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              itemCount: feed.posts.length,
              itemBuilder: (_, index) {
                final post = feed.posts[index];
                final routine = library.byId(post.routine.id) ?? post.routine;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    onTap: () => _play(context, routine),
                    leading: IconButton(
                      onPressed: () => _play(context, routine),
                      tooltip: '재생',
                      icon: const Icon(Icons.play_circle_fill, size: 34),
                    ),
                    title: Text(routine.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          onPressed: () => _openProfile(context, post),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text('@${post.authorName}'),
                        ),
                        Text(post.description.isEmpty ? '설명 없음' : post.description),
                      ],
                    ),
                    trailing: FavoriteButton(
                      initialValue: routine.isFavorite,
                      onChanged: (value) => feed.toggleFavorite(routine, value, library, context),
                    ),
                  ),
                );
              },
        );
      },
    );
  }
}

class UserProfileRoutinesScreen extends StatelessWidget {
  const UserProfileRoutinesScreen({
    super.key,
    required this.authorId,
    required this.authorName,
    required this.feed,
    required this.library,
  });

  final String authorId;
  final String authorName;
  final CommunityFeedStore feed;
  final RoutineLibrary library;

  @override
  Widget build(BuildContext context) {
    final posts = feed.posts.where((post) => post.authorId == authorId).toList();
    return Scaffold(
      appBar: AppBar(title: Text('@$authorName')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final routine = library.byId(post.routine.id) ?? post.routine;
          return ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(routine.name),
            subtitle: Text(post.description),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PracticeModeScreen(routine: routine, library: library)),
            ),
          );
        },
      ),
    );
  }
}

