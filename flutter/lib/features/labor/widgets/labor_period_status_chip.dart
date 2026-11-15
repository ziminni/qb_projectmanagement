import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/payroll_period.dart';
import '../../../shared/widgets/app_status_chip.dart';

class LaborPeriodStatusChip extends StatelessWidget {
  const LaborPeriodStatusChip({super.key, required this.status});

  final PayrollStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      PayrollStatus.open => (AppColors.info, AppColors.infoContainer),
      PayrollStatus.verified => (AppColors.warning, AppColors.warningContainer),
      PayrollStatus.processed => (
        AppColors.success,
        AppColors.successContainer,
      ),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
