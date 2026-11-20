import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_request_item.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/order_form_viewmodel.dart';
import 'procurement_line_editor.dart';
import 'store_product_picker.dart';

/// One row per requested item: what the engineer asked for and the store
/// product the owner chose for it, at the store's (locked) price.
class OwnStoreMatchCard extends StatelessWidget {
  const OwnStoreMatchCard({super.key, required this.vm});

  final OrderFormViewModel vm;

  Future<void> _choose(BuildContext context, MaterialRequestItem item) async {
    final picked = await StoreProductPicker.show(
      context,
      item: item,
      rank: vm.rankFor,
    );
    if (picked != null) vm.match(item, picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final items = vm.detail!.items;
    final open = items.where((i) => !i.isCovered).toList();
    final matched = open.where((i) => vm.matchFor(i.id) != null).length;
    return AppSectionCard(
      title: 'Match requested items to store products',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            open.isEmpty
                ? 'Every requested item is already covered by an order.'
                : '$matched of ${open.length} matched. Items you leave '
                      'unmatched can be bought elsewhere later.',
            style: small,
          ),
          if (vm.catalogError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.cloud_off, color: theme.colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(vm.catalogError!)),
                TextButton(
                  onPressed: vm.reloadCatalog,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final item in items) ...[
            _ItemRow(
              item: item,
              vm: vm,
              onChoose: vm.catalogError == null
                  ? () => _choose(context, item)
                  : null,
            ),
            const Divider(height: AppSpacing.lg),
          ],
          if (vm.lines.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Order total ${Formatters.peso(vm.total)}',
                style: theme.textTheme.titleMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.vm, this.onChoose});

  final MaterialRequestItem item;
  final OrderFormViewModel vm;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asked = '${InputParsers.amountText(item.quantity)} ${item.unit}'
        .trim();
    final line = vm.matchFor(item.id);
    final header = Row(
      children: [
        Icon(
          item.isCovered || line != null
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          size: 20,
          color: item.isCovered || line != null ? AppColors.success : null,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '${item.description} · $asked',
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (!item.isCovered && line == null)
          FilledButton.tonalIcon(
            onPressed: onChoose,
            icon: const Icon(Icons.search),
            label: const Text('Choose store product'),
          ),
        if (line != null)
          TextButton(onPressed: onChoose, child: const Text('Change')),
      ],
    );
    if (item.isCovered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Covered by ${vm.orderNo(item.purchaseOrderId!)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    if (line == null) return header;
    final unitDiffers =
        line.unit.trim().toLowerCase() != item.unit.trim().toLowerCase() &&
        item.unit.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProcurementLineEditor(
                key: ObjectKey(line),
                line: line,
                nameLabel: 'Store product',
                fixedName: true,
                showPrice: true,
                lockPrice: true,
                onChanged: vm.changed,
                onRemove: () => vm.unmatch(item.id),
              ),
              if (unitDiffers)
                Text(
                  'The store sells this per ${line.unit}; the engineer asked '
                  'in ${item.unit}. Check the quantity.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
