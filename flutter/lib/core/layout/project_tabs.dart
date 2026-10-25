import '../../data/models/app_role.dart';

/// Project detail tabs from the design document, each shown only to the
/// roles the permission matrix lets see that data.
enum ProjectTab {
  overview('Overview', 'overview', _internal),
  schedule('Categories and to-dos', 'schedule', _siteTeam),
  gantt('Gantt', 'gantt', _siteTeam),
  dailyReports('Daily reports', 'daily-reports', _siteTeam),
  materials('Materials', 'materials', _internal),
  labor('Labor', 'labor', [
    AppRole.owner,
    AppRole.pm,
    AppRole.siteEngineer,
    AppRole.accountant,
  ]),
  financials('Financials', 'financials', [
    AppRole.owner,
    AppRole.pm,
    AppRole.accountant,
  ]),
  documents('Documents', 'documents', _internal);

  const ProjectTab(this.label, this.segment, this.roles);

  final String label;
  final String segment;
  final List<AppRole> roles;

  static List<ProjectTab> visibleTo(AppRole role) =>
      values.where((t) => t.roles.contains(role)).toList();

  static ProjectTab? fromSegment(String segment) {
    for (final t in values) {
      if (t.segment == segment) return t;
    }
    return null;
  }
}

const _internal = [
  AppRole.owner,
  AppRole.pm,
  AppRole.siteEngineer,
  AppRole.purchasing,
  AppRole.accountant,
];

const _siteTeam = [AppRole.owner, AppRole.pm, AppRole.siteEngineer];
