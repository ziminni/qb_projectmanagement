import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/variation_order.dart';
import 'app_status_chip.dart';

class AppVoStatusChip extends StatelessWidget {
  const AppVoStatusChip({super.key, required this.status});

  final VariationOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      VariationOrderStatus.proposed => (
        AppColors.textSecondary,
        AppColors.surfaceMuted,
      ),
      VariationOrderStatus.pendingClient => (
        AppColors.info,
        AppColors.infoContainer,
      ),
      VariationOrderStatus.approved => (
        AppColors.success,
        AppColors.successContainer,
      ),
      VariationOrderStatus.rejected => (
        AppColors.error,
        AppColors.errorContainer,
      ),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
