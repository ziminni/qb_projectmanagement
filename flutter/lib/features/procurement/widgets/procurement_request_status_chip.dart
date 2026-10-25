import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/material_request.dart';
import '../../../shared/widgets/app_status_chip.dart';

class ProcurementRequestStatusChip extends StatelessWidget {
  const ProcurementRequestStatusChip({super.key, required this.status});

  final MaterialRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      MaterialRequestStatus.pending => (
        AppColors.info,
        AppColors.infoContainer,
      ),
      MaterialRequestStatus.pendingOwner => (
        AppColors.warning,
        AppColors.warningContainer,
      ),
      MaterialRequestStatus.approved => (
        AppColors.success,
        AppColors.successContainer,
      ),
      MaterialRequestStatus.rejected => (
        AppColors.error,
        AppColors.errorContainer,
      ),
      MaterialRequestStatus.ordered => (
        AppColors.textSecondary,
        AppColors.surfaceMuted,
      ),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
