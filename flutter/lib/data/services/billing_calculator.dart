import '../models/project.dart';
import 'progress_calculator.dart';

/// Figures for one progress billing.
class BillingComputation {
  const BillingComputation({
    required this.pctAccomplished,
    required this.grossEarned,
    required this.lessPrevious,
    required this.lessDpRecoupment,
    required this.lessRetention,
  });

  /// Cumulative, 0–1.
  final double pctAccomplished;

  /// Cumulative gross earned: % accomplished × contract amount.
  final double grossEarned;

  /// Gross earned on previous billings.
  final double lessPrevious;
  final double lessDpRecoupment;
  final double lessRetention;

  double get thisPeriod => grossEarned - lessPrevious;

  /// Amount earned − previous billings − down payment recoupment −
  /// retention.
  double get netDue => thisPeriod - lessDpRecoupment - lessRetention;
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// Computes a billing from verified progress as of the period end.
///
/// [progress] must come from `computeProjectProgress` with `asOf` set to the
/// period end, so only to-dos verified on or before it count.
BillingComputation computeBilling({
  required Project project,
  required ProjectProgress progress,
  required double previousGross,
}) {
  final gross = _round(progress.progress * project.contractAmount);
  final period = gross - previousGross;
  return BillingComputation(
    pctAccomplished: progress.progress,
    grossEarned: gross,
    lessPrevious: previousGross,
    lessDpRecoupment: _round(period * project.downPaymentPct / 100),
    lessRetention: _round(period * project.retentionPct / 100),
  );
}
