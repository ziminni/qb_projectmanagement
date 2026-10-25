import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/services/payroll_calculator.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/payroll_period_detail_viewmodel.dart';
import '../widgets/labor_cash_advance_dialog.dart';
import '../widgets/labor_payroll_table.dart';
import '../widgets/labor_period_status_chip.dart';

/// A payroll period: the PM verifies attendance at cut-off, then the
/// accountant sets cash advances and processes pay.
class PayrollPeriodDetailPage extends StatelessWidget {
  const PayrollPeriodDetailPage({super.key, required this.periodId});

  final int periodId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(periodId),
      create: (_) => PayrollPeriodDetailViewModel(
        periodId: periodId,
        session: getIt(),
        projects: getIt(),
        labor: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PayrollPeriodDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final p = vm.period!;
        final textTheme = Theme.of(context).textTheme;
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Payroll · ${Formatters.dateRange(p.periodStart, p.periodEnd)}',
                  style: textTheme.headlineSmall,
                ),
                LaborPeriodStatusChip(status: p.status),
              ],
            ),
            Text(
              '${vm.project!.code} · ${vm.project!.name}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppWorkflowSteps.payroll(p.status),
            const SizedBox(height: AppSpacing.lg),
            if (vm.canVerify)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Wrap(
                  spacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy || vm.verifyBlocker != null
                          ? null
                          : () => reportAction(
                              context,
                              vm.verify(),
                              success: 'Attendance verified.',
                            ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Verify attendance'),
                    ),
                    if (vm.verifyBlocker != null)
                      Text(vm.verifyBlocker!, style: textTheme.bodySmall),
                  ],
                ),
              ),
            if (vm.canProcess)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final ok = await showAppConfirmDialog(
                              context,
                              title: 'Process payroll?',
                              message:
                                  'Pay is computed and locked, and the '
                                  "period's attendance can no longer be "
                                  'edited. Labor cost posts to the project.',
                              confirmLabel: 'Process',
                            );
                            if (ok && context.mounted) {
                              await reportAction(
                                context,
                                vm.process(),
                                success: 'Payroll processed.',
                              );
                            }
                          },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Process payroll'),
                  ),
                ),
              ),
            AppSectionCard(
              title: 'Totals',
              child: Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  AppFigure(label: 'Workers', value: '${vm.lines.length}'),
                  AppFigure(
                    label: 'Gross pay (labor cost)',
                    value: Formatters.peso(vm.totalGross),
                  ),
                  AppFigure(
                    label: 'Net pay',
                    value: Formatters.peso(vm.totalNet),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: p.status == PayrollStatus.processed
                  ? 'Pay'
                  : 'Pay preview',
              padding: EdgeInsets.zero,
              child: LaborPayrollTable(
                lines: vm.lines,
                workerName: vm.workerName,
                onCashAdvance: vm.canEditCashAdvance
                    ? (line) async {
                        final amount = await LaborCashAdvanceDialog.show(
                          context,
                          line: line,
                          workerName: vm.workerName(line.workerId),
                        );
                        if (amount != null && context.mounted) {
                          await reportAction(
                            context,
                            vm.setCashAdvance(line, amount),
                          );
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Overtime at +${((ContributionRates.overtimePremium - 1) * 100).round()}% '
              'of the hourly rate. Contributions use simplified employee-share '
              'rates (SSS ${(ContributionRates.sss * 100).toStringAsFixed(1)}%, '
              'PhilHealth ${(ContributionRates.philhealth * 100).toStringAsFixed(1)}%, '
              'Pag-IBIG ${(ContributionRates.pagibig * 100).toStringAsFixed(0)}% '
              'up to ₱${ContributionRates.pagibigCapPerPeriod.toStringAsFixed(0)}), '
              'not the official contribution tables.',
              style: textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
