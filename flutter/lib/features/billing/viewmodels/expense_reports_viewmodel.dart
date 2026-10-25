import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/category.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/project_cost_service.dart';
import '../../../data/services/session_service.dart';

/// Budget vs. actual for one category.
class CategoryCost {
  const CategoryCost(this.category, this.actual);

  final Category category;
  final double actual;

  double? get budget => category.budget;
  double? get variance => budget == null ? null : budget! - actual;
}

/// A project's costs: actual spend against budget and earned value.
class CostReport {
  const CostReport({
    required this.project,
    required this.costs,
    required this.categories,
    required this.progress,
  });

  final Project project;
  final ProjectCosts costs;
  final List<CategoryCost> categories;
  final ProjectProgress progress;

  double get totalBudget => categories.fold(0, (s, c) => s + (c.budget ?? 0));

  /// Earned value less actual cost; positive is under cost.
  double get costVariance => progress.earnedValue - costs.total;
}

/// Builds [CostReport]s; shared by expense reports and the Financials tab.
class CostReportBuilder {
  CostReportBuilder({
    required ProjectCostService costs,
    required ScheduleRepository schedule,
  }) : _costs = costs,
       _schedule = schedule;

  final ProjectCostService _costs;
  final ScheduleRepository _schedule;

  Future<CostReport> build(Project project) async {
    final costs = await _costs.costsFor(project.id);
    final categories = await _schedule.getCategories(project.id);
    return CostReport(
      project: project,
      costs: costs,
      categories: [
        for (final c in categories)
          CategoryCost(c, costs.materialsByCategory[c.id] ?? 0),
      ],
      progress: computeProjectProgress(
        project: project,
        categories: categories,
        todos: await _schedule.getTodos(project.id),
      ),
    );
  }
}

/// Accountant's expense reports, one project at a time.
class ExpenseReportsViewModel extends ChangeNotifier {
  ExpenseReportsViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required CostReportBuilder builder,
  }) : _session = session,
       _projects = projects,
       _builder = builder;

  final SessionService _session;
  final ProjectRepository _projects;
  final CostReportBuilder _builder;

  bool _loading = true;
  List<Project> projects = const [];
  int? _projectId;
  CostReport? _report;

  bool get isLoading => _loading;
  int? get projectId => _projectId;
  CostReport? get report => _report;

  Future<void> load() async {
    projects = (await _projects.getProjectsFor(
      _session.user!.id,
      _session.activeRole!,
    )).where((p) => p.status != ProjectStatus.draft).toList();
    _projectId = projects.firstOrNull?.id;
    await _refresh();
  }

  Future<void> setProject(int? id) async {
    _projectId = id;
    await _refresh();
  }

  Future<void> _refresh() async {
    final p = projects.where((x) => x.id == _projectId).firstOrNull;
    _report = p == null ? null : await _builder.build(p);
    _loading = false;
    notifyListeners();
  }
}
