import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/material_request.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/material_requests_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_request_tile.dart';

/// Material requests list. With [queue] set it is the Project Manager's
/// Purchasing workspace, opening on pending requests waiting for POs with
/// direct shortcuts to Purchase orders, Deliveries, and Suppliers.
class MaterialRequestsPage extends StatelessWidget {
  const MaterialRequestsPage({super.key, this.queue = false});

  final bool queue;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MaterialRequestsViewModel(
        queue: queue,
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<MaterialRequestsViewModel>();
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ListView(
          padding: pagePadding(context),
          children: [
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
                    for (final s in MaterialRequestStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: vm.statusFilter == s,
                        onSelected: (_) => vm.setStatus(s),
                      ),
                    if (!vm.isLoading)
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
                          '${vm.items.length} request${vm.items.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (queue) ...[
                      OutlinedButton.icon(
                        onPressed: () => context.go(AppRoutes.purchaseOrders),
                        icon: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 17,
                        ),
                        label: const Text('Purchase orders'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.go(AppRoutes.deliveries),
                        icon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 17,
                        ),
                        label: const Text('Deliveries'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.go(AppRoutes.suppliers),
                        icon: const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 17,
                        ),
                        label: const Text('Suppliers'),
                      ),
                    ],
                    if (vm.canCreate)
                      FilledButton.icon(
                        onPressed: () => context.go(AppRoutes.materialRequestNew),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New request'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.items.isEmpty)
              AppEmptyState(
                icon: Icons.inventory_2_outlined,
                message: queue
                    ? 'No approved requests are waiting for purchase orders.'
                    : 'No material requests match.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, r) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ProcurementRequestTile(
                        request: r,
                        projectCode: vm.lookups.projectCode(r.projectId),
                        categoryName: vm.lookups.categoryName(r.categoryId),
                        onTap: () =>
                            context.go(AppRoutes.materialRequest(r.id)),
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
