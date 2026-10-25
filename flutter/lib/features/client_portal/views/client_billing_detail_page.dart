import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_billing_statement.dart';
import '../../../shared/widgets/app_billing_status_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/client_billing_detail_viewmodel.dart';

/// A billing in the client portal, with Approve and Dispute.
class ClientBillingDetailPage extends StatelessWidget {
  const ClientBillingDetailPage({super.key, required this.billingId});

  final int billingId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(billingId),
      create: (_) => ClientBillingDetailViewModel(
        billingId: billingId,
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientBillingDetailViewModel>();
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
                    'Billing #${d.billing.billingNo}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                AppBillingStatusChip(status: d.billing.status),
              ],
            ),
            gap,
            AppWorkflowSteps.billing(d.billing.status),
            gap,
            if (vm.disputeReason != null && !vm.canRespond) ...[
              Card(
                color: AppColors.warningContainer,
                child: ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('You disputed this billing'),
                  subtitle: Text(vm.disputeReason!),
                ),
              ),
              gap,
            ],
            if (vm.canRespond) ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () => reportAction(
                            context,
                            vm.approve(),
                            success: 'Billing approved. Thank you.',
                          ),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve billing'),
                  ),
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final reason = await AppReasonDialog.show(
                              context,
                              title: 'Dispute billing',
                              label: 'What should be corrected?',
                              confirmLabel: 'Send dispute',
                            );
                            if (reason != null && context.mounted) {
                              await reportAction(
                                context,
                                vm.dispute(reason),
                                success: 'Dispute sent to the project manager.',
                              );
                            }
                          },
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Dispute'),
                  ),
                ],
              ),
              gap,
            ],
            AppBillingStatement(
              billing: d.billing,
              project: vm.project!,
              company: vm.company,
            ),
            gap,
            AppSectionCard(
              title:
                  'Payments · ${Formatters.peso(d.paid)} of ${Formatters.peso(d.billing.netDue)}',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (d.payments.isEmpty)
                    const ListTile(title: Text('No payments recorded yet.')),
                  for (final p in d.payments)
                    ListTile(
                      title: Text(Formatters.peso(p.amount)),
                      subtitle: Text(
                        '${Formatters.date(p.paidOn)} · ${p.method.label}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
