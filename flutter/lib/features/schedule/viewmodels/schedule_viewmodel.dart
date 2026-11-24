import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/di/service_locator.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/json_utils.dart';
import '../../../data/models/project.dart';
import '../../../data/models/todo.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/category_catalog_service.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/schedule_rules.dart';
import '../../../data/services/session_service.dart';

/// Categories, to-dos and progress for one project.
///
/// Permissions follow the matrix: the PM edits and verifies, the site
/// engineer checks to-dos off, the owner and client view. Clients never see
/// budgets, weights or peso amounts.
class ScheduleViewModel extends ChangeNotifier with ActionRunner {
  ScheduleViewModel({
    required this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required UserRepository users,
    required CompanyRepository company,
    BillingRepository? billing,
  }) : _company = company,
       _session = session,
       _projects = projects,
       _schedule = schedule,
       _users = users,
       _billing = billing;

  final int projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final UserRepository _users;
  final CompanyRepository _company;
  final BillingRepository? _billing;

  static const int plannedVersionKey = -1;
  static const int actualVersionKey = -2;

  bool _loading = true;
  String? _error;
  bool _assigned = false;
  Project? _project;
  List<Category> _categories = const [];
  List<Todo> _todos = const [];
  List<VariationOrder> _variationOrders = const [];
  int _selectedVersionKey = plannedVersionKey;
  ProjectProgress? _progress;
  final _userNames = <int, String>{};
  double _behindThreshold = 0.05;

  bool get isLoading => _loading;

  String? get error => _error;
  Project? get project => _project;
  ProjectProgress? get progress => _progress;
  AppRole get role => _session.activeRole!;

  /// Non-rejected variation orders for this project, oldest first.
  List<VariationOrder> get variationOrders => _variationOrders;

  /// Active Gantt schedule version:
  /// - [plannedVersionKey] (-1): relative `W1, W2, ...` planned bar chart
  /// - [actualVersionKey] (-2): dated timeline starting from `project.timelineStartDate`
  /// - `0..N-1`: cumulative up to Variation Order `i+1`
  int get selectedVersionKey => _selectedVersionKey;

  bool get isRelativePlannedView => _selectedVersionKey == plannedVersionKey;

  bool get hasActualTimeline => _project?.timelineStartDate != null;

  /// True when the Gantt should render relative `W1, W2, ...` headers:
  /// always in `Planned` view, and also in VO views before an actual start
  /// date has been set.
  bool get isGanttRelativeMode =>
      isRelativePlannedView || (!hasActualTimeline && selectedVariationOrder != null);

  DateTime get effectiveProjectStart =>
      _project!.timelineStartDate ?? _project!.startDate;

  VariationOrder? get selectedVariationOrder =>
      _selectedVersionKey >= 0 && _selectedVersionKey < _variationOrders.length
      ? _variationOrders[_selectedVersionKey]
      : null;

  /// Variation orders plotted as standalone VO bars (only for legacy VOs
  /// without a full revised bar chart).
  List<VariationOrder> get visibleVariationOrders {
    final idx = _selectedVersionKey;
    if (idx < 0 || _variationOrders.isEmpty) return const [];
    final selected = selectedVariationOrder;
    if (selected != null && selected.hasRevisedSchedule) return const [];
    final end = (idx + 1).clamp(0, _variationOrders.length);
    return _variationOrders.sublist(0, end);
  }

  /// Project progress snapshot plotted on the Gantt chart: when a VO with a
  /// revised Bar Chart is selected, plots that VO's full revised item timeline.
  ProjectProgress get activeGanttProgress {
    final vo = selectedVariationOrder;
    if (vo == null || !vo.hasRevisedSchedule) return _progress!;
    final baseDate = effectiveProjectStart;
    final revisedCategories = <Category>[];
    var order = 1;
    for (final row in vo.revisedItems) {
      if ('${row['status'] ?? ''}' == 'removed') continue;
      final dayStart = (row['new_day_to_start'] as int?) ?? 1;
      final dur = (row['new_days'] as int?) ?? 1;
      final start = baseDate.add(Duration(days: dayStart - 1));
      final end = start.add(Duration(days: dur - 1));
      final catId = (row['baseline_category_id'] as int?) ?? -order;
      revisedCategories.add(
        Category(
          id: catId,
          projectId: projectId,
          name: '${row['name'] ?? row['item_no'] ?? 'Item $order'}',
          budget: JsonUtils.toDoubleOrNull(row['new_budget']),
          plannedWeeks: row['planned_weeks'] as String?,
          plannedDays: dur,
          dayToStart: dayStart,
          startDate: start,
          endDate: end,
          sortOrder: order++,
        ),
      );
    }
    return computeProjectProgress(
      project: _project!,
      categories: revisedCategories,
      todos: _todos,
    );
  }

