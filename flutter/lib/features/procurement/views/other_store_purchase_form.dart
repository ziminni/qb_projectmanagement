import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/material_source.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_action_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/order_form_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_budget_card.dart';
import '../widgets/procurement_category_field.dart';
import '../widgets/procurement_line_editor.dart';
import '../widgets/procurement_order_confirm_dialog.dart';
import '../widgets/procurement_receipt_photo.dart';
import '../widgets/procurement_request_summary.dart';

/// The "Other store" tab: the owner logs materials already bought and paid
/// at another store, with the official receipt number and its photo.
class OtherStorePurchaseForm extends StatefulWidget {
  const OtherStorePurchaseForm({
    super.key,
    required this.requestId,
    this.onSaved,
  });

  final int requestId;
  final VoidCallback? onSaved;

  @override
  State<OtherStorePurchaseForm> createState() => _OtherStorePurchaseFormState();
}

class _OtherStorePurchaseFormState extends State<OtherStorePurchaseForm> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = OrderFormViewModel(
    requestId: widget.requestId,
    source: MaterialSource.external,
    session: getIt(),
    procurement: getIt(),
    catalog: getIt(),
    lookups: ProcurementLookups.fromServices(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await ProcurementOrderConfirmDialog.show(context, _vm) || !mounted) {
      return;
    }
    final coversAll = _vm.coversAll;
    final ok = await reportAction(
      context,
      _vm.submit(),
      success: coversAll
          ? 'Purchase saved. Every requested item is covered.'
          : 'Purchase saved. Add another order for the rest if needed.',
    );
    // Back to the request (or modal caller), where the rest can go to the other source.
    if (ok && mounted) {
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        context.go(AppRoutes.materialRequest(widget.requestId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<OrderFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final r = vm.request!;
          final small = Theme.of(context).textTheme.bodySmall;
          const gap = SizedBox(height: AppSpacing.lg);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      Text(
                        '${r.number} · ${vm.project!.code}'
                        ' · needed by ${Formatters.date(r.neededBy)}',
                        style: small,
                      ),
                      gap,
                      ProcurementRequestedItems(
                        items: vm.detail!.items,
                        orderNo: vm.orderNo,
                        selected: vm.covers,
                        onToggle: vm.toggleCover,
                      ),
                      gap,
                      ProcurementCategoryField(vm: vm),
                      gap,
                      AppSectionCard(
                        title: 'What you bought',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Store name',
                              ),
                              validator: (v) =>
                                  ProcurementRules.validateRequired(
                                    v,
                                    'store name',
                                  ),
                              onChanged: (v) => vm.storeName = v,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Pick a suggested name when it is on the price '
                              'list so it counts in site inventory.',
                              style: small,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            for (final line in vm.lines)
                              ProcurementLineEditor(
                                key: ObjectKey(line),
                                line: line,
                                nameLabel: 'Material',
                                showPrice: true,
                                suggestions: vm.priceList,
                                onChanged: vm.changed,
                                onRemove: () => vm.removeLine(line),
                              ),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: vm.addLine,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add material'),
                                ),
                                const Spacer(),
                                Text(
                                  'Total ${Formatters.peso(vm.total)}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (vm.budget != null) ...[
                        gap,
                        ProcurementBudgetCard(check: vm.budget!),
                      ],
                      gap,
                      AppSectionCard(
                        title: 'Official receipt',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'OR number',
                              ),
                              validator: (v) =>
                                  ProcurementRules.validateRequired(
                                    v,
                                    'OR number',
                                  ),
                              onChanged: (v) => vm.orNumber = v,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ProcurementReceiptPhotoField(
                              path: vm.receiptPhotoPath,
                              onChanged: vm.setReceiptPhoto,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'Paid at the store, so it is not a payable. The site '
                      'engineer confirms it when it arrives.',
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save purchase'),
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
