import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/daily_report.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/daily_report_repository.dart';
import '../../../data/repositories/master_data_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/session_service.dart';

class DailyReportDetailViewModel extends ChangeNotifier with ActionRunner {
  DailyReportDetailViewModel({
    required this.reportId,
    required SessionService session,
    required ProjectRepository projects,
    required DailyReportRepository reports,
    required MasterDataRepository masterData,
    required UserRepository users,
  }) : _session = session,
       _projects = projects,
       _reports = reports,
       _masterData = masterData,
       _users = users;

  final int reportId;
  final SessionService _session;
  final ProjectRepository _projects;
  final DailyReportRepository _reports;
  final MasterDataRepository _masterData;
  final UserRepository _users;

  bool _loading = true;
  String? _error;
  DailyReportDetail? _detail;
  Project? _project;
  bool _isPm = false;
  final _materialNames = <int, String>{};
  final _equipmentNames = <int, String>{};
  final _userNames = <int, String>{};

  bool get isLoading => _loading;
  String? get error => _error;
  DailyReportDetail? get detail => _detail;
  DailyReport? get report => _detail?.report;
  Project? get project => _project;

  String materialName(int id) => _materialNames[id] ?? 'Material #$id';
  String equipmentName(int id) => _equipmentNames[id] ?? 'Equipment #$id';
  String? userName(int? id) => id == null ? null : _userNames[id];

  bool get canEdit =>
      report != null &&
      report!.status.isEditable &&
      report!.submittedBy == _session.user!.id &&
      _session.activeRole == AppRole.siteEngineer;

  bool get canReview => _isPm && report?.status == DailyReportStatus.submitted;

  Future<void> load() async {
    try {
      await _refresh();
      if (_detail == null) return;
      _project = await _projects.getProject(_detail!.report.projectId);
      final role = _session.activeRole!;
      final visible = await _projects.getProjectsFor(_session.user!.id, role);
      if (!visible.any((p) => p.id == _project?.id)) {
        _error = 'You cannot see this report.';
        return;
      }
      _isPm =
          role == AppRole.owner &&
          await _projects.isAssigned(
            _project!.id,
            _session.user!.id,
            AppRole.owner,
          );
      for (final m in await _masterData.getMaterials()) {
        _materialNames[m.id] = '${m.name} (${m.unit})';
      }
      for (final e in await _masterData.getEquipment()) {
        _equipmentNames[e.id] = e.name;
      }
      for (final u in await _users.getUsers()) {
        _userNames[u.id] = u.fullName;
      }
    } catch (e) {
      _error = 'Could not load the report. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    _detail = await _reports.getDetail(reportId);
    if (_detail == null) _error = 'Report not found.';
  }

  Future<String?> submit() => runAction(() async {
    await _reports.submit(reportId, userId: _session.user!.id);
    await _refresh();
  });

  Future<String?> approve() => runAction(() async {
    await _reports.approve(reportId, userId: _session.user!.id);
    await _refresh();
  });

  Future<String?> returnReport(String remarks) => runAction(() async {
    await _reports.returnReport(
      reportId,
      userId: _session.user!.id,
      remarks: remarks,
    );
    await _refresh();
  });
}
