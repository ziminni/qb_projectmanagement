import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/project_rules.dart';
import '../../../data/models/category.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/project_cost_service.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/pdf/pdf_report.dart';

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

  /// Budget vs. actual as a printable expense report.
  PdfReport pdfReport() {
    String peso(double? v) => v == null ? '—' : Formatters.peso(v);
    return PdfReport(
      title: 'Expense report',
      fileName: 'expense-report-${project.code}',
      subtitle: '${project.code} · ${project.name}',
      info: [
        ('Contract amount', peso(project.contractAmount)),
        ('Progress', Formatters.percent(progress.progress)),
        ('Earned value', peso(progress.earnedValue)),
        ('Cost variance', peso(costVariance)),
      ],
      tables: [
        PdfTable(
          title: 'Actual cost',
          headers: const ['Cost', 'Amount'],
          rows: [
            ['Materials', peso(costs.materials)],
            if (costs.storeMaterials != 0)
              ['  of which from our store', peso(costs.storeMaterials)],
            ['Labor', peso(costs.labor)],
            ['Equipment', peso(costs.equipment)],
          ],
          numeric: const {1},
          totals: ['Total', peso(costs.total)],
        ),
        PdfTable(
          title: 'Materials: budget vs. actual by category',
          headers: const ['Category', 'Budget', 'Actual', 'Variance'],
          rows: [
            for (final c in categories)
              [
                c.category.name,
                peso(c.budget),
                peso(c.actual),
                peso(c.variance),
              ],
            if (costs.storeMaterials != 0)
              [
                'Materials from our store',
                '—',
                peso(costs.storeMaterials),
                '—',
              ],
          ],
          numeric: const {1, 2, 3},
          totals: [
            'Total',
            peso(totalBudget),
            peso(costs.materials),
            peso(totalBudget - costs.materials),
          ],
        ),
      ],
      signatures: const ['Prepared by (accountant)', 'Noted by (owner)'],
    );
  }
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
  String? _error;
  List<Project> projects = const [];
  int? _projectId;
  CostReport? _report;

  bool get isLoading => _loading;
  String? get error => _error;
  int? get projectId => _projectId;
  CostReport? get report => _report;

  Future<void> load() async {
    projects =
        (await _projects.getProjectsFor(
              _session.user!.id,
              _session.activeRole!,
            ))
            .where(
              // Projects that have not reached site work have no costs to report.
              (p) =>
                  !ProjectRules.isRequest(p.status) &&
                  p.status != ProjectStatus.accepted,
            )
            .toList();
    _projectId = projects.firstOrNull?.id;
    await _refresh();
  }

  Future<void> setProject(int? id) async {
    _projectId = id;
    await _refresh();
  }

  Future<void> _refresh() async {
    final p = projects.where((x) => x.id == _projectId).firstOrNull;
    _error = null;
    try {
      _report = p == null ? null : await _builder.build(p);
    } on UnsupportedError {
      // Delivered-value costing is blocked in API mode (blocker 1).
      _report = null;
      _error = supplierAccountingUnavailable;
    } on BusinessRuleException catch (e) {
      _report = null;
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
