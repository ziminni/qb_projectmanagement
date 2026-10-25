import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/daily_report.dart';
import '../../../shared/widgets/app_status_chip.dart';

class DailyReportsStatusChip extends StatelessWidget {
  const DailyReportsStatusChip({super.key, required this.status});

  final DailyReportStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      DailyReportStatus.draft => (
        AppColors.textSecondary,
        AppColors.surfaceMuted,
      ),
      DailyReportStatus.submitted => (AppColors.info, AppColors.infoContainer),
      DailyReportStatus.approved => (
        AppColors.success,
        AppColors.successContainer,
      ),
      DailyReportStatus.returned => (
        AppColors.warning,
        AppColors.warningContainer,
      ),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
