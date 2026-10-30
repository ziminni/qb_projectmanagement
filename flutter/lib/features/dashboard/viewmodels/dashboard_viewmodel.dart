import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/session_service.dart';

class DashboardProject {
  const DashboardProject(this.project, this.progress, {required this.isBehind});

  final Project project;
  final ProjectProgress progress;
  final bool isBehind;
}

/// Owner: company dashboard. PM: my projects dashboard.
class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required CompanyRepository company,
    required ApprovalInbox inbox,
    required BillingRepository billing,
  }) : _billing = billing,
       _session = session,
       _projects = projects,
       _schedule = schedule,
       _company = company,
       _inbox = inbox;

  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final CompanyRepository _company;
  final ApprovalInbox _inbox;
  final BillingRepository _billing;

  bool _loading = true;
  String? _error;
  List<DashboardProject> _projectsList = const [];
  Map<ApprovalKind, int> _pending = const {};
  BilledSummary? _billed;

  bool get isLoading => _loading;
  String? get error => _error;
  AppRole get role => _session.activeRole!;
  String get firstName => _session.user!.fullName.split(' ').first;

  /// Ongoing projects first, then the rest of the pipeline.
  List<DashboardProject> get projects => _projectsList;

  List<DashboardProject> get active => _projectsList
      .where((p) => p.project.status == ProjectStatus.ongoing)
      .toList();

  List<DashboardProject> get behind =>
      _projectsList.where((p) => p.isBehind).toList();

  double get activeContractValue =>
      active.fold(0, (s, p) => s + p.project.contractAmount);

  double get activeEarnedValue =>
      active.fold(0, (s, p) => s + p.progress.earnedValue);

  Map<ApprovalKind, int> get pendingByKind => _pending;

  int get pendingTotal => _pending.values.fold(0, (a, b) => a + b);

  /// Billed to clients vs. collected, across the visible projects.
  BilledSummary? get billed => _billed;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final userId = _session.user!.id;
      final threshold =
          (await _company.getSettings()).behindScheduleThresholdPct / 100;
      final list = <DashboardProject>[];
      for (final p in await _projects.getProjectsFor(userId, role)) {
        final progress = computeProjectProgress(
          project: p,
          categories: await _schedule.getCategories(p.id),
          todos: await _schedule.getTodos(p.id),
        );
        list.add(
          DashboardProject(
            p,
            progress,
            isBehind:
                p.status == ProjectStatus.ongoing &&
                progress.scheduleVariance > threshold,
          ),
        );
      }
      list.sort((a, b) {
        final ao = a.project.status == ProjectStatus.ongoing ? 0 : 1;
        final bo = b.project.status == ProjectStatus.ongoing ? 0 : 1;
        return ao != bo ? ao - bo : a.project.code.compareTo(b.project.code);
      });
      _projectsList = list;

      final counts = <ApprovalKind, int>{};
      for (final item in await _inbox.pendingFor(userId, role)) {
        counts[item.kind] = (counts[item.kind] ?? 0) + 1;
      }
      _pending = counts;
      _billed = await _billing.billedSummary(
        projectIds: _projectsList.map((p) => p.project.id).toList(),
      );
    } catch (e) {
      _error = 'Could not load the dashboard. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
