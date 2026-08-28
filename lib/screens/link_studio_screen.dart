import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/routine_models.dart';
import '../state/link_studio_session.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/youtube_id.dart';
import '../utils/media_blob.dart';
import '../widgets/app_logo.dart';
import '../widgets/save_routine_dialog.dart';
import 'practice_mode_screen.dart';

const String kDefaultVideoUrl = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';

String? _platformFilePath(PlatformFile? file) {
  if (file == null || kIsWeb) return null;
  return file.path;
}

String? _createSelectedVideoBlobUrl(PlatformFile file) {
  final extension = file.extension?.toLowerCase();
  final mimeType = switch (extension) {
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    _ => 'video/mp4',
  };
  return createMediaBlobUrl(file.bytes!, mimeType);
}

class LinkStudioScreen extends StatefulWidget {
  const LinkStudioScreen({
    super.key,
    required this.library,
    this.initialVideoUrl = kDefaultVideoUrl,
    this.sourceType = SourceType.youtube,
    this.embedded = false,
    this.file,
    this.localFilePath,
    this.fileName,
  });

  final RoutineLibrary library;
  final String initialVideoUrl;
  final SourceType sourceType;
  final bool embedded;
  final PlatformFile? file;
  final String? localFilePath;
  final String? fileName;

  @override
  State<LinkStudioScreen> createState() => _LinkStudioScreenState();
}

class _LinkStudioScreenState extends State<LinkStudioScreen> with WidgetsBindingObserver {
  final LinkStudioSession _session = LinkStudioSession();
  final TextEditingController _urlController = TextEditingController();
  final List<TextEditingController> _startControllers = [];
  final List<TextEditingController> _endControllers = [];
  final List<FocusNode> _startFocus = [];
  final List<FocusNode> _endFocus = [];

  late YoutubePlayerController _youtubePlayer;
  bool _youtubeInitialized = false;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _stateSub;
  Timer? _pollTimer;
  Timer? _delayTimer;
  DateTime? _ignoreLoopUntil;
  DateTime? _lastSeekAt;
  String _videoUrl = kDefaultVideoUrl;
  String _videoId = 'M7lc1UVf-VE';
  RangeValues? _rangeBeforeDrag;
  bool _saveDialogOpen = false;
  bool _delayPending = false;
  int _highlightedSection = 0;
  Completer<void>? _delayCompleter;
  String? _lastDetectedClipboardText;
  String? _mediaObjectUrl;
  bool _audioLoading = false;
  double? _activePlaybackStart;
  double? _activePlaybackEnd;

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoUrl = widget.initialVideoUrl;
    _urlController.text = _videoUrl;
    _videoId = extractYoutubeVideoId(_videoUrl) ?? 'M7lc1UVf-VE';
    _syncRowControllers();
    _session.addListener(_onSessionChanged);

    _session.setSourceType(
      widget.sourceType,
      localFilePath: _platformFilePath(widget.file) ?? widget.localFilePath,
      fileName: widget.file?.name ?? widget.fileName,
      localDataBytes: widget.file?.bytes,
    );

