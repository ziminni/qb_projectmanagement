import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../repositories/project_repository.dart';
import '../repositories/schedule_repository.dart';

/// Shared catalog of work categories (WBS defaults + categories added in
/// projects or Settings).
class CategoryCatalogService extends ChangeNotifier {
  CategoryCatalogService({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
  }) : _projects = projects,
       _schedule = schedule;

  final ProjectRepository _projects;
  final ScheduleRepository _schedule;

  static const defaultCategories = [
    'Site preparation',
    'Foundation',
    'Structural',
    'Masonry',
    'Roofing',
    'Electrical',
    'Plumbing',
    'Finishing',
  ];

  final List<String> _custom = [];
  final List<String> _fromProjects = [];

  List<String> get suggestions {
    final seen = <String>{};
    final out = <String>[];
    for (final name in [...defaultCategories, ..._fromProjects, ..._custom]) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) {
        out.add(trimmed);
      }
    }
    return List.unmodifiable(out);
  }

  bool isDefault(String name) => defaultCategories.any(
    (d) => d.toLowerCase() == name.trim().toLowerCase(),
  );

  bool isCustomOnly(String name) =>
      _custom.any((c) => c.toLowerCase() == name.trim().toLowerCase()) &&
      !isDefault(name) &&
      !_fromProjects.any((p) => p.toLowerCase() == name.trim().toLowerCase());

  Future<List<String>> loadAll() async {
    try {
      final projects = await _projects.getProjects();
      final loaded = <String>[];
      for (final p in projects) {
        try {
          for (final c in await _schedule.getCategories(p.id)) {
            loaded.add(c.name);
          }
        } catch (_) {
          // Ignore individual project load failures.
        }
      }
      _fromProjects
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (_) {
      // Keep defaults + custom categories when offline.
    }
    return suggestions;
  }

  void register(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    if (suggestions.any((s) => s.toLowerCase() == lower)) return;
    _custom.add(trimmed);
    notifyListeners();
  }

  void removeCustom(String name) {
    final lower = name.trim().toLowerCase();
    _custom.removeWhere((c) => c.toLowerCase() == lower);
    notifyListeners();
  }
}
