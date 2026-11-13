import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/project.dart';
import 'app_status_chip.dart';

class AppProjectStatusChip extends StatelessWidget {
  const AppProjectStatusChip({super.key, required this.status});

  final ProjectStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      ProjectStatus.ongoing => (AppColors.info, AppColors.infoContainer),
      ProjectStatus.completed ||
      ProjectStatus.closed => (AppColors.success, AppColors.successContainer),
      ProjectStatus.onHold => (AppColors.warning, AppColors.warningContainer),
      ProjectStatus.changesRequested => (
        AppColors.error,
        AppColors.errorContainer,
      ),
      ProjectStatus.siteEngineerPending || ProjectStatus.requested => (
        AppColors.warning,
        AppColors.warningContainer,
      ),
      ProjectStatus.accepted => (AppColors.primary, AppColors.primaryContainer),
    };
    return AppStatusChip(label: status.label, foreground: fg, background: bg);
  }
}
