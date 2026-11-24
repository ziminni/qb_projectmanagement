import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/variation_orders_viewmodel.dart';
import '../widgets/billing_vo_tile.dart';

class VariationOrdersPage extends StatelessWidget {
  const VariationOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VariationOrdersViewModel(
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<VariationOrdersViewModel>();
        final showFinance = canSeeFinance();
        return ListView(
          padding: pagePadding(context),
          children: [
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
              _VoDashboard(vm: vm, showFinance: showFinance),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: Text('All (${vm.totalCount})'),
                        selected: vm.statusFilter == null,
                        onSelected: (_) => vm.setStatus(null),
                      ),
                      for (final s in VariationOrderStatus.values)
                        ChoiceChip(
                          label: Text('${s.label} (${vm.countByStatus(s)})'),
                          selected: vm.statusFilter == s,
                          onSelected: (_) => vm.setStatus(s),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (vm.projectsById.length > 1)
                        _ProjectScopePicker(vm: vm),
                      if (vm.canCreate)
                        FilledButton.icon(
                          onPressed: () =>
                              context.go(AppRoutes.variationOrderNew),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Raise a VO'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (vm.items.isEmpty)
                const AppEmptyState(message: 'No variation orders match.')
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, v) in vm.items.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        BillingVoTile(
                          vo: v,
                          projectCode:
                              vm.projectsById[v.projectId]?.code ?? 'Project',
                          onTap: () =>
                              context.go(AppRoutes.variationOrder(v.id)),
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

class _ProjectScopePicker extends StatelessWidget {
  const _ProjectScopePicker({required this.vm});

  final VariationOrdersViewModel vm;

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
          onChanged: vm.setProject,
        ),
      ),
    );
  }
}

class _VoDashboard extends StatelessWidget {
  const _VoDashboard({required this.vm, required this.showFinance});

  final VariationOrdersViewModel vm;
  final bool showFinance;

  @override
  Widget build(BuildContext context) {
    final proposedCount = vm.countByStatus(VariationOrderStatus.proposed);
    final pendingClientCount = vm.countByStatus(
      VariationOrderStatus.pendingClient,
    );
    final rejectedCount = vm.countByStatus(VariationOrderStatus.rejected);

    final tiles = <Widget>[
      DashboardStatTile(
        label: 'Total variation orders',
        value: '${vm.totalCount}',
        detail: '${vm.approvedCount} approved · $rejectedCount rejected',
        icon: Icons.difference_outlined,
        onTap: () => vm.setStatus(null),
      ),
      DashboardStatTile(
        label: 'Awaiting approval',
        value: '${vm.awaitingApprovalCount}',
        detail: '$proposedCount proposed · $pendingClientCount with client',
        icon: Icons.pending_actions_outlined,
        color: vm.awaitingApprovalCount > 0
            ? AppColors.warning
            : AppColors.success,
        onTap: () {
          if (pendingClientCount > 0) {
            vm.setStatus(VariationOrderStatus.pendingClient);
          } else if (proposedCount > 0) {
            vm.setStatus(VariationOrderStatus.proposed);
          }
        },
      ),
      if (showFinance)
        DashboardStatTile(
          label: 'Approved cost impact',
          value: _signedPeso(vm.approvedCostImpact),
          detail: vm.pendingCostImpact == 0
              ? 'No pending cost changes'
              : 'Pending: ${_signedPeso(vm.pendingCostImpact)}',
          icon: Icons.account_balance_wallet_outlined,
          color: vm.approvedCostImpact > 0
              ? AppColors.brandGoldText
              : vm.approvedCostImpact < 0
              ? AppColors.success
              : AppColors.textSecondary,
          onTap: () => vm.setStatus(VariationOrderStatus.approved),
        )
      else
        DashboardStatTile(
          label: 'Approved VOs',
          value: '${vm.approvedCount}',
          detail: vm.totalCount == 0
              ? 'No variation orders yet'
              : '${Formatters.percent(vm.approvedCount / vm.totalCount)} of total',
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          progress: vm.totalCount == 0 ? 0 : vm.approvedCount / vm.totalCount,
          onTap: () => vm.setStatus(VariationOrderStatus.approved),
        ),
      DashboardStatTile(
        label: 'Approved schedule impact',
        value: _signedDays(vm.approvedDaysImpact),
        detail: vm.pendingDaysImpact == 0
            ? 'No pending day changes'
            : 'Pending: ${_signedDays(vm.pendingDaysImpact)}',
        icon: Icons.event_repeat_outlined,
        color: vm.approvedDaysImpact > 0
            ? AppColors.warning
            : AppColors.success,
      ),
    ];

    final wide =
        MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResponsiveTileGrid(tiles: tiles),
        const SizedBox(height: AppSpacing.md),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatusBreakdownCard(vm: vm)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TypeBreakdownCard(vm: vm, showFinance: showFinance),
              ),
            ],
          )
        else ...[
          _StatusBreakdownCard(vm: vm),
          const SizedBox(height: AppSpacing.md),
          _TypeBreakdownCard(vm: vm, showFinance: showFinance),
        ],
      ],
    );
  }
}

