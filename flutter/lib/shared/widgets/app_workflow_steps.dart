import '../../data/models/daily_report.dart';
import '../../data/models/material_request.dart';
import '../../data/models/payroll_period.dart';
import '../../data/models/progress_billing.dart';
import '../../data/models/variation_order.dart';
import 'app_status_steps.dart';

/// Step indicators for each approval workflow in the design document, so
/// every screen shows the same stages and who acts next.
abstract final class AppWorkflowSteps {
  static AppStatusSteps billing(BillingStatus status) {
    const steps = [
      AppStep('Prepared', who: 'PM'),
      AppStep('Internal approval', who: 'Owner'),
      AppStep('Client approval', who: 'Client'),
      AppStep('Payment', who: 'Accountant'),
    ];
    return switch (status) {
      BillingStatus.draft => const AppStatusSteps(steps: steps, current: 0),
      BillingStatus.pendingOwner => const AppStatusSteps(
        steps: steps,
        current: 1,
      ),
      BillingStatus.pendingClient => const AppStatusSteps(
        steps: steps,
        current: 2,
      ),
      BillingStatus.disputed => const AppStatusSteps(
        steps: steps,
        current: 2,
        stoppedLabel: 'Disputed',
      ),
      BillingStatus.approved => const AppStatusSteps(steps: steps, current: 3),
      BillingStatus.paid => const AppStatusSteps(
        steps: steps,
        current: 3,
        allDone: true,
      ),
      BillingStatus.rejected => const AppStatusSteps(
        steps: steps,
        current: 1,
        stoppedLabel: 'Rejected',
      ),
    };
  }

  static AppStatusSteps variationOrder(VariationOrder vo) {
    const steps = [
      AppStep('Proposed', who: 'Site engineer / PM'),
      AppStep('Internal approval', who: 'Owner'),
      AppStep('Client approval', who: 'Client'),
    ];
    return switch (vo.status) {
      VariationOrderStatus.proposed => const AppStatusSteps(
        steps: steps,
        current: 0,
      ),
      VariationOrderStatus.pendingOwner => const AppStatusSteps(
        steps: steps,
        current: 1,
      ),
      VariationOrderStatus.pendingClient => const AppStatusSteps(
        steps: steps,
        current: 2,
      ),
      VariationOrderStatus.approved => const AppStatusSteps(
        steps: steps,
        current: 2,
        allDone: true,
      ),
      VariationOrderStatus.rejected => AppStatusSteps(
        steps: steps,
        current: vo.approvedByOwner == null ? 1 : 2,
        stoppedLabel: 'Rejected',
      ),
    };
  }

  static AppStatusSteps materialRequest(MaterialRequestStatus status) {
    const steps = [
      AppStep('Requested', who: 'Site engineer'),
      AppStep('Approval', who: 'PM'),
      AppStep('Over-budget approval', who: 'Owner, if needed'),
      AppStep('Purchase orders', who: 'Purchasing'),
    ];
    return switch (status) {
      MaterialRequestStatus.pending => const AppStatusSteps(
        steps: steps,
        current: 1,
      ),
      MaterialRequestStatus.pendingOwner => const AppStatusSteps(
        steps: steps,
        current: 2,
      ),
      MaterialRequestStatus.approved => const AppStatusSteps(
        steps: steps,
        current: 3,
      ),
      MaterialRequestStatus.ordered => const AppStatusSteps(
        steps: steps,
        current: 3,
        allDone: true,
      ),
      MaterialRequestStatus.rejected => const AppStatusSteps(
        steps: steps,
        current: 1,
        stoppedLabel: 'Rejected',
      ),
    };
  }

  static AppStatusSteps dailyReport(DailyReportStatus status) {
    const steps = [
      AppStep('Draft', who: 'Site engineer'),
      AppStep('Review', who: 'PM'),
      AppStep('Approved'),
    ];
    return switch (status) {
      DailyReportStatus.draft => const AppStatusSteps(steps: steps, current: 0),
      DailyReportStatus.submitted => const AppStatusSteps(
        steps: steps,
        current: 1,
      ),
      DailyReportStatus.returned => const AppStatusSteps(
        steps: steps,
        current: 1,
        stoppedLabel: 'Returned',
      ),
      DailyReportStatus.approved => const AppStatusSteps(
        steps: steps,
        current: 2,
        allDone: true,
      ),
    };
  }

  static AppStatusSteps payroll(PayrollStatus status) {
    const steps = [
      AppStep('Attendance', who: 'Site engineer'),
      AppStep('Verify at cut-off', who: 'PM'),
      AppStep('Process pay', who: 'Accountant'),
    ];
    return switch (status) {
      PayrollStatus.open => const AppStatusSteps(steps: steps, current: 1),
      PayrollStatus.verified => const AppStatusSteps(steps: steps, current: 2),
      PayrollStatus.processed => const AppStatusSteps(
        steps: steps,
        current: 2,
        allDone: true,
      ),
    };
  }
}
