import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/progress_billing.dart';
import 'app_status_chip.dart';

class AppBillingStatusChip extends StatelessWidget {
  const AppBillingStatusChip({super.key, required this.status});

  final BillingStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      BillingStatus.draft => (AppColors.textSecondary, AppColors.surfaceMuted),
      BillingStatus.pendingOwner ||
      BillingStatus.pendingClient => (AppColors.info, AppColors.infoContainer),
      BillingStatus.disputed => (AppColors.warning, AppColors.warningContainer),
      BillingStatus.approved => (AppColors.primary, AppColors.primaryContainer),
      BillingStatus.paid => (AppColors.success, AppColors.successContainer),
      BillingStatus.rejected => (AppColors.error, AppColors.errorContainer),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
