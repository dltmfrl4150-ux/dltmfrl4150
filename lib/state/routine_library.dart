import 'package:flutter/foundation.dart';

import '../models/routine_models.dart';

/// In-memory library of saved routine presets for the current session.
class RoutineLibrary extends ChangeNotifier {
  final List<SavedRoutine> _routines = [];
  final List<RoutineGroup> _groups = [];

  List<SavedRoutine> get routines => List.unmodifiable(_routines);
  List<RoutineGroup> get groups => List.unmodifiable(_groups);

  SavedRoutine? byId(String id) {
    for (final routine in _routines) {
      if (routine.id == id) return routine;
    }
    return null;
  }

  Set<String> get groupedRoutineIds {
    return {
      for (final group in _groups) ...group.routineIds,
    };
  }

  List<SavedRoutine> get ungroupedRoutines {
    final grouped = groupedRoutineIds;
    return _routines.where((routine) => !grouped.contains(routine.id)).toList();
  }

  void save(SavedRoutine routine) {
    _routines.insert(0, routine);
    notifyListeners();
  }

  void deleteMany(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _routines.removeWhere((routine) => idSet.contains(routine.id));
    final nextGroups = <RoutineGroup>[];
    for (final group in _groups) {
      final remaining = group.routineIds.where((id) => !idSet.contains(id)).toList();
      if (remaining.isNotEmpty) {
        nextGroups.add(group.copyWith(routineIds: remaining));
      }
    }
    _groups
      ..clear()
      ..addAll(nextGroups);
    notifyListeners();
  }

  void createGroup({required String name, required List<String> routineIds}) {
    final unique = routineIds.toSet().toList();
    if (unique.isEmpty) return;
    final nextGroups = <RoutineGroup>[];
    for (final group in _groups) {
      final remaining = group.routineIds.where((id) => !unique.contains(id)).toList();
      if (remaining.isNotEmpty) {
        nextGroups.add(group.copyWith(routineIds: remaining));
      }
    }
    nextGroups.add(
      RoutineGroup(
        id: 'grp_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        routineIds: unique,
      ),
    );
    _groups
      ..clear()
      ..addAll(nextGroups);
    notifyListeners();
  }
}
