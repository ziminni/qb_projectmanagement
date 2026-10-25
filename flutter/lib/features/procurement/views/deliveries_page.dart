import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/deliveries_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_delivery_tile.dart';
import '../widgets/procurement_po_tile.dart';

/// POs waiting for delivery and the delivery history.
class DeliveriesPage extends StatelessWidget {
  const DeliveriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DeliveriesViewModel(
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<DeliveriesViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final l = vm.lookups;
        return ListView(
          padding: pagePadding(context),
          children: [
            AppSectionCard(
              title: 'Waiting for delivery (${vm.awaiting.length})',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.awaiting.isEmpty)
                    const ListTile(title: Text('No open purchase orders.')),
                  for (final o in vm.awaiting)
                    ProcurementPoTile(
                      order: o,
                      projectCode: l.projectCode(o.projectId),
                      supplierName: l.supplierName(o.supplierId),
                      onTap: () => context.go(AppRoutes.purchaseOrder(o.id)),
                      trailing: vm.canConfirm
                          ? FilledButton.tonal(
                              onPressed: () =>
                                  context.go(AppRoutes.deliveryConfirm(o.id)),
                              child: const Text('Confirm'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: 'Received',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.history.isEmpty)
                    const ListTile(title: Text('No deliveries yet.')),
                  for (final h in vm.history)
                    ProcurementDeliveryTile(
                      delivery: h.delivery,
                      order: h.order,
                      receivedBy: l.userName(h.delivery.delivery.receivedBy),
                      onTap: () =>
                          context.go(AppRoutes.purchaseOrder(h.order.id)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
