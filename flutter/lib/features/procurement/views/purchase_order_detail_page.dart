import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/finance_access.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/procurement_lookups.dart';
import '../viewmodels/purchase_order_detail_viewmodel.dart';
import '../widgets/procurement_po_status_chip.dart';

class PurchaseOrderDetailPage extends StatelessWidget {
  const PurchaseOrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(orderId),
      create: (_) => PurchaseOrderDetailViewModel(
        orderId: orderId,
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PurchaseOrderDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final d = vm.detail!;
        final o = d.order;
        final l = vm.lookups;
        String q(double v) => InputParsers.amountText(v);
        final finance = canSeeFinance();
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(o.poNo, style: Theme.of(context).textTheme.headlineSmall),
                ProcurementPoStatusChip(status: o.status),
              ],
            ),
            gap,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (vm.canReceive)
                  FilledButton.icon(
                    onPressed: () =>
                        context.go(AppRoutes.deliveryConfirm(o.id)),
                    icon: const Icon(Icons.inventory_outlined),
                    label: const Text('Confirm delivery'),
                  ),
                if (vm.canCancel)
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final ok = await showAppConfirmDialog(
                              context,
                              title: 'Cancel ${o.poNo}?',
                              message:
                                  'Its request items go back to the queue to '
                                  'be reordered.',
                              confirmLabel: 'Cancel PO',
                              destructive: true,
                            );
                            if (ok && context.mounted) {
                              await reportAction(context, vm.cancel());
                            }
                          },
                    icon: const Icon(Icons.block),
                    label: const Text('Cancel PO'),
                  ),
                if (d.requestId != null)
                  TextButton(
                    onPressed: () =>
                        context.go(AppRoutes.materialRequest(d.requestId!)),
                    child: const Text('View request'),
                  ),
              ],
            ),
            gap,
            AppSectionCard(
              title: 'Order',
              child: Column(
                children: [
                  AppInfoRow(
                    label: 'Project',
                    value: l.projectCode(o.projectId),
                  ),
                  AppInfoRow(
                    label: 'Supplier',
                    value: l.supplierName(o.supplierId),
                  ),
                  AppInfoRow(label: 'Source', value: o.source.label),
                  if (finance) ...[
                    AppInfoRow(
                      label: 'Total',
                      value: Formatters.peso(o.totalAmount),
                    ),
                    AppInfoRow(label: 'Paid', value: Formatters.peso(vm.paid)),
                  ],
                  if (o.approvedBy != null)
                    AppInfoRow(
                      label: 'Ordered by',
                      value: l.userName(o.approvedBy),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Lines',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final i in d.items)
                    ListTile(
                      title: Text(l.materialName(i.materialId)),
                      subtitle: Text(
                        '${q(i.quantity)} ${l.unit(i.materialId)}'
                        '${finance ? ' × ${Formatters.peso(i.unitPrice)}' : ''}'
                        ' · received ${q(d.receivedFor(i.id))}',
                      ),
                      trailing: finance
                          ? Text(Formatters.peso(i.amount))
                          : null,
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
                  if (d.deliveries.isEmpty)
                    const ListTile(title: Text('Nothing received yet.')),
                  for (final dd in d.deliveries)
                    ListTile(
                      title: Text(Formatters.dateTime(dd.delivery.receivedAt)),
                      subtitle: Text(
                        [
                          for (final it in dd.items)
                            '${l.materialName(d.items.firstWhere((x) => x.id == it.purchaseOrderItemId).materialId)}: '
                                '${q(it.qtyReceived)}'
                                '${it.qtyDamaged > 0 ? ' (${q(it.qtyDamaged)} damaged)' : ''}',
                        ].join('\n'),
                      ),
                      trailing: Text(l.userName(dd.delivery.receivedBy)),
                    ),
                ],
              ),
            ),
            if (finance && d.payments.isNotEmpty) ...[
              gap,
              AppSectionCard(
                title: 'Supplier payments',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final p in d.payments)
                      ListTile(
                        title: Text(Formatters.peso(p.amount)),
                        subtitle: Text(
                          [
                            Formatters.date(p.paidOn),
                            p.method.label,
                            ?p.referenceNo,
                          ].join(' · '),
                        ),
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
