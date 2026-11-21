import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/finance_access.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_project_status_chip.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_projects_viewmodel.dart';
import 'admin_dashboard_kit.dart';

/// Portfolio status, deadlines, staffing and site reporting.
class AdminProjectsTab extends StatelessWidget {
  const AdminProjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminProjectsViewModel>(
      create: () => AdminProjectsViewModel(
        projects: getIt(),
        reports: getIt(),
        users: getIt(),
      ),
      build: (context, vm) {
        final finance = canSeeFinance();
        final attention = <Widget>[
          for (final r in vm.overdue)
            AdminListRow(
              icon: Icons.event_busy_outlined,
              iconColor: AppColors.error,
              title: '${r.project.code} · ${r.project.name} is overdue',
              subtitle:
                  'Target end was ${Formatters.date(r.project.targetEndDate)}'
                  ' (${-r.daysLeft} days ago).',
            ),
          for (final r in vm.withoutEngineer)
            AdminListRow(
              icon: Icons.engineering_outlined,
              iconColor: AppColors.warning,
              title: '${r.project.code} has no site engineer',
              subtitle:
                  'Nobody can file daily reports or attendance for '
                  '${r.project.name}.',
            ),
          for (final r in vm.quietSites)
            AdminListRow(
              icon: Icons.edit_off_outlined,
              iconColor: AppColors.warning,
              title: '${r.project.code} has gone quiet',
              subtitle: r.lastReport == null
                  ? 'No daily report has been filed yet.'
                  : 'Last daily report '
                        '${Formatters.date(r.lastReport!)}.',
            ),
        ];
        return [
          AdminStatGrid(
            tiles: [
              DashboardStatTile(
                label: 'Ongoing',
                value: '${vm.countIn(ProjectStage.active)}',
                detail: vm.overdue.isEmpty
                    ? 'All on schedule'
                    : '${vm.overdue.length} past target end',
                icon: Icons.construction_outlined,
                color: vm.overdue.isEmpty ? null : AppColors.error,
              ),
              DashboardStatTile(
                label: 'Setting up',
                value: '${vm.countIn(ProjectStage.pipeline)}',
                detail: 'Waiting on client or engineer',
                icon: Icons.hourglass_top_outlined,
              ),
              DashboardStatTile(
                label: 'Due in ${AdminProjectsViewModel.dueSoonDays} days',
                value: '${vm.dueSoon.length}',
                detail: vm.dueSoon.isEmpty
                    ? 'No deadlines coming up'
                    : 'Next: ${vm.dueSoon.first.project.code}',
                icon: Icons.event_outlined,
                color: vm.dueSoon.isEmpty ? null : AppColors.warning,
              ),
              DashboardStatTile(
                label: finance ? 'Open contract value' : 'Finished',
                value: finance
                    ? Formatters.pesoWhole(vm.openContractValue)
                    : '${vm.countIn(ProjectStage.done)}',
                detail: finance
                    ? '${vm.countIn(ProjectStage.done)} finished projects'
                    : 'Completed or closed',
                icon: finance
                    ? Icons.request_quote_outlined
                    : Icons.task_alt_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminTwoColumn(
            main: [
              AppSectionCard(
                title: 'Needs attention',
                icon: Icons.flag_outlined,
                subtitle: attention.isEmpty
                    ? null
                    : '${attention.length} open items',
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  rows: attention,
                  emptyTitle: 'All projects on track',
                  emptySubtitle:
                      'Nothing overdue, unstaffed or missing reports.',
                ),
              ),
            ],
            side: [
              AppSectionCard(
                title: 'By status',
                icon: Icons.donut_large_outlined,
                child: AdminBreakdownBars(
                  emptyMessage: 'No projects yet.',
                  items: [
                    for (final e in vm.byStatus.entries)
                      AdminBreakdownItem(
                        e.key.label,
                        e.value.toDouble(),
                        color: switch (ProjectStage.of(e.key)) {
                          ProjectStage.active => AppColors.brandGold,
                          ProjectStage.pipeline => AppColors.brandGoldLight,
                          ProjectStage.onHold => AppColors.warning,
                          ProjectStage.done => AppColors.success,
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionCard(
            title: 'Open projects',
            icon: Icons.apartment_outlined,
            subtitle: 'Nearest deadline first. Open a row for details.',
            padding: EdgeInsets.zero,
            child: vm.openProjects.isEmpty
                ? const ListTile(title: Text('No open projects.'))
                : Column(
                    children: [
                      for (final (i, r) in vm.openProjects.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _ProjectRow(row: r, finance: finance),
                      ],
                    ],
                  ),
          ),
        ];
      },
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.row, required this.finance});
  final AdminProjectRow row;
  final bool finance;

  @override
  Widget build(BuildContext context) {
    final p = row.project;
    final textTheme = Theme.of(context).textTheme;
    final due = row.isOverdue
        ? '${-row.daysLeft} days overdue'
        : row.stage == ProjectStage.active
        ? '${row.daysLeft} days left'
        : 'Ends ${Formatters.date(p.targetEndDate)}';
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('${p.code} · ${p.name}'),
      subtitle: Text(
        due,
        style: textTheme.bodySmall?.copyWith(
          color: row.isOverdue ? AppColors.error : null,
        ),
      ),
      trailing: AppProjectStatusChip(status: p.status),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xxl,
          runSpacing: AppSpacing.md,
          children: [
            _Fact('Location', p.location),
            _Fact(
              'Schedule',
              Formatters.dateRange(p.startDate, p.targetEndDate),
            ),
            _Fact(
              'Site engineer',
              row.engineers.isEmpty ? 'None' : row.engineers.join(', '),
            ),
            _Fact(
              'Last daily report',
              row.lastReport == null
                  ? 'None yet'
                  : Formatters.date(row.lastReport!),
            ),
            if (finance) _Fact('Contract', Formatters.peso(p.contractAmount)),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: textTheme.bodyMedium),
      ],
    );
  }
}
