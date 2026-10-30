import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/session_service.dart';

class VariationOrderDetailViewModel extends ChangeNotifier with ActionRunner {
  VariationOrderDetailViewModel({
    required this.voId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
    required UserRepository users,
  }) : _session = session,
       _projects = projects,
       _billing = billing,
       _users = users;

  final int voId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final UserRepository _users;

  bool _loading = true;
  String? _error;
  VariationOrderDetail? _detail;
  Project? _project;
  bool _isPm = false;
  Map<int, String> _userNames = const {};

  bool get isLoading => _loading;
  String? get error => _error;
  VariationOrderDetail? get detail => _detail;
  VariationOrder? get vo => _detail?.order;
  Project? get project => _project;
  String userName(int id) => _userNames[id] ?? 'User #$id';
  AppRole get role => _session.activeRole!;

  bool get canPrepare => _isPm && vo?.status == VariationOrderStatus.proposed;

  Future<void> load() async {
    try {
      _detail = await _billing.getVariationOrder(voId);
      if (_detail == null) {
        _error = 'Variation order not found.';
        return;
      }
      final visible = await _projects.getProjectsFor(_session.user!.id, role);
      _project = visible.where((p) => p.id == vo!.projectId).firstOrNull;
      if (_project == null) {
        _error = 'You cannot see this variation order.';
        return;
      }
      _isPm =
          role == AppRole.owner &&
          await _projects.isAssigned(
            _project!.id,
            _session.user!.id,
            AppRole.owner,
          );
      _userNames = {for (final u in await _users.getUsers()) u.id: u.fullName};
    } catch (e) {
      _error = 'Could not load the variation order. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> _act(Future<Object?> Function() action) =>
      runAction(() async {
        await action();
        _detail = await _billing.getVariationOrder(voId);
      });

  int get _me => _session.user!.id;

  Future<String?> submit() =>
      _act(() => _billing.submitVariationOrder(voId, userId: _me));

  Future<String?> reject(String reason) =>
      _act(() => _billing.ownerRejectVo(voId, userId: _me, reason: reason));
}
