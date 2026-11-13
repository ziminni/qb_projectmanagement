import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
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
    ApprovalKind.todoVerification => Icons.fact_check_outlined,
    ApprovalKind.dailyReport => Icons.edit_note_outlined,
    ApprovalKind.materialRequest => Icons.inventory_2_outlined,
    ApprovalKind.payroll => Icons.badge_outlined,
    ApprovalKind.variationOrder => Icons.difference_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: AppRadii.mdAll,
        ),
        child: Icon(iconFor(kind), size: 19, color: AppColors.primary),
      ),
      title: Text(kind.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: const BoxDecoration(
              color: AppColors.accentContainer,
              borderRadius: AppRadii.pillAll,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textDisabled,
          ),
        ],
      ),
    );
  }
}
