import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

class ScheduleProjectSummary {
  const ScheduleProjectSummary(this.project, this.progress);

  final Project project;
  final ProjectProgress progress;
}

/// Lists the projects the active role can open in the schedule, with their
/// progress.
class ScheduleProjectsViewModel extends ChangeNotifier {
  ScheduleProjectsViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
  }) : _session = session,
       _projects = projects,
       _schedule = schedule;

  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;

  bool _loading = true;
  String? _error;
  List<ScheduleProjectSummary> _items = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  List<ScheduleProjectSummary> get items => _items;
  AppRole get role => _session.activeRole!;
  bool get showCosts => role.seesFinance;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final projects = await _projects.getProjectsFor(_session.user!.id, role);
      _items = [
        for (final p in projects)
          ScheduleProjectSummary(
            p,
            computeProjectProgress(
              project: p,
              categories: await _schedule.getCategories(p.id),
              todos: await _schedule.getTodos(p.id),
            ),
          ),
      ];
    } catch (e) {
      _error = 'Could not load projects. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