    switch (widget.sourceType) {
      case SourceType.youtube:
        if (!_inWidgetTest) {
          _initializeYouTubePlayer();
        }
        break;
      case SourceType.localVideo:
        _initializeVideoPlayer();
        break;
      case SourceType.audio:
        _initializeAudioPlayer();
        break;
    }
  }

  Future<void> _initializeYouTubePlayer() async {
    _youtubePlayer = YoutubePlayerController.fromVideoId(
      videoId: _videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        mute: false,
        showFullscreenButton: true,
        showControls: true,
        loop: false,
        captionLanguage: 'en',
        enableKeyboard: true,
      ),
    );
    _youtubeInitialized = true;
    _valueSub = _youtubePlayer.stream.listen(_onPlayerValue);
    _stateSub = _youtubePlayer.videoStateStream.listen(_onVideoState);
  }

  Future<void> _initializeVideoPlayer() async {
    final path = _platformFilePath(widget.file) ?? widget.localFilePath;
    if (path != null) {
      _videoPlayer = VideoPlayerController.file(File(path));
    } else if (widget.file?.bytes != null) {
      final extension = widget.file!.extension?.toLowerCase();
      final mimeType = switch (extension) {
        'webm' => 'video/webm',
        'mov' => 'video/quicktime',
        'mkv' => 'video/x-matroska',
        _ => 'video/mp4',
      };
        _mediaObjectUrl = createMediaBlobUrl(widget.file!.bytes!, mimeType);
        final uri = _mediaObjectUrl == null
          ? Uri.dataFromBytes(widget.file!.bytes!, mimeType: mimeType)
          : Uri.parse(_mediaObjectUrl!);
      _videoPlayer = VideoPlayerController.networkUrl(uri);
    } else {
      return;
    }
    await _videoPlayer!.initialize();
    _session.setVideoDuration(_videoPlayer!.value.duration.inMilliseconds / 1000.0);
    _videoPlayer!.addListener(_onVideoPlayerUpdate);
    if (mounted) setState(() {});
  }

  Future<void> _initializeAudioPlayer() async {
    _audioLoading = true;
    if (mounted) setState(() {});
    final path = _platformFilePath(widget.file) ?? widget.localFilePath;
    _audioPlayer = AudioPlayer();
    try {
      if (path != null) {
        await _audioPlayer!.setSourceDeviceFile(path);
      } else if (widget.file?.bytes != null) {
        await _audioPlayer!.setSourceBytes(widget.file!.bytes!);
      } else {
        return;
      }
      final duration = await _audioPlayer!.getDuration();
      if (duration != null) {
        _session.setVideoDuration(duration.inMilliseconds / 1000.0);
      }
      _audioPlayer!.onPositionChanged.listen((position) {
        final seconds = position.inMilliseconds / 1000.0;
        _syncSectionHighlight(seconds);
        if (_session.isTesting) {
          _handleTestTime(seconds);
        }
      });
    } finally {
      _audioLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _onVideoPlayerUpdate() {
    if (_videoPlayer == null) return;
    final duration = _videoPlayer!.value.duration.inMilliseconds / 1000.0;
    final position = _videoPlayer!.value.position.inMilliseconds / 1000.0;
    
    if (duration > 1) {
      _session.setVideoDuration(duration);
    }
    
    _syncSectionHighlight(position);
    if (_session.isTesting) {
      _handleTestTime(position);
    }
    
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    _syncRowControllers();
    if (mounted) setState(() {});
  }

  void _onPlayerValue(YoutubePlayerValue value) {
    final seconds = value.metaData.duration.inMilliseconds / 1000.0;
    if (seconds > 1) {
      _session.setVideoDuration(seconds);
    }
  }

  void _onVideoState(YoutubeVideoState state) {
    final seconds = state.position.inMilliseconds / 1000.0;
    _syncSectionHighlight(seconds);
    if (!_session.isTesting) return;
    _handleTestTime(seconds);
  }

  void _syncSectionHighlight(double time) {
    final index = _sectionIndexForTime(time);
    if (index == _highlightedSection) return;
    _highlightedSection = index;
    if (mounted) setState(() {});
  }

  int _sectionIndexForTime(double time) {
    final segments = _session.segments;
    if (_session.isTesting) {
      final playing = _session.testSegmentIndex.clamp(0, segments.length - 1);
      final segment = segments[playing];
      if (time >= segment.startSec - 0.3 && time <= segment.endSec + 0.3) {
        return playing;
      }
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (time >= segment.startSec && time <= segment.endSec) {
        return i;
      }
    }
    if (_session.isTesting) return _session.testSegmentIndex;
    return _session.selectedIndex;
  }

  void _syncRowControllers() {
    while (_startControllers.length < _session.segments.length) {
      final index = _startControllers.length;
      final segment = _session.segments[index];
      _startControllers.add(TextEditingController(text: formatMmSs(segment.startSec)));
      _endControllers.add(TextEditingController(text: formatMmSs(segment.endSec)));
      _startFocus.add(FocusNode()..addListener(_onTimeFocusChanged));
      _endFocus.add(FocusNode()..addListener(_onTimeFocusChanged));
    }
    while (_startControllers.length > _session.segments.length) {
      _startControllers.removeLast().dispose();
      _endControllers.removeLast().dispose();
      _startFocus.removeLast()
        ..removeListener(_onTimeFocusChanged)
        ..dispose();
      _endFocus.removeLast()
        ..removeListener(_onTimeFocusChanged)
        ..dispose();
    }
    for (var i = 0; i < _session.segments.length; i++) {
      final segment = _session.segments[i];
      if (!_startFocus[i].hasFocus) {
        final text = formatMmSs(segment.startSec);
        if (_startControllers[i].text != text) {
          _startControllers[i].text = text;
        }
      }
      if (!_endFocus[i].hasFocus) {
        final text = formatMmSs(segment.endSec);
        if (_endControllers[i].text != text) {
          _endControllers[i].text = text;
        }
      }
    }
  }

  void _onTimeFocusChanged() {
    for (var i = 0; i < _session.segments.length; i++) {
      if (!_startFocus[i].hasFocus) {
        _commitTimeField(index: i, isStart: true);
      }
      if (!_endFocus[i].hasFocus) {
        _commitTimeField(index: i, isStart: false);
      }
    }
  }

  Future<void> _seekTo(double seconds, {bool force = false}) async {
    if (_inWidgetTest) return;
    final now = DateTime.now();
    if (!force &&
        _lastSeekAt != null &&
        now.difference(_lastSeekAt!) < const Duration(milliseconds: 40)) {
      return;
    }
    _lastSeekAt = now;
    
    try {
      switch (_session.sourceType) {
        case SourceType.youtube:
          await _youtubePlayer.seekTo(seconds: seconds, allowSeekAhead: true);
          break;
        case SourceType.localVideo:
          await _videoPlayer?.seekTo(Duration(milliseconds: (seconds * 1000).toInt()));
          break;
        case SourceType.audio:
          await _audioPlayer?.seek(Duration(milliseconds: (seconds * 1000).toInt()));
          break;
      }
    } catch (_) {}
  }

  Future<void> _applySpeed(double speed) async {
    if (_inWidgetTest) return;
    try {
      switch (_session.sourceType) {
        case SourceType.youtube:
          await _youtubePlayer.setPlaybackRate(speed);
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          break;
      }
    } catch (_) {}
  }

  Future<void> _play() async {
    if (_inWidgetTest) return;
    try {
      switch (_session.sourceType) {
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
    } catch (_) {}
  }

  Future<void> _pause() async {
    if (_inWidgetTest) return;
    try {
      switch (_session.sourceType) {
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

  Future<double> _getCurrentTime() async {
    switch (_session.sourceType) {
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

  void _commitTimeField({required int index, required bool isStart}) {
    final controller = isStart ? _startControllers[index] : _endControllers[index];
    final ok = _session.applyManualTime(index: index, isStart: isStart, text: controller.text);
    final segment = _session.segments[index];
    controller.text = formatMmSs(isStart ? segment.startSec : segment.endSec);
    if (ok && index == _session.selectedIndex) {
      _seekTo(isStart ? segment.startSec : segment.endSec, force: true);
    }
  }

  Future<void> _loadUrl() async {
    final trimmed = _urlController.text.trim();
    final id = extractYoutubeVideoId(trimmed);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }
    setState(() {
      _videoId = id;
      _videoUrl = trimmed;
    });
    await _youtubePlayer.cueVideoById(videoId: id);
  }

  String? _normalizeYoutubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final explicitId = extractYoutubeVideoId(trimmed);
    if (explicitId != null) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && (uri.host.contains('youtube.com') || uri.host.contains('youtu.be'))) {
        return trimmed;
      }
      return 'https://www.youtube.com/watch?v=$explicitId';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
      return null;
    }
    return uri.toString();
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = clipboardData?.text?.trim();
    if (pasted == null || pasted.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }

    final normalized = _normalizeYoutubeUrl(pasted);
    if (normalized == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }

    _urlController.text = normalized;
    setState(() {
      _videoUrl = normalized;
      _videoId = extractYoutubeVideoId(normalized) ?? _videoId;
    });
    await _loadUrl();
  }

  Future<void> _openYoutubeSearchOrHome() async {
    final query = _urlController.text.trim();
    final uri = query.isEmpty
        ? Uri.parse('https://www.youtube.com')
        : (extractYoutubeVideoId(query) != null
            ? Uri.parse(query)
            : Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}'));

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
    }
  }

  Future<void> _checkClipboardForDetectedLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim();
    if (text == null || text.isEmpty) return;

    final normalized = _normalizeYoutubeUrl(text);
    if (normalized == null || normalized == _lastDetectedClipboardText) return;

    _lastDetectedClipboardText = normalized;
    if (!mounted) return;

    _urlController.text = normalized;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${'link_studio.detected_copied_link'.tr()} ${'studio.load'.tr()}'),
        action: SnackBarAction(
          label: 'studio.load'.tr(),
          onPressed: () {
            _loadUrl();
          },
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkClipboardForDetectedLink());
    }
  }

  Future<void> _selectRow(int index) async {
    if (_session.isTesting) return;
    _session.selectSegment(index);
    final segment = _session.segments[index];
    await _applySpeed(segment.speed);
    await _seekTo(segment.startSec, force: true);
  }

  void _onRangeChangeStart(RangeValues values) {
    _rangeBeforeDrag = values;
  }

  void _onRangeChanged(RangeValues values) {
    if (_session.isTesting) return;
    final previous = _rangeBeforeDrag ?? _session.activeRange;
    final startMoved = (values.start - previous.start).abs();
    final endMoved = (values.end - previous.end).abs();
    _session.updateActiveRange(values);
    _rangeBeforeDrag = _session.activeRange;
    if (startMoved >= endMoved) {
      _seekTo(_session.active.startSec);
    } else {
      _seekTo(_session.active.endSec);
    }
  }

  Future<void> _toggleTestPlayback() async {
    if (_session.isTesting) {
      await _stopTestPlayback();
      return;
    }
    _session.beginTest(startIndex: _session.selectedIndex);
    _highlightedSection = _session.testSegmentIndex;
    _delayPending = false;
    _ignoreLoopUntil = DateTime.now().add(const Duration(milliseconds: 400));
    final first = _session.testSegment;
    _activePlaybackStart = first.startSec;
    _activePlaybackEnd = first.endSec;
    await _applySpeed(first.speed);
    await _seekTo(first.startSec, force: true);
    if (!_inWidgetTest) {
      await _play();
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_session.isTesting) return;
      try {
        final time = await _getCurrentTime();
        _syncSectionHighlight(time);
        _handleTestTime(time);
      } catch (_) {}
    });
  }

  void _handleTestTime(double time) {
    if (!_session.isTesting || _delayPending) return;
    final now = DateTime.now();
    if (_ignoreLoopUntil != null && now.isBefore(_ignoreLoopUntil!)) return;
    final segment = _session.testSegment;
    final start = _activePlaybackStart ?? segment.startSec;
    if (time + 0.04 < start) return;
    final end = _activePlaybackEnd ?? segment.endSec;
    final reachedEnd = time >= end - 0.04;
    if (!reachedEnd) return;

    _ignoreLoopUntil = DateTime.now().add(const Duration(days: 1));
    final delaySec = segment.delaySec;
    final result = _session.onLoopHit();
    unawaited(_afterLoopHit(result, delaySec));
  }

  Future<void> _afterLoopHit(LoopHitResult result, int delaySec) async {
    if (result == LoopHitResult.finished) {
      await _stopTestPlayback();
      return;
    }
    await _waitDelay(delaySec);
    if (!_session.isTesting || !mounted) return;
    _ignoreLoopUntil = DateTime.now().add(const Duration(milliseconds: 280));
    _highlightedSection = _session.testSegmentIndex;
    _activePlaybackStart = _session.testSegment.startSec;
    _activePlaybackEnd = _session.testSegment.endSec;
    if (result == LoopHitResult.nextSegment) {
      await _applySpeed(_session.testSegment.speed);
    }
    await _seekTo(_session.testSegment.startSec, force: true);
    if (!_inWidgetTest) {
      await _play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _waitDelay(int delaySec) async {
    if (delaySec <= 0 || _inWidgetTest) return;
    _delayPending = true;
    try {
      await _pause();
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

  Future<void> _stopTestPlayback() async {
    _delayTimer?.cancel();
    _delayTimer = null;
    _delayPending = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _session.stopTest();
    _activePlaybackStart = null;
    _activePlaybackEnd = null;
    _highlightedSection = _session.selectedIndex;
    if (!_inWidgetTest) {
      try {
        await _pause();
        await _applySpeed(_session.active.speed);
        await _seekTo(_session.active.startSec, force: true);
      } catch (_) {}
    }
  }

  Future<void> _onSavePressed() async {
    if (_session.isTesting) {
      await _stopTestPlayback();
    }
    if (!mounted) return;

    // HtmlElementView (YouTube iframe) sits above Flutter overlays on web and
    // swallows pointer/keyboard events. Unmount it while the dialog is open.
    setState(() => _saveDialogOpen = true);
    if (!_inWidgetTest) {
      try {
        await _pause();
      } catch (_) {}
    }
    if (!mounted) return;

    final name = await showSaveRoutineDialog(context);
    if (!mounted) return;
    setState(() => _saveDialogOpen = false);
    if (name == null) return;

    final routine = _session.toSavedRoutine(
      name: name,
      videoUrl: _videoUrl,
      videoId: _videoId,
    );
    widget.library.save(routine);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" ${'studio.save_success'.tr()}')),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeModeScreen(routine: routine, library: widget.library),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _delayTimer?.cancel();
    _valueSub?.cancel();
    _stateSub?.cancel();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _urlController.dispose();
    for (final c in _startControllers) {
      c.dispose();
    }
    for (final c in _endControllers) {
      c.dispose();
    }
    for (final n in _startFocus) {
      n.removeListener(_onTimeFocusChanged);
      n.dispose();
    }
    for (final n in _endFocus) {
      n.removeListener(_onTimeFocusChanged);
      n.dispose();
    }
    if (_youtubeInitialized) {
      _youtubePlayer.close();
    }
    _videoPlayer?.dispose();
    _audioPlayer?.dispose();
    revokeMediaBlobUrl(_mediaObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testing = _session.isTesting;
    
    switch (_session.sourceType) {
      case SourceType.youtube:
        return _buildYouTubeScaffold(testing);
      case SourceType.localVideo:
        return _buildVideoScaffold(testing);
      case SourceType.audio:
        return _buildAudioScaffold(testing);
    }
  }

  Widget _buildYouTubeScaffold(bool testing) {
    if (!_youtubeInitialized) {
      return _buildMainScaffold(
        testing: testing,
        mediaWidget: Center(
          child: Text(
            'studio.player_placeholder'.tr(),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        showUrlBar: true,
      );
    }
    return YoutubePlayerScaffold(
      controller: _youtubePlayer,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return _buildMainScaffold(
          testing: testing,
          mediaWidget: _inWidgetTest || _saveDialogOpen
              ? Center(
                  child: Text(
                    'studio.player_placeholder'.tr(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : player,
          showUrlBar: true,
        );
      },
    );
  }

  Widget _buildVideoScaffold(bool testing) {
    return _buildMainScaffold(
      testing: testing,
      mediaWidget: _videoPlayer != null && _videoPlayer!.value.isInitialized
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: _videoPlayer!.value.aspectRatio,
                child: VideoPlayer(_videoPlayer!),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
      showUrlBar: false,
    );
  }

  Widget _buildAudioScaffold(bool testing) {
    return _buildMainScaffold(
      testing: testing,
      mediaWidget: _buildAudioPlayerWidget(),
      showUrlBar: false,
    );
  }

  Widget _buildAudioPlayerWidget() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq_rounded, color: LoopiColors.purple, size: 64),
          const SizedBox(height: 16),
          if (_audioLoading) const CircularProgressIndicator(color: LoopiColors.purple),
          if (_audioLoading) const SizedBox(height: 12),
          Text(
            'studio.audio_mode'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_session.fileName != null)
            Text(
              _session.fileName!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildMainScaffold({
    required bool testing,
    required Widget mediaWidget,
    required bool showUrlBar,
  }) {
    return Scaffold(
      backgroundColor: LoopiColors.canvas,
        appBar: widget.embedded || !Navigator.of(context).canPop()
          ? null
          : AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: LoopiColors.ink,
        elevation: 0,
        title: const AppLogo(height: 30),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                if (showUrlBar) _urlBar() else _fileInfoBar(),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: Colors.black,
                      child: mediaWidget,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _sectionChips(),
                const SizedBox(height: 8),
                _timeline(),
                const SizedBox(height: 16),
                _routineTable(testing),
              ],
            ),
          ),
          _bottomBar(testing),
        ],
      ),
    );
  }

  Widget _urlBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                enabled: !_session.isTesting,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Paste a YouTube URL',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  suffixIcon: IconButton(
                    tooltip: 'link_studio.paste_from_clipboard'.tr(),
                    onPressed: _session.isTesting ? null : _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, color: LoopiColors.deepPurple),
                  ),
                ),
                onSubmitted: (_) => _loadUrl(),
              ),
            ),
            TextButton(
              onPressed: _session.isTesting ? null : _loadUrl,
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: LoopiColors.deepPurple),
              child: Text('studio.load'.tr()),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'link_studio.search_on_youtube'.tr(),
              onPressed: _openYoutubeSearchOrHome,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000).withValues(alpha: 0.12),
                foregroundColor: const Color(0xFFFF0000),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileInfoBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              _session.sourceType == SourceType.audio 
                  ? Icons.graphic_eq_rounded 
                  : Icons.videocam_rounded,
              color: LoopiColors.deepPurple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _session.fileName ?? 'studio.file_selected'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _session.sourceType == SourceType.audio 
                        ? 'studio.audio_mode'.tr() 
                        : 'studio.video_mode'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _session.isTesting ? null : _changeFile,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('studio.change_file'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: LoopiColors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: _session.sourceType == SourceType.audio
          ? FileType.custom
          : FileType.video,
      allowedExtensions: _session.sourceType == SourceType.audio
          ? ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'mov', 'webm']
          : null,
      allowMultiple: false,
      withData: true,
    );
    
    if (result != null && result.files.isNotEmpty) {
      final selectedFile = result.files.single;
      final filePath = _platformFilePath(selectedFile);
      final fileBytes = selectedFile.bytes;
      if (filePath == null && fileBytes == null) return;
      final fileName = result.files.single.name;
      
      // Reinitialize the appropriate player
      if (_session.sourceType == SourceType.localVideo) {
        await _videoPlayer?.dispose();
        revokeMediaBlobUrl(_mediaObjectUrl);
        _mediaObjectUrl = _createSelectedVideoBlobUrl(selectedFile);
        _videoPlayer = filePath != null
            ? VideoPlayerController.file(File(filePath))
          : VideoPlayerController.networkUrl(
            _mediaObjectUrl == null
              ? Uri.dataFromBytes(fileBytes!, mimeType: 'video/mp4')
              : Uri.parse(_mediaObjectUrl!),
            );
        await _videoPlayer!.initialize();
        _session.setVideoDuration(_videoPlayer!.value.duration.inMilliseconds / 1000.0);
        _videoPlayer!.addListener(_onVideoPlayerUpdate);
      } else if (_session.sourceType == SourceType.audio) {
        await _audioPlayer?.dispose();
        _audioPlayer = AudioPlayer();
        if (filePath != null) {
          await _audioPlayer!.setSourceDeviceFile(filePath);
        } else {
          await _audioPlayer!.setSourceBytes(fileBytes!);
        }
        final duration = await _audioPlayer!.getDuration();
        if (duration != null) {
          _session.setVideoDuration(duration.inMilliseconds / 1000.0);
        }
        _audioPlayer!.onPositionChanged.listen((position) {
          final seconds = position.inMilliseconds / 1000.0;
          _syncSectionHighlight(seconds);
          if (_session.isTesting) {
            _handleTestTime(seconds);
          }
        });
      }
      
      _session.setSourceType(
        _session.sourceType,
        localFilePath: filePath,
        fileName: fileName,
        localDataBytes: fileBytes,
      );
      
      if (mounted) setState(() {});
    }
  }

  Widget _sectionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _session.segments.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(
                builder: (context) {
                  final testing = _session.isTesting;
                  final active = testing ? i == _highlightedSection : i == _session.selectedIndex;
                  return ChoiceChip(
                    label: Text(sectionLabelForIndex(i)),
                    selected: active,
                    showCheckmark: !testing,
                    selectedColor: testing
                        ? LoopiColors.deepPurple
                        : LoopiColors.purple.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      color: testing && active
                          ? Colors.white
                          : active
                              ? LoopiColors.purpleDark
                              : LoopiColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: testing ? null : (_) => _selectRow(i),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeline() {
    final range = _session.activeRange;
    final max = _session.videoDuration <= 0 ? 1.0 : _session.videoDuration;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'studio.timeline'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, color: LoopiColors.ink),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${'studio.start'.tr()} ${formatMmSs(range.start)}', style: const TextStyle(color: LoopiColors.muted, fontSize: 12)),
                const Spacer(),
                Text('${'studio.end'.tr()} ${formatMmSs(range.end)}', style: const TextStyle(color: LoopiColors.muted, fontSize: 12)),
              ],
            ),
            RangeSlider(
              values: RangeValues(
                range.start.clamp(0.0, max),
                range.end.clamp(0.0, max),
              ),
              min: 0,
              max: max,
              divisions: max.floor().clamp(1, 6000),
              activeColor: LoopiColors.purple,
              labels: RangeLabels(formatMmSs(range.start), formatMmSs(range.end)),
              onChangeStart: _session.isTesting ? null : _onRangeChangeStart,
              onChanged: _session.isTesting ? null : _onRangeChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _routineTable(bool testing) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'studio.routine_list'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton.filled(
                  onPressed: testing ? null : _session.addSegment,
                  style: IconButton.styleFrom(backgroundColor: LoopiColors.deepPurple),
                  icon: const Icon(Icons.add, color: Colors.white),
                  tooltip: 'studio.add_section'.tr(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.sizeOf(context).width - 56,
                ),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowHeight: 36,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 64,
                  headingTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LoopiColors.muted,
                  ),
                  columns: [
                    DataColumn(label: Text('studio.section'.tr())),
                    DataColumn(label: Text('studio.start'.tr())),
                    DataColumn(label: Text('studio.end'.tr())),
                    DataColumn(label: Text('studio.speed'.tr())),
                    DataColumn(label: Text('studio.loop'.tr())),
                    DataColumn(label: Text('studio.delay'.tr())),
                    const DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (var i = 0; i < _session.segments.length; i++) _buildRow(i, testing),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(int index, bool testing) {
    final selected = index == _session.selectedIndex;
    return DataRow(
      selected: selected,
      color: WidgetStatePropertyAll(
        selected ? LoopiColors.purple.withValues(alpha: 0.08) : Colors.transparent,
      ),
      onSelectChanged: testing ? null : (_) => _selectRow(index),
      cells: [
        DataCell(Text(sectionLabelForIndex(index), style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(_timeField(index: index, isStart: true, enabled: !testing)),
        DataCell(_timeField(index: index, isStart: false, enabled: !testing)),
        DataCell(
          DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: _session.segments[index].speed,
              isDense: true,
              onChanged: testing
                  ? null
                  : (value) {
                      if (value == null) return;
                      _session.selectSegment(index);
                      _session.setSpeed(index, value);
                      _applySpeed(value);
                    },
              items: [
                for (final speed in kPlaybackSpeeds)
                  DropdownMenuItem(value: speed, child: Text(formatSpeedLabel(speed))),
              ],
            ),
          ),
        ),
        DataCell(
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _session.segments[index].loopCount,
              isDense: true,
              onChanged: testing
                  ? null
                  : (value) {
                      if (value == null) return;
                      _session.selectSegment(index);
                      _session.setLoopCount(index, value);
                    },
              items: [
                for (var n = 1; n <= 10; n++)
                  DropdownMenuItem(value: n, child: Text('${n}x')),
                const DropdownMenuItem(value: kInfiniteLoop, child: Text('Infinite')),
              ],
            ),
          ),
        ),
        DataCell(
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: kDelaySeconds.contains(_session.segments[index].delaySec)
                  ? _session.segments[index].delaySec
                  : kDelaySeconds.first,
              isDense: true,
              onChanged: testing
                  ? null
                  : (value) {
                      if (value == null) return;
                      _session.selectSegment(index);
                      _session.setDelaySec(index, value);
                    },
              items: [
                for (final delay in kDelaySeconds)
                  DropdownMenuItem(value: delay, child: Text(formatDelayLabel(delay))),
              ],
            ),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Delete section',
            onPressed: testing || _session.segments.length <= 1
                ? null
                : () => _session.removeSegment(index),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Widget _timeField({
    required int index,
    required bool isStart,
    required bool enabled,
  }) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: isStart ? _startControllers[index] : _endControllers[index],
        focusNode: isStart ? _startFocus[index] : _endFocus[index],
        enabled: enabled,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onTap: () {
          if (!enabled) return;
          _session.selectSegment(index);
        },
        onSubmitted: (_) => _commitTimeField(index: index, isStart: isStart),
        onEditingComplete: () => _commitTimeField(index: index, isStart: isStart),
      ),
    );
  }

  Widget _bottomBar(bool testing) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _toggleTestPlayback,
                  style: FilledButton.styleFrom(
                    backgroundColor: testing ? Colors.redAccent : LoopiColors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(testing ? 'Stop Routine' : 'Start Routine'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: testing ? null : _onSavePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: LoopiColors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Save Routine'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
