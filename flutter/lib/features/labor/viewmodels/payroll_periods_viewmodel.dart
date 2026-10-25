import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// Payroll periods: the accountant creates and processes them, PMs verify
/// attendance on their projects, the owner views.
class PayrollPeriodsViewModel extends ChangeNotifier with ActionRunner {
  PayrollPeriodsViewModel({
    this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required LaborRepository labor,
  }) : _session = session,
       _projects = projects,
       _labor = labor;

  /// Limits the list to one project (the project Labor tab).
  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final LaborRepository _labor;

  bool _loading = true;
  Map<int, Project> projectsById = const {};
  List<PayrollPeriod> _items = const [];

  bool get isLoading => _loading;
  List<PayrollPeriod> get items => _items;
  bool get canCreate => _session.activeRole == AppRole.accountant;

  Future<void> load() async {
    final role = _session.activeRole!;
    final visible = await _projects.getProjectsFor(_session.user!.id, role);
    projectsById = {for (final p in visible) p.id: p};
    _items = await _labor.getPeriods(
      projectIds: projectId != null ? [projectId!] : projectsById.keys.toList(),
    );
    _loading = false;
    notifyListeners();
  }

  Future<String?> create(int projectId, DateTime start, DateTime end) =>
      runAction(() async {
        await _labor.createPeriod(
          projectId,
          start,
          end,
          userId: _session.user!.id,
        );
        await load();
      });
}