class _ResponsiveTileGrid extends StatelessWidget {
  const _ResponsiveTileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 960) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, tile) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(child: tile),
                ],
              ],
            ),
          );
        }
        if (w >= 520) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i += 2) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({required this.vm});

  final VariationOrdersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final total = vm.totalCount;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppSectionCard(
      title: 'Approval pipeline',
      subtitle: total == 0
          ? 'No variation orders recorded yet'
          : 'Click any status to filter the list below',
      icon: Icons.donut_large_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 0) ...[
            ClipRRect(
              borderRadius: AppRadii.smAll,
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final s in VariationOrderStatus.values)
                      if (vm.countByStatus(s) > 0)
                        Expanded(
                          flex: vm.countByStatus(s),
                          child: Container(color: _statusColor(s)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final s in VariationOrderStatus.values) ...[
            Builder(
              builder: (context) {
                final count = vm.countByStatus(s);
                final selected = vm.statusFilter == s;
                final share = total == 0
                    ? '0%'
                    : Formatters.percent(count / total);
                return InkWell(
                  borderRadius: AppRadii.smAll,
                  onTap: () => vm.setStatus(selected ? null : s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _statusColor(s),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            s.label,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text(
                          '$count',
                          style: textTheme.bodyMedium
                              ?.merge(AppTextStyles.numeric)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 40,
                          child: Text(
                            share,
                            textAlign: TextAlign.right,
                            style: textTheme.bodySmall?.merge(
                              AppTextStyles.numeric,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeBreakdownCard extends StatelessWidget {
  const _TypeBreakdownCard({required this.vm, required this.showFinance});

  final VariationOrdersViewModel vm;
  final bool showFinance;

  @override
  Widget build(BuildContext context) {
    final total = vm.totalCount;
    final textTheme = Theme.of(context).textTheme;

    return AppSectionCard(
      title: 'By change type',
      subtitle: 'Breakdown across added work, removals, and design changes',
      icon: Icons.category_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in VariationOrderType.values.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Builder(
              builder: (context) {
                final count = vm.countByType(t);
                final fraction = total == 0 ? 0.0 : count / total;
                final days = vm.daysByType(t);
                final amount = vm.amountByType(t);
                final color = _typeColor(t);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(_typeIcon(t), size: 16, color: color),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '${t.label} ($count)',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          showFinance
                              ? '${_signedPeso(amount)} · ${_signedDays(days)}'
                              : _signedDays(days),
                          style: textTheme.bodySmall?.merge(
                            AppTextStyles.numeric,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppProgressBar(
                      value: fraction,
                      height: 6,
                      color: color,
                      semanticsLabel: '${t.label} share',
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(VariationOrderStatus status) => switch (status) {
  VariationOrderStatus.proposed => AppColors.brandGold,
  VariationOrderStatus.pendingClient => AppColors.warning,
  VariationOrderStatus.approved => AppColors.success,
  VariationOrderStatus.rejected => AppColors.error,
};

Color _typeColor(VariationOrderType type) => switch (type) {
  VariationOrderType.additive => AppColors.brandGoldText,
  VariationOrderType.deductive => AppColors.success,
  VariationOrderType.change => AppColors.warning,
};

IconData _typeIcon(VariationOrderType type) => switch (type) {
  VariationOrderType.additive => Icons.add_circle_outline,
  VariationOrderType.deductive => Icons.remove_circle_outline,
  VariationOrderType.change => Icons.swap_horiz_rounded,
};

String _signedPeso(double amount) {
  if (amount == 0) return Formatters.peso(0);
  final sign = amount > 0 ? '+' : '−';
  return '$sign${Formatters.peso(amount.abs())}';
}

String _signedDays(int days) {
  final unit = days.abs() == 1 ? 'day' : 'days';
  if (days == 0) return '0 days';
  final sign = days > 0 ? '+' : '−';
  return '$sign${days.abs()} $unit';
}
