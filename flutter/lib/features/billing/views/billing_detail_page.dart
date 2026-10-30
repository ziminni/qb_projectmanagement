import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_billing_statement.dart';
import '../../../shared/widgets/app_billing_status_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_history_list.dart';
import '../../../shared/widgets/app_payment_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/billing_detail_viewmodel.dart';

class BillingDetailPage extends StatelessWidget {
  const BillingDetailPage({super.key, required this.billingId});

  final int billingId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(billingId),
      create: (_) => BillingDetailViewModel(
        billingId: billingId,
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
        clients: getIt(),
        company: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<BillingDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final d = vm.detail!;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Billing #${d.billing.billingNo} · ${vm.project!.code}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                AppBillingStatusChip(status: d.billing.status),
              ],
            ),
            gap,
            AppWorkflowSteps.billing(d.billing.status),
            gap,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (vm.canSubmit)
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () => reportAction(
                            context,
                            vm.submit(),
                            success: 'Sent to the client for approval.',
                          ),
                    icon: const Icon(Icons.send),
                    label: const Text('Send to client'),
                  ),
                if (vm.canCancel)
                  OutlinedButton(
                    onPressed: vm.isBusy
                        ? null
                        : () => reportAction(
                            context,
                            vm.cancel(),
                            success: 'Billing withdrawn.',
                          ),
                    child: const Text('Withdraw'),
                  ),
                if (vm.canRecordPayment)
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final input = await AppPaymentDialog.show(
                              context,
                              title: 'Client payment',
                              balance: d.balance,
                              validateAmount: vm.validatePayment,
                            );
                            if (input != null && context.mounted) {
                              await reportAction(
                                context,
                                vm.recordPayment(input),
                                success: 'Payment recorded.',
                              );
                            }
                          },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record payment'),
                  ),
              ],
            ),
            gap,
            AppBillingStatement(
              billing: d.billing,
              project: vm.project!,
              company: vm.company,
              client: vm.client,
            ),
            gap,
            AppSectionCard(
              title:
                  'Payments · ${Formatters.peso(d.paid)} of ${Formatters.peso(d.billing.netDue)}',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (d.payments.isEmpty)
                    const ListTile(title: Text('No payments yet.')),
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
            gap,
            AppSectionCard(
              title: 'History',
              padding: EdgeInsets.zero,
              child: AppHistoryList(entries: d.history, userName: vm.userName),
            ),
          ],
        );
      },
    );
  }
}
