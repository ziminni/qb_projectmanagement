import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/variation_order.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_history_list.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/variation_order_detail_viewmodel.dart';

class VariationOrderDetailPage extends StatelessWidget {
  const VariationOrderDetailPage({super.key, required this.voId});

  final int voId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(voId),
      create: (_) => VariationOrderDetailViewModel(
        voId: voId,
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<VariationOrderDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final v = vm.vo!;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${v.voNo} · ${vm.project!.code}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                AppVoStatusChip(status: v.status),
              ],
            ),
            gap,
            AppWorkflowSteps.variationOrder(v),
            gap,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (vm.canPrepare) ...[
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () => reportAction(
                            context,
                            vm.submit(),
                            success: 'Sent to the client.',
                          ),
                    icon: const Icon(Icons.send),
                    label: const Text('Send to client'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('${AppRoutes.variationOrders}/${v.id}/edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
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
                if (v.status == VariationOrderStatus.approved &&
                    vm.role == AppRole.owner)
                  OutlinedButton.icon(
                    onPressed: () => context.go(
                      AppRoutes.projectTab(v.projectId, ProjectTab.schedule),
                    ),
                    icon: const Icon(Icons.checklist),
                    label: const Text('Update categories and to-dos'),
                  ),
              ],
            ),
            gap,
            AppSectionCard(
              title: 'Change',
              child: Column(
                children: [
                  AppInfoRow(label: 'Type', value: v.type.label),
                  AppInfoRow(label: 'Description', value: v.description),
                  if (vm.role.seesFinance)
                    AppInfoRow(
                      label: 'Cost impact',
                      value:
                          '${v.amount >= 0 ? '+' : '−'}${Formatters.peso(v.amount.abs())}',
                    ),
                  AppInfoRow(
                    label: 'Time impact',
                    value: '${v.daysImpact} day(s)',
                  ),
                  AppInfoRow(
                    label: 'Sent to client by',
                    value: v.approvedByOwner == null
                        ? 'Pending'
                        : vm.userName(v.approvedByOwner!),
                  ),
                  AppInfoRow(
                    label: 'Client approval',
                    value: v.approvedByClient == null
                        ? 'Pending'
                        : vm.userName(v.approvedByClient!),
                  ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'History',
              padding: EdgeInsets.zero,
              child: AppHistoryList(
                entries: vm.detail!.history,
                userName: vm.userName,
              ),
            ),
          ],
        );
      },
    );
  }
}
