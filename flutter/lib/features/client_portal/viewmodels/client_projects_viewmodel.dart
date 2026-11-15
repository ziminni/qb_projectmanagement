import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_assignment.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

class ClientProjectSummary {
  const ClientProjectSummary(this.project, this.progress);

  final Project project;
  final ProjectProgress progress;
}

/// The client's own projects with their progress, and new project requests
/// to accept or decline.
class ClientProjectsViewModel extends ChangeNotifier with ActionRunner {
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
  List<ProjectRequest> _requests = const [];

  bool get isLoading => _loading;
  List<ClientProjectSummary> get items => _items;
  List<ProjectRequest> get requests => _requests;

  Future<String?> respond(
    ProjectRequest r, {
    required RequestResponse answer,
    String? note,
  }) => runAction(() async {
    await _projects.respondToRequest(
      r.assignment.id,
      userId: _session.user!.id,
      answer: answer,
      note: note,
    );
    await load();
  });

  Future<void> load() async {
    _requests = await _projects.getRequestsFor(
      _session.user!.id,
      AppRole.client,
    );
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
