import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/daily_report.dart';
import '../../../data/models/project.dart';
import '../../../data/models/report_photo.dart';
import '../../../data/repositories/daily_report_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// Site photos from approved daily reports on the client's projects.
class ClientPhotosViewModel extends ChangeNotifier {
  ClientPhotosViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required DailyReportRepository reports,
  }) : _session = session,
       _projects = projects,
       _reports = reports;

  final SessionService _session;
  final ProjectRepository _projects;
  final DailyReportRepository _reports;

  bool _loading = true;
  Map<int, Project> projectsById = const {};
  List<({ReportPhoto photo, DailyReport report})> _all = const [];
  int? _projectFilter;

  bool get isLoading => _loading;
  int? get projectFilter => _projectFilter;

  List<({ReportPhoto photo, DailyReport report})> get photos =>
      _projectFilter == null
      ? _all
      : _all.where((p) => p.report.projectId == _projectFilter).toList();

  Future<void> load() async {
    final projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    projectsById = {for (final p in projects) p.id: p};
    _all = await _reports.getApprovedPhotos(projectsById.keys.toList());
    _loading = false;
    notifyListeners();
  }

  void setProject(int? id) {
    _projectFilter = id;
    notifyListeners();
  }
}
