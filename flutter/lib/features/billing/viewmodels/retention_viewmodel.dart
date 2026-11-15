import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../../../data/models/retention_release.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/billing_rules.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_payment_dialog.dart';

class RetentionRow {
  const RetentionRow(this.project, this.held, this.released, this.releases);

  final Project project;
  final double held;
  final double released;
  final List<RetentionRelease> releases;

  double get balance => held - released;

  /// Why retention cannot be released yet, if anything blocks it.
  String? get releaseBlocker => BillingRules.canReleaseRetention(project);
}

/// Retention withheld per project and its release after completion.
class RetentionViewModel extends ChangeNotifier with ActionRunner {
  RetentionViewModel({
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
  List<RetentionRow> _rows = const [];

  bool get isLoading => _loading;
  List<RetentionRow> get rows => _rows;
  bool get canRelease => _session.activeRole == AppRole.accountant;
  double get totalBalance => _rows.fold(0, (s, r) => s + r.balance);

  Future<void> load() async {
    final visible = await _projects.getProjectsFor(
      _session.user!.id,
      _session.activeRole!,
    );
    final releases = await _billing.getRetentionReleases();
    _rows = [
      for (final p in visible)
        if (p.retentionPct > 0)
          await () async {
            final r = await _billing.retentionFor(p.id);
            return RetentionRow(
              p,
              r.held,
              r.released,
              releases.where((x) => x.projectId == p.id).toList(),
            );
          }(),
    ]..sort((a, b) => b.balance.compareTo(a.balance));
    _loading = false;
    notifyListeners();
  }

  String? validateAmount(RetentionRow row, double? amount) =>
      BillingRules.validatePayment(amount, row.balance);

  Future<String?> release(RetentionRow row, AppPaymentInput input) =>
      runAction(() async {
        await _billing.releaseRetention(
          row.project.id,
          amount: input.amount,
          releasedOn: input.paidOn,
          method: input.method,
          referenceNo: input.referenceNo,
          userId: _session.user!.id,
        );
        await load();
      });
}
