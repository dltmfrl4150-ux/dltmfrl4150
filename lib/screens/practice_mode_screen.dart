import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/routine_models.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../widgets/app_logo.dart';

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({super.key, required this.routine});

  final SavedRoutine routine;

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
  DateTime? _ignoreUntil;
  bool _delayPending = false;
  Completer<void>? _delayCompleter;
  bool _isPlaying = false;

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  RoutineSegment get _segment => widget.routine.segments[_segmentIndex];

  @override
  void initState() {
    super.initState();
    _playsRemaining = widget.routine.segments.first.loopCount;
    _player = YoutubePlayerController.fromVideoId(
      videoId: widget.routine.videoId,
      autoPlay: false,
      startSeconds: widget.routine.segments.first.startSec,
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

  Future<void> _startSegment(int index) async {
    _segmentIndex = index;
    _playsRemaining = widget.routine.segments[index].loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 400));
    setState(() {});
    if (_inWidgetTest) return;
    try {
      await _player.setPlaybackRate(widget.routine.segments[index].speed);
      await _player.seekTo(seconds: widget.routine.segments[index].startSec, allowSeekAhead: true);
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
    if (index < 0 || index >= widget.routine.segments.length) return;
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
    final nextIndex = _segmentIndex + 1 < widget.routine.segments.length ? _segmentIndex + 1 : 0;
    await _jumpToSegment(nextIndex);
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
    if (_segmentIndex + 1 < widget.routine.segments.length) {
      _startSegmentWithDelay(_segmentIndex + 1, delaySec);
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: _skipToPreviousSegment,
            icon: const Icon(Icons.skip_previous),
            tooltip: 'player.previous_segment'.tr(),
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
            icon: const Icon(Icons.skip_next),
            tooltip: 'player.next_segment'.tr(),
            color: Colors.white,
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
                    widget.routine.name,
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
                  itemCount: widget.routine.segments.length,
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
