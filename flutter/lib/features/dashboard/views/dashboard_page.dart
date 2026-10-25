import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../widgets/dashboard_project_row.dart';
import '../widgets/dashboard_stat_tile.dart';
import '../widgets/dashboard_waiting_row.dart';

/// Company dashboard for the owner; "My projects" dashboard for PMs.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardViewModel(
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        company: getIt(),
        inbox: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<DashboardViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final textTheme = Theme.of(context).textTheme;
        void openProject(int id) =>
            context.go(AppRoutes.projectTab(id, ProjectTab.overview));

        return RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: pagePadding(context),
            children: [
              Text(
                vm.isOwner ? 'Company overview' : 'Good day, ${vm.firstName}',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (vm.isOwner) ...[
                    _action(
                      context,
                      Icons.add,
                      'New project',
                      AppRoutes.projectNew,
                    ),
                    _action(
                      context,
                      Icons.summarize_outlined,
                      'Expense reports',
                      AppRoutes.expenseReports,
                    ),
                  ] else ...[
                    _action(
                      context,
                      Icons.fact_check_outlined,
                      'Verify to-dos',
                      AppRoutes.todoVerification,
                    ),
                    _action(
                      context,
                      Icons.receipt_long_outlined,
                      'New billing',
                      AppRoutes.billingNew,
                    ),
                    _action(
                      context,
                      Icons.difference_outlined,
                      'Raise a VO',
                      AppRoutes.variationOrderNew,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  DashboardStatTile(
                    label: vm.isOwner
                        ? 'Active projects'
                        : 'My active projects',
                    value: '${vm.active.length}',
                    detail: '${vm.projects.length} in total',
                    icon: Icons.apartment_outlined,
                    onTap: () => context.go(AppRoutes.projects),
                  ),
                  DashboardStatTile(
                    label: 'Behind schedule',
                    value: '${vm.behind.length}',
                    detail: 'Past the threshold in Settings',
                    icon: Icons.warning_amber_rounded,
                    color: vm.behind.isEmpty ? null : AppColors.warning,
                  ),
                  DashboardStatTile(
                    label: 'Pending approvals',
                    value: '${vm.pendingTotal}',
                    detail: vm.pendingTotal == 0 ? 'All clear' : 'Open inbox',
                    icon: Icons.inbox_outlined,
                    onTap: () => context.go(AppRoutes.approvals),
                  ),
                  if (vm.billed != null)
                    DashboardStatTile(
                      label: 'Billed vs. collected',
                      value: Formatters.pesoWhole(vm.billed!.collected),
                      detail:
                          'collected of ${Formatters.pesoWhole(vm.billed!.billed)} billed',
                      icon: Icons.receipt_long_outlined,
                      onTap: () => context.go(AppRoutes.billings),
                    ),
                  DashboardStatTile(
                    label: 'Earned value (active)',
                    value: Formatters.pesoWhole(vm.activeEarnedValue),
                    detail:
                        'of ${Formatters.pesoWhole(vm.activeContractValue)} '
                        'contract value',
                    icon: Icons.trending_up,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (vm.behind.isNotEmpty) ...[
                AppSectionCard(
                  title: 'Behind schedule',
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final p in vm.behind)
                        DashboardProjectRow(
                          item: p,
                          onTap: () => openProject(p.project.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (vm.pendingByKind.isNotEmpty) ...[
                AppSectionCard(
                  title: 'Waiting for you',
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final e in vm.pendingByKind.entries)
                        DashboardWaitingRow(
                          kind: e.key,
                          count: e.value,
                          onTap: () => context.go(
                            '${AppRoutes.approvals}?kind=${e.key.name}',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              AppSectionCard(
                title: vm.isOwner ? 'All projects' : 'My projects',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (vm.projects.isEmpty)
                      const ListTile(title: Text('No projects yet.')),
                    for (final (i, p) in vm.projects.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      DashboardProjectRow(
                        item: p,
                        onTap: () => openProject(p.project.id),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    String path,
  ) => OutlinedButton.icon(
    onPressed: () => context.go(path),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}
