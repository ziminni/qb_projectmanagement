import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../routes/routes.dart';

/// Shortcuts for the site engineer's most frequent jobs on a site.
class ProjectsSiteActions extends StatelessWidget {
  const ProjectsSiteActions({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two per row on phones, four per row when there is room.
        final perRow = constraints.maxWidth >= 640 ? 4 : 2;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;
        Widget action(IconData icon, String label, String path) => SizedBox(
          width: width,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => context.go(path),
            icon: Icon(icon, size: 20),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        );
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            action(
              Icons.edit_note_outlined,
              'Daily report',
              '${AppRoutes.dailyReportNew}?projectId=$projectId',
            ),
            action(
              Icons.checklist_outlined,
              'To-dos',
              AppRoutes.projectTab(projectId, ProjectTab.schedule),
            ),
            action(
              Icons.badge_outlined,
              'Attendance',
              '${AppRoutes.attendance}?projectId=$projectId',
            ),
            action(
              Icons.inventory_2_outlined,
              'Materials',
              '${AppRoutes.materialRequestNew}?projectId=$projectId',
            ),
          ],
        );
      },
    );
  }
}
