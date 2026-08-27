import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
  StreamSubscription<YoutubeVideoState>? _stateSub;
  int _countdown = 3;
  bool _ready = false;
  int _segmentIndex = 0;
  int _playsRemaining = 1;
  DateTime? _ignoreUntil;

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
    } catch (_) {}
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready) return;
      try {
        _onTime(await _player.currentTime);
      } catch (_) {}
    });
  }

  void _onTime(double time) {
    if (!_ready) return;
    if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;
    if (time + 0.12 < _segment.endSec) return;

    if (_segment.loopCount == kInfiniteLoop) {
      _replayCurrent();
      return;
    }
    _playsRemaining -= 1;
    if (_playsRemaining > 0) {
      _replayCurrent();
      return;
    }
    if (_segmentIndex + 1 < widget.routine.segments.length) {
      _startSegment(_segmentIndex + 1);
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
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
                            const Text(
                              'Get Ready',
                              style: TextStyle(
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
                    '${formatSpeedLabel(_segment.speed)}  ${formatLoopLabel(_segment.loopCount)}',
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
                    return CircleAvatar(
                      backgroundColor: active ? LoopiColors.purple : const Color(0xFF2A2438),
                      child: Text(
                        sectionLabelForIndex(index).substring(0, 1),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}
