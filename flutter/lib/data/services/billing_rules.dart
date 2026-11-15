import '../models/project.dart';
import '../models/variation_order.dart';
import 'business_rule_exception.dart';

/// Billing and variation-order rules from "Business rules and validations".
abstract final class BillingRules {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Billings are allowed once a project is Ongoing (and for the final
  /// billing after completion).
  static String? requireBillable(Project p) =>
      p.status == ProjectStatus.ongoing || p.status == ProjectStatus.completed
      ? null
      : 'Billings can be prepared only for Ongoing or Completed projects '
            '(this one is ${p.status.label}).';

  static String? validatePeriodEnd(
    DateTime? periodEnd,
    DateTime today,
    DateTime? previousPeriodEnd,
  ) {
    if (periodEnd == null) return 'Choose the period end date.';
    if (_day(periodEnd).isAfter(_day(today))) {
      return 'The period end cannot be in the future.';
    }
    if (previousPeriodEnd != null &&
        !_day(periodEnd).isAfter(_day(previousPeriodEnd))) {
      return 'The period must end after the previous billing\'s period.';
    }
    return null;
  }

  /// Cumulative accomplishment cannot exceed 100%, and a billing needs new
  /// accomplishment since the last one.
  static String? validateAccomplishment(double pct, double thisPeriod) {
    if (pct > 1.0000001) return 'Cumulative accomplishment cannot exceed 100%.';
    if (thisPeriod <= 0.005) {
      return 'There is no new verified accomplishment since the last billing.';
    }
    return null;
  }

  static String? validatePayment(double? amount, double balance) {
    if (amount == null || amount <= 0) return 'Enter an amount greater than 0.';
    if (amount > balance + 0.005) {
      return 'The payment exceeds the balance of ₱${balance.toStringAsFixed(2)}.';
    }
    return null;
  }

  /// Retention is released only after the project is Completed.
  static String? canReleaseRetention(Project p) =>
      p.status == ProjectStatus.completed || p.status == ProjectStatus.closed
      ? null
      : 'Retention is released only after the project is Completed.';

  static String? validateVoDescription(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Describe the change.' : null;

  /// Signed amount for a VO type: deleted work reduces the contract.
  static double signedAmount(VariationOrderType type, double amount) =>
      type == VariationOrderType.deductive ? -amount.abs() : amount;

  static String? validateVoAmount(VariationOrderType type, double? amount) {
    if (amount == null) return 'Enter the cost impact.';
    if (type != VariationOrderType.change && amount <= 0) {
      return 'Enter an amount greater than 0.';
    }
    return null;
  }

  /// A deductive VO cannot reduce the contract below the total already
  /// billed.
  static String? validateContractAfterVo({
    required double contractAmount,
    required double voAmount,
    required double totalBilled,
  }) => contractAmount + voAmount < totalBilled
      ? 'This would reduce the contract below the ₱${totalBilled.toStringAsFixed(2)} '
            'already billed.'
      : null;

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}
