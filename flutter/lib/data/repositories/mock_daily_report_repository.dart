import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/daily_report.dart';
import '../models/equipment_log.dart';
import '../models/issue.dart';
import '../models/report_manpower.dart';
import '../models/report_material_usage.dart';
import '../models/report_photo.dart';
import '../services/business_rule_exception.dart';
import '../services/daily_report_rules.dart';
import '../services/notification_service.dart';
import '../services/project_rules.dart';
import 'audit_log_repository.dart';
import 'daily_report_repository.dart';
import 'mock_site_data.dart';
import 'project_repository.dart';
import 'schedule_repository.dart';

class MockDailyReportRepository implements DailyReportRepository {
  MockDailyReportRepository({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
    DateTime Function()? clock,
  }) : _projects = projects,
       _schedule = schedule,
       _auditLog = auditLog,
       _notifications = notifications,
       _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final DateTime Function() _clock;

  final _reports = [...MockSiteData.reports];
  final _manpower = [...MockSiteData.manpower];
  final _materials = [...MockSiteData.materials];
  final _equipment = [...MockSiteData.equipmentLogs];
  final _issues = [...MockSiteData.issues];
  final _photos = [...MockSiteData.photos];

  static int _next(Iterable<int> ids) =>
      ids.fold(0, (m, id) => id > m ? id : m) + 1;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Future<List<DailyReport>> getReports({
    List<int>? projectIds,
    DailyReportStatus? status,
    DateTime? from,
    DateTime? to,
  }) async => _reports.where((r) {
    if (projectIds != null && !projectIds.contains(r.projectId)) {
      return false;
    }
    if (status != null && r.status != status) return false;
    if (from != null && r.reportDate.isBefore(_day(from))) return false;
    if (to != null && r.reportDate.isAfter(_day(to))) return false;
    return true;
  }).toList()..sort((a, b) => b.reportDate.compareTo(a.reportDate));

  @override
  Future<DailyReportDetail?> getDetail(int id) async {
    final i = _reports.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    final report = _reports[i];
    final todos = (await _schedule.getTodos(
      report.projectId,
    )).where((t) => t.dailyReportId == id).toList();
    return DailyReportDetail(
      report: report,
      manpower: _manpower.where((m) => m.dailyReportId == id).toList(),
      materials: _materials.where((m) => m.dailyReportId == id).toList(),
      equipment: _equipment.where((e) => e.dailyReportId == id).toList(),
      issues: _issues.where((x) => x.dailyReportId == id).toList(),
      photos: _photos.where((p) => p.dailyReportId == id).toList(),
      todos: todos,
    );
  }

