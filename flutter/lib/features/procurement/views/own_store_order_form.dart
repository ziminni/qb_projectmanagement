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
import '../widgets/own_store_match_card.dart';
import '../widgets/procurement_order_confirm_dialog.dart';

/// The "Own hardware store" tab: the owner matches each requested item to a
/// store product (at the store's price), and says where to deliver.
class OwnStoreOrderForm extends StatefulWidget {
  const OwnStoreOrderForm({super.key, required this.requestId});

  final int requestId;

  @override
  State<OwnStoreOrderForm> createState() => _OwnStoreOrderFormState();
}

class _OwnStoreOrderFormState extends State<OwnStoreOrderForm> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  late final OrderFormViewModel _vm = OrderFormViewModel(
    requestId: widget.requestId,
    source: MaterialSource.ownStore,
    session: getIt(),
    procurement: getIt(),
    catalog: getIt(),
    lookups: ProcurementLookups.fromServices(),
  )..load().then((_) => _address.text = _vm.deliveryAddress);

  @override
  void dispose() {
    _vm.dispose();
    _address.dispose();
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
          ? 'Ordered from own store. Every requested item is covered.'
          : 'Ordered from own store. Add another order for the rest if needed.',
    );
    // Back to the request, where the rest can go to the other source.
    if (ok && mounted) context.go(AppRoutes.materialRequest(widget.requestId));
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
                      OwnStoreMatchCard(vm: vm),
                      gap,
                      ProcurementCategoryField(vm: vm),
                      if (vm.budget != null) ...[
                        gap,
                        ProcurementBudgetCard(check: vm.budget!),
                      ],
                      gap,
                      AppSectionCard(
                        title: 'Deliver to',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _address,
                              decoration: const InputDecoration(
                                labelText: 'Delivery address',
                              ),
                              maxLines: 2,
                              minLines: 1,
                              validator: (v) =>
                                  ProcurementRules.validateRequired(
                                    v,
                                    'delivery address',
                                  ),
                              onChanged: (v) => vm.deliveryAddress = v,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  vm.useSiteAddress();
                                  _address.text = vm.deliveryAddress;
                                },
                                icon: const Icon(Icons.place_outlined),
                                label: const Text('Deliver on site'),
                              ),
                            ),
                            Text('Site: ${vm.project!.location}', style: small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'The site engineer confirms the delivery when it arrives.',
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy || vm.catalogError != null
                          ? null
                          : _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Send order'),
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
