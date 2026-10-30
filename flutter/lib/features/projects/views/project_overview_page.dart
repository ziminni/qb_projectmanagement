import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_detail_shell.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_project_status_chip.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/project_overview_viewmodel.dart';
import '../widgets/projects_add_member_dialog.dart';
import '../widgets/projects_progress_card.dart';
import '../widgets/projects_status_dialog.dart';
import '../widgets/projects_team_card.dart';

/// Overview tab: progress bar and S-curve, contract amount, key dates,
/// status and team.
class ProjectOverviewPage extends StatelessWidget {
  const ProjectOverviewPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ProjectOverviewViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        clients: getIt(),
        users: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectOverviewViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final p = vm.project!;
        final progress = vm.progress!;
        final wide = MediaQuery.sizeOf(context).width >= 1000;

        final status = AppSectionCard(
          title: 'Status',
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppProjectStatusChip(status: p.status),
              if (vm.statusOptions.isNotEmpty)
                OutlinedButton(
                  onPressed: vm.isBusy
                      ? null
                      : () => _changeStatus(context, vm),
                  child: const Text('Change status'),
                ),
              if (vm.canEdit)
                TextButton.icon(
                  onPressed: () => context.go(AppRoutes.projectEdit(p.id)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit project'),
                ),
            ],
          ),
        );

        final finance = vm.role.seesFinance;
        final contract = AppSectionCard(
          title: finance ? 'Contract and key dates' : 'Key dates',
          child: Column(
            children: [
              if (finance)
                AppInfoRow(
                  label: 'Contract amount',
                  value: Formatters.peso(p.contractAmount),
                ),
              AppInfoRow(
                label: '% accomplished',
                value: Formatters.percent(progress.progress),
              ),
              if (finance) ...[
                AppInfoRow(
                  label: 'Earned value',
                  value: Formatters.peso(progress.earnedValue),
                ),
                AppInfoRow(
                  label: 'Down payment',
                  value: '${p.downPaymentPct.toStringAsFixed(0)}%',
                ),
                AppInfoRow(
                  label: 'Retention',
                  value: '${p.retentionPct.toStringAsFixed(0)}%',
                ),
              ],
              const Divider(),
              AppInfoRow(label: 'Start', value: Formatters.date(p.startDate)),
              AppInfoRow(
                label: 'Target end',
                value: Formatters.date(p.targetEndDate),
              ),
              if (p.actualEndDate != null)
                AppInfoRow(
                  label: 'Actual end',
                  value: Formatters.date(p.actualEndDate!),
                ),
              if (vm.client != null) ...[
                const Divider(),
                AppInfoRow(label: 'Client', value: vm.client!.name),
                if (vm.client!.contactPerson != null)
                  AppInfoRow(
                    label: 'Contact',
                    value: [
                      vm.client!.contactPerson!,
                      ?vm.client!.phone,
                    ].join(' · '),
                  ),
              ],
            ],
          ),
        );

        final team = ProjectsTeamCard(
          team: vm.team,
          onAdd: vm.canManageTeam ? () => _addMember(context, vm) : null,
          onRemove: vm.canManageTeam
              ? (m) => _removeMember(context, vm, m)
              : null,
        );

        final progressCard = ProjectsProgressCard(
          progress: progress,
          sCurve: vm.sCurve,
          isBehind: vm.isBehind,
        );

        const gap = SizedBox(height: AppSpacing.lg, width: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: wide
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: progressCard),
                      gap,
                      Expanded(
                        flex: 2,
                        child: Column(children: [status, gap, contract]),
                      ),
                    ],
                  ),
                  gap,
                  team,
                ]
              : [progressCard, gap, status, gap, contract, gap, team],
        );
      },
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    ProjectOverviewViewModel vm,
  ) async {
    final next = await ProjectsStatusDialog.show(
      context,
      current: vm.project!.status,
      options: vm.statusOptions,
    );
    if (next == null || !context.mounted) return;
    final ok = await reportAction(
      context,
      vm.changeStatus(next),
      success: 'Status changed to ${next.label}.',
    );
    if (ok && context.mounted) {
      await context.read<ProjectDetailController>().reload();
    }
  }

  Future<void> _addMember(
    BuildContext context,
    ProjectOverviewViewModel vm,
  ) async {
    final result = await ProjectsAddMemberDialog.show(
      context,
      candidatesFor: vm.candidatesFor,
    );
    if (result == null || !context.mounted) return;
    await reportAction(context, vm.addMember(result.userId, result.role));
  }

  Future<void> _removeMember(
    BuildContext context,
    ProjectOverviewViewModel vm,
    TeamMember member,
  ) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Remove from team?',
      message:
          '${member.user?.fullName ?? 'This user'} will lose access to this '
          'project as ${member.assignment.roleOnProject.label}.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok && context.mounted) {
      await reportAction(context, vm.removeMember(member));
    }
  }
}
