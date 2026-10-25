import '../models/payment.dart';
import '../models/payment_method.dart';
import '../models/progress_billing.dart';
import '../models/variation_order.dart';

/// Seed billings, payments and VOs. Billing figures follow
/// `computeBilling` from the seeded to-do verification dates.
abstract final class MockBillingData {
  static final billings = [
    // Project 1 as of Sep 15: Foundation 100% (25%) + Pillars 1/5 (4%) = 29%.
    ProgressBilling(
      id: 1,
      projectId: 1,
      billingNo: 1,
      periodEnd: DateTime(2026, 9, 15),
      pctAccomplished: 0.29,
      grossEarned: 580000,
      lessPrevious: 0,
      lessDpRecoupment: 87000,
      lessRetention: 58000,
      netDue: 435000,
      status: BillingStatus.paid,
      createdAt: DateTime(2026, 9, 16),
    ),
    // Project 2 as of Oct 15, equal weights: (100% + 33.3% + 0 + 0) ÷ 4.
    ProgressBilling(
      id: 2,
      projectId: 2,
      billingNo: 1,
      periodEnd: DateTime(2026, 10, 15),
      pctAccomplished: 1 / 3,
      grossEarned: 1166666.67,
      lessPrevious: 0,
      lessDpRecoupment: 233333.33,
      lessRetention: 116666.67,
      netDue: 816666.67,
      status: BillingStatus.pendingOwner,
      createdAt: DateTime(2026, 10, 16),
    ),
  ];

  static final payments = [
    Payment(
      id: 1,
      progressBillingId: 1,
      amount: 435000,
      paidOn: DateTime(2026, 9, 30),
      method: PaymentMethod.bankTransfer,
      referenceNo: 'BDO-0930-7781',
    ),
  ];

  static final variationOrders = [
    VariationOrder(
      id: 1,
      projectId: 1,
      voNo: 'VO-01',
      type: VariationOrderType.additive,
      description: 'Additional perimeter fence along the rear lot line (18 m).',
      amount: 85000,
      daysImpact: 5,
      status: VariationOrderStatus.pendingClient,
      approvedByOwner: 2,
      createdAt: DateTime(2026, 10, 14),
    ),
    VariationOrder(
      id: 2,
      projectId: 1,
      voNo: 'VO-02',
      type: VariationOrderType.deductive,
      description: 'Delete the ceiling cove lighting in the living room.',
      amount: -18000,
      daysImpact: 0,
      status: VariationOrderStatus.proposed,
      createdAt: DateTime(2026, 10, 23),
    ),
    VariationOrder(
      id: 3,
      projectId: 2,
      voNo: 'VO-01',
      type: VariationOrderType.change,
      description: 'Change roof sheets from 0.4 mm to 0.5 mm gauge.',
      amount: 62000,
      daysImpact: 0,
      status: VariationOrderStatus.pendingOwner,
      createdAt: DateTime(2026, 10, 20),
    ),
  ];
}
