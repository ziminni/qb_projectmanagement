import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/supplier.dart';
import '../../../data/services/procurement_rules.dart';
import '../viewmodels/purchase_order_create_viewmodel.dart';

/// One request item: include it, pick Own store or Other supplier, and set
/// the unit price.
class ProcurementOrderLineCard extends StatelessWidget {
  const ProcurementOrderLineCard({
    super.key,
    required this.line,
    required this.materialLabel,
    required this.ownStore,
    required this.externalSuppliers,
    required this.onSource,
    required this.onChanged,
  });

  final OrderLineDraft line;
  final String materialLabel;
  final Supplier? ownStore;
  final List<Supplier> externalSuppliers;
  final ValueChanged<MaterialSource> onSource;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: line.include,
                  onChanged: (v) {
                    line.include = v ?? false;
                    onChanged();
                  },
                ),
                Expanded(
                  child: Text(materialLabel, style: textTheme.titleSmall),
                ),
                Text(Formatters.peso(line.amount)),
              ],
            ),
            if (line.include) ...[
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<MaterialSource>(
                segments: [
                  for (final s in MaterialSource.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {line.source},
                onSelectionChanged: (s) => onSource(s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: 280,
                    child: line.source == MaterialSource.ownStore
                        ? InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Supplier',
                            ),
                            child: Text(
                              ownStore?.name ?? 'No own store set up',
                            ),
                          )
                        : DropdownButtonFormField<int>(
                            key: ValueKey(
                              'supplier-${line.item.id}-${line.source}',
                            ),
                            initialValue: line.supplierId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Supplier',
                            ),
                            items: [
                              for (final s in externalSuppliers)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                            ],
                            validator: (v) =>
                                v == null ? 'Choose a supplier.' : null,
                            onChanged: (v) {
                              line.supplierId = v;
                              onChanged();
                            },
                          ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      key: ValueKey('price-${line.item.id}'),
                      initialValue: InputParsers.amountText(line.unitPrice),
                      decoration: const InputDecoration(
                        labelText: 'Unit price',
                        prefixText: '₱ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) => ProcurementRules.validateUnitPrice(
                        InputParsers.amount(v),
                      ),
                      onChanged: (v) {
                        line.unitPrice = InputParsers.amount(v) ?? 0;
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
