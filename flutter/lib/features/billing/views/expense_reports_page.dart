import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_budget_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_pdf_button.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/expense_reports_viewmodel.dart';
import '../widgets/billing_cost_table.dart';

/// Project expense report: actual cost by source, budget vs. actual, and
/// cost vs. earned value.
class ExpenseReportsPage extends StatelessWidget {
  const ExpenseReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (getIt.isRegistered<SessionService>() &&
        getIt<SessionService>().isSignedIn &&
        !canSeeFinance()) {
      return const AppEmptyState(
        icon: Icons.lock_outline,
        message: 'Expense reports are available only to finance roles.',
      );
    }

    return ChangeNotifierProvider(
      create: (_) => ExpenseReportsViewModel(
        session: getIt(),
        projects: getIt(),
        builder: CostReportBuilder(costs: getIt(), schedule: getIt()),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ExpenseReportsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final r = vm.report;
        return ListView(
          padding: pagePadding(context),
          children: [
            const AppPageHeader(
              title: 'Expense reports',
              subtitle:
                  'Actual cost by source, category budget utilization, and earned value variance.',
            ),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 420,
                  child: DropdownButtonFormField<int>(
                    initialValue: vm.projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: [
                      for (final p in vm.projects)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.code} · ${p.name}'),
                        ),
                    ],
                    onChanged: vm.setProject,
                  ),
                ),
                if (r != null) AppPdfButton(build: r.pdfReport),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (r == null)
              AppEmptyState(
                message: vm.projects.isEmpty
                    ? 'No projects with costs to report yet.'
                    : 'Choose a project.',
              )
            else ...[
              AppSectionCard(
                title: 'Actual cost',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.md,
                      children: [
                        AppFigure(
                          label: 'Materials',
                          value: Formatters.peso(r.costs.materials),
                          detail: r.costs.total > 0
                              ? '${Formatters.percent(r.costs.materials / r.costs.total)} of spend'
                              : null,
                        ),
                        AppFigure(
                          label: 'Labor',
                          value: Formatters.peso(r.costs.labor),
                          detail: r.costs.total > 0
                              ? '${Formatters.percent(r.costs.labor / r.costs.total)} of spend'
                              : null,
                        ),
                        AppFigure(
                          label: 'Equipment',
                          value: Formatters.peso(r.costs.equipment),
                          detail: r.costs.total > 0
                              ? '${Formatters.percent(r.costs.equipment / r.costs.total)} of spend'
                              : null,
                        ),
                        AppFigure(
                          label: 'Total',
                          value: Formatters.peso(r.costs.total),
                          detail:
                              'of ${Formatters.pesoWhole(r.project.contractAmount)} contract',
                        ),
                        AppFigure(
                          label: 'Earned value',
                          value: Formatters.peso(r.progress.earnedValue),
                          detail:
                              '${Formatters.percent(r.progress.progress)} accomplished',
                        ),
                        AppFigure(
                          label: r.costVariance >= 0
                              ? 'Under cost by'
                              : 'Over cost by',
                          value: Formatters.peso(r.costVariance.abs()),
                          detail: 'vs. earned value',
                          valueColor: r.costVariance >= 0
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    AppBudgetBar(
                      label: 'Material spend vs. category budgets',
                      budget: r.totalBudget,
                      actual: r.costs.materials,
                      showAmounts: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Budget vs. actual',
                padding: EdgeInsets.zero,
                child: BillingCostTable(report: r),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Materials are delivered (undamaged) value by request '
                'category; goods from our own store are one line, at what the '
                'store charged. Labor is processed payroll; equipment is hours '
                'on approved daily reports × rate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}
