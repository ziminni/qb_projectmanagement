import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/worker.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/workers_viewmodel.dart';
import '../widgets/labor_worker_dialog.dart';

class WorkersPage extends StatelessWidget {
  const WorkersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          WorkersViewModel(labor: getIt(), masterData: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<WorkersViewModel>();
        return ListView(
          padding: pagePadding(context),
          children: [
            AppPageHeader(
              title: 'Workers',
              subtitle:
                  'Crew directory, trade assignments, daily rates, and contact details.',
              actions: [
                FilledButton.icon(
                  onPressed: () async {
                    final w = await LaborWorkerDialog.show(
                      context,
                      trades: vm.trades,
                    );
                    if (w != null && context.mounted) {
                      final ok = await reportAction(context, vm.save(w));
                      if (ok && context.mounted) {
                        showSuccessAlert(
                          context,
                          '${w.fullName} added to the worker directory.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Add worker'),
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
              _WorkersKpiGrid(vm: vm),
              const SizedBox(height: AppSpacing.lg),
              _WorkersFilterBar(vm: vm),
              const SizedBox(height: AppSpacing.md),
              if (vm.items.isEmpty)
                const AppEmptyState(
                  icon: Icons.engineering_outlined,
                  message: 'No workers match the current filter.',
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, w) in vm.items.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _WorkerRow(worker: w, vm: vm),
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

class _WorkersKpiGrid extends StatelessWidget {
  const _WorkersKpiGrid({required this.vm});

  final WorkersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      DashboardStatTile(
        label: 'Total workers',
        value: '${vm.totalCount}',
        detail: '${vm.distinctTradeCount} trades represented',
        icon: Icons.groups_outlined,
        onTap: () {
          vm.setTradeFilter(null);
          vm.setActiveFilter(null);
        },
      ),
      DashboardStatTile(
        label: 'Active crew',
        value: '${vm.activeCount}',
        detail: '${vm.inactiveCount} inactive',
        icon: Icons.engineering_outlined,
        color: AppColors.success,
        progress: vm.totalCount == 0 ? 0 : vm.activeCount / vm.totalCount,
        onTap: () => vm.setActiveFilter(vm.activeFilter == true ? null : true),
      ),
      if (vm.ratesVisible) ...[
        DashboardStatTile(
          label: 'Avg. daily rate',
          value: Formatters.peso(vm.averageDailyRate),
          detail: 'Active crew average',
          icon: Icons.payments_outlined,
          color: AppColors.brandGoldText,
        ),
        DashboardStatTile(
          label: 'Outstanding advances',
          value: Formatters.peso(vm.totalCashAdvanceBalance),
          detail: vm.workersWithAdvanceCount == 0
              ? 'No unpaid cash advances'
              : '${vm.workersWithAdvanceCount} worker${vm.workersWithAdvanceCount == 1 ? '' : 's'} · auto-deducts next payday',
          icon: Icons.account_balance_wallet_outlined,
          color: vm.totalCashAdvanceBalance > 0
              ? AppColors.warning
              : AppColors.success,
        ),
      ] else
        DashboardStatTile(
          label: 'Trades',
          value: '${vm.distinctTradeCount}',
          detail: 'Across ${vm.activeCount} active workers',
          icon: Icons.construction_outlined,
          color: AppColors.brandGoldText,
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

class _WorkersFilterBar extends StatelessWidget {
  const _WorkersFilterBar({required this.vm});

  final WorkersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trades = vm.availableTrades;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search name or trade',
              isDense: true,
            ),
            onChanged: vm.setQuery,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadii.mdAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: vm.tradeFilter,
              isDense: true,
              icon: const Icon(Icons.expand_more, size: 18),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All trades'),
                ),
                for (final t in trades)
                  DropdownMenuItem<String?>(value: t, child: Text(t)),
              ],
              onChanged: vm.setTradeFilter,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadii.mdAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<bool?>(
              value: vm.activeFilter,
              isDense: true,
              icon: const Icon(Icons.expand_more, size: 18),
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('All status')),
                DropdownMenuItem<bool?>(value: true, child: Text('Active')),
                DropdownMenuItem<bool?>(value: false, child: Text('Inactive')),
              ],
              onChanged: vm.setActiveFilter,
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({required this.worker, required this.vm});

  final Worker worker;
  final WorkersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final initials = worker.fullName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join();

    return InkWell(
      onTap: () async {
        final edited = await LaborWorkerDialog.show(
          context,
          initial: worker,
          trades: vm.trades,
        );
        if (edited != null && context.mounted) {
          final ok = await reportAction(context, vm.save(edited));
          if (ok && context.mounted) {
            showSuccessAlert(context, '${edited.fullName} updated.');
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: worker.isActive
                  ? AppColors.selected
                  : scheme.surfaceContainerHighest,
              child: Text(
                initials,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: worker.isActive
                      ? AppColors.brandGoldText
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          worker.fullName,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.7,
                          ),
                          borderRadius: AppRadii.smAll,
                        ),
                        child: Text(
                          worker.trade,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (!worker.dailyRateHidden)
                        '${Formatters.peso(worker.dailyRate)}/day',
                      if (worker.phone != null &&
                          worker.phone!.trim().isNotEmpty)
                        worker.phone!,
                      if (worker.address != null &&
                          worker.address!.trim().isNotEmpty)
                        worker.address!,
                    ].join(' · '),
                    style: textTheme.bodySmall?.merge(AppTextStyles.numeric),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (!worker.dailyRateHidden && worker.cashAdvanceBalance > 0) ...[
              AppStatusChip(
                label: 'CA ${Formatters.peso(worker.cashAdvanceBalance)}',
                foreground: AppColors.warning,
                background: AppColors.warningContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            AppStatusChip(
              label: worker.isActive ? 'Active' : 'Inactive',
              foreground: worker.isActive
                  ? AppColors.success
                  : AppColors.textSecondary,
              background: worker.isActive
                  ? AppColors.successContainer
                  : AppColors.surfaceMuted,
            ),
            if (!worker.dailyRateHidden && worker.isActive) ...[
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'Record cash advance',
                icon: const Icon(Icons.payments_outlined, size: 19),
                onPressed: vm.isBusy
                    ? null
                    : () async {
                        final amount = await _RecordWorkerAdvanceDialog.show(
                          context,
                          worker: worker,
                        );
                        if (amount != null && context.mounted) {
                          final ok = await reportAction(
                            context,
                            vm.recordCashAdvance(worker.id, amount),
                          );
                          if (ok && context.mounted) {
                            showSuccessAlert(
                              context,
                              '${Formatters.peso(amount)} cash advance recorded for ${worker.fullName}. It will auto-deduct on upcoming paydays.',
                            );
                          }
                        }
                      },
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: worker.isActive ? 'Set inactive' : 'Reactivate worker',
              icon: Icon(
                worker.isActive
                    ? Icons.person_off_outlined
                    : Icons.person_outline,
                size: 19,
              ),
              onPressed: vm.isBusy
                  ? null
                  : () async {
                      final ok = await reportAction(
                        context,
                        vm.toggleActive(worker),
                      );
                      if (ok && context.mounted) {
                        showSuccessAlert(
                          context,
                          worker.isActive
                              ? '${worker.fullName} marked inactive.'
                              : '${worker.fullName} reactivated.',
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordWorkerAdvanceDialog extends StatefulWidget {
  const _RecordWorkerAdvanceDialog({required this.worker});

  final Worker worker;

  static Future<double?> show(
    BuildContext context, {
    required Worker worker,
  }) => showDialog<double>(
    context: context,
    builder: (_) => _RecordWorkerAdvanceDialog(worker: worker),
  );

  @override
  State<_RecordWorkerAdvanceDialog> createState() =>
      _RecordWorkerAdvanceDialogState();
}

class _RecordWorkerAdvanceDialogState
    extends State<_RecordWorkerAdvanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(InputParsers.amount(_amount.text));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = widget.worker.cashAdvanceBalance;

    return AlertDialog(
      title: Text('Cash advance · ${widget.worker.fullName}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (current > 0) ...[
                Text(
                  'Current unpaid balance: ${Formatters.peso(current)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount borrowed',
                  helperText:
                      'Automatically deducted on upcoming paydays until paid off.',
                  prefixIcon: SizedBox(
                    width: 36,
                    child: Center(
                      child: Text(
                        '₱',
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          fontFamilyFallback: AppFonts.fallback,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 0,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final val = InputParsers.amount(v);
                  if (val == null || val <= 0) {
                    return 'Enter an amount greater than 0.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record')),
      ],
    );
  }
}
