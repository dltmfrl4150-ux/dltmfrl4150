import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/routine_models.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../widgets/app_logo.dart';

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({
    super.key,
    required this.routine,
    this.routines,
    this.repeatPlaylist = true,
  });

  final SavedRoutine routine;
  final List<SavedRoutine>? routines;
  final bool repeatPlaylist;

  List<SavedRoutine> get playlist =>
      (routines == null || routines!.isEmpty) ? [routine] : List.unmodifiable(routines!);

  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  late final YoutubePlayerController _player;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  Timer? _delayTimer;
  StreamSubscription<YoutubeVideoState>? _stateSub;
  int _countdown = 3;
  bool _ready = false;
  int _segmentIndex = 0;
  int _playsRemaining = 1;
  int _playlistIndex = 0;
  DateTime? _ignoreUntil;
  bool _delayPending = false;
  Completer<void>? _delayCompleter;
  bool _isPlaying = false;

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  List<SavedRoutine> get _playlist => widget.playlist;
  SavedRoutine get _currentRoutine => _playlist[_playlistIndex];
  RoutineSegment get _segment => _currentRoutine.segments[_segmentIndex];
  bool get _isGroupPlayback => _playlist.length > 1;

  @override
  void initState() {
    super.initState();
    _playlistIndex = _playlist.indexWhere((routine) => routine.id == widget.routine.id);
    if (_playlistIndex < 0) _playlistIndex = 0;
    _playsRemaining = _currentRoutine.segments.first.loopCount;
    _player = YoutubePlayerController.fromVideoId(
      videoId: _currentRoutine.videoId,
      autoPlay: false,
      startSeconds: _currentRoutine.segments.first.startSec,
      params: const YoutubePlayerParams(
        mute: false,
        showFullscreenButton: true,
        showControls: true,
        loop: false,
      ),
    );
    _stateSub = _player.videoStateStream.listen((state) {
      if (!_ready) return;
      _onTime(state.position.inMilliseconds / 1000.0);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() {
          _countdown = 0;
          _ready = true;
        });
        _startSegment(0);
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  Future<void> _startRoutine(int index, {bool immediate = true}) async {
    if (index < 0 || index >= _playlist.length) return;
    _playlistIndex = index;
    _segmentIndex = 0;
    _playsRemaining = _currentRoutine.segments.first.loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 400));
    setState(() {});
    if (_inWidgetTest) return;
    try {
      await _player.loadVideoById(videoId: _currentRoutine.videoId);
      await _player.seekTo(seconds: _currentRoutine.segments.first.startSec, allowSeekAhead: true);
      if (immediate) {
        await _player.playVideo();
        _isPlaying = true;
      }
    } catch (_) {}
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready) return;
      try {
        _onTime(await _player.currentTime);
      } catch (_) {}
    });
  }

  Future<void> _startSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    _segmentIndex = index;
    _playsRemaining = _currentRoutine.segments[index].loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 400));
    setState(() {});
    if (_inWidgetTest) return;
    try {
      await _player.setPlaybackRate(_currentRoutine.segments[index].speed);
      await _player.seekTo(seconds: _currentRoutine.segments[index].startSec, allowSeekAhead: true);
      await _player.playVideo();
      _isPlaying = true;
    } catch (_) {}
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready) return;
      try {
        _onTime(await _player.currentTime);
      } catch (_) {}
    });
  }

  Future<void> _jumpToSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    await _startSegment(index);
  }

  Future<void> _togglePlayPause() async {
    if (_inWidgetTest) return;
    try {
      if (_isPlaying) {
        await _player.pauseVideo();
        _isPlaying = false;
      } else {
        await _player.playVideo();
        _isPlaying = true;
      }
      setState(() {});
    } catch (_) {}
  }

  Future<void> _seekRelative(double seconds) async {
    if (_inWidgetTest) return;
    try {
      final currentTime = await _player.currentTime;
      final newTime = currentTime + seconds;
      final clampedTime = newTime.clamp(_segment.startSec, _segment.endSec);
      await _player.seekTo(seconds: clampedTime, allowSeekAhead: true);
    } catch (_) {}
  }

  Future<void> _skipToPreviousSegment() async {
    final prevIndex = _segmentIndex > 0 ? _segmentIndex - 1 : 0;
    await _jumpToSegment(prevIndex);
  }

  Future<void> _skipToNextSegment() async {
    final nextIndex = _segmentIndex + 1 < _currentRoutine.segments.length ? _segmentIndex + 1 : 0;
    await _jumpToSegment(nextIndex);
  }

  Future<void> _previousRoutine() async {
    final prev = _playlistIndex - 1;
    if (prev < 0) {
      if (_isGroupPlayback && widget.repeatPlaylist) {
        await _startRoutine(_playlist.length - 1, immediate: true);
      }
      return;
    }
    await _startRoutine(prev, immediate: true);
  }

  Future<void> _nextRoutine() async {
    final next = _playlistIndex + 1;
    if (next >= _playlist.length) {
      if (_isGroupPlayback && widget.repeatPlaylist) {
        await _startRoutine(0, immediate: true);
      }
      return;
    }
    await _startRoutine(next, immediate: true);
  }

  void _onTime(double time) {
    if (!_ready || _delayPending) return;
    if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;
    if (time + 0.12 < _segment.endSec) return;

    _ignoreUntil = DateTime.now().add(const Duration(days: 1));
    final delaySec = _segment.delaySec;

    if (_segment.loopCount == kInfiniteLoop) {
      _replayWithDelay(delaySec);
      return;
    }
    _playsRemaining -= 1;
    if (_playsRemaining > 0) {
      _replayWithDelay(delaySec);
      return;
    }
    if (_segmentIndex + 1 < _currentRoutine.segments.length) {
      _startSegmentWithDelay(_segmentIndex + 1, delaySec);
      return;
    }
    if (_isGroupPlayback) {
      _advanceToNextRoutine(delaySec);
      return;
    }
    _pollTimer?.cancel();
    if (!_inWidgetTest) {
      _player.pauseVideo();
    }
  }

  void _replayCurrent() {
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 280));
    if (_inWidgetTest) return;
    _player.seekTo(seconds: _segment.startSec, allowSeekAhead: true);
    _player.playVideo();
  }

  Future<void> _replayWithDelay(int delaySec) async {
    await _waitDelay(delaySec);
    if (!_ready) return;
    _replayCurrent();
  }

  Future<void> _startSegmentWithDelay(int index, int delaySec) async {
    await _waitDelay(delaySec);
    if (!_ready) return;
    _startSegment(index);
  }

  Future<void> _advanceToNextRoutine(int delaySec) async {
    if (!_ready) return;
    await _waitDelay(delaySec);
    if (!_ready || !mounted) return;

    if (_playlistIndex + 1 < _playlist.length) {
      await _startRoutine(_playlistIndex + 1, immediate: true);
      return;
    }

    if (widget.repeatPlaylist) {
      await _startRoutine(0, immediate: true);
      return;
    }

    _pollTimer?.cancel();
    if (!_inWidgetTest) {
      await _player.pauseVideo();
    }
  }

  Future<void> _waitDelay(int delaySec) async {
    if (delaySec <= 0 || _inWidgetTest) return;
    _delayPending = true;
    try {
      await _player.pauseVideo();
    } catch (_) {}
    _delayCompleter = Completer<void>();
    _delayTimer?.cancel();
    _delayTimer = Timer(Duration(seconds: delaySec), () {
      final pending = _delayCompleter;
      if (pending != null && !pending.isCompleted) pending.complete();
    });
    await _delayCompleter!.future;
    _delayPending = false;
    _delayCompleter = null;
  }

  Widget _playerControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_isGroupPlayback)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_playlistIndex + 1} / ${_playlist.length}  •  ${_currentRoutine.name}',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_isGroupPlayback)
                IconButton(
                  onPressed: _previousRoutine,
                  icon: const Icon(Icons.skip_previous_rounded),
                  tooltip: '이전 루틴',
                  color: Colors.white,
                ),
              IconButton(
                onPressed: _skipToPreviousSegment,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                tooltip: '이전 구간',
                color: Colors.white,
              ),
              IconButton(
                onPressed: () => _seekRelative(-5),
                icon: const Icon(Icons.replay_5),
                tooltip: 'player.rewind_5s'.tr(),
                color: Colors.white,
              ),
              Container(
                decoration: BoxDecoration(
                  color: LoopiColors.purple,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  tooltip: _isPlaying ? 'player.pause'.tr() : 'player.play'.tr(),
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => _seekRelative(5),
                icon: const Icon(Icons.forward_5),
                tooltip: 'player.forward_5s'.tr(),
                color: Colors.white,
              ),
              IconButton(
                onPressed: _skipToNextSegment,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                tooltip: '다음 구간',
                color: Colors.white,
              ),
              if (_isGroupPlayback)
                IconButton(
                  onPressed: _nextRoutine,
                  icon: const Icon(Icons.skip_next_rounded),
                  tooltip: '다음 루틴',
                  color: Colors.white,
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _delayTimer?.cancel();
    _stateSub?.cancel();
    _player.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _player,
      builder: (context, player) {
        return Theme(
          data: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: LoopiColors.purple,
              brightness: Brightness.dark,
            ),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFF120F1C),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              title: Row(
                children: [
                  const AppLogo(height: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentRoutine.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_inWidgetTest)
                        const ColoredBox(color: Colors.black)
                      else
                        player,
                      if (!_ready)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'player.get_ready'.tr(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              CircleAvatar(
                                radius: 42,
                                backgroundColor: LoopiColors.purple,
                                child: Text(
                                  '$_countdown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${sectionLabelForIndex(_segmentIndex)}  '
                      '${formatMmSs(_segment.startSec)} – ${formatMmSs(_segment.endSec)}  '
                      '${formatSpeedLabel(_segment.speed)}  ${formatLoopLabel(_segment.loopCount)}  '
                      '${formatDelayLabel(_segment.delaySec)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: _currentRoutine.segments.length,
                    itemBuilder: (context, index) {
                      final active = index == _segmentIndex;
                      return InkWell(
                        onTap: () => _jumpToSegment(index),
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          backgroundColor: active ? LoopiColors.purple : const Color(0xFF2A2438),
                          child: Text(
                            sectionLabelForIndex(index).substring(0, 1),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _playerControls(),
              ],
            ),
          ),
        );
      },
    );
  }
}
																																																																																						 

