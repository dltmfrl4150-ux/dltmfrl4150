import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key, required this.library, this.selectedRoutine, this.selectedView});

  final RoutineLibrary library;
  final SavedRoutine? selectedRoutine;
  final Widget? selectedView;

  void _open(BuildContext context, SavedRoutine routine) {
    final Widget screen;
    switch (routine.sourceType) {
      case SourceType.localVideo:
        screen = VideoPracticeScreen(routine: routine, library: library);
        break;
      case SourceType.audio:
        screen = AudioPracticeScreen(routine: routine);
        break;
      case SourceType.youtube:
        screen = VideoPracticeScreen(routine: routine, library: library);
        break;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    if (selectedView != null) {
      return selectedView!;
    }
    if (selectedRoutine != null) {
      return selectedRoutine!.sourceType == SourceType.audio
          ? AudioPracticeScreen(routine: selectedRoutine!)
          : VideoPracticeScreen(routine: selectedRoutine!, library: library);
    }
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final routines = library.routines;
        if (routines.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('저장한 루틴을 선택해 연습을 시작하세요.'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('연습 모드', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('연습할 저장 루틴을 선택하세요.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            for (final routine in routines)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(_iconFor(routine.sourceType), color: LoopiColors.purple),
                  title: Text(routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${routine.segments.length}개 구간 · ${_typeLabel(routine.sourceType)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, routine),
                ),
              ),
          ],
        );
      },
    );
  }

  static IconData _iconFor(SourceType type) {
    switch (type) {
      case SourceType.youtube:
        return Icons.play_circle_outline;
      case SourceType.localVideo:
        return Icons.videocam_outlined;
      case SourceType.audio:
        return Icons.graphic_eq;
    }
  }

  static String _typeLabel(SourceType type) {
    switch (type) {
      case SourceType.youtube:
        return 'YouTube';
      case SourceType.localVideo:
        return '비디오';
      case SourceType.audio:
        return '오디오';
    }
  }
}

class VideoPracticeScreen extends StatefulWidget {
  const VideoPracticeScreen({super.key, required this.routine, required this.library});

  final SavedRoutine routine;
  final RoutineLibrary library;

  @override
  State<VideoPracticeScreen> createState() => _VideoPracticeScreenState();
}

class _VideoPracticeScreenState extends State<VideoPracticeScreen> {
  CameraController? _camera;
  VideoPlayerController? _original;
  YoutubePlayerController? _youtubeOriginal;
  VideoPlayerController? _recorded;
  bool _recording = false;
  bool _comparing = false;
  bool _loading = true;
  String? _error;
  String? _cameraError;
  String? _originalError;
  Timer? _syncTimer;
  String? _originalObjectUrl;
  double _previewAspectRatio = 9 / 16;
  bool _virtualRecording = false;
  int _virtualSeconds = 0;
  Timer? _virtualTimer;
  Timer? _recordingTimer;
  final AudioRecorder _recorder = AudioRecorder();

