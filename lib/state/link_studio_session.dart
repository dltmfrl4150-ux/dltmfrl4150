import 'package:flutter/material.dart';

import '../models/routine_models.dart';
import '../utils/time_format.dart';

enum LoopHitResult { seekToStart, nextSegment, finished }

/// Holds LinkStudio segment list, selection, and in-app test-playback counters.
class LinkStudioSession extends ChangeNotifier {
  LinkStudioSession({double initialDuration = 180, SourceType sourceType = SourceType.youtube})
    : _videoDuration = initialDuration,
      _sourceType = sourceType,
      _segments = [
        RoutineSegment(
          id: 'seg_0',
          startSec: 0,
          endSec: _defaultEnd(initialDuration),
        ),
      ];

  static const double minGap = 1;

  final List<RoutineSegment> _segments;
  int _selectedIndex = 0;
  double _videoDuration;
  int _idSeed = 1;
  SourceType _sourceType;
  String? _localFilePath;
  String? _fileName;
  List<int>? _localDataBytes;

  bool isTesting = false;
  int testSegmentIndex = 0;
  int playsRemaining = 1;

  List<RoutineSegment> get segments => List.unmodifiable(_segments);
  int get selectedIndex => _selectedIndex;
  double get videoDuration => _videoDuration;
  RoutineSegment get active => _segments[_selectedIndex];
  RangeValues get activeRange => RangeValues(active.startSec, active.endSec);
  SourceType get sourceType => _sourceType;
  String? get localFilePath => _localFilePath;
  String? get fileName => _fileName;
  List<int>? get localDataBytes => _localDataBytes;

  static double _defaultEnd(double duration) {
    if (duration <= minGap) return duration;
    return 30.clamp(minGap, duration).toDouble();
  }

  void setVideoDuration(double duration) {
    if (duration <= 0) return;
    if ((duration - _videoDuration).abs() < 0.05) return;
    _videoDuration = duration;
    for (var i = 0; i < _segments.length; i++) {
      _segments[i] = _clampSegment(_segments[i]);
    }
    notifyListeners();
  }

  void setSourceType(
    SourceType type, {
    String? localFilePath,
    String? fileName,
    List<int>? localDataBytes,
  }) {
    _sourceType = type;
    _localFilePath = localFilePath;
    _fileName = fileName;
    _localDataBytes = localDataBytes;
    notifyListeners();
  }

  void selectSegment(int index) {
    if (index < 0 || index >= _segments.length) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void addSegment() {
    final last = _segments.last;
    _segments.add(
      RoutineSegment(
        id: 'seg_${_idSeed++}',
        startSec: last.startSec,
        endSec: last.endSec,
        speed: last.speed,
        loopCount: last.loopCount,
        delaySec: last.delaySec,
      ),
    );
    _selectedIndex = _segments.length - 1;
    notifyListeners();
  }

  void removeSegment(int index) {
    if (_segments.length <= 1) return;
    if (index < 0 || index >= _segments.length) return;
    _segments.removeAt(index);
    if (_selectedIndex >= _segments.length) {
      _selectedIndex = _segments.length - 1;
    }
    notifyListeners();
  }

  void updateActiveRange(RangeValues values) {
    updateRangeAt(_selectedIndex, values);
  }

  void updateRangeAt(int index, RangeValues values) {
    if (index < 0 || index >= _segments.length) return;
    var start = values.start.clamp(0.0, _videoDuration);
    var end = values.end.clamp(0.0, _videoDuration);
    if (end - start < minGap) {
      if ((start - _segments[index].startSec).abs() >= (end - _segments[index].endSec).abs()) {
        start = (end - minGap).clamp(0.0, _videoDuration);
      } else {
        end = (start + minGap).clamp(0.0, _videoDuration);
      }
    }
    _segments[index] = _segments[index].copyWith(startSec: start, endSec: end);
    notifyListeners();
  }

  bool applyManualTime({
    required int index,
    required bool isStart,
    required String text,
  }) {
    final parsed = parseTimeInput(text);
    if (parsed == null) {
      notifyListeners();
      return false;
    }
    final segment = _segments[index];
    if (isStart) {
      updateRangeAt(index, RangeValues(parsed, segment.endSec));
    } else {
      updateRangeAt(index, RangeValues(segment.startSec, parsed));
    }
    return true;
  }

  void setSpeed(int index, double speed) {
    _segments[index] = _segments[index].copyWith(speed: speed);
    notifyListeners();
  }

  void setLoopCount(int index, int loopCount) {
    _segments[index] = _segments[index].copyWith(loopCount: loopCount);
    notifyListeners();
  }

  void setDelaySec(int index, int delaySec) {
    _segments[index] = _segments[index].copyWith(delaySec: delaySec);
    notifyListeners();
  }

  void beginTest({int startIndex = 0}) {
    isTesting = true;
    testSegmentIndex = startIndex.clamp(0, _segments.length - 1);
    playsRemaining = _segments[testSegmentIndex].loopCount;
    notifyListeners();
  }

  void stopTest() {
    isTesting = false;
    testSegmentIndex = 0;
    playsRemaining = 1;
    notifyListeners();
  }

  RoutineSegment get testSegment => _segments[testSegmentIndex];

  LoopHitResult onLoopHit() {
    final segment = _segments[testSegmentIndex];
    if (segment.loopCount == kInfiniteLoop) {
      return LoopHitResult.seekToStart;
    }
    playsRemaining -= 1;
    if (playsRemaining > 0) {
      return LoopHitResult.seekToStart;
    }
    if (testSegmentIndex + 1 < _segments.length) {
      testSegmentIndex += 1;
      playsRemaining = _segments[testSegmentIndex].loopCount;
      notifyListeners();
      return LoopHitResult.nextSegment;
    }
    return LoopHitResult.finished;
  }

  SavedRoutine toSavedRoutine({
    required String name,
    required String videoUrl,
    required String videoId,
  }) {
    return SavedRoutine(
      id: 'rtn_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      videoUrl: videoUrl,
      videoId: videoId,
      segments: List<RoutineSegment>.unmodifiable(
        _segments.map(
          (s) => RoutineSegment(
            id: s.id,
            startSec: s.startSec,
            endSec: s.endSec,
            speed: s.speed,
            loopCount: s.loopCount,
            delaySec: s.delaySec,
          ),
        ),
      ),
      createdAt: DateTime.now(),
      sourceType: _sourceType,
      localFilePath: _localFilePath,
      fileName: _fileName,
      localDataBytes: _localDataBytes,
    );
  }

  RoutineSegment _clampSegment(RoutineSegment segment) {
    var start = segment.startSec.clamp(0.0, _videoDuration);
    var end = segment.endSec.clamp(0.0, _videoDuration);
    if (end - start < minGap) {
      end = (start + minGap).clamp(0.0, _videoDuration);
      if (end - start < minGap) {
        start = (end - minGap).clamp(0.0, _videoDuration);
      }
    }
    return segment.copyWith(startSec: start, endSec: end);
  }
}