  /// Total schedule day impact of the currently visible variation orders.
  int get cumulativeVoDays =>
      visibleVariationOrders.fold<int>(0, (sum, vo) => sum + vo.daysImpact);

  /// Target end date adjusted by the selected variation order version.
  DateTime get effectiveProjectEnd =>
      _project!.targetEndDate.add(Duration(days: cumulativeVoDays));

  void selectScheduleVersion(int? key) {
    if (key == null || _selectedVersionKey == key) return;
    _selectedVersionKey = key;
    notifyListeners();
  }

  Future<String?> startTimeline(DateTime startDate) => runAction(() async {
    _project = await _schedule.startTimeline(projectId, startDate);
    _selectedVersionKey = actualVersionKey;
    await _refresh();
  });

  String voVersionLabel(int index) {
    final vo = _variationOrders[index];
    final sign = vo.daysImpact > 0
        ? '+${vo.daysImpact}d'
        : vo.daysImpact < 0
        ? '${vo.daysImpact}d'
        : '0d';
    final pending = vo.status == VariationOrderStatus.approved
        ? ''
        : ' · ${vo.status.label}';
    return 'Variation Order ${index + 1} ($sign$pending)';
  }

  bool get canView => _assigned;
  bool get canEdit => role == AppRole.owner && _assigned;
  bool get canVerify => role == AppRole.owner && _assigned;
  bool get canMarkDone =>
      _assigned && (role == AppRole.siteEngineer || role == AppRole.owner);
  bool get showCosts => role.seesFinance;

  String? userName(int? id) => id == null ? null : _userNames[id];

  /// Points behind plan (0–1) before the project counts as behind schedule.
  double get behindThreshold => _behindThreshold;

  /// Shown to the PM and owner when budgets fall short of the contract.
  String? get budgetWarning {
    final project = _project;
    if (project == null || !showCosts) return null;
    return ScheduleRules.budgetShortfallWarning(
      categories: _categories,
      contractAmount: project.contractAmount,
    );
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final userId = _session.user!.id;
      _project = await _projects.getProject(projectId);
      if (_project == null) {
        _error = 'Project not found.';
        return;
      }
      _assigned = await _projects.isAssigned(projectId, userId, role);
      if (!canView) {
        _error = 'You are not assigned to this project.';
        return;
      }
      _selectedVersionKey = _project!.timelineStartDate != null
          ? actualVersionKey
          : plannedVersionKey;
      await _refresh();
      _behindThreshold =
          (await _company.getSettings()).behindScheduleThresholdPct / 100;
      for (final user in await _users.getUsers()) {
        _userNames[user.id] = user.fullName;
      }
    } catch (e) {
      _error = 'Could not load the schedule. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    _categories = await _schedule.getCategories(projectId);
    _todos = await _schedule.getTodos(projectId);
    if (_billing != null) {
      try {
        final vos = await _billing.getVariationOrders(projectIds: [projectId]);
        _variationOrders =
            vos
                .where((v) => v.status != VariationOrderStatus.rejected)
                .toList()
              ..sort((a, b) => a.id.compareTo(b.id));
        if (_selectedVersionKey >= 0 &&
            _selectedVersionKey >= _variationOrders.length) {
          _selectedVersionKey = hasActualTimeline
              ? actualVersionKey
              : plannedVersionKey;
        }
      } catch (_) {
        _variationOrders = const [];
      }
    }
    _progress = computeProjectProgress(
      project: _project!,
      categories: _categories,
      todos: _todos,
    );
  }

  // Form validation, shared with the repository through ScheduleRules.

  String? validateBudgetTotal(double? budget, {int? excludingCategoryId}) {
    final others = _categories
        .where((c) => c.id != excludingCategoryId)
        .fold<double>(0, (s, c) => s + (c.budget ?? 0));
    return ScheduleRules.validateBudgetTotal(
      budget: budget,
      otherBudgetsTotal: others,
      contractAmount: _project!.contractAmount,
    );
  }

