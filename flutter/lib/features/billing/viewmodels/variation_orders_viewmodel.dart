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
  Map<int, Project> projectsById = const {};
  List<VariationOrder> _items = const [];
  VariationOrderStatus? _status;

  bool get isLoading => _loading;
  List<VariationOrder> get items => _items;
  VariationOrderStatus? get statusFilter => _status;

  /// Site engineers propose; PMs prepare.
  bool get canCreate =>
      _session.activeRole == AppRole.pm ||
      _session.activeRole == AppRole.siteEngineer;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final visible = await _projects.getProjectsFor(
      _session.user!.id,
      _session.activeRole!,
    );
    projectsById = {for (final p in visible) p.id: p};
    _items = await _billing.getVariationOrders(
      projectIds: projectsById.keys.toList(),
      statuses: _status == null ? null : [_status!],
    );
    _loading = false;
    notifyListeners();
  }

  void setStatus(VariationOrderStatus? s) {
    _status = s;
    load();
  }
}
