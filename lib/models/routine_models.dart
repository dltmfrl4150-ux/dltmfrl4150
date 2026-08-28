import 'dart:convert';

import 'package:flutter/foundation.dart';

enum SourceType {
  youtube,
  localVideo,
  audio,
}

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

  factory RoutineSegment.fromJson(Map<String, dynamic> json) {
    return RoutineSegment(
      id: json['id'] as String? ?? 'seg_${DateTime.now().microsecondsSinceEpoch}',
      startSec: (json['startSec'] as num?)?.toDouble() ?? 0,
      endSec: (json['endSec'] as num?)?.toDouble() ?? 30,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      loopCount: (json['loopCount'] as num?)?.toInt() ?? 1,
      delaySec: (json['delaySec'] as num?)?.toInt() ?? 3,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startSec': startSec,
        'endSec': endSec,
        'speed': speed,
        'loopCount': loopCount,
        'delaySec': delaySec,
      };

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
    this.sourceType = SourceType.youtube,
    this.localFilePath,
    this.fileName,
    this.localDataBytes,
    this.isFavorite = false,
    this.authorId = 'me',
    this.authorName = '나',
  });

  final String id;
  final String name;
  final String videoUrl;
  final String videoId;
  final List<RoutineSegment> segments;
  final DateTime createdAt;
  final SourceType sourceType;
  final String? localFilePath;
  final String? fileName;
  final List<int>? localDataBytes;
  final bool isFavorite;
  final String authorId;
  final String authorName;

  factory SavedRoutine.fromJson(Map<String, dynamic> json) {
    return SavedRoutine(
      id: json['id'] as String? ?? 'rtn_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Routine',
      videoUrl: json['videoUrl'] as String? ?? '',
      videoId: json['videoId'] as String? ?? '',
      segments: (json['segments'] as List<dynamic>? ?? const [])
          .map((segment) => RoutineSegment.fromJson(segment as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      sourceType: json['sourceType'] != null 
          ? SourceType.values.firstWhere(
              (e) => e.name == json['sourceType'] as String,
              orElse: () => SourceType.youtube,
            )
          : SourceType.youtube,
      localFilePath: json['localFilePath'] as String?,
      fileName: json['fileName'] as String?,
        localDataBytes: json['localDataBytes'] is String
          ? base64Decode(json['localDataBytes'] as String)
          : null,
          isFavorite: json['isFavorite'] as bool? ?? false,
          authorId: json['authorId'] as String? ?? 'me',
          authorName: json['authorName'] as String? ?? '나',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoUrl': videoUrl,
        'videoId': videoId,
        'segments': segments.map((segment) => segment.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'sourceType': sourceType.name,
        'localFilePath': localFilePath,
        'fileName': fileName,
        'localDataBytes': localDataBytes == null ? null : base64Encode(localDataBytes!),
        'isFavorite': isFavorite,
        'authorId': authorId,
        'authorName': authorName,
      };

  SavedRoutine copyWith({
    bool? isFavorite,
    String? authorId,
    String? authorName,
  }) {
    return SavedRoutine(
      id: id,
      name: name,
      videoUrl: videoUrl,
      videoId: videoId,
      segments: segments,
      createdAt: createdAt,
      sourceType: sourceType,
      localFilePath: localFilePath,
      fileName: fileName,
      localDataBytes: localDataBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
    );
  }
}

@immutable
class PracticeResult {
  const PracticeResult({
    required this.id,
    required this.name,
    required this.routineId,
    required this.createdAt,
    this.recordedPath,
    this.recordedDataBytes,
  });

  final String id;
  final String name;
  final String routineId;
  final DateTime createdAt;
  final String? recordedPath;
  final List<int>? recordedDataBytes;

  factory PracticeResult.fromJson(Map<String, dynamic> json) {
    return PracticeResult(
      id: json['id'] as String? ?? 'practice_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Practice Result',
      routineId: json['routineId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      recordedPath: json['recordedPath'] as String?,
      recordedDataBytes: json['recordedDataBytes'] is String
          ? base64Decode(json['recordedDataBytes'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'routineId': routineId,
        'createdAt': createdAt.toIso8601String(),
        'recordedPath': recordedPath,
        'recordedDataBytes': recordedDataBytes == null ? null : base64Encode(recordedDataBytes!),
      };
}

@immutable
class RoutineGroupModel {
  const RoutineGroupModel({
    required this.id,
    required this.title,
    required this.routineIds,
    required this.createdAt,
  });

  final String id;
  final String title;
  final List<String> routineIds;
  final DateTime createdAt;

  String get name => title;

  factory RoutineGroupModel.fromJson(Map<String, dynamic> json) {
    final routineIds = (json['routineIds'] as List<dynamic>? ?? const [])
        .map((id) => id.toString())
        .toList();
    return RoutineGroupModel(
      id: json['id'] as String? ?? 'grp_${DateTime.now().microsecondsSinceEpoch}',
      title: (json['title'] as String?) ?? (json['name'] as String?) ?? 'Untitled Group',
      routineIds: routineIds,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'routineIds': routineIds,
        'createdAt': createdAt.toIso8601String(),
      };

  RoutineGroupModel copyWith({
    String? id,
    String? title,
    List<String>? routineIds,
    DateTime? createdAt,
  }) {
    return RoutineGroupModel(
      id: id ?? this.id,
      title: title ?? this.title,
      routineIds: routineIds ?? this.routineIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

@immutable
class RoutineGroup extends RoutineGroupModel {
  RoutineGroup({
    required super.id,
    required super.title,
    required super.routineIds,
    DateTime? createdAt,
  }) : super(createdAt: createdAt ?? DateTime.now());

  factory RoutineGroup.fromJson(Map<String, dynamic> json) {
    return RoutineGroup(
      id: json['id'] as String? ?? 'grp_${DateTime.now().microsecondsSinceEpoch}',
      title: (json['title'] as String?) ?? (json['name'] as String?) ?? 'Untitled Group',
      routineIds: (json['routineIds'] as List<dynamic>? ?? const [])
          .map((id) => id.toString())
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'routineIds': routineIds,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  RoutineGroup copyWith({
    String? id,
    String? title,
    List<String>? routineIds,
    DateTime? createdAt,
  }) {
    return RoutineGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      routineIds: routineIds ?? this.routineIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
