import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/procurement_repository.dart';
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

/// Site engineer's material request. First they count every material the
/// system shows on site (forced compliance); then they type each item and
/// its quantity. The owner picks the actual materials and budget category.
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
  int? _savedId;

  int? projectId;
  DateTime neededBy = DateTime.now().add(const Duration(days: 3));
  List<CountDraft> counts = [];
  final lines = <LineDraft>[LineDraft()];

  bool get isLoading => _loading;
  String? get error => _error;
  int? get savedId => _savedId;

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
      await _loadCounts(id);
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCounts(int? id) async {
    projectId = id;
    counts = id == null
        ? []
        : [
            for (final l in await _procurement.getSiteInventory(id))
              if (l.needsCount) CountDraft(l),
          ];
  }

  Future<void> setProject(int? id) async {
    await _loadCounts(id);
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

  void removeLine(LineDraft line) {
    lines.remove(line);
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> submit() => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
    final request = await _procurement.createRequest(
      MaterialRequestDraft(
        projectId: projectId!,
        neededBy: neededBy,
        items: [for (final l in lines) l.toRequestLine()],
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
