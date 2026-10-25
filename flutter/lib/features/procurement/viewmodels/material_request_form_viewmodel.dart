import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_quantity_rows_editor.dart';
import 'procurement_lookups.dart';

/// Site engineer's material request: item, quantity, needed-by date, with a
/// live check against the category's remaining budget.
class MaterialRequestFormViewModel extends ChangeNotifier with ActionRunner {
  MaterialRequestFormViewModel({
    this.initialProjectId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int? initialProjectId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  BudgetCheck? _budget;
  int? _savedId;

  int? projectId;
  int? categoryId;
  DateTime neededBy = DateTime.now().add(const Duration(days: 3));
  final rows = <AppQuantityRow>[AppQuantityRow()];

  bool get isLoading => _loading;
  String? get error => _error;
  BudgetCheck? get budget => _budget;
  int? get savedId => _savedId;

  List<Project> get projectOptions => lookups.projects.values
      .where((p) => p.status == ProjectStatus.ongoing)
      .toList();

  List<Category> get categoryOptions =>
      lookups.categories.values.where((c) => c.projectId == projectId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<void> load() async {
    try {
      await lookups.load(_session.user!.id, AppRole.siteEngineer);
      if (projectOptions.isEmpty) {
        _error = 'You have no ongoing site to request materials for.';
        return;
      }
      projectId = projectOptions.any((p) => p.id == initialProjectId)
          ? initialProjectId
          : (projectOptions.length == 1 ? projectOptions.first.id : null);
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setProject(int? id) {
    projectId = id;
    categoryId = null;
    _budget = null;
    notifyListeners();
  }

  void setCategory(int? id) {
    categoryId = id;
    refreshBudget();
  }

  void setNeededBy(DateTime d) {
    neededBy = d;
    notifyListeners();
  }

  List<({int materialId, double quantity})> get _items => [
    for (final r in rows)
      if (r.itemId != null && r.quantity > 0)
        (materialId: r.itemId!, quantity: r.quantity),
  ];

  /// Recomputes the budget check after a row or category change.
  Future<void> refreshBudget() async {
    if (categoryId == null) {
      _budget = null;
    } else {
      _budget = await _procurement.checkBudget(categoryId!, _items);
    }
    notifyListeners();
  }

  Future<String?> submit() => runAction(() async {
    if (projectId == null || categoryId == null) {
      throw const BusinessRuleException('Choose the project and category.');
    }
    if (rows.any((r) => r.itemId == null)) {
      throw const BusinessRuleException('Choose a material for every row.');
    }
    final request = await _procurement.createRequest(
      MaterialRequestDraft(
        projectId: projectId!,
        categoryId: categoryId!,
        neededBy: neededBy,
        items: _items,
      ),
      userId: _session.user!.id,
    );
    _savedId = request.id;
  });
}
