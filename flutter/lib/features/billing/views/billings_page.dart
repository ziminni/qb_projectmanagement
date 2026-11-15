import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/progress_billing.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../viewmodels/billings_viewmodel.dart';
import '../widgets/billing_tile.dart';

/// Progress billings with billed vs. collected totals.
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
        return ListView(
          padding: pagePadding(context),
          children: [
            const AppPageHeader(
              title: 'Progress billings',
              subtitle:
                  'Bill clients for verified progress and track their payments.',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (context) {
                        final billed = vm.summary!.billed;
                        final collected = vm.summary!.collected;
                        final outstanding = billed - collected;
                        final projectCount = vm.projectsById.length;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: AppSpacing.xl,
                              runSpacing: AppSpacing.md,
                              children: [
                                AppFigure(
                                  label: 'Billed to clients',
                                  value: Formatters.peso(billed),
                                  detail:
                                      '$projectCount project'
                                      '${projectCount == 1 ? '' : 's'}',
                                ),
                                AppFigure(
                                  label: 'Collected',
                                  value: Formatters.peso(collected),
                                  detail: billed > 0
                                      ? '${Formatters.percent(collected / billed)} collected'
                                      : 'Nothing billed yet',
                                  valueColor: AppColors.success,
                                ),
                                AppFigure(
                                  label: 'Outstanding',
                                  value: Formatters.peso(outstanding),
                                  detail: outstanding > 0
                                      ? 'Awaiting payment'
                                      : 'All collected',
                                  valueColor: outstanding > 0
                                      ? AppColors.warning
                                      : AppColors.success,
                                ),
                              ],
                            ),
                            if (billed > 0) ...[
                              const SizedBox(height: AppSpacing.md),
                              AppProgressBar(
                                value: (collected / billed).clamp(0.0, 1.0),
                                height: 8,
                                color: outstanding <= 0
                                    ? AppColors.success
                                    : AppColors.brandGold,
                                semanticsLabel: 'Collection progress',
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                if (vm.canCreate)
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.billingNew),
                    icon: const Icon(Icons.add),
                    label: const Text('New billing'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.items.isEmpty)
              const AppEmptyState(message: 'No billings match.')
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
