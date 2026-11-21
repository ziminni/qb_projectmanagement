import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

class VariationOrdersViewModel extends ChangeNotifier {
  VariationOrdersViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _session = session,
       _projects = projects,
       _billing = billing;

  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;

  bool _loading = true;
  String? _error;
  Map<int, Project> projectsById = const {};
  List<VariationOrder> _allItems = const [];
  VariationOrderStatus? _status;
  int? _projectId;

  bool get isLoading => _loading;
  String? get error => _error;
  VariationOrderStatus? get statusFilter => _status;
  int? get projectFilter => _projectId;

  /// All variation orders in the current project scope (unfiltered by status),
  /// used to compute stable dashboard metrics.
  List<VariationOrder> get scopedItems => _projectId == null
      ? _allItems
      : _allItems.where((v) => v.projectId == _projectId).toList();

  /// Variation orders matching both project and status filters.
  List<VariationOrder> get items => _status == null
      ? scopedItems
      : scopedItems.where((v) => v.status == _status).toList();

  int get totalCount => scopedItems.length;

  int countByStatus(VariationOrderStatus status) =>
      scopedItems.where((v) => v.status == status).length;

  int get awaitingApprovalCount =>
      countByStatus(VariationOrderStatus.proposed) +
      countByStatus(VariationOrderStatus.pendingClient);

  int get approvedCount => countByStatus(VariationOrderStatus.approved);

  double get approvedCostImpact => scopedItems
      .where((v) => v.status == VariationOrderStatus.approved)
      .fold(0.0, (sum, v) => sum + v.amount);

  double get pendingCostImpact => scopedItems
      .where(
        (v) =>
            v.status == VariationOrderStatus.proposed ||
            v.status == VariationOrderStatus.pendingClient,
      )
      .fold(0.0, (sum, v) => sum + v.amount);

  int get approvedDaysImpact => scopedItems
      .where((v) => v.status == VariationOrderStatus.approved)
      .fold(0, (sum, v) => sum + v.daysImpact);

  int get pendingDaysImpact => scopedItems
      .where(
        (v) =>
            v.status == VariationOrderStatus.proposed ||
            v.status == VariationOrderStatus.pendingClient,
      )
      .fold(0, (sum, v) => sum + v.daysImpact);

  int countByType(VariationOrderType type) =>
      scopedItems.where((v) => v.type == type).length;

  double amountByType(VariationOrderType type) => scopedItems
      .where((v) => v.type == type)
      .fold(0.0, (sum, v) => sum + v.amount);

  int daysByType(VariationOrderType type) => scopedItems
      .where((v) => v.type == type)
      .fold(0, (sum, v) => sum + v.daysImpact);

  /// Site engineers propose; PMs prepare.
  bool get canCreate =>
      _session.activeRole == AppRole.owner ||
      _session.activeRole == AppRole.siteEngineer;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final visible = await _projects.getProjectsFor(
        _session.user!.id,
        _session.activeRole!,
      );
      projectsById = {for (final p in visible) p.id: p};
      _allItems = await _billing.getVariationOrders(
        projectIds: projectsById.keys.toList(),
      );
    } catch (e) {
      _error = 'Could not load variation orders. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setStatus(VariationOrderStatus? s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  void setProject(int? projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    notifyListeners();
  }
}