  static const _aspectRatios = <String, double>{
    '9:16 Shorts / Reels': 9 / 16,
    '16:9 YouTube': 16 / 9,
    '1:1 정사각형': 1,
    '4:3 표준': 4 / 3,
  };

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('카메라가 감지되지 않았습니다.');
      _camera = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: true);
      await _camera!.initialize();
    } catch (error) {
      _cameraError = error.toString();
    }

    try {
      if (widget.routine.sourceType == SourceType.youtube) {
        _youtubeOriginal = YoutubePlayerController.fromVideoId(
          videoId: widget.routine.videoId,
          autoPlay: false,
          params: const YoutubePlayerParams(showControls: true),
        );
      }
      final path = widget.routine.localFilePath;
      if (path != null && !kIsWeb && widget.routine.sourceType == SourceType.localVideo) {
        _original = VideoPlayerController.file(File(path));
        await _original!.initialize();
      } else if (widget.routine.localDataBytes != null && widget.routine.sourceType == SourceType.localVideo) {
        _originalObjectUrl = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
        final uri = _originalObjectUrl == null
            ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(_originalObjectUrl!);
        _original = VideoPlayerController.networkUrl(uri);
        await _original!.initialize();
      } else if (path != null && widget.routine.sourceType == SourceType.localVideo) {
        _original = VideoPlayerController.networkUrl(Uri.parse(path));
        await _original!.initialize();
      }
    } catch (error) {
      _originalError = '원본 영상을 준비하지 못했습니다: $error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleRecording() async {
    final camera = _camera;
    final cameraAvailable = camera?.value.isInitialized == true;
    final microphoneAvailable = await _recorder.hasPermission();
    if (!cameraAvailable || !microphoneAvailable) {
      final missing = !cameraAvailable && !microphoneAvailable
          ? '카메라, 마이크가 감지되지 않습니다'
          : !cameraAvailable
              ? '카메라가 감지되지 않습니다'
              : '마이크가 감지되지 않습니다';
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(missing),
          content: const Text('계속 진행하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('아니오')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('네')),
          ],
        ),
      );
      if (proceed == true) _startVirtualRecording();
      return;
    }
    try {
      if (_recording) {
        final file = await camera!.stopVideoRecording();
        _recorded = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(file.path))
            : VideoPlayerController.file(File(file.path));
        await _recorded!.initialize();
        _recording = false;
        await _finishRecording(file.path);
      } else {
        final original = _original;
        if (original != null) {
          await original.seekTo(Duration(milliseconds: (widget.routine.segments.first.startSec * 1000).round()));
          await original.play();
        }
        if (_youtubeOriginal != null) {
          await _youtubeOriginal!.seekTo(seconds: widget.routine.segments.first.startSec);
          await _youtubeOriginal!.playVideo();
        }
        await camera!.startVideoRecording();
        _recording = true;
        _recordingTimer?.cancel();
        _recordingTimer = Timer(_routineDuration, () {
          if (_recording) _toggleRecording();
        });
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '녹화에 실패했습니다: $error');
    }
  }

  void _startVirtualRecording() {
    final original = _original;
    if (original != null) {
      original.seekTo(Duration(milliseconds: (widget.routine.segments.first.startSec * 1000).round()));
      original.play();
    }
    if (_youtubeOriginal != null) {
      _youtubeOriginal!.seekTo(seconds: widget.routine.segments.first.startSec);
      _youtubeOriginal!.playVideo();
    }
    _virtualTimer?.cancel();
    setState(() {
      _virtualRecording = true;
      _virtualSeconds = 0;
    });
    _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final duration = widget.routine.segments.fold<double>(0, (sum, segment) => sum + segment.endSec - segment.startSec);
      if (_virtualSeconds >= duration.ceil()) {
        _stopVirtualRecording();
      } else if (mounted) {
        setState(() {
          _virtualSeconds += 1;
        });
      }
    });
  }

  void _stopVirtualRecording() {
    _virtualTimer?.cancel();
    _original?.pause();
    _youtubeOriginal?.pauseVideo();
    if (mounted) {
      setState(() {
        _virtualRecording = false;
        _comparing = true;
      });
      _showSaveDialog();
    }
  }

  Duration get _routineDuration {
    final seconds = widget.routine.segments.fold<double>(0, (sum, segment) => sum + segment.endSec - segment.startSec);
    return Duration(milliseconds: (seconds * 1000).round().clamp(1000, 86400000));
  }

  Future<void> _finishRecording(String path) async {
    _recordingTimer?.cancel();
    _recording = false;
    if (mounted) setState(() {});
    await _showSaveDialog(recordedPath: path);
  }

  Future<void> _showSaveDialog({String? recordedPath}) async {
    final controller = TextEditingController(text: '${_dateLabel()} ${widget.routine.name} 연습 1');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('연습 영상 저장'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '파일 이름')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('저장하기')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await widget.library.savePracticeResult(PracticeResult(
      id: 'practice_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      routineId: widget.routine.id,
      createdAt: DateTime.now(),
      recordedPath: recordedPath,
    ));
    if (mounted) setState(() => _comparing = true);
  }

  String _dateLabel() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playComparison() async {
    final recorded = _recorded;
    if (recorded == null) return;
    final start = Duration(milliseconds: (widget.routine.segments.first.startSec * 1000).round());
    final original = _original;
    if (original != null) {
      await Future.wait([original.seekTo(start), recorded.seekTo(Duration.zero)]);
      await Future.wait([original.play(), recorded.play()]);
    } else if (_youtubeOriginal != null) {
      await _youtubeOriginal!.seekTo(seconds: widget.routine.segments.first.startSec);
      await recorded.seekTo(Duration.zero);
      await Future.wait([_youtubeOriginal!.playVideo(), recorded.play()]);
    } else {
      return;
    }
    _syncTimer?.cancel();
    _recordingTimer?.cancel();
    _virtualTimer?.cancel();
    _recorder.dispose();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || original == null || !original.value.isInitialized || !recorded.value.isInitialized) return;
      recorded.seekTo(original.value.position);
    });
    setState(() => _comparing = true);
  }

  @override
  void dispose() {
    _camera?.dispose();
    _original?.dispose();
    _recorded?.dispose();
    _syncTimer?.cancel();
    _youtubeOriginal?.close();
    revokeMediaBlobUrl(_originalObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.name)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: !_loading && _error == null
          ? FloatingActionButton(
            onPressed: _virtualRecording
              ? _stopVirtualRecording
              : _recorded == null
                ? _toggleRecording
                : _playComparison,
            backgroundColor: _recorded == null ? Colors.redAccent : LoopiColors.purple,
            tooltip: _virtualRecording || _recording ? '녹화 중지 및 저장' : '녹화 시작',
            child: Icon(_virtualRecording || _recording ? Icons.stop : Icons.fiber_manual_record),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final landscape = constraints.maxWidth > constraints.maxHeight;
                    final original = _comparing
                        ? MotionComparisonViewer(
                            original: _original,
                            recorded: _recorded,
                            originalYoutube: _youtubeOriginal,
                            segments: widget.routine.segments,
                            originalWidget: _youtubeOriginal == null
                                ? null
                                : YoutubePlayer(controller: _youtubeOriginal!),
                          )
                        : _originalPane();
                    final camera = _comparing ? const SizedBox.shrink() : _cameraPane();
                    final content = landscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _fitPane(original)),
                              const SizedBox(width: 12),
                              Expanded(child: _fitPane(camera)),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: _fitPane(original)),
                              const SizedBox(height: 12),
                              Expanded(child: _fitPane(camera)),
                            ],
                          );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      child: content,
                    );
                  },
                ),
    );
  }

  Widget _fitPane(Widget child) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
          child: child,
        ),
      ),
    );
  }

  Widget _originalPane() {
    if (_originalError != null && _youtubeOriginal == null && _original == null) {
      return Container(
        height: 220,
        color: Colors.black87,
        alignment: Alignment.center,
        child: Text(_originalError!, style: const TextStyle(color: Colors.white70)),
      );
    }
    if (_youtubeOriginal != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('원본 영상', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 16 / 9, child: YoutubePlayer(controller: _youtubeOriginal!)),
      ]);
    }
    return _mediaPane('원본 영상', _original);
  }

  Widget _cameraPane() {
    final camera = _camera;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          const Text('카메라 프리뷰', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          DropdownButton<double>(
            value: _previewAspectRatio,
            isDense: true,
            items: [
              for (final entry in _aspectRatios.entries)
                DropdownMenuItem(value: entry.value, child: Text(entry.key)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _previewAspectRatio = value);
            },
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (_cameraError != null)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('카메라가 감지되지 않았습니다 (가상 녹화 모드).'),
        ),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AspectRatio(
            aspectRatio: _previewAspectRatio,
            child: ColoredBox(
              color: Colors.black87,
              child: camera == null || !camera.value.isInitialized
                  ? const Center(
                      child: Text(
                        '카메라가 감지되지 않았습니다\n(가상 녹화 모드)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: camera.value.previewSize?.height ?? 320,
                            height: camera.value.previewSize?.width ?? 480,
                            child: CameraPreview(camera),
                          ),
                        ),
                        if (_virtualRecording)
                          DecoratedBox(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                '$_virtualSeconds초',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _mediaPane(String label, VideoPlayerController? player) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: player?.value.isInitialized == true ? player!.value.aspectRatio : 16 / 9,
        child: player?.value.isInitialized == true ? VideoPlayer(player!) : const ColoredBox(color: Colors.black),
      ),
    ]);
  }
}

