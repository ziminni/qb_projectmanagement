import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/billing_calculator.dart';
import '../../../data/services/billing_rules.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

/// PM generates a billing: accomplishment comes from to-dos verified on or
/// before the period end.
class BillingFormViewModel extends ChangeNotifier with ActionRunner {
  BillingFormViewModel({
    this.initialProjectId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _session = session,
       _projects = projects,
       _billing = billing;

  final int? initialProjectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;

  bool _loading = true;
  String? _error;
  List<Project> _options = const [];
  BillingComputation? _preview;
  String? _previewError;
  int? _savedId;

  int? projectId;
  DateTime periodEnd = DateTime.now();

  bool get isLoading => _loading;
  String? get error => _error;
  List<Project> get projectOptions => _options;
  BillingComputation? get preview => _preview;

  /// Why this billing cannot be created, if a rule blocks it.
  String? get previewError => _previewError;
  int? get savedId => _savedId;
  Project? get project => _options.where((p) => p.id == projectId).firstOrNull;

  Future<void> load() async {
    try {
      if (_session.activeRole != AppRole.owner) {
        _error = 'Progress billings are prepared by the owner.';
        return;
      }
      _options = (await _projects.getProjectsFor(
        _session.user!.id,
        AppRole.owner,
      )).where((p) => BillingRules.requireBillable(p) == null).toList();
      if (_options.isEmpty) {
        _error = 'None of your projects can be billed yet.';
        return;
      }
      projectId = _options.any((p) => p.id == initialProjectId)
          ? initialProjectId
          : _options.first.id;
      await _refreshPreview();
    } catch (e) {
      _error = 'Could not load the billing form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshPreview() async {
    if (projectId == null) return;
    final open = await _billing.getBillings(projectIds: [projectId!]);
    final inProgress = open.where((b) => b.status.inProgress).firstOrNull;
    _preview = await _billing.previewBilling(projectId!, periodEnd);
    final previousEnd = open
        .where((b) => b.status != BillingStatus.rejected)
        .map((b) => b.periodEnd)
        .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
    _previewError = inProgress != null
        ? 'Billing #${inProgress.billingNo} is still ${inProgress.status.label.toLowerCase()}; '
              'it must be paid or rejected first.'
        : BillingRules.validatePeriodEnd(
                periodEnd,
                DateTime.now(),
                previousEnd,
              ) ??
              BillingRules.validateAccomplishment(
                _preview!.pctAccomplished,
                _preview!.thisPeriod,
              );
    notifyListeners();
  }

  Future<void> setProject(int? id) async {
    projectId = id;
    await _refreshPreview();
  }

  Future<void> setPeriodEnd(DateTime d) async {
    periodEnd = d;
    await _refreshPreview();
  }

  Future<String?> create() => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
    final b = await _billing.createBilling(
      projectId!,
      periodEnd,
      userId: _session.user!.id,
    );
    _savedId = b.id;
  });
}
