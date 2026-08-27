import 'package:flutter/foundation.dart';

const List<double> kPlaybackSpeeds = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.5, 2.0];

/// Delay between loop iterations, in seconds.
const List<int> kDelaySeconds = [0, 1, 2, 3, 5, 10, 30, 60];

/// Loop count of `-1` means infinite.
const int kInfiniteLoop = -1;

String sectionLabelForIndex(int index) {
  final letter = String.fromCharCode(65 + (index % 26));
  return "$letter-$letter'";
}

String formatSpeedLabel(double speed) => '${speed.toStringAsFixed(1)}x';

String formatLoopLabel(int loopCount) {
  if (loopCount == kInfiniteLoop) return 'Infinite';
  return '${loopCount}x';
}

String formatDelayLabel(int delaySec) {
  if (delaySec >= 60 && delaySec % 60 == 0) {
    return '${delaySec ~/ 60}min';
  }
  return '${delaySec}s';
}

@immutable
class RoutineSegment {
  const RoutineSegment({
    required this.id,
    required this.startSec,
    required this.endSec,
    this.speed = 1.0,
    this.loopCount = 1,
    this.delaySec = 3,
  });

  final String id;
  final double startSec;
  final double endSec;
  final double speed;
  final int loopCount;
  final int delaySec;

  RoutineSegment copyWith({
    String? id,
    double? startSec,
    double? endSec,
    double? speed,
    int? loopCount,
    int? delaySec,
  }) {
    return RoutineSegment(
      id: id ?? this.id,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      speed: speed ?? this.speed,
      loopCount: loopCount ?? this.loopCount,
      delaySec: delaySec ?? this.delaySec,
    );
  }
}

@immutable
class SavedRoutine {
  const SavedRoutine({
    required this.id,
    required this.name,
    required this.videoUrl,
    required this.videoId,
    required this.segments,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String videoUrl;
  final String videoId;
  final List<RoutineSegment> segments;
  final DateTime createdAt;
}

@immutable
class RoutineGroup {
  const RoutineGroup({
    required this.id,
    required this.name,
    required this.routineIds,
  });

  final String id;
  final String name;
  final List<String> routineIds;

  RoutineGroup copyWith({
    String? id,
    String? name,
    List<String>? routineIds,
  }) {
    return RoutineGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      routineIds: routineIds ?? this.routineIds,
    );
  }
}
