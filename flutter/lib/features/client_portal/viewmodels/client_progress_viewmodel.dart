import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

/// Client progress view: progress bar, S-curve and read-only Gantt, all from
/// the shared progress calculation.
class ClientProgressViewModel extends ChangeNotifier {
  ClientProgressViewModel({
    this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
  }) : _session = session,
       _projects = projects,
       _schedule = schedule;

  /// Null shows the client's first project.
  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;

  bool _loading = true;
  String? _error;
  List<Project> projects = const [];
  Project? _project;
  ProjectProgress? _progress;
  List<SCurvePoint> _sCurve = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  Project? get project => _project;
  ProjectProgress? get progress => _progress;
  List<SCurvePoint> get sCurve => _sCurve;

  Future<void> load() async {
    projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    _project = projectId == null
        ? projects.firstOrNull
        : projects.where((p) => p.id == projectId).firstOrNull;
    if (_project == null) {
      _error = projects.isEmpty
          ? 'No projects are linked to your account yet.'
          : 'This project is not linked to your account.';
    } else {
      final categories = await _schedule.getCategories(_project!.id);
      final todos = await _schedule.getTodos(_project!.id);
      _progress = computeProjectProgress(
        project: _project!,
        categories: categories,
        todos: todos,
      );
      _sCurve = computeSCurve(
        project: _project!,
        categories: categories,
        todos: todos,
      );
    }
    _loading = false;
    notifyListeners();
  }
}
