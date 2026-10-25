import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/delivery_confirm_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_receipt_line_card.dart';

/// Site engineer confirms a delivery receipt: actual quantity and damage.
class DeliveryConfirmPage extends StatefulWidget {
  const DeliveryConfirmPage({super.key, required this.orderId});

  final int orderId;

  @override
  State<DeliveryConfirmPage> createState() => _DeliveryConfirmPageState();
}

class _DeliveryConfirmPageState extends State<DeliveryConfirmPage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = DeliveryConfirmViewModel(
    orderId: widget.orderId,
    session: getIt(),
    procurement: getIt(),
    lookups: ProcurementLookups.fromServices(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(
      context,
      _vm.confirm(),
      success: 'Delivery confirmed. Site inventory updated.',
    );
    if (ok && mounted) context.go(AppRoutes.deliveries);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<DeliveryConfirmViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final o = vm.detail!.order;
          final l = vm.lookups;
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      Text(
                        'Receive ${o.poNo}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${l.supplierName(o.supplierId)} · ${l.projectCode(o.projectId)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      for (final line in vm.lines) ...[
                        ProcurementReceiptLineCard(
                          line: line,
                          materialLabel:
                              '${l.materialName(line.item.materialId)} '
                              '(${l.unit(line.item.materialId)})',
                          onChanged: vm.changed,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      SwitchListTile(
                        title: const Text('Delivery receipt photo taken'),
                        subtitle: const Text(
                          'Camera upload arrives with file storage; a placeholder '
                          'is attached for now.',
                        ),
                        value: vm.receiptPhoto,
                        onChanged: vm.setReceiptPhoto,
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'Good items go into site inventory; damaged ones are recorded.',
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm delivery'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
