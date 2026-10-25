import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

class ClientProjectSummary {
  const ClientProjectSummary(this.project, this.progress);

  final Project project;
  final ProjectProgress progress;
}

/// The client's own projects with their progress.
class ClientProjectsViewModel extends ChangeNotifier {
  ClientProjectsViewModel({
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
  List<ClientProjectSummary> _items = const [];

  bool get isLoading => _loading;
  List<ClientProjectSummary> get items => _items;

  Future<void> load() async {
    final projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    _items = [
      for (final p in projects)
        ClientProjectSummary(
          p,
          computeProjectProgress(
            project: p,
            categories: await _schedule.getCategories(p.id),
            todos: await _schedule.getTodos(p.id),
          ),
        ),
    ];
    _loading = false;
    notifyListeners();
  }
}
