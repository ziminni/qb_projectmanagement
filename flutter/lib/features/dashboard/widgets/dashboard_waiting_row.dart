import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/approval_inbox.dart';

/// One kind of pending work on the dashboard, opening the inbox filtered to
/// that kind.
class DashboardWaitingRow extends StatelessWidget {
  const DashboardWaitingRow({
    super.key,
    required this.kind,
    required this.count,
    required this.onTap,
  });

  final ApprovalKind kind;
  final int count;
  final VoidCallback onTap;

  static IconData iconFor(ApprovalKind kind) => switch (kind) {
    ApprovalKind.bid => Icons.gavel_outlined,
    ApprovalKind.todoVerification => Icons.fact_check_outlined,
    ApprovalKind.dailyReport => Icons.edit_note_outlined,
    ApprovalKind.materialRequest => Icons.inventory_2_outlined,
    ApprovalKind.purchaseOrder => Icons.shopping_cart_outlined,
    ApprovalKind.payroll => Icons.badge_outlined,
    ApprovalKind.billing => Icons.receipt_long_outlined,
    ApprovalKind.variationOrder => Icons.difference_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(iconFor(kind), color: AppColors.primary),
      title: Text(kind.label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            backgroundColor: AppColors.accent,
            textColor: AppColors.onAccent,
            label: Text('$count'),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
