import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/material_request_detail_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_budget_card.dart';
import '../widgets/procurement_po_tile.dart';
import '../widgets/procurement_request_status_chip.dart';

/// A material request with its review actions (PM, then owner when over
/// budget) and purchasing's "Create purchase orders".
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
            if (vm.canReview || vm.canOrder) ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (vm.canReview) ...[
                    FilledButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () => reportAction(
                              context,
                              vm.approve(),
                              success: 'Request approved.',
                            ),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
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
                  if (vm.canOrder)
                    FilledButton.icon(
                      onPressed: () =>
                          context.go(AppRoutes.materialRequestOrder(r.id)),
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text('Create purchase orders'),
                    ),
                ],
              ),
              gap,
            ],
            AppSectionCard(
              title: 'Details',
              child: Column(
                children: [
                  AppInfoRow(
                    label: 'Category',
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
            AppSectionCard(
              title: 'Items',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final i in vm.detail!.items)
                    ListTile(
                      title: Text(l.materialName(i.materialId)),
                      subtitle: Text(
                        [
                          '${InputParsers.amountText(i.quantity)} ${l.unit(i.materialId)}',
                          i.status.label,
                          if (i.source != null) i.source!.label,
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
            ),
            gap,
            if (vm.budget != null) ProcurementBudgetCard(check: vm.budget!),
            if (vm.orders.isNotEmpty) ...[
              gap,
              AppSectionCard(
                title: 'Purchase orders',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
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
            ],
          ],
        );
      },
    );
  }
}
