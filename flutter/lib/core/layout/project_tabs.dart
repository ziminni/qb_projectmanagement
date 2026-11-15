import '../../data/models/app_role.dart';

/// Project detail tabs, each shown only to the roles whose job needs it.
/// The site team works the site; the accountant sees only the money side.
enum ProjectTab {
  overview('Overview', 'overview', _internal),
  schedule('Categories and to-dos', 'schedule', _siteTeam),
  gantt('Gantt', 'gantt', _siteTeam),
  dailyReports('Daily reports', 'daily-reports', _siteTeam),
  materials('Materials', 'materials', _siteTeam),
  labor('Labor', 'labor', [
    AppRole.owner,
    AppRole.siteEngineer,
    AppRole.accountant,
  ]),
  financials('Financials', 'financials', [AppRole.owner, AppRole.accountant]),
  documents('Documents', 'documents', _siteTeam);

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

const _internal = [AppRole.owner, AppRole.siteEngineer, AppRole.accountant];

const _siteTeam = [AppRole.owner, AppRole.siteEngineer];
