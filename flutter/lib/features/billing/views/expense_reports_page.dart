import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/expense_reports_viewmodel.dart';
import '../widgets/billing_cost_table.dart';

/// Project expense report: actual cost by source, budget vs. actual, and
/// cost vs. earned value.
class ExpenseReportsPage extends StatelessWidget {
  const ExpenseReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        final r = vm.report;
        return ListView(
          padding: pagePadding(context),
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
            const SizedBox(height: AppSpacing.lg),
            if (r == null)
              const AppEmptyState(message: 'Choose a project.')
            else ...[
              AppSectionCard(
                title: 'Actual cost',
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.md,
                  children: [
                    AppFigure(
                      label: 'Materials',
                      value: Formatters.peso(r.costs.materials),
                    ),
                    AppFigure(
                      label: 'Labor',
                      value: Formatters.peso(r.costs.labor),
                    ),
                    AppFigure(
                      label: 'Equipment',
                      value: Formatters.peso(r.costs.equipment),
                    ),
                    AppFigure(
                      label: 'Total',
                      value: Formatters.peso(r.costs.total),
                    ),
                    AppFigure(
                      label: 'Earned value',
                      value: Formatters.peso(r.progress.earnedValue),
                    ),
                    AppFigure(
                      label: r.costVariance >= 0
                          ? 'Under cost by'
                          : 'Over cost by',
                      value: Formatters.peso(r.costVariance.abs()),
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
                'category. Labor is processed payroll; equipment is hours on '
                'approved daily reports × rate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}
