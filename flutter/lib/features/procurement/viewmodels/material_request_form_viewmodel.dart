import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/planned_material.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/inventory_calculator.dart';
import '../../../data/services/session_service.dart';
import 'line_draft.dart';
import 'procurement_lookups.dart';

/// One material to count on site before requesting more.
class CountDraft {
  CountDraft(this.line);

  final InventoryLine line;
  double? counted;
}

/// Site engineer's material request.
///
/// First they count every material the system shows on site (forced
/// compliance); then they pick the Item of Work and select materials directly
/// from its DUPA Section C Planned Materials (quantities & units only, never
/// prices), with remaining-quantity guardrails and an optional unplanned item
/// escape hatch requiring a reason.
class MaterialRequestFormViewModel extends ChangeNotifier with ActionRunner {
  MaterialRequestFormViewModel({
    this.initialProjectId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
    ScheduleRepository? schedule,
  }) : _session = session,
       _procurement = procurement,
       _schedule = schedule;

  final int? initialProjectId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ScheduleRepository? _schedule;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  int? _savedId;

  int? projectId;
  int? categoryId;
  DateTime neededBy = DateTime.now().add(const Duration(days: 3));
  List<CountDraft> counts = [];
  List<Category> _categories = const [];
  List<PlannedMaterial> _plannedMaterials = const [];
  final lines = <LineDraft>[LineDraft()];

  bool get isLoading => _loading;
  String? get error => _error;
  int? get savedId => _savedId;
  List<Category> get categories => _categories;
  List<PlannedMaterial> get allPlannedMaterials => _plannedMaterials;
  bool get hasPlannedMaterials => _plannedMaterials.isNotEmpty;

  List<PlannedMaterial> get availablePlannedMaterials {
    if (categoryId == null) return _plannedMaterials;
    return [
      for (final pm in _plannedMaterials)
        if (pm.categoryId == categoryId) pm,
    ];
  }

  int plannedCountForCategory(int catId) =>
      _plannedMaterials.where((pm) => pm.categoryId == catId).length;

  PlannedMaterial? plannedMaterialById(int? id) {
    if (id == null) return null;
    for (final pm in _plannedMaterials) {
      if (pm.id == id) return pm;
    }
    return null;
  }

  /// Remaining planned qty for [pm], subtracting quantities already entered on
  /// other lines of this same draft.
  double remainingFor(PlannedMaterial pm, {LineDraft? excluding}) {
    var otherQty = 0.0;
    for (final l in lines) {
      if (identical(l, excluding)) continue;
      if (l.plannedMaterialId == pm.id) otherQty += l.quantity;
    }
    return pm.remainingQty - otherQty;
  }

  bool isLineOverPlan(LineDraft line) {
    final pm = plannedMaterialById(line.plannedMaterialId);
    if (pm == null || line.quantity <= 0) return false;
    return line.quantity > remainingFor(pm, excluding: line) + 0.0001;
  }

  List<Project> get projectOptions => lookups.projects.values
      .where((p) => p.status == ProjectStatus.ongoing)
      .toList();

  Future<void> load() async {
    try {
      await lookups.load(_session.user!.id, AppRole.siteEngineer);
      if (projectOptions.isEmpty) {
        _error = 'You have no ongoing site to request materials for.';
        return;
      }
      final id = projectOptions.any((p) => p.id == initialProjectId)
          ? initialProjectId
          : (projectOptions.length == 1 ? projectOptions.first.id : null);
      await _loadProjectContext(id);
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProjectContext(int? id) async {
    projectId = id;
    categoryId = null;
    if (id == null) {
      counts = [];
      _categories = const [];
      _plannedMaterials = const [];
      return;
    }
    counts = [
      for (final l in await _procurement.getSiteInventory(id))
        if (l.needsCount) CountDraft(l),
    ];
    if (_schedule != null) {
      try {
        final results = await Future.wait([
          _schedule.getCategories(id),
          _schedule.getPlannedMaterials(id),
        ]);
        _categories = results[0] as List<Category>;
        _plannedMaterials = results[1] as List<PlannedMaterial>;
      } catch (_) {
        _categories = const [];
        _plannedMaterials = const [];
      }
    } else {
      _categories = const [];
      _plannedMaterials = const [];
    }
  }

  Future<void> setProject(int? id) async {
    await _loadProjectContext(id);
    lines
      ..clear()
      ..add(LineDraft());
    notifyListeners();
  }

  void setCategory(int? id) {
    if (categoryId == id) return;
    categoryId = id;
    // Clear planned selections that no longer match the chosen Item of Work.
    if (id != null) {
      for (final l in lines) {
        final pm = plannedMaterialById(l.plannedMaterialId);
        if (pm != null && pm.categoryId != id) {
          l.plannedMaterialId = null;
          l.description = '';
          l.unit = '';
        }
      }
    }
    notifyListeners();
  }

  void selectPlannedMaterial(LineDraft line, PlannedMaterial? pm) {
    if (pm == null) {
      line.plannedMaterialId = null;
      line.description = '';
      line.unit = '';
    } else {
      line.plannedMaterialId = pm.id;
      line.isUnplanned = false;
      line.description = pm.name;
      line.unit = pm.unit;
      if (categoryId == null && pm.categoryId != null) {
        categoryId = pm.categoryId;
      }
    }
    notifyListeners();
  }

  void setNeededBy(DateTime d) {
    neededBy = d;
    notifyListeners();
  }

  void addLine() {
    lines.add(LineDraft());
    notifyListeners();
  }

  void addUnplannedLine() {
    lines.add(LineDraft(isUnplanned: true));
    notifyListeners();
  }

  void removeLine(LineDraft line) {
    lines.remove(line);
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> submit() => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
    if (lines.isEmpty) {
      throw const BusinessRuleException('Add at least one material item.');
    }
    for (final l in lines) {
      if (hasPlannedMaterials && !l.isUnplanned && l.plannedMaterialId == null) {
        throw const BusinessRuleException(
          'Choose a planned material from DUPA (or use "Add unplanned material").',
        );
      }
      if (l.isUnplanned && l.overPlanReason.trim().isEmpty) {
        throw const BusinessRuleException(
          'Enter a reason for requesting an unplanned material not in the DUPA.',
        );
      }
      if (isLineOverPlan(l) && l.overPlanReason.trim().isEmpty) {
        throw BusinessRuleException(
          'Enter a reason for exceeding the DUPA planned quantity on "${l.description}".',
        );
      }
    }

    final request = await _procurement.createRequest(
      MaterialRequestDraft(
        projectId: projectId!,
        categoryId: categoryId,
        neededBy: neededBy,
        items: [for (final l in lines) l.toRequestLine()],
        itemLinks: [for (final l in lines) l.toRequestLineLink()],
        counts: [
          for (final c in counts)
            if (c.counted != null)
              (
                materialId: c.line.materialId,
                name: c.line.name,
                unit: c.line.unit,
                expected: c.line.onHand,
                counted: c.counted!,
              ),
        ],
      ),
      userId: _session.user!.id,
    );
    _savedId = request.id;
  });
}
