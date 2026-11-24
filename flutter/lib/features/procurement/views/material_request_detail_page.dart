import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/material_request_detail_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_po_tile.dart';
import '../widgets/procurement_request_status_chip.dart';
import '../widgets/procurement_request_summary.dart';

/// A material request with the site count taken before it. The owner
/// answers by ordering from the own store, logging a purchase from another
/// store, or rejecting it.
class MaterialRequestDetailPage extends StatelessWidget {
  const MaterialRequestDetailPage({super.key, required this.requestId});

  final int requestId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(requestId),
      create: (_) => MaterialRequestDetailViewModel(
        requestId: requestId,
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<MaterialRequestDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final r = vm.request!;
        final l = vm.lookups;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${r.number} · ${l.projectCode(r.projectId)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                ProcurementRequestStatusChip(status: r.status),
              ],
            ),
            gap,
            AppWorkflowSteps.materialRequest(r.status),
            gap,
            if (vm.canReject || vm.canOrder) ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (vm.canOrder) ...[
                    FilledButton.icon(
                      onPressed: () =>
                          context.go(AppRoutes.materialRequestOrder(r.id)),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Own hardware store'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.go(AppRoutes.materialRequestBuy(r.id)),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Other store'),
                    ),
                  ],
                  if (vm.canReject)
                    OutlinedButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () async {
                              final reason = await AppReasonDialog.show(
                                context,
                                title: 'Reject ${r.number}',
                                confirmLabel: 'Reject',
                              );
                              if (reason != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.reject(reason),
                                  success: 'Request rejected.',
                                );
                              }
                            },
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                ],
              ),
              gap,
            ],
            AppSectionCard(
              title: 'Details',
              child: Column(
                children: [
                  if (r.categoryId != null)
                    AppInfoRow(
                      label: 'Item of work',
                      value: l.categoryName(r.categoryId),
                    ),
                  AppInfoRow(
                    label: 'Needed by',
                    value: Formatters.date(r.neededBy),
                  ),
                  AppInfoRow(
                    label: 'Requested by',
                    value: l.userName(r.requestedBy),
                  ),
                  if (r.approvedBy != null)
                    AppInfoRow(
                      label: 'Approved by',
                      value: l.userName(r.approvedBy),
                    ),
                ],
              ),
            ),
            gap,
            ProcurementRequestedItems(
              items: vm.detail!.items,
              orderNo: (id) =>
                  vm.orders.where((o) => o.id == id).firstOrNull?.poNo ??
                  'PO #$id',
            ),
            gap,
            ProcurementSiteCounts(counts: vm.detail!.counts),
            if (vm.orders.isNotEmpty) ...[
              gap,
              AppSectionCard(
                title: 'Orders and purchases',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final o in vm.orders) ...[
                      ProcurementPoTile(
                        order: o,
                        projectCode: l.projectCode(o.projectId),
                        supplierName: l.storeName(o),
                        onTap: () => context.go(AppRoutes.purchaseOrder(o.id)),
                      ),
                      if (vm.storeStatusFor(o) case final storeStatus?)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            56,
                            0,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              storeStatus,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
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
