import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/progress_billing.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/billings_viewmodel.dart';
import '../widgets/billing_tile.dart';

/// Progress billings with full-width KPI tiles and unified status/action bar.
class BillingsPage extends StatelessWidget {
  const BillingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BillingsViewModel(
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<BillingsViewModel>();
        if (vm.isLoading && vm.summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final billed = vm.summary!.billed;
        final collected = vm.summary!.collected;
        final outstanding = billed - collected;
        final projectCount = vm.projectsById.length;
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final kpiTiles = [
          DashboardStatTile(
            label: 'Billed to clients',
            value: Formatters.peso(billed),
            detail: '$projectCount project${projectCount == 1 ? '' : 's'}',
            icon: Icons.receipt_long_rounded,
          ),
          DashboardStatTile(
            label: 'Collected',
            value: Formatters.peso(collected),
            detail: billed > 0
                ? '${Formatters.percent(collected / billed)} collected'
                : 'Nothing billed yet',
            icon: Icons.payments_outlined,
            color: AppColors.success,
            progress: billed > 0 ? (collected / billed).clamp(0.0, 1.0) : null,
          ),
          DashboardStatTile(
            label: 'Outstanding',
            value: Formatters.peso(outstanding),
            detail: outstanding > 0 ? 'Awaiting payment' : 'All collected',
            icon: outstanding > 0
                ? Icons.account_balance_wallet_outlined
                : Icons.verified_outlined,
            color: outstanding > 0 ? AppColors.warning : AppColors.success,
          ),
        ];

        return ListView(
          padding: pagePadding(context),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 820 ? 3 : 1;
                final w =
                    (constraints.maxWidth - AppSpacing.md * (cols - 1)) / cols;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final tile in kpiTiles) SizedBox(width: w, child: tile),
                  ],
                );
              },
            ),
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
                      label: const Text('All'),
                      selected: vm.statusFilter == null,
                      onSelected: (_) => vm.setStatus(null),
                    ),
                    for (final s in BillingStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: vm.statusFilter == s,
                        onSelected: (_) => vm.setStatus(s),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? cs.surfaceContainer
                            : AppColors.surfaceSunken,
                        borderRadius: AppRadii.mdAll,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        '${vm.items.length} billing${vm.items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (vm.canCreate)
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.billingNew),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New billing'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.items.isEmpty)
              const AppEmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'No billings match.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, b) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      BillingTile(
                        billing: b,
                        projectCode:
                            vm.projectsById[b.projectId]?.code ?? 'Project',
                        onTap: () => context.go(AppRoutes.billing(b.id)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
