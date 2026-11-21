import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../shared/pdf/pdf_renderer.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_pdf_button.dart';
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

  Future<void> _exportPayslip(
    BuildContext context,
    PayrollPeriodDetailViewModel vm,
    PayrollLine line,
  ) async {
    try {
      final report = vm.payslipReport(line);
      final company = (await getIt<CompanyRepository>().getCompany()).name;
      final bytes = await PdfRenderer.render(report, company: company);
      await Printing.layoutPdf(
        name: '${report.fileName}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (context.mounted) {
        showAppMessage(context, 'Could not export payslip. $e');
      }
    }
  }

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
        final scheme = Theme.of(context).colorScheme;
        final totalDays = vm.lines.fold<double>(0, (s, l) => s + l.daysWorked);

        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Payroll · ${Formatters.dateRange(p.periodStart, p.periodEnd)}',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        LaborPeriodStatusChip(status: p.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${vm.project!.code} · ${vm.project!.name}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (vm.canVerify)
                      FilledButton.icon(
                        onPressed: vm.isBusy || vm.verifyBlocker != null
                            ? null
                            : () async {
                                final ok = await reportAction(
                                  context,
                                  vm.verify(),
                                );
                                if (ok && context.mounted) {
                                  showSuccessAlert(
                                    context,
                                    'Attendance verified.',
                                  );
                                }
                              },
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Verify attendance'),
                      ),
                    if (vm.canProcess)
                      FilledButton.icon(
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
                                  final done = await reportAction(
                                    context,
                                    vm.process(),
                                  );
                                  if (done && context.mounted) {
                                    showSuccessAlert(
                                      context,
                                      'Payroll processed.',
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Process payroll'),
                      ),
                    AppPdfButton(build: vm.pdfReport, label: 'Export payroll'),
                  ],
                ),
              ],
            ),
            if (vm.canVerify && vm.verifyBlocker != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                vm.verifyBlocker!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.warning),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppWorkflowSteps.payroll(p.status),
            const SizedBox(height: AppSpacing.lg),
            _PayrollTotalsStrip(
              workerCount: vm.lines.length,
              totalDays: totalDays,
              totalCashAdvance: vm.totalCashAdvance,
              totalNet: vm.totalNet,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: p.status == PayrollStatus.processed
                  ? 'Pay'
                  : 'Pay preview',
              subtitle: vm.lines.isEmpty
                  ? null
                  : 'Click the receipt icon on any row to export an individual payslip PDF',
              icon: Icons.payments_outlined,
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
                          final ok = await reportAction(
                            context,
                            vm.setCashAdvance(line, amount),
                          );
                          if (ok && context.mounted) {
                            showSuccessAlert(
                              context,
                              'Cash advance updated for ${vm.workerName(line.workerId)}.',
                            );
                          }
                        }
                      }
                    : null,
                onExportPayslip: (line) => _exportPayslip(context, vm, line),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PayrollTotalsStrip extends StatelessWidget {
  const _PayrollTotalsStrip({
    required this.workerCount,
    required this.totalDays,
    required this.totalCashAdvance,
    required this.totalNet,
  });

  final int workerCount;
  final double totalDays;
  final double totalCashAdvance;
  final double totalNet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      _TotalCell(
        label: 'Workers',
        value: '$workerCount',
        detail: '${InputParsers.amountText(totalDays)} total days',
      ),
      _TotalCell(
        label: 'Cash advances',
        value: Formatters.peso(totalCashAdvance),
        detail: totalCashAdvance > 0 ? 'Deducted from pay' : 'No cash advances',
        accent: totalCashAdvance > 0 ? AppColors.warning : null,
      ),
      _TotalCell(
        label: 'Net pay',
        value: Formatters.peso(totalNet),
        detail: 'Total payable for period',
        accent: AppColors.success,
      ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0)
                        VerticalDivider(
                          width: AppSpacing.xl,
                          thickness: 1,
                          color: scheme.outlineVariant,
                        ),
                      Expanded(child: item),
                    ],
                  ],
                ),
              );
            }
            return Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                for (final item in items) SizedBox(width: 180, child: item),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  const _TotalCell({
    required this.label,
    required this.value,
    this.detail,
    this.accent,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: textTheme.titleLarge
                ?.merge(AppTextStyles.numeric)
                .copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent ?? scheme.onSurface,
                ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
