import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/expense_reports_viewmodel.dart';
import '../viewmodels/project_financials_viewmodel.dart';
import '../widgets/billing_cost_table.dart';
import '../widgets/billing_tile.dart';
import '../widgets/billing_vo_tile.dart';

/// Project "Financials" tab.
class ProjectFinancialsPage extends StatelessWidget {
  const ProjectFinancialsPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ProjectFinancialsViewModel(
        projectId: projectId,
        projects: getIt(),
        billing: getIt(),
        builder: CostReportBuilder(costs: getIt(), schedule: getIt()),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectFinancialsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = vm.report!;
        final p = r.project;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            AppSectionCard(
              title: 'Overview',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xl,
                    runSpacing: AppSpacing.md,
                    children: [
                      AppFigure(
                        label: 'Contract amount',
                        value: Formatters.peso(p.contractAmount),
                      ),
                      AppFigure(
                        label: 'Approved VOs',
                        value: Formatters.peso(vm.approvedVoTotal),
                      ),
                      AppFigure(
                        label: '% accomplished',
                        value: Formatters.percent(r.progress.progress),
                      ),
                      AppFigure(
                        label: 'Earned value',
                        value: Formatters.peso(r.progress.earnedValue),
                      ),
                      AppFigure(
                        label: 'Billed',
                        value: Formatters.peso(vm.summary!.billed),
                      ),
                      AppFigure(
                        label: 'Collected',
                        value: Formatters.peso(vm.summary!.collected),
                      ),
                      AppFigure(
                        label: 'Retention held',
                        value: Formatters.peso(vm.retentionHeld),
                      ),
                      AppFigure(
                        label: 'Actual cost',
                        value: Formatters.peso(r.costs.total),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppProgressBar(
                    value: r.progress.progress,
                    planned: r.progress.plannedProgress,
                    semanticsLabel: 'Accomplishment',
                  ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Budget vs. actual',
              padding: EdgeInsets.zero,
              child: BillingCostTable(report: r),
            ),
            gap,
            AppSectionCard(
              title: 'Progress billings',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.billings.isEmpty)
                    const ListTile(title: Text('No billings yet.')),
                  for (final b in vm.billings)
                    BillingTile(
                      billing: b,
                      projectCode: p.code,
                      onTap: () => context.go(AppRoutes.billing(b.id)),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Payments received',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.payments.isEmpty)
                    const ListTile(title: Text('No payments yet.')),
                  for (final pay in vm.payments)
                    ListTile(
                      title: Text(Formatters.peso(pay.amount)),
                      subtitle: Text(
                        '${Formatters.date(pay.paidOn)} · ${pay.method.label}',
                      ),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Variation orders',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.variationOrders.isEmpty)
                    const ListTile(title: Text('No variation orders.')),
                  for (final v in vm.variationOrders)
                    BillingVoTile(
                      vo: v,
                      projectCode: p.code,
                      onTap: () => context.go(AppRoutes.variationOrder(v.id)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
