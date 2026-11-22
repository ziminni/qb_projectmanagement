import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/di/service_locator.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
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

  bool _loading = true;
  String? _error;
  bool _assigned = false;
  Project? _project;
  List<Category> _categories = const [];
  List<Todo> _todos = const [];
  List<VariationOrder> _variationOrders = const [];
  int? _selectedVoIndex;
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

  /// Null means "Original"; 0..N-1 means cumulative up to Variation Order i+1.
  int? get selectedVoIndex => _selectedVoIndex;

  VariationOrder? get selectedVariationOrder =>
      _selectedVoIndex != null &&
          _selectedVoIndex! >= 0 &&
          _selectedVoIndex! < _variationOrders.length
      ? _variationOrders[_selectedVoIndex!]
      : null;

  /// Variation orders plotted on the Gantt chart for the active version tab.
  List<VariationOrder> get visibleVariationOrders {
    final idx = _selectedVoIndex;
    if (idx == null || _variationOrders.isEmpty) return const [];
    final end = (idx + 1).clamp(0, _variationOrders.length);
    return _variationOrders.sublist(0, end);
  }

  /// Total schedule day impact of the currently visible variation orders.
  int get cumulativeVoDays =>
      visibleVariationOrders.fold<int>(0, (sum, vo) => sum + vo.daysImpact);

  /// Target end date adjusted by the selected variation order version.
  DateTime get effectiveProjectEnd =>
      _project!.targetEndDate.add(Duration(days: cumulativeVoDays));

  void selectVoVersion(int? index) {
    if (_selectedVoIndex == index) return;
    _selectedVoIndex = index;
    notifyListeners();
  }

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
        if (_selectedVoIndex != null &&
            _selectedVoIndex! >= _variationOrders.length) {
          _selectedVoIndex = null;
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

  String? validateTodoDates(DateTime? start, DateTime? end) =>
      ScheduleRules.validateTodoDates(
        start: start,
        end: end,
        project: _project!,
      );

  String? canDeleteCategory(Category category) =>
      ScheduleRules.canDeleteCategory(
        _todos.where((t) => t.categoryId == category.id).toList(),
      );

  // Actions. Each returns an error message, or null on success.

  Future<String?> addCategory({required String name, double? budget}) {
    final nextOrder =
        _categories.fold(0, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;
    return _run(() async {
      final saved = await _schedule.saveCategory(
        Category(
          id: 0,
          projectId: projectId,
          name: name,
          budget: budget,
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
  }) => _run(() async {
    final saved = await _schedule.saveCategory(
      category.copyWith(name: name, budget: () => budget),
    );
    if (getIt.isRegistered<CategoryCatalogService>()) {
      getIt<CategoryCatalogService>().register(name);
    }
    return saved;
  });

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
