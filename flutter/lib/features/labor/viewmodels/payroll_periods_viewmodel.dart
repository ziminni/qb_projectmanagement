import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

typedef PeriodSummary = ({int workers, double gross, double net});

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
  String? _error;
  Map<int, Project> projectsById = const {};
  List<PayrollPeriod> _allItems = const [];
  Map<int, PeriodSummary> _summaries = const {};
  PayrollStatus? _statusFilter;
  int? _projectFilter;

  bool get isLoading => _loading;
  String? get error => _error;
  PayrollStatus? get statusFilter => _statusFilter;
  int? get projectFilter => _projectFilter;
  bool get canCreate => _session.activeRole == AppRole.accountant;

  PeriodSummary summaryFor(int periodId) =>
      _summaries[periodId] ?? (workers: 0, gross: 0.0, net: 0.0);

  List<PayrollPeriod> get scopedItems => _projectFilter == null
      ? _allItems
      : _allItems.where((p) => p.projectId == _projectFilter).toList();

  List<PayrollPeriod> get items => _statusFilter == null
      ? scopedItems
      : scopedItems.where((p) => p.status == _statusFilter).toList();

  int get totalPeriods => scopedItems.length;

  int countByStatus(PayrollStatus status) =>
      scopedItems.where((p) => p.status == status).length;

  double get processedTotalNet => scopedItems
      .where((p) => p.status == PayrollStatus.processed)
      .fold(0.0, (s, p) => s + summaryFor(p.id).net);

  double get pendingTotalNet => scopedItems
      .where((p) => p.status != PayrollStatus.processed)
      .fold(0.0, (s, p) => s + summaryFor(p.id).net);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final role = _session.activeRole!;
      final visible = await _projects.getProjectsFor(_session.user!.id, role);
      projectsById = {for (final p in visible) p.id: p};
      _allItems = await _labor.getPeriods(
        projectIds: projectId != null
            ? [projectId!]
            : projectsById.keys.toList(),
      );
      final lineLists = await Future.wait([
        for (final p in _allItems)
          _labor.getLines(p.id).catchError((_) => const <PayrollLine>[]),
      ]);
      _summaries = {
        for (var i = 0; i < _allItems.length; i++)
          _allItems[i].id: (
            workers: lineLists[i].length,
            gross: lineLists[i].fold(0.0, (s, l) => s + l.grossPay),
            net: lineLists[i].fold(0.0, (s, l) => s + l.netPay),
          ),
      };
    } catch (e) {
      _error = 'Could not load payroll. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setStatusFilter(PayrollStatus? s) {
    if (_statusFilter == s) return;
    _statusFilter = s;
    notifyListeners();
  }

  void setProjectFilter(int? id) {
    if (_projectFilter == id) return;
    _projectFilter = id;
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