  @override
  Future<DailyReport> saveDraft(
    DailyReportDraft draft, {
    required int userId,
  }) async {
    final project = await _projects.getProject(draft.projectId);
    if (project == null) {
      throw const BusinessRuleException('Project not found.');
    }
    ProjectRules.enforce(ProjectRules.requireOngoing(project, 'Daily reports'));
    if (!await _projects.isAssigned(
      draft.projectId,
      userId,
      AppRole.siteEngineer,
    )) {
      throw const BusinessRuleException(
        'Only the site engineer assigned to this project can file its reports.',
      );
    }
    DailyReportRules.enforce(
      DailyReportRules.validateDate(draft.reportDate, _clock()),
    );
    final date = _day(draft.reportDate);
    if (_reports.any(
      (r) =>
          r.projectId == draft.projectId &&
          r.reportDate == date &&
          r.id != draft.id,
    )) {
      throw const BusinessRuleException(
        'There is already a report for this project on this date.',
      );
    }
    for (final m in draft.manpower) {
      DailyReportRules.enforce(DailyReportRules.validateHeadcount(m.headcount));
      if (m.trade.trim().isEmpty) {
        throw const BusinessRuleException(
          'Choose a trade for each manpower row.',
        );
      }
    }
    for (final m in draft.materials) {
      DailyReportRules.enforce(DailyReportRules.validateQuantity(m.quantity));
    }
    for (final e in draft.equipment) {
      DailyReportRules.enforce(DailyReportRules.validateHours(e.hours));
    }
    for (final x in draft.issues) {
      if (x.description.trim().isEmpty) {
        throw const BusinessRuleException('Describe each issue.');
      }
      DailyReportRules.enforce(DailyReportRules.validateDaysLost(x.daysLost));
    }

    final now = _clock();
    late DailyReport report;
    if (draft.id == null) {
      report = DailyReport(
        id: _next(_reports.map((r) => r.id)),
        projectId: draft.projectId,
        reportDate: date,
        weather: draft.weather,
        status: DailyReportStatus.draft,
        submittedBy: userId,
        toolboxMeetingHeld: draft.toolboxMeetingHeld,
        createdAt: now,
        updatedAt: now,
      );
      _reports.add(report);
    } else {
      final i = _indexOf(draft.id!);
      DailyReportRules.enforce(DailyReportRules.canEdit(_reports[i]));
      report = _reports[i].copyWith(
        reportDate: date,
        weather: draft.weather,
        toolboxMeetingHeld: draft.toolboxMeetingHeld,
        updatedAt: now,
      );
      _reports[i] = report;
    }
    final id = report.id;

    _manpower.removeWhere((m) => m.dailyReportId == id);
    for (final m in draft.manpower) {
      _manpower.add(
        ReportManpower(
          id: _next(_manpower.map((x) => x.id)),
          dailyReportId: id,
          trade: m.trade.trim(),
          headcount: m.headcount,
        ),
      );
    }
    _materials.removeWhere((m) => m.dailyReportId == id);
    for (final m in draft.materials) {
      _materials.add(
        ReportMaterialUsage(
          id: _next(_materials.map((x) => x.id)),
          dailyReportId: id,
          materialId: m.materialId,
          quantity: m.quantity,
        ),
      );
    }
    _equipment.removeWhere((e) => e.dailyReportId == id);
    for (final e in draft.equipment) {
      _equipment.add(
        EquipmentLog(
          id: _next(_equipment.map((x) => x.id)),
          equipmentId: e.equipmentId,
          projectId: draft.projectId,
          logDate: date,
          hoursUsed: e.hours,
          dailyReportId: id,
        ),
      );
    }
    _issues.removeWhere((x) => x.dailyReportId == id);
    for (final x in draft.issues) {
      _issues.add(
        Issue(
          id: _next(_issues.map((i) => i.id)),
          projectId: draft.projectId,
          dailyReportId: id,
          type: x.type,
          reason: x.reason,
          description: x.description.trim(),
          daysLost: x.daysLost,
        ),
      );
    }
    _photos.removeWhere((p) => p.dailyReportId == id);
    for (final p in draft.photos) {
      _photos.add(
        ReportPhoto(
          id: _next(_photos.map((x) => x.id)),
          dailyReportId: id,
          fileUrl: p.fileUrl,
          caption: p.caption,
          latitude: p.latitude,
          longitude: p.longitude,
          takenAt: p.takenAt ?? now,
        ),
      );
    }

    // Link the chosen to-dos; unlink ones no longer chosen if still open.
    for (final t in await _schedule.getTodos(draft.projectId)) {
      final chosen = draft.todoIds.contains(t.id);
      if (chosen && t.dailyReportId != id) {
        if (t.isDone) {
          throw BusinessRuleException('"${t.title}" is already done.');
        }
        await _schedule.setReportLink(t.id, id);
      } else if (!chosen && t.dailyReportId == id && !t.isDone) {
        await _schedule.setReportLink(t.id, null);
      }
    }
    return report;
  }

  @override
  Future<DailyReport> submit(int id, {required int userId}) async {
    final i = _indexOf(id);
    final report = _reports[i];
    DailyReportRules.enforce(DailyReportRules.canSubmit(report));
    if (report.submittedBy != userId) {
      throw const BusinessRuleException(
        'Only the site engineer who wrote this report can submit it.',
      );
    }
    for (final t in await _schedule.getTodos(report.projectId)) {
      if (t.dailyReportId == id && !t.isDone) {
        await _schedule.setDone(
          t.id,
          done: true,
          userId: userId,
          dailyReportId: id,
        );
      }
    }
    final updated = report.copyWith(
      status: DailyReportStatus.submitted,
      updatedAt: _clock(),
    );
    _reports[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'daily_report_submitted',
      entity: 'daily_report',
      entityId: id,
    );
    final project = await _projects.getProject(report.projectId);
    await _notifications?.notifyProjectRole(
      report.projectId,
      AppRole.pm,
      type: 'report_submitted',
      message:
          'Daily report for ${project?.code} on ${_fmt(report.reportDate)} '
          'is waiting for your approval.',
      link: AppRoutes.dailyReport(id),
    );
    return updated;
  }

