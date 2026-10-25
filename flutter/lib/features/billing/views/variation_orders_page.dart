import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
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
        return ListView(
          padding: pagePadding(context),
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
                for (final s in VariationOrderStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: vm.statusFilter == s,
                    onSelected: (_) => vm.setStatus(s),
                  ),
                if (vm.canCreate)
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.variationOrderNew),
                    icon: const Icon(Icons.add),
                    label: const Text('Raise a VO'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.items.isEmpty)
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
                        onTap: () => context.go(AppRoutes.variationOrder(v.id)),
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
