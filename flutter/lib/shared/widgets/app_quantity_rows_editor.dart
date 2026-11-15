import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/input_parsers.dart';

/// One editable row: a chosen item and its quantity.
class AppQuantityRow {
  AppQuantityRow({this.itemId, this.quantity = 1});

  int? itemId;
  double quantity;
}

/// Rows of item + quantity, e.g. materials used, equipment hours or the
/// items on a material request. Rows are edited in place.
class AppQuantityRowsEditor extends StatelessWidget {
  const AppQuantityRowsEditor({
    super.key,
    required this.rows,
    required this.options,
    required this.itemLabel,
    required this.quantityLabel,
    required this.addLabel,
    required this.validateQuantity,
    required this.onChanged,
  });

  final List<AppQuantityRow> rows;

  /// (id, label) pairs for the dropdown.
  final List<(int, String)> options;
  final String itemLabel;
  final String quantityLabel;
  final String addLabel;
  final String? Function(double?) validateQuantity;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('$itemLabel-$i-${row.itemId}'),
                    initialValue: row.itemId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: itemLabel),
                    items: [
                      for (final (id, label) in options)
                        DropdownMenuItem(value: id, child: Text(label)),
                    ],
                    validator: (v) => v == null ? 'Choose one.' : null,
                    onChanged: (v) {
                      row.itemId = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('$quantityLabel-$i'),
                    initialValue: InputParsers.amountText(row.quantity),
                    decoration: InputDecoration(labelText: quantityLabel),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => validateQuantity(InputParsers.amount(v)),
                    onChanged: (v) {
                      row.quantity = InputParsers.amount(v) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    rows.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              rows.add(AppQuantityRow());
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: Text(addLabel),
          ),
        ),
      ],
    );
  }
}
