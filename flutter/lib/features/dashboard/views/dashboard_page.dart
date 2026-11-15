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
import '../widgets/dashboard_hero.dart';
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
        void openProject(int id) =>
            context.go(AppRoutes.projectTab(id, ProjectTab.overview));
        final waiting = vm.pendingTotal;
        final seesFinance = vm.role.seesFinance;

        final tiles = [
          DashboardStatTile(
            label: 'Active projects',
            value: '${vm.active.length}',
            detail: '${vm.projects.length} in total',
            icon: Icons.apartment_rounded,
            onTap: () => context.go(AppRoutes.projects),
          ),
          DashboardStatTile(
            label: 'Pending approvals',
            value: '$waiting',
            detail: waiting == 0 ? 'All clear' : 'Open inbox',
            icon: Icons.inbox_rounded,
            color: waiting == 0 ? AppColors.success : AppColors.accent,
            onTap: () => context.go(AppRoutes.approvals),
          ),
          DashboardStatTile(
            label: 'Behind schedule',
            value: '${vm.behind.length}',
            detail: 'Past the threshold in Settings',
            icon: Icons.warning_amber_rounded,
            color: vm.behind.isEmpty ? AppColors.success : AppColors.warning,
          ),
          if (seesFinance && vm.billed != null)
            DashboardStatTile(
              label: 'Billed vs. collected',
              value: Formatters.pesoWhole(vm.billed!.collected),
              detail:
                  'collected of ${Formatters.pesoWhole(vm.billed!.billed)} billed',
              icon: Icons.receipt_long_rounded,
              color: AppColors.info,
              progress: vm.billed!.billed > 0
                  ? vm.billed!.collected / vm.billed!.billed
                  : 0,
              onTap: () => context.go(AppRoutes.billings),
            ),
          if (seesFinance)
            DashboardStatTile(
              label: 'Earned value (active)',
              value: Formatters.pesoWhole(vm.activeEarnedValue),
              detail:
                  'of ${Formatters.pesoWhole(vm.activeContractValue)} '
                  'contract value',
              icon: Icons.trending_up_rounded,
              color: AppColors.success,
              progress: vm.activeContractValue > 0
                  ? vm.activeEarnedValue / vm.activeContractValue
                  : 0,
            ),
        ];

        final projects = AppSectionCard(
          title: 'My projects',
          subtitle: 'Progress against plan',
          icon: Icons.apartment_rounded,
          padding: EdgeInsets.zero,
          trailing: TextButton(
            onPressed: () => context.go(AppRoutes.projects),
            child: const Text('View all'),
          ),
          child: Column(
            children: [
              if (vm.projects.isEmpty)
                const AppEmptyState(
                  message: 'No projects yet.',
                  icon: Icons.apartment_rounded,
                ),
              for (final (i, p) in vm.projects.indexed) ...[
                if (i > 0) const Divider(height: 1),
                DashboardProjectRow(
                  item: p,
                  onTap: () => openProject(p.project.id),
                ),
              ],
            ],
          ),
        );

        final waitingCard = AppSectionCard(
          title: 'Waiting for you',
          icon: Icons.inbox_rounded,
          padding: EdgeInsets.zero,
          child: vm.pendingByKind.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nothing needs your approval.'),
                )
              : Column(
                  children: [
                    for (final e in vm.pendingByKind.entries)
                      DashboardWaitingRow(
                        kind: e.key,
                        count: e.value,
                        onTap: () => context.go(
                          '${AppRoutes.approvals}?kind=${e.key.name}',
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
        );

        final behindCard = vm.behind.isEmpty
            ? null
            : AppSectionCard(
                title: 'Behind schedule',
                icon: Icons.warning_amber_rounded,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, p) in vm.behind.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      DashboardProjectRow(
                        item: p,
                        onTap: () => openProject(p.project.id),
                      ),
                    ],
                  ],
                ),
              );

        const gap = SizedBox(height: AppSpacing.lg, width: AppSpacing.lg);
        return RefreshIndicator(
          onRefresh: vm.load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pad = pagePadding(context);
              final width = constraints.maxWidth - pad.horizontal;
              final columns = (width / 210).floor().clamp(1, tiles.length);
              final tileWidth =
                  (width - AppSpacing.lg * (columns - 1)) / columns;
              final wide = width >= 900;
              return ListView(
                padding: pad.copyWith(top: AppSpacing.xl),
                children: [
                  DashboardHero(
                    greeting: 'Good day, ${vm.firstName}',
                    summary:
                        '${vm.active.length} active project'
                        '${vm.active.length == 1 ? '' : 's'} · '
                        '${waiting == 0 ? 'nothing waiting for you' : '$waiting item${waiting == 1 ? '' : 's'} waiting for you'}',
                    actions: [
                      (
                        Icons.add_rounded,
                        'New project',
                        () => context.go(AppRoutes.projectNew),
                      ),
                      (
                        Icons.fact_check_outlined,
                        'Verify to-dos',
                        () => context.go(AppRoutes.todoVerification),
                      ),
                      if (seesFinance)
                        (
                          Icons.receipt_long_outlined,
                          'New billing',
                          () => context.go(AppRoutes.billingNew),
                        ),
                      (
                        Icons.difference_outlined,
                        'Raise a VO',
                        () => context.go(AppRoutes.variationOrderNew),
                      ),
                      if (seesFinance)
                        (
                          Icons.summarize_outlined,
                          'Expense reports',
                          () => context.go(AppRoutes.expenseReports),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final t in tiles)
                        SizedBox(width: tileWidth, child: t),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: projects),
                        gap,
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              waitingCard,
                              if (behindCard != null) ...[gap, behindCard],
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    waitingCard,
                    if (behindCard != null) ...[gap, behindCard],
                    gap,
                    projects,
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}
