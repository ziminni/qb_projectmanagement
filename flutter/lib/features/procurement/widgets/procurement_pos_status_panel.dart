import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/purchase_order_detail_viewmodel.dart';

class ProcurementPosStatusPanel extends StatelessWidget {
  const ProcurementPosStatusPanel({super.key, required this.vm, this.clock});

  final PurchaseOrderDetailViewModel vm;
  final DateTime Function()? clock;

  DateTime _now() => (clock ?? DateTime.now)();

  static String _lineSummary(PosStatusLine line) {
    final name = line.description.trim().isNotEmpty
        ? line.description.trim()
        : line.code;
    final released = InputParsers.amountText(line.released);
    final requested = InputParsers.amountText(line.requested);
    final unit = line.unit.trim().isNotEmpty ? ' ${line.unit.trim()}' : '';
    return '$name — released $released of $requested$unit';
  }

  static String _relativeLastChecked(DateTime checkedAt, DateTime now) {
    final diff = now.difference(checkedAt.toLocal());
    if (diff.isNegative || diff.inSeconds < 60) {
      return 'Last checked just now';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'Last checked $m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'Last checked $h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    final d = diff.inDays;
    return 'Last checked $d ${d == 1 ? 'day' : 'days'} ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!vm.supportsPosStatus) return const SizedBox.shrink();
    final status = vm.posStatus;
    final busy = vm.posBusy || vm.isBusy;
    final textTheme = Theme.of(context).textTheme;
    final hasStoreStatus =
        status != null &&
        status.storeStatus != null &&
        status.storeStatus!.trim().isNotEmpty;
    return AppSectionCard(
      title: 'At the store',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != null) ...[
            Text(
              status.statusSentence,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (hasStoreStatus && status.syncStatus == 'pending_sync') ...[
              const SizedBox(height: AppSpacing.xs),
              const Text('Waiting to send this order to the store.'),
            ],
            if (hasStoreStatus && status.syncStatus == 'failed') ...[
              const SizedBox(height: AppSpacing.xs),
              const Text('Could not send this order to the store.'),
            ],
            if (status.declineReason.trim().isNotEmpty &&
                status.storeStatus?.trim().toUpperCase() != 'DECLINED') ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Reason: ${status.declineReason.trim()}'),
            ],
            if (status.lines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final line in status.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Text(_lineSummary(line)),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              status.lastCheckedAt == null
                  ? 'Not checked with the store yet'
                  : _relativeLastChecked(status.lastCheckedAt!, _now()),
              style: textTheme.bodySmall,
            ),
            if (status.detail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(status.detail),
            ],
            if (status.closePending) ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Cancellation sent — waiting for the store to close this order.',
              ),
            ],
            if (status.closeNeedsReview &&
                !status.detail.contains('store may still hold')) ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Could not close this order at the store. '
                'The store may still hold this request. Retry the close.',
              ),
            ],
          ],
          if (vm.posError != null) ...[
            if (status != null) const SizedBox(height: AppSpacing.xs),
            Text(vm.posError!, style: const TextStyle(color: AppColors.error)),
          ],
          if (vm.posQueued) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Queued — checking with the store shortly.'),
          ],
          if (vm.posBusy) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Checking with the store…'),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: busy ? null : vm.refreshPosStatus,
                child: const Text('Check store now'),
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