class MotionComparisonViewer extends StatefulWidget {
  const MotionComparisonViewer({
    super.key,
    required this.original,
    required this.recorded,
    this.segments = const [],
    this.originalYoutube,
    this.originalWidget,
  });

  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final List<RoutineSegment> segments;
  final YoutubePlayerController? originalYoutube;
  final Widget? originalWidget;

  @override
  State<MotionComparisonViewer> createState() => _MotionComparisonViewerState();
}

class _MotionComparisonViewerState extends State<MotionComparisonViewer> {
  double _position = 0;
  bool _playing = false;
  int _segmentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.original?.addListener(_onVideoChanged);
    widget.recorded?.addListener(_onVideoChanged);
  }

  void _onVideoChanged() {
    final player = widget.original ?? widget.recorded;
    if (!mounted || player == null || !player.value.isInitialized) return;
    final position = player.value.position.inMilliseconds / 1000.0;
    setState(() {
      _position = position.clamp(0.0, _maxPosition);
      _playing = player.value.isPlaying;
    });
  }

  double get _maxPosition {
    final original = widget.original;
    if (original?.value.isInitialized == true) {
      return original!.value.duration.inMilliseconds / 1000.0;
    }
    final recorded = widget.recorded;
    if (recorded?.value.isInitialized == true) {
      return recorded!.value.duration.inMilliseconds / 1000.0;
    }
    return 1;
  }

  Future<void> _seekBoth(double seconds) async {
    final clamped = seconds.clamp(0.0, _maxPosition).toDouble();
    setState(() => _position = clamped);
    await widget.original?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
    await widget.recorded?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
    if (widget.originalYoutube != null) {
      await widget.originalYoutube!.seekTo(seconds: clamped);
    }
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await widget.original?.pause();
      await widget.recorded?.pause();
      await widget.originalYoutube?.pauseVideo();
    } else {
      await widget.original?.play();
      await widget.recorded?.play();
      await widget.originalYoutube?.playVideo();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  Future<void> _moveSegment(int delta) async {
    if (widget.segments.isEmpty) return;
    final next = (_segmentIndex + delta).clamp(0, widget.segments.length - 1);
    _segmentIndex = next;
    await _seekBoth(widget.segments[next].startSec);
  }

  @override
  void dispose() {
    widget.original?.removeListener(_onVideoChanged);
    widget.recorded?.removeListener(_onVideoChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('동작 비교', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (widget.originalWidget != null)
          AspectRatio(aspectRatio: 16 / 9, child: widget.originalWidget!)
        else
          _videoPane('원본 영상', widget.original),
        const SizedBox(height: 12),
        _videoPane('내 동작', widget.recorded),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(onPressed: () => _moveSegment(-1), icon: const Icon(Icons.skip_previous), tooltip: '이전 구간'),
            IconButton(onPressed: () => _seekBoth(_position - 5), icon: const Icon(Icons.replay_5), tooltip: '5초 뒤로'),
            IconButton(
              onPressed: _togglePlayback,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              tooltip: _playing ? '일시정지' : '재생',
            ),
            IconButton(onPressed: () => _seekBoth(_position + 5), icon: const Icon(Icons.forward_5), tooltip: '5초 앞으로'),
            IconButton(onPressed: () => _moveSegment(1), icon: const Icon(Icons.skip_next), tooltip: '다음 구간'),
          ],
        ),
        Slider(
          value: _position.clamp(0.0, _maxPosition),
          min: 0,
          max: _maxPosition,
          onChanged: _seekBoth,
        ),
      ],
    );
  }

  Widget _videoPane(String label, VideoPlayerController? player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: player?.value.isInitialized == true ? player!.value.aspectRatio : 16 / 9,
          child: player?.value.isInitialized == true ? VideoPlayer(player!) : const ColoredBox(color: Colors.black),
        ),
      ],
    );
  }
}

