import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';
import '../widgets/app_logo.dart';
import '../widgets/favorite_icon_button.dart';

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({
    super.key,
    required this.routine,
    this.library,
    this.routines,
    this.repeatPlaylist = true,
  });

  final SavedRoutine routine;
  final RoutineLibrary? library;
  final List<SavedRoutine>? routines;
  final bool repeatPlaylist;

  List<SavedRoutine> get playlist =>
      (routines == null || routines!.isEmpty) ? [routine] : List.unmodifiable(routines!);

  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  late final YoutubePlayerController _youtubePlayer;
  bool _youtubeInitialized = false;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
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
  String? _mediaObjectUrl;

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  List<SavedRoutine> get _playlist => widget.playlist;
  SavedRoutine get _currentRoutine => _playlist[_playlistIndex];
  RoutineSegment get _segment => _currentRoutine.segments[_segmentIndex];
  bool get _isGroupPlayback => _playlist.length > 1;
  SavedRoutine get _libraryRoutine => widget.library?.byId(_currentRoutine.id) ?? _currentRoutine;

  @override
  void initState() {
    super.initState();
    _playlistIndex = _playlist.indexWhere((routine) => routine.id == widget.routine.id);
    if (_playlistIndex < 0) _playlistIndex = 0;
    _playsRemaining = _currentRoutine.segments.first.loopCount;
    
    _initializePlayer();
    
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

  Future<void> _initializePlayer() async {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        if (_inWidgetTest) break;
        _youtubePlayer = YoutubePlayerController.fromVideoId(
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
        _youtubeInitialized = true;
        _stateSub = _youtubePlayer.videoStateStream.listen((state) {
          if (!_ready) return;
          _onTime(state.position.inMilliseconds / 1000.0);
        });
        break;
      case SourceType.localVideo:
        if (_currentRoutine.localFilePath != null && !kIsWeb) {
          _videoPlayer = VideoPlayerController.file(File(_currentRoutine.localFilePath!));
          await _videoPlayer!.initialize();
          _videoPlayer!.addListener(_onVideoPlayerUpdate);
        } else if (_currentRoutine.localDataBytes != null) {
          _mediaObjectUrl = createMediaBlobUrl(_currentRoutine.localDataBytes!, 'video/mp4');
          final uri = _mediaObjectUrl == null
              ? Uri.dataFromBytes(_currentRoutine.localDataBytes!, mimeType: 'video/mp4')
              : Uri.parse(_mediaObjectUrl!);
          _videoPlayer = VideoPlayerController.networkUrl(uri);
          await _videoPlayer!.initialize();
          _videoPlayer!.addListener(_onVideoPlayerUpdate);
        } else if (_currentRoutine.localFilePath != null) {
          _videoPlayer = VideoPlayerController.networkUrl(Uri.parse(_currentRoutine.localFilePath!));
          await _videoPlayer!.initialize();
          _videoPlayer!.addListener(_onVideoPlayerUpdate);
        }
        break;
      case SourceType.audio:
        if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
          _audioPlayer = AudioPlayer();
          if (_currentRoutine.localFilePath != null && !kIsWeb) {
            await _audioPlayer!.setSourceDeviceFile(_currentRoutine.localFilePath!);
          } else if (_currentRoutine.localDataBytes != null) {
            await _audioPlayer!.setSourceBytes(Uint8List.fromList(_currentRoutine.localDataBytes!));
          } else {
            await _audioPlayer!.setSourceUrl(_currentRoutine.localFilePath!);
          }
          _audioPlayer!.onPositionChanged.listen((position) {
            if (!_ready) return;
            _onTime(position.inMilliseconds / 1000.0);
          });
        }
        break;
    }
  }

  void _onVideoPlayerUpdate() {
    if (_videoPlayer == null || !_ready) return;
    final position = _videoPlayer!.value.position.inMilliseconds / 1000.0;
    _onTime(position);
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
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _youtubePlayer.loadVideoById(videoId: _currentRoutine.videoId);
          await _youtubePlayer.seekTo(seconds: _currentRoutine.segments.first.startSec, allowSeekAhead: true);
          if (immediate) {
            await _youtubePlayer.playVideo();
            _isPlaying = true;
          }
          break;
        case SourceType.localVideo:
          if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
            await _videoPlayer?.dispose();
            if (_currentRoutine.localFilePath != null && !kIsWeb) {
              _videoPlayer = VideoPlayerController.file(File(_currentRoutine.localFilePath!));
            } else if (_currentRoutine.localDataBytes != null) {
              _mediaObjectUrl = createMediaBlobUrl(_currentRoutine.localDataBytes!, 'video/mp4');
              _videoPlayer = VideoPlayerController.networkUrl(
                _mediaObjectUrl == null
                    ? Uri.dataFromBytes(_currentRoutine.localDataBytes!, mimeType: 'video/mp4')
                    : Uri.parse(_mediaObjectUrl!),
              );
            } else {
              _videoPlayer = VideoPlayerController.networkUrl(Uri.parse(_currentRoutine.localFilePath!));
            }
            await _videoPlayer!.initialize();
            await _videoPlayer!.seekTo(Duration(milliseconds: (_currentRoutine.segments.first.startSec * 1000).toInt()));
            if (immediate) {
              await _videoPlayer!.play();
              _isPlaying = true;
            }
            _videoPlayer!.addListener(_onVideoPlayerUpdate);
          }
          break;
        case SourceType.audio:
          if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
            await _audioPlayer?.dispose();
            _audioPlayer = AudioPlayer();
            if (_currentRoutine.localFilePath != null && !kIsWeb) {
              await _audioPlayer!.setSourceDeviceFile(_currentRoutine.localFilePath!);
            } else if (_currentRoutine.localDataBytes != null) {
              await _audioPlayer!.setSourceBytes(Uint8List.fromList(_currentRoutine.localDataBytes!));
            } else {
              await _audioPlayer!.setSourceUrl(_currentRoutine.localFilePath!);
            }
            await _audioPlayer!.seek(Duration(milliseconds: (_currentRoutine.segments.first.startSec * 1000).toInt()));
            if (immediate) {
              await _audioPlayer!.resume();
              _isPlaying = true;
            }
          }
          break;
      }
    } catch (_) {}
    
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready) return;
      try {
        final time = await _getCurrentTime();
        _onTime(time);
      } catch (_) {}
    });
  }

  Future<double> _getCurrentTime() async {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        return await _youtubePlayer.currentTime;
      case SourceType.localVideo:
        final position = _videoPlayer?.value.position.inMilliseconds;
        return position != null ? position / 1000.0 : 0;
      case SourceType.audio:
        final position = await _audioPlayer?.getCurrentPosition();
        final positionMs = position?.inMilliseconds;
        return positionMs != null ? positionMs / 1000.0 : 0;
    }
  }

  Future<void> _startSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    _segmentIndex = index;
    _playsRemaining = _currentRoutine.segments[index].loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 400));
    setState(() {});
    if (_inWidgetTest) return;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _youtubePlayer.setPlaybackRate(_currentRoutine.segments[index].speed);
          await _youtubePlayer.seekTo(seconds: _currentRoutine.segments[index].startSec, allowSeekAhead: true);
          await _youtubePlayer.playVideo();
          _isPlaying = true;
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(_currentRoutine.segments[index].speed);
          await _videoPlayer?.seekTo(Duration(milliseconds: (_currentRoutine.segments[index].startSec * 1000).toInt()));
          await _videoPlayer?.play();
          _isPlaying = true;
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(_currentRoutine.segments[index].speed);
          await _audioPlayer?.seek(Duration(milliseconds: (_currentRoutine.segments[index].startSec * 1000).toInt()));
          await _audioPlayer?.resume();
          _isPlaying = true;
          break;
      }
    } catch (_) {}
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready) return;
      try {
        final time = await _getCurrentTime();
        _onTime(time);
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
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            await _youtubePlayer.pauseVideo();
            break;
          case SourceType.localVideo:
            await _videoPlayer?.pause();
            break;
          case SourceType.audio:
            await _audioPlayer?.pause();
            break;
        }
        _isPlaying = false;
      } else {
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            await _youtubePlayer.playVideo();
            break;
          case SourceType.localVideo:
            await _videoPlayer?.play();
            break;
          case SourceType.audio:
            await _audioPlayer?.resume();
            break;
        }
        _isPlaying = true;
      }
      setState(() {});
    } catch (_) {}
  }

  Future<void> _seekRelative(double seconds) async {
    if (_inWidgetTest) return;
    try {
      final currentTime = await _getCurrentTime();
      final newTime = currentTime + seconds;
      final clampedTime = newTime.clamp(_segment.startSec, _segment.endSec);
      
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _youtubePlayer.seekTo(seconds: clampedTime, allowSeekAhead: true);
          break;
        case SourceType.localVideo:
          await _videoPlayer?.seekTo(Duration(milliseconds: (clampedTime * 1000).toInt()));
          break;
        case SourceType.audio:
          await _audioPlayer?.seek(Duration(milliseconds: (clampedTime * 1000).toInt()));
          break;
      }
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
      try {
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            _youtubePlayer.pauseVideo();
            break;
          case SourceType.localVideo:
            _videoPlayer?.pause();
            break;
          case SourceType.audio:
            _audioPlayer?.pause();
            break;
        }
      } catch (_) {}
    }
  }

  void _replayCurrent() {
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 280));
    if (_inWidgetTest) return;
    
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        _youtubePlayer.seekTo(seconds: _segment.startSec, allowSeekAhead: true);
        _youtubePlayer.playVideo();
        break;
      case SourceType.localVideo:
        _videoPlayer?.seekTo(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
        _videoPlayer?.play();
        break;
      case SourceType.audio:
        _audioPlayer?.seek(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
        _audioPlayer?.resume();
        break;
    }
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
      try {
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            await _youtubePlayer.pauseVideo();
            break;
          case SourceType.localVideo:
            await _videoPlayer?.pause();
            break;
          case SourceType.audio:
            await _audioPlayer?.pause();
            break;
        }
      } catch (_) {}
    }
  }

  Future<void> _waitDelay(int delaySec) async {
    if (delaySec <= 0 || _inWidgetTest) return;
    _delayPending = true;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          _youtubePlayer.pauseVideo();
          break;
        case SourceType.localVideo:
          _videoPlayer?.pause();
          break;
        case SourceType.audio:
          _audioPlayer?.pause();
          break;
      }
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
    if (_youtubeInitialized) _youtubePlayer.close();
    _videoPlayer?.dispose();
    _audioPlayer?.dispose();
    revokeMediaBlobUrl(_mediaObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        return _buildYouTubeScaffold();
      case SourceType.localVideo:
        return _buildVideoScaffold();
      case SourceType.audio:
        return _buildAudioScaffold();
    }
  }

  Widget _buildYouTubeScaffold() {
    if (!_youtubeInitialized) {
      return _buildMainScaffold(mediaWidget: const ColoredBox(color: Colors.black));
    }
    return YoutubePlayerScaffold(
      controller: _youtubePlayer,
      builder: (context, player) {
        return _buildMainScaffold(
          mediaWidget: _inWidgetTest
              ? const ColoredBox(color: Colors.black)
              : player,
        );
      },
    );
  }

  Widget _buildVideoScaffold() {
    return _buildMainScaffold(
      mediaWidget: _videoPlayer != null && _videoPlayer!.value.isInitialized
          ? VideoPlayer(_videoPlayer!)
          : const ColoredBox(color: Colors.black),
    );
  }

  Widget _buildAudioScaffold() {
    return _buildMainScaffold(
      mediaWidget: _buildAudioPlayerWidget(),
    );
  }

  Widget _buildAudioPlayerWidget() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq_rounded, color: LoopiColors.purple, size: 80),
          const SizedBox(height: 16),
          Text(
            'studio.audio_mode'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 8),
          if (_currentRoutine.fileName != null)
            Text(
              _currentRoutine.fileName!,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildMainScaffold({required Widget mediaWidget}) {
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
          actions: [
              if (widget.library != null)
                FavoriteButton(
                  initialValue: _libraryRoutine.isFavorite,
                  onChanged: (value) async {
                    await widget.library!.setFavorite(_currentRoutine.id, value);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(value ? '즐겨찾기에 추가했습니다.' : '즐겨찾기에서 삭제했습니다.')),
                    );
                  },
                ),
          ],
        ),
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  mediaWidget,
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
  }
}
