import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// VOs the owner has approved and sent to the client.
class ClientVariationOrdersViewModel extends ChangeNotifier {
  ClientVariationOrdersViewModel({
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

  bool get isLoading => _loading;
  List<VariationOrder> get items => _items;

  Future<void> load() async {
    final projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    projectsById = {for (final p in projects) p.id: p};
    _items = (await _billing.getVariationOrders(
      projectIds: projectsById.keys.toList(),
    )).where((v) => v.approvedByOwner != null).toList();
    _loading = false;
    notifyListeners();
  }
}