class PracticeResultViewer extends StatefulWidget {
  const PracticeResultViewer({super.key, required this.routine, required this.result});

  final SavedRoutine routine;
  final PracticeResult result;

  @override
  State<PracticeResultViewer> createState() => _PracticeResultViewerState();
}

class _PracticeResultViewerState extends State<PracticeResultViewer> {
  VideoPlayerController? _original;
  VideoPlayerController? _recorded;
  YoutubePlayerController? _youtube;
  String? _recordedObjectUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.routine.sourceType == SourceType.youtube) {
        _youtube = YoutubePlayerController.fromVideoId(videoId: widget.routine.videoId, autoPlay: false);
      } else if (widget.routine.localDataBytes != null) {
        final url = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
        _original = VideoPlayerController.networkUrl(url == null
            ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(url));
        await _original!.initialize();
      } else if (widget.routine.localFilePath != null) {
        _original = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(widget.routine.localFilePath!))
            : VideoPlayerController.file(File(widget.routine.localFilePath!));
        await _original!.initialize();
      }
      final path = widget.result.recordedPath;
      if (path != null) {
        _recorded = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(path))
            : VideoPlayerController.file(File(path));
        await _recorded!.initialize();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _original?.dispose();
    _recorded?.dispose();
    _youtube?.close();
    revokeMediaBlobUrl(_recordedObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(widget.result.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: MotionComparisonViewer(
          original: _original,
          recorded: _recorded,
          segments: widget.routine.segments,
          originalYoutube: _youtube,
          originalWidget: _youtube == null ? null : YoutubePlayer(controller: _youtube!),
        ),
      ),
    );
  }
}

