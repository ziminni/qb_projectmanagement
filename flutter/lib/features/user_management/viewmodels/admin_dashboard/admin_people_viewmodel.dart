import '../../../../data/models/attendance.dart';
import '../../../../data/models/daily_report.dart';
import '../../../../data/models/project.dart';
import '../../../../data/models/user.dart';
import '../../../../data/models/worker.dart';
import '../../../../data/repositories/daily_report_repository.dart';
import '../../../../data/repositories/labor_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import 'admin_tab_viewmodel.dart';

/// One ongoing site's reporting and attendance over the last week.
class AdminSiteActivity {
  const AdminSiteActivity({
    required this.project,
    required this.reportDays,
    required this.workDays,
    required this.manDays,
    required this.overtimeHours,
    required this.workersSeen,
    this.attendanceError = false,
  });

  final Project project;

  /// Days in the window with a submitted or approved daily report.
  final int reportDays;

  /// Working days (Monday to Saturday) in the window.
  final int workDays;
  final double manDays;
  final double overtimeHours;

  /// Distinct workers with attendance in the window.
  final int workersSeen;

  /// The attendance for this site could not be read.
  final bool attendanceError;

  double get reportRate => workDays == 0 ? 0 : reportDays / workDays;
}

/// The People & Labor tab: the workforce, site reporting and attendance.
class AdminPeopleViewModel extends AdminTabViewModel {
  AdminPeopleViewModel({
    required LaborRepository labor,
    required DailyReportRepository reports,
    required ProjectRepository projects,
    required UserRepository users,
    super.now,
  }) : _labor = labor,
       _reports = reports,
       _projects = projects,
       _users = users;

  final LaborRepository _labor;
  final DailyReportRepository _reports;
  final ProjectRepository _projects;
  final UserRepository _users;

  /// Days looked back over for reporting and attendance.
  static const windowDays = 7;

  List<Worker> _workers = const [];
  List<DailyReport> _recentReports = const [];
  List<AdminSiteActivity> _sites = const [];
  Map<int, String> _names = const {};
  Map<int, Project> _projectsById = const {};

  @override
  String get subject => 'people and labor';

  int get activeWorkers => _workers.where((w) => w.isActive).length;
  int get inactiveWorkers => _workers.length - activeWorkers;

  /// Active workers per trade, largest first.
  List<MapEntry<String, int>> get workersByTrade {
    final out = <String, int>{};
    for (final w in _workers.where((w) => w.isActive)) {
      final t = w.trade.trim().isEmpty ? 'Unassigned' : w.trade.trim();
      out[t] = (out[t] ?? 0) + 1;
    }
    return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Average daily rate of active workers whose rate is visible.
  double? get averageDailyRate {
    final rated = _workers.where((w) => w.isActive && !w.dailyRateHidden);
    if (rated.isEmpty) return null;
    return rated.fold<double>(0, (s, w) => s + w.dailyRate) / rated.length;
  }

  /// Submitted reports waiting for the owner, oldest first.
  List<DailyReport> get awaitingReview =>
      _recentReports
          .where((r) => r.status == DailyReportStatus.submitted)
          .toList()
        ..sort((a, b) => a.reportDate.compareTo(b.reportDate));

  int get returnedReports => _recentReports
      .where((r) => r.status == DailyReportStatus.returned)
      .length;

  int get approvedThisWeek {
    final since = today.subtract(const Duration(days: windowDays));
    return _recentReports
        .where(
          (r) =>
              r.status == DailyReportStatus.approved &&
              !r.reportDate.isBefore(since),
        )
        .length;
  }

  List<AdminSiteActivity> get sites => _sites;

  double get manDaysThisWeek => _sites.fold(0, (s, a) => s + a.manDays);

  /// Share of working days with a report, across ongoing sites.
  double get reportCompliance {
    final due = _sites.fold<int>(0, (s, a) => s + a.workDays);
    final filed = _sites.fold<int>(0, (s, a) => s + a.reportDays);
    return due == 0 ? 0 : filed / due;
  }

  String userName(int id) => _names[id] ?? 'User #$id';

  String projectLabel(int id) {
    final p = _projectsById[id];
    return p == null ? 'Project #$id' : '${p.code} · ${p.name}';
  }

  @override
  Future<void> fetch() async {
    final (workers, projects, users) = await (
      _labor.getWorkers(),
      _projects.getProjects(),
      _users.getUsers(),
    ).wait;
    _workers = workers;
    _names = {for (final User u in users) u.id: u.fullName};
    _projectsById = {for (final p in projects) p.id: p};

    final ongoing = [
      for (final p in projects)
        if (p.status == ProjectStatus.ongoing) p,
    ];
    final from = today.subtract(const Duration(days: windowDays - 1));
    final (reports, attendance) = await (
      _reports.getReports(
        projectIds: [for (final p in projects) p.id],
        from: today.subtract(const Duration(days: 30)),
      ),
      Future.wait([
        for (final p in ongoing)
          _labor
              .getAttendance(projectId: p.id, from: from, to: today)
              .then<List<Attendance>?>((a) => a, onError: (_) => null),
      ]),
    ).wait;
    _recentReports = reports;

    var workDays = 0;
    for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.sunday) workDays++;
    }

    _sites = [
      for (final (i, p) in ongoing.indexed)
        _site(p, reports, attendance[i], from, workDays),
    ]..sort((a, b) => a.reportRate.compareTo(b.reportRate));
  }

  AdminSiteActivity _site(
    Project p,
    List<DailyReport> reports,
    List<Attendance>? attendance,
    DateTime from,
    int workDays,
  ) {
    final days = <DateTime>{
      for (final r in reports)
        if (r.projectId == p.id &&
            r.status != DailyReportStatus.draft &&
            !r.reportDate.isBefore(from))
          DateTime(r.reportDate.year, r.reportDate.month, r.reportDate.day),
    };
    final rows = attendance ?? const <Attendance>[];
    return AdminSiteActivity(
      project: p,
      reportDays: days.length.clamp(0, workDays),
      workDays: workDays,
      manDays: rows.fold(0, (s, a) => s + a.status.dayFraction),
      overtimeHours: rows.fold(0, (s, a) => s + a.overtimeHours),
      workersSeen: {
        for (final a in rows)
          if (a.status != AttendanceStatus.absent) a.workerId,
      }.length,
      attendanceError: attendance == null,
    );
  }
}
