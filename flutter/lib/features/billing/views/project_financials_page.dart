import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_budget_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/expense_reports_viewmodel.dart';
import '../viewmodels/project_financials_viewmodel.dart';
import '../widgets/store_balance_card.dart';
import '../widgets/billing_cost_table.dart';
import '../widgets/billing_tile.dart';
import '../widgets/billing_vo_tile.dart';

/// Project "Financials" tab.
class ProjectFinancialsPage extends StatelessWidget {
  const ProjectFinancialsPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    if (getIt.isRegistered<SessionService>() &&
        getIt<SessionService>().isSignedIn &&
        !canSeeFinance()) {
      return const AppEmptyState(
        icon: Icons.lock_outline,
        message: 'Project financials are available only to finance roles.',
      );
    }

    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ProjectFinancialsViewModel(
        projectId: projectId,
        projects: getIt(),
        billing: getIt(),
        builder: CostReportBuilder(costs: getIt(), schedule: getIt()),
        procurement: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectFinancialsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final r = vm.report;
        final p = vm.project!;
        final approvedVoCount = vm.variationOrders
            .where((v) => v.status == VariationOrderStatus.approved)
            .length;
        final billed = vm.summary?.billed ?? 0;
        final collected = vm.summary?.collected ?? 0;
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
                        detail: 'Base contract',
                      ),
                      AppFigure(
                        label: 'Approved VOs',
                        value: Formatters.peso(vm.approvedVoTotal),
                        detail: '$approvedVoCount approved',
                      ),
                      if (r != null) ...[
                        AppFigure(
                          label: '% accomplished',
                          value: Formatters.percent(r.progress.progress),
                          detail:
                              'Planned ${Formatters.percent(r.progress.plannedProgress)}',
                        ),
                        AppFigure(
                          label: 'Earned value',
                          value: Formatters.peso(r.progress.earnedValue),
                          detail:
                              'of ${Formatters.pesoWhole(p.contractAmount)} contract',
                        ),
                      ],
                      AppFigure(
                        label: 'Billed',
                        value: Formatters.peso(billed),
                        detail: p.contractAmount > 0
                            ? '${Formatters.percent(billed / p.contractAmount)} of contract'
                            : null,
                      ),
                      AppFigure(
                        label: 'Collected',
                        value: Formatters.peso(collected),
                        detail: billed > 0
                            ? '${Formatters.percent(collected / billed)} of billed'
                            : null,
                      ),
                      AppFigure(
                        label: 'Retention held',
                        value: Formatters.peso(vm.retentionHeld),
                        detail: '${p.retentionPct.toStringAsFixed(0)}% retention',
                      ),
                      if (r != null)
                        AppFigure(
                          label: 'Actual cost',
                          value: Formatters.peso(r.costs.total),
                          detail: r.costVariance >= 0
                              ? 'Under earned by ${Formatters.pesoWhole(r.costVariance)}'
                              : 'Over earned by ${Formatters.pesoWhole(r.costVariance.abs())}',
                          valueColor: r.costVariance < 0
                              ? AppColors.error
                              : null,
                        ),
                    ],
                  ),
                  if (r != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textTheme = Theme.of(context).textTheme;
                        final accomplishmentBar = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xxs,
                              children: [
                                Text(
                                  'Schedule accomplishment',
                                  style: textTheme.labelMedium,
                                ),
                                Text(
                                  '${Formatters.percent(r.progress.progress)} actual · '
                                  '${Formatters.percent(r.progress.plannedProgress)} planned',
                                  style: textTheme.bodySmall?.merge(
                                    AppTextStyles.numeric,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppProgressBar(
                              value: r.progress.progress,
                              planned: r.progress.plannedProgress,
                              semanticsLabel: 'Accomplishment',
                            ),
                          ],
                        );
                        final budgetBar = AppBudgetBar(
                          label: 'Material budget used',
                          budget: r.totalBudget,
                          actual: r.costs.materials,
                          showAmounts: true,
                        );
                        if (constraints.maxWidth >= 640) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: accomplishmentBar),
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(child: budgetBar),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accomplishmentBar,
                            const SizedBox(height: AppSpacing.md),
                            budgetBar,
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (vm.storeBalance != null || vm.storeBalanceError != null) ...[
              gap,
              StoreBalanceCard(
                balance: vm.storeBalance,
                error: vm.storeBalanceError,
                receipts: vm.storeReceipts,
                onSubmitReceipt: canManageFinance()
                    ? vm.submitStorePaymentReceipt
                    : null,
              ),
            ],
            gap,
            AppSectionCard(
              title: 'Budget vs. actual',
              padding: EdgeInsets.zero,
              // Derived costs (materials, payroll, equipment) have no route
              // yet: the billing half of the tab still shows.
              child: r == null
                  ? ListTile(
                      title: Text(
                        vm.costsError ?? supplierAccountingUnavailable,
                      ),
                    )
                  : BillingCostTable(report: r),
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
                      title: Text(
                        Formatters.peso(pay.amount),
                        style: Theme.of(context).textTheme.titleSmall?.merge(
                          AppTextStyles.numeric,
                        ),
                      ),
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
