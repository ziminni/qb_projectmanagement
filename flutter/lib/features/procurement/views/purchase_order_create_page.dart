import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/procurement_lookups.dart';
import '../viewmodels/purchase_order_create_viewmodel.dart';
import '../widgets/procurement_order_line_card.dart';

/// Purchasing picks a source per item; each supplier becomes one PO.
class PurchaseOrderCreatePage extends StatefulWidget {
  const PurchaseOrderCreatePage({super.key, required this.requestId});

  final int requestId;

  @override
  State<PurchaseOrderCreatePage> createState() =>
      _PurchaseOrderCreatePageState();
}

class _PurchaseOrderCreatePageState extends State<PurchaseOrderCreatePage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = PurchaseOrderCreateViewModel(
    requestId: widget.requestId,
    session: getIt(),
    procurement: getIt(),
    company: getIt(),
    lookups: ProcurementLookups.fromServices(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(context, _vm.create());
    if (ok && mounted) {
      showAppMessage(context, '${_vm.createdCount} purchase order(s) created.');
      context.go(AppRoutes.purchaseOrders);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<PurchaseOrderCreateViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final r = vm.detail!.request;
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
                        'Order ${r.number} · ${l.projectCode(r.projectId)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        'Pick Own store or Other supplier per item. One request can '
                        'be split between both; each supplier becomes its own PO.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      for (final line in vm.lines) ...[
                        ProcurementOrderLineCard(
                          line: line,
                          materialLabel:
                              '${l.materialName(line.item.materialId)} · '
                              '${InputParsers.amountText(line.item.quantity)} '
                              '${l.unit(line.item.materialId)}',
                          ownStore: vm.ownStore,
                          externalSuppliers: vm.externalSuppliers,
                          onSource: (s) => vm.setSource(line, s),
                          onChanged: vm.changed,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      AppSectionCard(
                        title: 'Purchase orders to create',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (vm.totalsBySupplier.isEmpty)
                              const Text('Choose suppliers above.'),
                            for (final e in vm.totalsBySupplier.entries)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l.supplierName(e.key)),
                                subtitle: e.value > vm.threshold
                                    ? const Text(
                                        'Above the approval threshold; goes to the '
                                        'owner first.',
                                        style: TextStyle(
                                          color: AppColors.warning,
                                        ),
                                      )
                                    : const Text('Released to the supplier.'),
                                trailing: Text(Formatters.peso(e.value)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'Each supplier becomes one PO. POs above ₱${vm.threshold.toStringAsFixed(0)} go to the owner first.',
                  children: [
                    FilledButton(
                      onPressed: vm.isBusy ? null : _create,
                      child: const Text('Create purchase orders'),
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
