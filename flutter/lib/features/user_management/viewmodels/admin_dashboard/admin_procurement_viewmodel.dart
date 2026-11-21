import '../../../../data/models/material_request.dart';
import '../../../../data/models/material_source.dart';
import '../../../../data/models/project.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../data/models/user.dart';
import '../../../../data/repositories/procurement_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import 'admin_tab_viewmodel.dart';

/// The Procurement tab: material requests, orders and the store link.
class AdminProcurementViewModel extends AdminTabViewModel {
  AdminProcurementViewModel({
    required ProcurementRepository procurement,
    required ProjectRepository projects,
    required UserRepository users,
    super.now,
  }) : _procurement = procurement,
       _projects = projects,
       _users = users;

  final ProcurementRepository _procurement;
  final ProjectRepository _projects;
  final UserRepository _users;

  /// An own-store order unanswered for this many days counts as stuck.
  static const stuckAfterDays = 2;

  List<MaterialRequest> _requests = const [];
  List<PurchaseOrder> _orders = const [];
  Map<int, Project> _projectsById = const {};
  Map<int, String> _names = const {};

  @override
  String get subject => 'procurement';

  List<MaterialRequest> get pendingRequests =>
      _requests.where((r) => r.status == MaterialRequestStatus.pending).toList()
        ..sort((a, b) => a.neededBy.compareTo(b.neededBy));

  /// Pending requests whose needed-by date has passed.
  int get latePendingCount =>
      pendingRequests.where((r) => r.neededBy.isBefore(today)).length;

  int requestsIn(MaterialRequestStatus s) =>
      _requests.where((r) => r.status == s).length;

  /// Order count per status, own store and other suppliers together.
  Map<PurchaseOrderStatus, int> get ordersByStatus => {
    for (final s in PurchaseOrderStatus.values)
      if (_orders.any((o) => o.status == s))
        s: _orders.where((o) => o.status == s).length,
  };

  int get awaitingDelivery =>
      _orders.where((o) => o.status.awaitsDelivery).length;

  List<PurchaseOrder> get _live =>
      _orders.where((o) => o.status != PurchaseOrderStatus.cancelled).toList();

  /// Non-cancelled order value per source in the last 30 days.
  Map<MaterialSource, double> get spendLast30Days {
    final since = today.subtract(const Duration(days: 30));
    final out = <MaterialSource, double>{};
    for (final o in _live) {
      final at = o.createdAt;
      if (at == null || at.isBefore(since)) continue;
      out[o.source] = (out[o.source] ?? 0) + o.totalAmount;
    }
    return out;
  }

  /// Order count per source, cancelled orders left out.
  Map<MaterialSource, int> get ordersBySource => {
    for (final s in MaterialSource.values)
      s: _live.where((o) => o.source == s).length,
  };

  /// Own-store orders the store declined.
  List<PurchaseOrder> get declinedByStore => _orders
      .where(
        (o) =>
            o.source == MaterialSource.ownStore &&
            o.storeStatus?.trim().toUpperCase() == 'DECLINED',
      )
      .toList();

  /// Own-store orders the store has not answered after [stuckAfterDays].
  List<PurchaseOrder> get unansweredByStore => _orders.where((o) {
    if (o.source != MaterialSource.ownStore) return false;
    if (o.status != PurchaseOrderStatus.released) return false;
    final store = o.storeStatus?.trim().toUpperCase();
    if (store != null && store.isNotEmpty) return false;
    final sent = o.createdAt;
    return sent != null && today.difference(sent).inDays >= stuckAfterDays;
  }).toList();

  /// Orders still expecting delivery, oldest first.
  List<PurchaseOrder> get openOrders =>
      _orders.where((o) => o.status.awaitsDelivery).toList()..sort(
        (a, b) => (a.createdAt ?? today).compareTo(b.createdAt ?? today),
      );

  String projectLabel(int id) {
    final p = _projectsById[id];
    return p == null ? 'Project #$id' : '${p.code} · ${p.name}';
  }

  String userName(int id) => _names[id] ?? 'User #$id';

  @override
  Future<void> fetch() async {
    final (requests, orders, projects, users) = await (
      _procurement.getRequests(),
      _procurement.getPurchaseOrders(),
      _projects.getProjects(),
      _users.getUsers(),
    ).wait;
    _requests = requests;
    _orders = orders;
    _projectsById = {for (final p in projects) p.id: p};
    _names = {for (final User u in users) u.id: u.fullName};
  }
}
