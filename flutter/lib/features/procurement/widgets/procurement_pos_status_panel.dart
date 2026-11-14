import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/purchase_order_detail_viewmodel.dart';

class ProcurementPosStatusPanel extends StatelessWidget {
  const ProcurementPosStatusPanel({super.key, required this.vm});

  final PurchaseOrderDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (!vm.supportsPosStatus) return const SizedBox.shrink();
    final status = vm.posStatus;
    final busy = vm.posBusy || vm.isBusy;
    return AppSectionCard(
      title: 'Store sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cached snapshot only. Refresh reads the CPMS cache, '
            'not the store.',
          ),
          const Text(
            'PO “Released” means ordered; not proof of physical release.',
          ),
          if (status != null) ...[
            AppInfoRow(label: 'Cached sync state', value: status.syncStatus),
            AppInfoRow(
              label: 'Raw store status',
              value: status.storeStatus ?? 'Not checked',
            ),
            Text(
              status.stale
                  ? 'Stale cached data'
                  : 'Cached data (fresh when read)',
            ),
            AppInfoRow(
              label: 'Last checked',
              value: status.lastCheckedAt == null
                  ? 'Never'
                  : Formatters.dateTime(status.lastCheckedAt!.toLocal()),
            ),
            if (status.detail.isNotEmpty) Text(status.detail),
            if (status.declineReason.isNotEmpty)
              AppInfoRow(label: 'Decline reason', value: status.declineReason),
            if (status.closePending)
              const Text('Store close queued; not confirmed.'),
            if (status.closeNeedsReview)
              const Text(
                'Close failed. The store may still hold this request. Retry the close.',
              ),
          ],
          if (vm.posError != null) Text(vm.posError!),
          if (vm.posQueued) const Text('Queued'),
          if (vm.posBusy) const Text('Store sync request in progress…'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: busy ? null : vm.refreshPosStatus,
                child: const Text('Refresh cached snapshot'),
              ),
              if (vm.canRetryStoreSync)
                OutlinedButton(
                  onPressed: busy ? null : vm.retryStoreSync,
                  child: const Text('Retry store sync'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
