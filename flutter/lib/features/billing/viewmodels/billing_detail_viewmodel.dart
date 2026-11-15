import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/client.dart';
import '../../../data/models/company.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/billing_rules.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_payment_dialog.dart';

/// One progress billing: PM submits or withdraws, the owner approves or
/// rejects, the accountant records payments.
class BillingDetailViewModel extends ChangeNotifier with ActionRunner {
  BillingDetailViewModel({
    required this.billingId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
    required ClientRepository clients,
    required CompanyRepository company,
    required UserRepository users,
  }) : _session = session,
       _projects = projects,
       _billing = billing,
       _clients = clients,
       _company = company,
       _users = users;

  final int billingId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final ClientRepository _clients;
  final CompanyRepository _company;
  final UserRepository _users;

  bool _loading = true;
  String? _error;
  BillingDetail? _detail;
  Project? _project;
  Client? _client;
  Company? _companyInfo;
  bool _isPm = false;
  Map<int, String> _userNames = const {};

  bool get isLoading => _loading;
  String? get error => _error;
  BillingDetail? get detail => _detail;
  ProgressBilling? get billing => _detail?.billing;
  Project? get project => _project;
  Client? get client => _client;
  Company? get company => _companyInfo;
  String userName(int id) => _userNames[id] ?? 'User #$id';
  AppRole get role => _session.activeRole!;

  bool get canSubmit =>
      _isPm &&
      (billing?.status == BillingStatus.draft ||
          billing?.status == BillingStatus.disputed);
  bool get canCancel => canSubmit;
  bool get canRecordPayment =>
      role == AppRole.accountant && billing?.status == BillingStatus.approved;

  Future<void> load() async {
    try {
      _detail = await _billing.getBilling(billingId);
      if (_detail == null) {
        _error = 'Billing not found.';
        return;
      }
      final visible = await _projects.getProjectsFor(_session.user!.id, role);
      _project = visible
          .where((p) => p.id == _detail!.billing.projectId)
          .firstOrNull;
      if (_project == null) {
        _error = 'You cannot see this billing.';
        return;
      }
      _client = await _clients.getClient(_project!.clientId);
      _companyInfo = await _company.getCompany();
      _isPm =
          role == AppRole.owner &&
          await _projects.isAssigned(
            _project!.id,
            _session.user!.id,
            AppRole.owner,
          );
      _userNames = {for (final u in await _users.getUsers()) u.id: u.fullName};
    } catch (e) {
      _error = 'Could not load the billing. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> _act(Future<Object?> Function() action) =>
      runAction(() async {
        await action();
        _detail = await _billing.getBilling(billingId);
      });

  int get _me => _session.user!.id;

  Future<String?> submit() =>
      _act(() => _billing.submitBilling(billingId, userId: _me));

  Future<String?> cancel() =>
      _act(() => _billing.cancelBilling(billingId, userId: _me));

  String? validatePayment(double? amount) =>
      BillingRules.validatePayment(amount, _detail!.balance);

  Future<String?> recordPayment(AppPaymentInput input) => _act(
    () => _billing.recordPayment(
      billingId,
      amount: input.amount,
      paidOn: input.paidOn,
      method: input.method,
      referenceNo: input.referenceNo,
      userId: _me,
    ),
  );
}
