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
import '../../../shared/widgets/app_payment_dialog.dart';
import '../viewmodels/payables_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';

/// Accountant's supplier payables: delivered value vs. paid per PO.
class PayablesPage extends StatelessWidget {
  const PayablesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PayablesViewModel(
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PayablesViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = vm.lookups;
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Unpaid: ${Formatters.peso(vm.totalBalance)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilterChip(
                  label: const Text('Unpaid only'),
                  selected: vm.unpaidOnly,
                  onSelected: vm.setUnpaidOnly,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.items.isEmpty)
              const AppEmptyState(message: 'No supplier balances.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, p) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        onTap: () =>
                            context.go(AppRoutes.purchaseOrder(p.order.id)),
                        title: Text(
                          '${p.order.poNo} · ${l.supplierName(p.order.supplierId)}',
                        ),
                        subtitle: Text(
                          '${l.projectCode(p.order.projectId)} · delivered '
                          '${Formatters.peso(p.deliveredValue)} · paid '
                          '${Formatters.peso(p.paid)}',
                        ),
                        trailing: Wrap(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(Formatters.peso(p.balance)),
                            if (vm.canPay && p.balance > 0.005)
                              FilledButton.tonal(
                                onPressed: () async {
                                  final input = await AppPaymentDialog.show(
                                    context,
                                    title: 'Pay ${p.order.poNo}',
                                    balance: p.balance,
                                    validateAmount: (a) =>
                                        vm.validateAmount(p, a),
                                  );
                                  if (input != null && context.mounted) {
                                    await reportAction(
                                      context,
                                      vm.pay(p, input),
                                      success: 'Payment recorded.',
                                    );
                                  }
                                },
                                child: const Text('Pay'),
                              ),
                          ],
                        ),
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
