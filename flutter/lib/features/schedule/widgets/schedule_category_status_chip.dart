import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_status_chip.dart';

class ScheduleCategoryStatusChip extends StatelessWidget {
  const ScheduleCategoryStatusChip({super.key, required this.status});

  final CategoryStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      CategoryStatus.notStarted => (
        AppColors.textSecondary,
        AppColors.surfaceMuted,
      ),
      CategoryStatus.inProgress => (AppColors.info, AppColors.infoContainer),
      CategoryStatus.completed => (
        AppColors.success,
        AppColors.successContainer,
      ),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
