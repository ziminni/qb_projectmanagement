import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// Progress billings: PMs see their projects, the owner and accountant see
/// all.
class BillingsViewModel extends ChangeNotifier {
  BillingsViewModel({
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
  BillingStatus? _status;
  BilledSummary? _summary;

  bool get isLoading => _loading;
  List<ProgressBilling> get items => _items;
  BillingStatus? get statusFilter => _status;
  BilledSummary? get summary => _summary;
  bool get canCreate => _session.activeRole == AppRole.owner;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final visible = await _projects.getProjectsFor(
      _session.user!.id,
      _session.activeRole!,
    );
    projectsById = {for (final p in visible) p.id: p};
    final ids = projectsById.keys.toList();
    _items = await _billing.getBillings(
      projectIds: ids,
      statuses: _status == null ? null : [_status!],
    );
    _summary = await _billing.billedSummary(projectIds: ids);
    _loading = false;
    notifyListeners();
  }

  void setStatus(BillingStatus? s) {
    _status = s;
    load();
  }
}
