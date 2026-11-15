import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

class ClientVariationOrderDetailViewModel extends ChangeNotifier
    with ActionRunner {
  ClientVariationOrderDetailViewModel({
    required this.voId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _session = session,
       _projects = projects,
       _billing = billing;

  final int voId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;

  bool _loading = true;
  String? _error;
  VariationOrder? _vo;
  Project? _project;

  bool get isLoading => _loading;
  String? get error => _error;
  VariationOrder? get vo => _vo;
  Project? get project => _project;
  bool get canRespond => _vo?.status == VariationOrderStatus.pendingClient;

  Future<void> load() async {
    _vo = (await _billing.getVariationOrder(voId))?.order;
    final mine = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    _project = mine.where((p) => p.id == _vo?.projectId).firstOrNull;
    if (_vo == null || _project == null || _vo!.approvedByOwner == null) {
      _error = 'Variation order not found.';
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _refresh() async {
    _vo = (await _billing.getVariationOrder(voId))?.order;
    _project = await _projects.getProject(_project!.id);
  }

  Future<String?> approve() => runAction(() async {
    await _billing.clientApproveVo(voId, userId: _session.user!.id);
    await _refresh();
  });

  Future<String?> reject(String reason) => runAction(() async {
    await _billing.clientRejectVo(
      voId,
      userId: _session.user!.id,
      reason: reason,
    );
    await _refresh();
  });
}
