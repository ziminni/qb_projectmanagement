import '../../../../data/models/app_role.dart';
import '../../../../data/models/daily_report.dart';
import '../../../../data/models/project.dart';
import '../../../../data/models/project_assignment.dart';
import '../../../../data/models/user.dart';
import '../../../../data/repositories/daily_report_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import 'admin_tab_viewmodel.dart';

/// Where a project is in its life.
enum ProjectStage {
  pipeline('Setting up'),
  active('Ongoing'),
  onHold('On hold'),
  done('Finished');

  const ProjectStage(this.label);
  final String label;

  static ProjectStage of(ProjectStatus s) => switch (s) {
    ProjectStatus.requested ||
    ProjectStatus.changesRequested ||
    ProjectStatus.siteEngineerPending ||
    ProjectStatus.accepted => pipeline,
    ProjectStatus.ongoing => active,
    ProjectStatus.onHold => onHold,
    ProjectStatus.completed || ProjectStatus.closed => done,
  };
}

/// One project as the admin's Projects tab shows it.
class AdminProjectRow {
  const AdminProjectRow({
    required this.project,
    required this.engineers,
    required this.lastReport,
    required this.daysLeft,
  });

  final Project project;

  /// Names of site engineers on the project (accepted or still invited).
  final List<String> engineers;

  /// Date of the latest submitted or approved daily report, if any.
  final DateTime? lastReport;

  /// Days to the target end date; negative when overdue.
  final int daysLeft;

  ProjectStage get stage => ProjectStage.of(project.status);
  bool get isOverdue => stage == ProjectStage.active && daysLeft < 0;
}

/// The Projects tab: portfolio status, deadlines, staffing and reporting.
class AdminProjectsViewModel extends AdminTabViewModel {
  AdminProjectsViewModel({
    required ProjectRepository projects,
    required DailyReportRepository reports,
    required UserRepository users,
    super.now,
  }) : _projects = projects,
       _reports = reports,
       _users = users;

  final ProjectRepository _projects;
  final DailyReportRepository _reports;
  final UserRepository _users;

  /// A site with no report for this many days counts as quiet.
  static const quietAfterDays = 3;

  /// Ongoing projects ending within this many days count as due soon.
  static const dueSoonDays = 30;

  List<AdminProjectRow> _rows = const [];

  @override
  String get subject => 'the projects';

  List<AdminProjectRow> get rows => _rows;

  int countIn(ProjectStage stage) =>
      _rows.where((r) => r.stage == stage).length;

  Map<ProjectStatus, int> get byStatus => {
    for (final s in ProjectStatus.values)
      if (_rows.any((r) => r.project.status == s))
        s: _rows.where((r) => r.project.status == s).length,
  };

  /// Contract value of projects that are not finished.
  double get openContractValue => _rows
      .where((r) => r.stage != ProjectStage.done)
      .fold(0, (sum, r) => sum + r.project.contractAmount);

  List<AdminProjectRow> get overdue =>
      _rows.where((r) => r.isOverdue).toList()
        ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

  List<AdminProjectRow> get dueSoon =>
      _rows
          .where(
            (r) =>
                r.stage == ProjectStage.active &&
                r.daysLeft >= 0 &&
                r.daysLeft <= dueSoonDays,
          )
          .toList()
        ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

  /// Projects not finished that have no site engineer.
  List<AdminProjectRow> get withoutEngineer => _rows
      .where((r) => r.stage != ProjectStage.done && r.engineers.isEmpty)
      .toList();

  /// Ongoing sites with no daily report in [quietAfterDays] days.
  List<AdminProjectRow> get quietSites => _rows.where((r) {
    if (r.stage != ProjectStage.active) return false;
    final last = r.lastReport;
    return last == null || today.difference(last).inDays >= quietAfterDays;
  }).toList();

  /// Not finished projects, most urgent deadline first.
  List<AdminProjectRow> get openProjects =>
      _rows.where((r) => r.stage != ProjectStage.done).toList()
        ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

  @override
  Future<void> fetch() async {
    final (projects, users) = await (
      _projects.getProjects(),
      _users.getUsers(),
    ).wait;
    final names = {for (final User u in users) u.id: u.fullName};

    final open = [
      for (final p in projects)
        if (ProjectStage.of(p.status) != ProjectStage.done) p,
    ];
    final (assignments, reports) = await (
      Future.wait([for (final p in open) _projects.getAssignments(p.id)]),
      _reports.getReports(
        projectIds: [for (final p in open) p.id],
        from: today.subtract(const Duration(days: 60)),
      ),
    ).wait;

    final engineersByProject = <int, List<String>>{};
    for (final (i, p) in open.indexed) {
      engineersByProject[p.id] = [
        for (final a in assignments[i])
          if (a.roleOnProject == AppRole.siteEngineer &&
              a.response != RequestResponse.declined)
            names[a.userId] ?? 'User #${a.userId}',
      ];
    }

    final lastReport = <int, DateTime>{};
    for (final r in reports) {
      if (r.status == DailyReportStatus.draft) continue;
      final prev = lastReport[r.projectId];
      if (prev == null || r.reportDate.isAfter(prev)) {
        lastReport[r.projectId] = r.reportDate;
      }
    }

    _rows = [
      for (final p in projects)
        AdminProjectRow(
          project: p,
          engineers: engineersByProject[p.id] ?? const [],
          lastReport: lastReport[p.id],
          daysLeft: DateTime(
            p.targetEndDate.year,
            p.targetEndDate.month,
            p.targetEndDate.day,
          ).difference(today).inDays,
        ),
    ];
  }
}