  @override
  Future<DailyReport> approve(int id, {required int userId}) async {
    final i = _indexOf(id);
    final report = _reports[i];
    DailyReportRules.enforce(DailyReportRules.canReview(report));
    await _requirePm(report.projectId, userId);
    for (final t in await _schedule.getTodos(report.projectId)) {
      if (t.dailyReportId == id && t.isDone && !t.isVerified) {
        await _schedule.verify(t.id, userId: userId);
      }
    }
    final updated = report.copyWith(
      status: DailyReportStatus.approved,
      reviewedBy: () => userId,
      remarks: () => null,
      updatedAt: _clock(),
    );
    _reports[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'daily_report_approved',
      entity: 'daily_report',
      entityId: id,
    );
    await _notifications?.notify(
      [report.submittedBy],
      type: 'report_approved',
      message: 'Your daily report for ${_fmt(report.reportDate)} was approved.',
      link: AppRoutes.dailyReport(id),
    );
    return updated;
  }

  @override
  Future<DailyReport> returnReport(
    int id, {
    required int userId,
    required String remarks,
  }) async {
    final i = _indexOf(id);
    final report = _reports[i];
    DailyReportRules.enforce(DailyReportRules.canReview(report));
    DailyReportRules.enforce(DailyReportRules.validateReturnRemarks(remarks));
    await _requirePm(report.projectId, userId);
    final updated = report.copyWith(
      status: DailyReportStatus.returned,
      reviewedBy: () => userId,
      remarks: () => remarks.trim(),
      updatedAt: _clock(),
    );
    _reports[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'daily_report_returned',
      entity: 'daily_report',
      entityId: id,
      details: {'remarks': remarks.trim()},
    );
    await _notifications?.notify(
      [report.submittedBy],
      type: 'report_returned',
      message:
          'Your daily report for ${_fmt(report.reportDate)} was returned: '
          '${remarks.trim()}',
      link: AppRoutes.dailyReport(id),
    );
    return updated;
  }

  Set<int> _approvedIds(int projectId) => {
    for (final r in _reports)
      if (r.projectId == projectId && r.status == DailyReportStatus.approved)
        r.id,
  };

  @override
  Future<List<ReportMaterialUsage>> getApprovedMaterialUsage(
    int projectId,
  ) async {
    final ids = _approvedIds(projectId);
    return _materials.where((m) => ids.contains(m.dailyReportId)).toList();
  }

  @override
  Future<List<EquipmentLog>> getApprovedEquipmentLogs(int projectId) async {
    final ids = _approvedIds(projectId);
    return _equipment.where((e) => ids.contains(e.dailyReportId)).toList();
  }

  @override
  Future<List<({ReportPhoto photo, DailyReport report})>> getApprovedPhotos(
    List<int> projectIds,
  ) async {
    final byId = {
      for (final r in _reports)
        if (projectIds.contains(r.projectId) &&
            r.status == DailyReportStatus.approved)
          r.id: r,
    };
    return [
      for (final p in _photos)
        if (byId[p.dailyReportId] != null)
          (photo: p, report: byId[p.dailyReportId]!),
    ]..sort(
      (a, b) => (b.photo.takenAt ?? b.report.reportDate).compareTo(
        a.photo.takenAt ?? a.report.reportDate,
      ),
    );
  }

  Future<void> _requirePm(int projectId, int userId) async {
    if (!await _projects.isAssigned(projectId, userId, AppRole.pm)) {
      throw const BusinessRuleException(
        'Only the PM of this project can review its reports.',
      );
    }
  }

  int _indexOf(int id) {
    final i = _reports.indexWhere((r) => r.id == id);
    if (i < 0) throw const BusinessRuleException('Report not found.');
    return i;
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
