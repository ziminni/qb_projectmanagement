import 'business_rule_exception.dart';

/// Material and purchasing rules from "Business rules and validations".
abstract final class ProcurementRules {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String? validateQuantity(double? value) =>
      (value == null || value <= 0) ? 'Quantity must be greater than 0.' : null;

  static String? validateNeededBy(DateTime? date, DateTime today) {
    if (date == null) return 'Choose the needed-by date.';
    if (_day(date).isBefore(_day(today))) {
      return 'The needed-by date cannot be in the past.';
    }
    return null;
  }

  static String? validateUnitPrice(double? value) =>
      (value == null || value < 0) ? 'Enter a unit price of 0 or more.' : null;

  /// Quantity received cannot exceed quantity ordered; damaged cannot
  /// exceed received.
  static String? validateReceipt({
    required double ordered,
    required double alreadyReceived,
    required double received,
    required double damaged,
  }) {
    if (received < 0 || damaged < 0) return 'Quantities cannot be negative.';
    if (damaged > received) return 'Damaged cannot exceed received.';
    if (alreadyReceived + received > ordered) {
      final left = ordered - alreadyReceived;
      return 'Only ${_q(left)} left to receive on this line.';
    }
    return null;
  }

  static String? validatePayment(double? amount, double balance) {
    if (amount == null || amount <= 0) return 'Enter an amount greater than 0.';
    if (amount > balance + 0.005) {
      return 'The payment exceeds the unpaid balance of ₱${balance.toStringAsFixed(2)}.';
    }
    return null;
  }

  static String _q(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}

/// A request's cost against its category's remaining budget.
class BudgetCheck {
  const BudgetCheck({
    required this.budget,
    required this.committed,
    required this.requestCost,
  });

  /// Null when the category has no budget yet.
  final double? budget;

  /// Approved and ordered material for the category.
  final double committed;

  /// This request at default unit costs.
  final double requestCost;

  double? get remaining => budget == null ? null : budget! - committed;

  /// A request that exceeds the category's remaining budget needs owner
  /// approval.
  bool get exceedsBudget => remaining != null && requestCost > remaining!;
}
