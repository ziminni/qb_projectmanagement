import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/daily_report.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/daily_report_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// Daily report history: the site engineer's own sites, a PM's projects,
/// every project for the owner, or one project when [projectId] is set.
class DailyReportsViewModel extends ChangeNotifier {
  DailyReportsViewModel({
    this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required DailyReportRepository reports,
  }) : _session = session,
       _projects = projects,
       _reports = reports;

  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final DailyReportRepository _reports;

  bool _loading = true;
  String? _error;
  Map<int, Project> _projectById = const {};
  List<DailyReport> _items = const [];
  DailyReportStatus? _status;
  DateTime? _from;
  DateTime? _to;

  bool get isLoading => _loading;
  String? get error => _error;
  List<DailyReport> get items => _items;
  DailyReportStatus? get statusFilter => _status;
  DateTime? get from => _from;
  DateTime? get to => _to;
  AppRole get role => _session.activeRole!;
  Project? projectFor(DailyReport r) => _projectById[r.projectId];

  /// Ongoing projects where the site engineer can file a new report.
  List<Project> get reportableProjects => role == AppRole.siteEngineer
      ? _projectById.values
            .where((p) => p.status == ProjectStatus.ongoing)
            .toList()
      : const [];

  bool get canCreate => reportableProjects.isNotEmpty;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final projects = await _projects.getProjectsFor(_session.user!.id, role);
      _projectById = {for (final p in projects) p.id: p};
      if (projectId != null && !_projectById.containsKey(projectId)) {
        _error = 'You cannot see this project\'s reports.';
        return;
      }
      _items = await _reports.getReports(
        projectIds: projectId != null
            ? [projectId!]
            : _projectById.keys.toList(),
        status: _status,
        from: _from,
        to: _to,
      );
    } catch (e) {
      _error = 'Could not load daily reports. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setStatus(DailyReportStatus? status) {
    _status = status;
    load();
  }

  void setRange(DateTime? from, DateTime? to) {
    _from = from;
    _to = to;
    load();
  }
}
