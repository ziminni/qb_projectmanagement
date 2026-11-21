import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/payroll_period.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/payroll_periods_viewmodel.dart';
import '../widgets/labor_period_dialog.dart';
import '../widgets/labor_period_status_chip.dart';

/// Payroll periods (weekly or 15-day cut-offs) with dashboard summary.
class PayrollPeriodsPage extends StatelessWidget {
  const PayrollPeriodsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PayrollPeriodsViewModel(
        session: getIt(),
        projects: getIt(),
        labor: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PayrollPeriodsViewModel>();
        final showFinance = canSeeFinance();
        return ListView(
          padding: pagePadding(context),
          children: [
            AppPageHeader(
              title: 'Payroll',
              subtitle:
                  'Pay periods, attendance verification, and payroll processing.',
              actions: [
                if (vm.projectsById.length > 1) _ProjectPicker(vm: vm),
                if (vm.canCreate)
                  FilledButton.icon(
                    onPressed: () async {
                      final input = await LaborPeriodDialog.show(
                        context,
                        projects: vm.projectsById.values.toList(),
                      );
                      if (input != null && context.mounted) {
                        final ok = await reportAction(
                          context,
                          vm.create(input.projectId, input.start, input.end),
                        );
                        if (ok && context.mounted) {
                          showSuccessAlert(context, 'Payroll period created.');
                        }
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New payroll period'),
                  ),
              ],
            ),
            if (vm.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (vm.error != null)
              AppEmptyState(
                message: vm.error!,
                icon: Icons.error_outline,
                action: FilledButton.icon(
                  onPressed: vm.load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              )
            else ...[
              _PayrollKpiGrid(vm: vm, showFinance: showFinance),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: Text('All (${vm.totalPeriods})'),
                    selected: vm.statusFilter == null,
                    onSelected: (_) => vm.setStatusFilter(null),
                  ),
                  for (final s in PayrollStatus.values)
                    ChoiceChip(
                      label: Text('${s.label} (${vm.countByStatus(s)})'),
                      selected: vm.statusFilter == s,
                      onSelected: (_) => vm.setStatusFilter(s),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (vm.items.isEmpty)
                const AppEmptyState(
                  icon: Icons.payments_outlined,
                  message: 'No payroll periods match.',
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, p) in vm.items.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _PayrollPeriodTile(
                          period: p,
                          projectCode:
                              vm.projectsById[p.projectId]?.code ?? 'Project',
                          projectName:
                              vm.projectsById[p.projectId]?.name ?? '',
                          summary: vm.summaryFor(p.id),
                          showFinance: showFinance,
                          onTap: () => context.go(AppRoutes.payrollPeriod(p.id)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({required this.vm});

  final PayrollPeriodsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final projects = vm.projectsById.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: vm.projectFilter,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 18),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All projects'),
            ),
            for (final p in projects)
              DropdownMenuItem<int?>(
                value: p.id,
                child: Text('${p.code} · ${p.name}'),
              ),
          ],
          onChanged: vm.setProjectFilter,
        ),
      ),
    );
  }
}

class _PayrollKpiGrid extends StatelessWidget {
  const _PayrollKpiGrid({required this.vm, required this.showFinance});

  final PayrollPeriodsViewModel vm;
  final bool showFinance;

  @override
  Widget build(BuildContext context) {
    final openCount = vm.countByStatus(PayrollStatus.open);
    final verifiedCount = vm.countByStatus(PayrollStatus.verified);
    final processedCount = vm.countByStatus(PayrollStatus.processed);

    final tiles = <Widget>[
      DashboardStatTile(
        label: 'Payroll periods',
        value: '${vm.totalPeriods}',
        detail: '$processedCount processed · $openCount open',
        icon: Icons.calendar_month_outlined,
        onTap: () => vm.setStatusFilter(null),
      ),
      DashboardStatTile(
        label: 'Open cut-offs',
        value: '$openCount',
        detail: 'Attendance recording in progress',
        icon: Icons.edit_calendar_outlined,
        color: AppColors.brandGoldText,
        onTap: () => vm.setStatusFilter(PayrollStatus.open),
      ),
      DashboardStatTile(
        label: 'Ready to process',
        value: '$verifiedCount',
        detail: verifiedCount > 0
            ? 'Verified by project manager'
            : 'All verified periods processed',
        icon: Icons.fact_check_outlined,
        color: verifiedCount > 0 ? AppColors.warning : AppColors.success,
        onTap: () => vm.setStatusFilter(PayrollStatus.verified),
      ),
      if (showFinance)
        DashboardStatTile(
          label: 'Processed net pay',
          value: Formatters.peso(vm.processedTotalNet),
          detail: vm.pendingTotalNet > 0
              ? 'Pending: ${Formatters.peso(vm.pendingTotalNet)}'
              : 'No pending payroll balance',
          icon: Icons.payments_outlined,
          color: AppColors.success,
          onTap: () => vm.setStatusFilter(PayrollStatus.processed),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 960) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tile),
              ],
            ],
          );
        }
        if (w >= 520) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i += 2) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: i + 1 < tiles.length
                          ? tiles[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, tile) in tiles.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              tile,
            ],
          ],
        );
      },
    );
  }
}

class _PayrollPeriodTile extends StatelessWidget {
  const _PayrollPeriodTile({
    required this.period,
    required this.projectCode,
    required this.projectName,
    required this.summary,
    required this.showFinance,
    required this.onTap,
  });

  final PayrollPeriod period;
  final String projectCode;
  final String projectName;
  final PeriodSummary summary;
  final bool showFinance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: AppRadii.mdAll,
              ),
              child: const Icon(
                Icons.date_range_outlined,
                size: 19,
                color: AppColors.brandGoldText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.dateRange(period.periodStart, period.periodEnd),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      projectCode,
                      if (projectName.isNotEmpty) projectName,
                      '${summary.workers} worker${summary.workers == 1 ? '' : 's'}',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showFinance && summary.workers > 0) ...[
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.peso(summary.net),
                    style: textTheme.titleSmall
                        ?.merge(AppTextStyles.numeric)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Net pay',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: AppSpacing.md),
            LaborPeriodStatusChip(status: period.status),
          ],
        ),
      ),
    );
  }
}
