import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

class ProjectSummary {
  const ProjectSummary(this.project, this.progress, {required this.isBehind});

  final Project project;
  final ProjectProgress progress;
  final bool isBehind;
}

/// Project list for owners and site engineers (assigned) and accountants
/// (all, read-only).
class ProjectsViewModel extends ChangeNotifier {
  ProjectsViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required CompanyRepository company,
  }) : _session = session,
       _projects = projects,
       _schedule = schedule,
       _company = company;

  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final CompanyRepository _company;

  bool _loading = true;
  String? _error;
  List<ProjectSummary> _all = const [];
  String _query = '';
  ProjectStatus? _status;

  bool get isLoading => _loading;
  String? get error => _error;
  AppRole get role => _session.activeRole!;
  bool get canCreate => role == AppRole.owner;
  bool get isSiteEngineer => role == AppRole.siteEngineer;
  ProjectStatus? get statusFilter => _status;

  List<ProjectSummary> get items {
    final q = _query.trim().toLowerCase();
    return _all.where((s) {
      if (_status != null && s.project.status != _status) return false;
      if (q.isEmpty) return true;
      return s.project.name.toLowerCase().contains(q) ||
          s.project.code.toLowerCase().contains(q) ||
          s.project.location.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final threshold =
          (await _company.getSettings()).behindScheduleThresholdPct / 100;
      final projects = await _projects.getProjectsFor(_session.user!.id, role);
      _all = [
        for (final p in projects)
          await () async {
            final progress = computeProjectProgress(
              project: p,
              categories: await _schedule.getCategories(p.id),
              todos: await _schedule.getTodos(p.id),
            );
            return ProjectSummary(
              p,
              progress,
              isBehind:
                  p.status == ProjectStatus.ongoing &&
                  progress.scheduleVariance > threshold,
            );
          }(),
      ]..sort((a, b) => a.project.code.compareTo(b.project.code));
    } catch (e) {
      _error = 'Could not load projects. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setStatus(ProjectStatus? status) {
    _status = status;
    notifyListeners();
  }
}
