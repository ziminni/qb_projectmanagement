import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/material_source.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/procurement_lookups.dart';
import '../viewmodels/project_materials_viewmodel.dart';
import '../widgets/procurement_delivery_tile.dart';
import '../widgets/procurement_inventory_table.dart';
import '../widgets/procurement_po_tile.dart';
import '../widgets/procurement_request_tile.dart';

/// Project "Materials" tab.
class ProjectMaterialsPage extends StatelessWidget {
  const ProjectMaterialsPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ProjectMaterialsViewModel(
        projectId: projectId,
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectMaterialsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = vm.lookups;
        final isSiteEngineer =
            getIt<SessionService>().activeRole == AppRole.siteEngineer;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            AppSectionCard(
              title: 'Ordered cost by source',
              child: Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  AppFigure(
                    label: 'Own store',
                    value: Formatters.peso(vm.costFor(MaterialSource.ownStore)),
                  ),
                  AppFigure(
                    label: 'Other suppliers',
                    value: Formatters.peso(vm.costFor(MaterialSource.external)),
                  ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Requests (${vm.requests.length})',
              padding: EdgeInsets.zero,
              trailing: isSiteEngineer
                  ? TextButton.icon(
                      onPressed: () => context.go(
                        '${AppRoutes.materialRequestNew}?projectId=$projectId',
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Request'),
                    )
                  : null,
              child: Column(
                children: [
                  if (vm.requests.isEmpty)
                    const ListTile(title: Text('No requests yet.')),
                  for (final r in vm.requests)
                    ProcurementRequestTile(
                      request: r,
                      projectCode: l.projectCode(r.projectId),
                      categoryName: l.categoryName(r.categoryId),
                      onTap: () => context.go(AppRoutes.materialRequest(r.id)),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Purchase orders (${vm.orders.length})',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.orders.isEmpty)
                    const ListTile(title: Text('No purchase orders yet.')),
                  for (final o in vm.orders)
                    ProcurementPoTile(
                      order: o,
                      projectCode: l.projectCode(o.projectId),
                      supplierName: l.supplierName(o.supplierId),
                      onTap: () => context.go(AppRoutes.purchaseOrder(o.id)),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Deliveries',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.deliveries.isEmpty)
                    const ListTile(title: Text('No deliveries yet.')),
                  for (final h in vm.deliveries)
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
            gap,
            AppSectionCard(
              title: 'Site inventory',
              padding: EdgeInsets.zero,
              child: ProcurementInventoryTable(
                lines: vm.inventory,
                materialName: l.materialName,
                unit: l.unit,
              ),
            ),
          ],
        );
      },
    );
  }
}
