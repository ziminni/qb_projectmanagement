import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/company.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';

/// One billing in the client portal: approve or dispute it.
class ClientBillingDetailViewModel extends ChangeNotifier with ActionRunner {
  ClientBillingDetailViewModel({
    required this.billingId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
    required CompanyRepository company,
  }) : _session = session,
       _projects = projects,
       _billing = billing,
       _company = company;

  final int billingId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final CompanyRepository _company;

  bool _loading = true;
  String? _error;
  BillingDetail? _detail;
  Project? _project;
  Company? _companyInfo;

  bool get isLoading => _loading;
  String? get error => _error;
  BillingDetail? get detail => _detail;
  Project? get project => _project;
  Company? get company => _companyInfo;
  bool get canRespond => _detail?.billing.status == BillingStatus.pendingClient;

  /// The client's latest dispute reason, if any.
  String? get disputeReason => _detail?.history
      .where((h) => h.action == 'billing_client_disputed')
      .map((h) => h.details['reason'] as String?)
      .lastOrNull;

  Future<void> load() async {
    _detail = await _billing.getBilling(billingId);
    final mine = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.client,
    );
    _project = mine
        .where((p) => p.id == _detail?.billing.projectId)
        .firstOrNull;
    if (_detail == null ||
        _project == null ||
        !_detail!.billing.status.isBilled) {
      _error = 'Billing not found.';
    } else {
      _companyInfo = await _company.getCompany();
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> approve() => runAction(() async {
    await _billing.clientApprove(billingId, userId: _session.user!.id);
    _detail = await _billing.getBilling(billingId);
  });

  Future<String?> dispute(String reason) => runAction(() async {
    await _billing.clientDispute(
      billingId,
      userId: _session.user!.id,
      reason: reason,
    );
    _detail = await _billing.getBilling(billingId);
  });
}