  String? validateTodoDates(
    DateTime? start,
    DateTime? end, {
    Category? category,
  }) => ScheduleRules.validateTodoDates(
    start: start,
    end: end,
    project: _project!,
    category: category,
  );

  String? canDeleteCategory(Category category) =>
      ScheduleRules.canDeleteCategory(
        _todos.where((t) => t.categoryId == category.id).toList(),
      );

  // Actions. Each returns an error message, or null on success.

  Future<String?> addCategory({
    required String name,
    double? budget,
    String? plannedWeeks,
    int? plannedDays,
  }) {
    final nextOrder =
        _categories.fold(0, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;
    final (startDate, endDate) = _datesForWeeksDays(plannedWeeks, plannedDays);
    return _run(() async {
      final saved = await _schedule.saveCategory(
        Category(
          id: 0,
          projectId: projectId,
          name: name,
          budget: budget,
          plannedWeeks: plannedWeeks,
          plannedDays: plannedDays,
          startDate: startDate,
          endDate: endDate,
          sortOrder: nextOrder,
        ),
      );
      if (getIt.isRegistered<CategoryCatalogService>()) {
        getIt<CategoryCatalogService>().register(name);
      }
      return saved;
    });
  }

  Future<String?> updateCategory(
    Category category, {
    required String name,
    double? budget,
    String? plannedWeeks,
    int? plannedDays,
  }) {
    final (startDate, endDate) = _datesForWeeksDays(plannedWeeks, plannedDays);
    return _run(() async {
      final saved = await _schedule.saveCategory(
        category.copyWith(
          name: name,
          budget: () => budget,
          plannedWeeks: () => plannedWeeks,
          plannedDays: () => plannedDays,
          startDate: () => startDate ?? category.startDate,
          endDate: () => endDate ?? category.endDate,
        ),
      );
      if (getIt.isRegistered<CategoryCatalogService>()) {
        getIt<CategoryCatalogService>().register(name);
      }
      return saved;
    });
  }

  (DateTime?, DateTime?) _datesForWeeksDays(String? weeks, int? days) {
    final base = _project?.startDate;
    if (base == null) return (null, null);
    final hasWeeks = weeks != null && weeks.trim().isNotEmpty;
    if (!hasWeeks && days == null) return (null, null);
    final matches = RegExp(r'\d+')
        .allMatches(weeks ?? '')
        .map((m) => int.parse(m.group(0)!))
        .where((n) => n >= 1)
        .toList();
    final startWeek = matches.isNotEmpty ? matches.first : 1;
    final endWeek = matches.length >= 2 && matches[1] >= startWeek
        ? matches[1]
        : null;
    final start = base.add(Duration(days: (startWeek - 1) * 7));
    final DateTime end;
    if (days != null && days > 0) {
      end = start.add(Duration(days: days - 1));
    } else if (endWeek != null) {
      end = base.add(Duration(days: endWeek * 7 - 1));
    } else {
      end = start.add(const Duration(days: 6));
    }
    return (start, end);
  }

  Future<String?> deleteCategory(Category category) =>
      _run(() => _schedule.deleteCategory(category.id));

  Future<String?> addTodo({
    required int categoryId,
    required String title,
    required DateTime start,
    required DateTime end,
  }) => _run(
    () => _schedule.saveTodo(
      Todo(
        id: 0,
        categoryId: categoryId,
        title: title,
        startDate: start,
        endDate: end,
      ),
    ),
  );

  Future<String?> updateTodo(
    Todo todo, {
    required String title,
    required DateTime start,
    required DateTime end,
  }) => _run(
    () => _schedule.saveTodo(
      todo.copyWith(title: title, startDate: start, endDate: end),
    ),
  );

  Future<String?> deleteTodo(Todo todo) =>
      _run(() => _schedule.deleteTodo(todo.id));

  Future<String?> setDone(Todo todo, bool done) => _run(
    () => _schedule.setDone(todo.id, done: done, userId: _session.user!.id),
  );

  Future<String?> verify(Todo todo) =>
      _run(() => _schedule.verify(todo.id, userId: _session.user!.id));

  Future<String?> unverify(Todo todo, String reason) => _run(
    () =>
        _schedule.unverify(todo.id, userId: _session.user!.id, reason: reason),
  );

  Future<String?> _run(Future<Object?> Function() action) =>
      runAction(() async {
        await action();
        await _refresh();
      });
}
