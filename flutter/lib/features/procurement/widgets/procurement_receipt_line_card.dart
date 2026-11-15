import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/services/procurement_rules.dart';
import '../viewmodels/delivery_confirm_viewmodel.dart';

/// One PO line on a delivery: quantity received now and how much is damaged.
class ProcurementReceiptLineCard extends StatelessWidget {
  const ProcurementReceiptLineCard({
    super.key,
    required this.line,
    required this.materialLabel,
    required this.onChanged,
  });

  final ReceiptLine line;
  final String materialLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    String q(double v) => InputParsers.amountText(v);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(materialLabel, style: textTheme.titleSmall),
            Text(
              'Ordered ${q(line.item.quantity)} · already received '
              '${q(line.alreadyReceived)} · ${q(line.remaining)} to go',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: q(line.received),
                    decoration: const InputDecoration(labelText: 'Received'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => ProcurementRules.validateReceipt(
                      ordered: line.item.quantity,
                      alreadyReceived: line.alreadyReceived,
                      received: InputParsers.amount(v) ?? 0,
                      damaged: line.damaged,
                    ),
                    onChanged: (v) {
                      line.received = InputParsers.amount(v) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    initialValue: q(line.damaged),
                    decoration: const InputDecoration(labelText: 'Damaged'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final d = InputParsers.amount(v) ?? 0;
                      return d > line.received
                          ? 'Damaged cannot exceed received.'
                          : null;
                    },
                    onChanged: (v) {
                      line.damaged = InputParsers.amount(v) ?? 0;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
