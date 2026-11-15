import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// Billings sent to the client: ones waiting for approval first.
class ClientBillingsViewModel extends ChangeNotifier {
  ClientBillingsViewModel({
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
  List<ProgressBilling> _items = const [];

  bool get isLoading => _loading;
  List<ProgressBilling> get items => _items;
  List<ProgressBilling> get waiting =>
      _items.where((b) => b.status == BillingStatus.pendingClient).toList();
  List<ProgressBilling> get others =>
      _items.where((b) => b.status != BillingStatus.pendingClient).toList();

  Future<void> load() async {
    final projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    projectsById = {for (final p in projects) p.id: p};
    _items = (await _billing.getBillings(
      projectIds: projectsById.keys.toList(),
    )).where((b) => b.status.isBilled).toList();
    _loading = false;
    notifyListeners();
  }
}
