import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/routine_models.dart';
import '../state/link_studio_session.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/youtube_id.dart';
import '../widgets/app_logo.dart';
import '../widgets/save_routine_dialog.dart';
import 'practice_mode_screen.dart';

const String kDefaultVideoUrl = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';

class LinkStudioScreen extends StatefulWidget {
  const LinkStudioScreen({
    super.key,
    required this.library,
    this.initialVideoUrl = kDefaultVideoUrl,
  });

  final RoutineLibrary library;
  final String initialVideoUrl;

  @override
  State<LinkStudioScreen> createState() => _LinkStudioScreenState();
}

class _LinkStudioScreenState extends State<LinkStudioScreen> {
  final LinkStudioSession _session = LinkStudioSession();
  final TextEditingController _urlController = TextEditingController();
  final List<TextEditingController> _startControllers = [];
  final List<TextEditingController> _endControllers = [];
  final List<FocusNode> _startFocus = [];
  final List<FocusNode> _endFocus = [];

  late YoutubePlayerController _player;
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

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    _videoUrl = widget.initialVideoUrl;
    _urlController.text = _videoUrl;
    _videoId = extractYoutubeVideoId(_videoUrl) ?? 'M7lc1UVf-VE';
    _syncRowControllers();
    _session.addListener(_onSessionChanged);

    _player = YoutubePlayerController.fromVideoId(
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
    _valueSub = _player.stream.listen(_onPlayerValue);
    _stateSub = _player.videoStateStream.listen(_onVideoState);
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
      await _player.seekTo(seconds: seconds, allowSeekAhead: true);
    } catch (_) {}
  }

  Future<void> _applySpeed(double speed) async {
    if (_inWidgetTest) return;
    try {
      await _player.setPlaybackRate(speed);
    } catch (_) {}
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
    final id = extractYoutubeVideoId(_urlController.text);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }
    setState(() {
      _videoId = id;
      _videoUrl = _urlController.text.trim();
    });
    await _player.cueVideoById(videoId: id);
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
    _session.beginTest();
    _highlightedSection = 0;
    _delayPending = false;
    _ignoreLoopUntil = DateTime.now().add(const Duration(milliseconds: 400));
    final first = _session.testSegment;
    await _applySpeed(first.speed);
    await _seekTo(first.startSec, force: true);
    if (!_inWidgetTest) {
      await _player.playVideo();
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_session.isTesting) return;
      try {
        final time = await _player.currentTime;
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
    if (time + 0.12 < segment.endSec) return;

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
    if (result == LoopHitResult.nextSegment) {
      await _applySpeed(_session.testSegment.speed);
    }
    await _seekTo(_session.testSegment.startSec, force: true);
    if (!_inWidgetTest) {
      await _player.playVideo();
    }
    if (mounted) setState(() {});
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

  Future<void> _stopTestPlayback() async {
    _delayTimer?.cancel();
    _delayTimer = null;
    _delayPending = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _session.stopTest();
    _highlightedSection = _session.selectedIndex;
    if (!_inWidgetTest) {
      try {
        await _player.pauseVideo();
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
        await _player.pauseVideo();
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
        builder: (_) => PracticeModeScreen(routine: routine),
      ),
    );
  }

  @override
  void dispose() {
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
    _player.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testing = _session.isTesting;
    return YoutubePlayerScaffold(
      controller: _player,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return Scaffold(
          backgroundColor: LoopiColors.canvas,
          appBar: AppBar(
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
                    _urlBar(),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ColoredBox(
                          color: Colors.black,
                          child: _inWidgetTest || _saveDialogOpen
                              ? Center(
                                  child: Text(
                                    'studio.player_placeholder'.tr(),
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                )
                              : player,
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
      },
    );
  }

  Widget _urlBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                enabled: !_session.isTesting,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Paste a YouTube URL',
                  isDense: true,
                ),
                onSubmitted: (_) => _loadUrl(),
              ),
            ),
            TextButton(
              onPressed: _session.isTesting ? null : _loadUrl,
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: LoopiColors.deepPurple),
              child: Text('studio.load'.tr()),
            ),
          ],
        ),
      ),
    );
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
