import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/client_variation_order_detail_viewmodel.dart';

/// A variation order in the client portal, with Approve and Reject.
class ClientVariationOrderDetailPage extends StatelessWidget {
  const ClientVariationOrderDetailPage({super.key, required this.voId});

  final int voId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(voId),
      create: (_) => ClientVariationOrderDetailViewModel(
        voId: voId,
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientVariationOrderDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final v = vm.vo!;
        final p = vm.project!;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${v.voNo} · ${p.name}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                AppVoStatusChip(status: v.status),
              ],
            ),
            gap,
            AppWorkflowSteps.variationOrder(v),
            gap,
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
                            success:
                                'Approved. The contract and schedule are updated.',
                          ),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve change'),
                  ),
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final reason = await AppReasonDialog.show(
                              context,
                              title: 'Reject ${v.voNo}',
                              confirmLabel: 'Reject',
                            );
                            if (reason != null && context.mounted) {
                              await reportAction(context, vm.reject(reason));
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
              title: 'Change',
              child: Column(
                children: [
                  AppInfoRow(label: 'Type', value: v.type.label),
                  AppInfoRow(label: 'Description', value: v.description),
                  AppInfoRow(
                    label: 'Contract change',
                    value:
                        '${v.amount >= 0 ? '+' : '−'}${Formatters.peso(v.amount.abs())}',
                  ),
                  AppInfoRow(
                    label: 'Schedule change',
                    value: '${v.daysImpact} day(s)',
                  ),
                  AppInfoRow(
                    label: 'Contract amount now',
                    value: Formatters.peso(p.contractAmount),
                  ),
                  AppInfoRow(
                    label: 'Target completion',
                    value: Formatters.date(p.targetEndDate),
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
