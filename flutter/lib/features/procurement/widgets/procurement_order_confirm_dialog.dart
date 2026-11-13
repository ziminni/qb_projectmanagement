import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../viewmodels/order_form_viewmodel.dart';

/// Before an order is saved: the site engineer's list next to what the
/// owner is ordering, with where it goes and the total. Returns true when
/// the owner confirms.
abstract final class ProcurementOrderConfirmDialog {
  static Future<bool> show(BuildContext context, OrderFormViewModel vm) async {
    final theme = Theme.of(context);
    String q(double v) => InputParsers.amountText(v);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(vm.isOwnStore ? 'Confirm order' : 'Confirm purchase'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${vm.request!.number} · ${vm.project!.code}',
                  style: theme.textTheme.bodySmall,
                ),
                heading('Requested by the site engineer'),
                for (final i in vm.detail!.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          vm.covers.contains(i.id) || i.isCovered
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: vm.covers.contains(i.id)
                              ? AppColors.success
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            vm.covers.contains(i.id)
                                ? i.description
                                : i.isCovered
                                ? '${i.description} (${vm.orderNo(i.purchaseOrderId!)})'
                                : '${i.description} (left for another order)',
                          ),
                        ),
                        Text(q(i.quantity)),
                      ],
                    ),
                  ),
                heading(vm.isOwnStore ? 'You are ordering' : 'You bought'),
                for (final l in vm.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${l.description}\n'
                            '${q(l.quantity)} ${l.unit} × '
                            '${Formatters.peso(l.unitPrice)}',
                          ),
                        ),
                        Text(Formatters.peso(l.amount)),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text('Total', style: theme.textTheme.titleSmall),
                    ),
                    Text(
                      Formatters.peso(vm.total),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppInfoRow(
                  label: 'Category',
                  value: vm.lookups.categoryName(vm.categoryId),
                ),
                if (vm.isOwnStore)
                  AppInfoRow(label: 'Deliver to', value: vm.deliveryAddress)
                else ...[
                  AppInfoRow(label: 'Store', value: vm.storeName),
                  AppInfoRow(label: 'OR number', value: vm.orNumber),
                  AppInfoRow(
                    label: 'Receipt photo',
                    value: vm.receiptPhotoPath == null
                        ? 'Not attached'
                        : 'Attached',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              vm.isOwnStore ? 'Confirm and send' : 'Confirm and save',
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
