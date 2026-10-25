import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/trade.dart';
import '../viewmodels/daily_report_form_viewmodel.dart';

/// Manpower per trade: one row per trade with a headcount.
class DailyReportsManpowerEditor extends StatelessWidget {
  const DailyReportsManpowerEditor({
    super.key,
    required this.rows,
    required this.trades,
    required this.onChanged,
  });

  final List<ManpowerRow> rows;
  final List<Trade> trades;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold(0, (s, r) => s + r.headcount);
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
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('trade-$i-${row.trade}'),
                    initialValue: row.trade,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Trade'),
                    items: [
                      for (final t in trades)
                        DropdownMenuItem(value: t.name, child: Text(t.name)),
                    ],
                    validator: (v) => v == null ? 'Choose a trade.' : null,
                    onChanged: (v) {
                      row.trade = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('headcount-$i'),
                    initialValue: '${row.headcount}',
                    decoration: const InputDecoration(labelText: 'Headcount'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n <= 0) ? 'More than 0' : null;
                    },
                    onChanged: (v) {
                      row.headcount = int.tryParse(v) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove trade',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    rows.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                rows.add(ManpowerRow());
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add trade'),
            ),
            const Spacer(),
            Text('Total: $total', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
