import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/routine_models.dart';

/// In-memory library of saved routine presets for the current session.
class RoutineLibrary extends ChangeNotifier {
  static const String _routineStorageKey = 'loopi_saved_routines';
  static const String _groupStorageKey = 'loopi_saved_groups';
  static const String _practiceStorageKey = 'loopi_practice_results';

  final List<SavedRoutine> _routines = [];
  final List<RoutineGroup> _groups = [];
  final List<PracticeResult> _practiceResults = [];

  List<SavedRoutine> get routines => List.unmodifiable(_routines);
  List<RoutineGroup> get groups => List.unmodifiable(_groups);
  List<PracticeResult> get practiceResults => List.unmodifiable(_practiceResults);
  List<SavedRoutine> get favoriteRoutines => _routines.where((routine) => routine.isFavorite).toList();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoutines = prefs.getStringList(_routineStorageKey) ?? const <String>[];
    final savedGroups = prefs.getStringList(_groupStorageKey) ?? const <String>[];
    final savedPracticeResults = prefs.getStringList(_practiceStorageKey) ?? const <String>[];

    _routines
      ..clear()
      ..addAll(
        savedRoutines
            .map((value) => jsonDecode(value))
            .whereType<Map<String, dynamic>>()
            .map(SavedRoutine.fromJson)
            .toList(),
      );

    _groups
      ..clear()
      ..addAll(
        savedGroups
            .map((value) => jsonDecode(value))
            .whereType<Map<String, dynamic>>()
            .map(RoutineGroup.fromJson)
            .toList(),
      );
            _practiceResults
          ..clear()
          ..addAll(
            savedPracticeResults
            .map((value) => jsonDecode(value))
            .whereType<Map<String, dynamic>>()
            .map(PracticeResult.fromJson),
          );
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _routineStorageKey,
      _routines.map((routine) => jsonEncode(routine.toJson())).toList(),
    );
    await prefs.setStringList(
      _groupStorageKey,
      _groups.map((group) => jsonEncode(group.toJson())).toList(),
    );
    await prefs.setStringList(
      _practiceStorageKey,
      _practiceResults.map((result) => jsonEncode(result.toJson())).toList(),
    );
  }

  SavedRoutine? byId(String id) {
    for (final routine in _routines) {
      if (routine.id == id) return routine;
    }
    return null;
  }

  List<SavedRoutine> routinesForGroup(RoutineGroup group) {
    return group.routineIds
        .map((id) => byId(id))
        .whereType<SavedRoutine>()
        .toList();
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

  Future<void> save(SavedRoutine routine) async {
    _routines.insert(0, routine);
    await _persist();
    notifyListeners();
  }

  Future<void> setFavorite(String id, bool value) async {
    final index = _routines.indexWhere((routine) => routine.id == id);
    if (index < 0 || _routines[index].isFavorite == value) return;
    _routines[index] = _routines[index].copyWith(isFavorite: value);
    notifyListeners();
    await Future<void>.microtask(() => _persist());
  }

  Future<void> savePracticeResult(PracticeResult result) async {
    _practiceResults.insert(0, result);
    notifyListeners();
    unawaited(_persist());
  }

  bool? toggleFavoriteOptimistic(String id) {
    final index = _routines.indexWhere((routine) => routine.id == id);
    if (index < 0) return null;
    final next = !_routines[index].isFavorite;
    setFavorite(id, next);
    return next;
  }

  Future<void> deleteMany(Iterable<String> ids) async {
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
    await _persist();
    notifyListeners();
  }

  Future<void> createGroup({required String name, required List<String> routineIds}) async {
    final unique = routineIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
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
        title: name.trim().isEmpty ? '새 폴더' : name.trim(),
        routineIds: unique,
      ),
    );
    _groups
      ..clear()
      ..addAll(nextGroups);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteGroup(String groupId, {bool keepRoutines = true}) async {
    final groupIndex = _groups.indexWhere((group) => group.id == groupId);
    if (groupIndex < 0) return;
    final group = _groups.removeAt(groupIndex);
    if (!keepRoutines) {
      await deleteMany(group.routineIds);
      return;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> renameGroup(String groupId, String title) async {
    final index = _groups.indexWhere((group) => group.id == groupId);
    if (index < 0) return;
    _groups[index] = _groups[index].copyWith(title: title.trim().isEmpty ? '새 폴더' : title.trim());
    await _persist();
    notifyListeners();
  }
}
