import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/purchase_order.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/procurement_lookups.dart';
import '../viewmodels/purchase_orders_viewmodel.dart';
import '../widgets/procurement_po_tile.dart';

class PurchaseOrdersPage extends StatelessWidget {
  const PurchaseOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PurchaseOrdersViewModel(
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PurchaseOrdersViewModel>();
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: vm.statusFilter == null,
                  onSelected: (_) => vm.setStatus(null),
                ),
                for (final s in PurchaseOrderStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: vm.statusFilter == s,
                    onSelected: (_) => vm.setStatus(s),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.items.isEmpty)
              const AppEmptyState(message: 'No purchase orders match.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, o) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ProcurementPoTile(
                        order: o,
                        projectCode: vm.lookups.projectCode(o.projectId),
                        supplierName: vm.lookups.supplierName(o.supplierId),
                        onTap: () => context.go(AppRoutes.purchaseOrder(o.id)),
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