class AudioPracticeScreen extends StatefulWidget {
  const AudioPracticeScreen({super.key, required this.routine});

  final SavedRoutine routine;

  @override
  State<AudioPracticeScreen> createState() => _AudioPracticeScreenState();
}

class _AudioPracticeScreenState extends State<AudioPracticeScreen> {
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  int _segmentIndex = 0;
  String _step = '준비';
  bool _running = false;
  String? _error;

  Future<void> _showMicrophoneError() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('마이크를 사용할 수 없습니다'),
        content: const Text('마이크가 연결되어 있지 않거나 권한이 없습니다. 마이크 연결 및 권한을 확인해주세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _loadAudioSource() async {
    final path = widget.routine.localFilePath;
    if (path != null && !kIsWeb) {
      await _player.setSourceDeviceFile(path);
    } else if (widget.routine.localDataBytes != null) {
      await _player.setSourceBytes(Uint8List.fromList(widget.routine.localDataBytes!));
    } else if (path != null) {
      await _player.setSourceUrl(path);
    } else {
      throw StateError('오디오 파일을 찾을 수 없습니다.');
    }
  }

  Future<void> _start() async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      await _showMicrophoneError();
      return;
    }
    setState(() {
      _running = true;
      _segmentIndex = 0;
    });
    try {
      for (var index = 0; index < widget.routine.segments.length; index++) {
        if (!mounted) return;
        final segment = widget.routine.segments[index];
        setState(() {
          _segmentIndex = index;
          _step = '구간 ${index + 1} 원본 재생';
        });
        await _loadAudioSource();
        await _player.seek(Duration(milliseconds: (segment.startSec * 1000).round()));
        await _player.resume();
        await Future<void>.delayed(Duration(milliseconds: ((segment.endSec - segment.startSec) * 1000).round()));
        await _player.pause();
        if (!mounted) return;
        setState(() => _step = '구간 ${index + 1} 내 음성 녹음');
        setState(() => _step = '구간 ${index + 1} 녹음 준비');
        await Future<void>.delayed(const Duration(seconds: 3));
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/loopi_${DateTime.now().microsecondsSinceEpoch}.m4a';
        if (await _recorder.hasPermission()) {
          await _recorder.start(const RecordConfig(), path: path);
          await Future<void>.delayed(Duration(milliseconds: ((segment.endSec - segment.startSec) * 1000).round()));
          await _recorder.stop();
        }
      }
      if (mounted) setState(() => _step = '연습 완료');
    } catch (error) {
      if (mounted) setState(() => _error = '오디오 연습을 시작하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.routine.segments[_segmentIndex.clamp(0, widget.routine.segments.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.name)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 180,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.graphic_eq, color: LoopiColors.purple, size: 72),
              Text(_step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              Text('${formatMmSs(segment.startSec)} - ${formatMmSs(segment.endSec)}', style: const TextStyle(color: Colors.white60)),
            ]),
          ),
          const SizedBox(height: 20),
          Text('구간 ${_segmentIndex + 1} / ${widget.routine.segments.length}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: const Icon(Icons.mic),
            label: Text(_running ? _step : '섀도잉 연습 시작'),
          ),
        ]),
      ),
    );
  }
}
