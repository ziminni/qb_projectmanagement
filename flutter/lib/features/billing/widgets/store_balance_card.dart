import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/store_balance.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';

/// What the project owes the company hardware store, from the store's record.
///
/// The store holds the debt and records its payments, so this card only reads:
/// it never adds or edits anything, and a store that cannot be reached is said
/// plainly instead of showing a stale or made-up figure.
class StoreBalanceCard extends StatelessWidget {
  const StoreBalanceCard({super.key, this.balance, this.error});

  final StoreBalance? balance;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final b = balance;
    return AppSectionCard(
      title: 'Owed to the store',
      child: b == null
          ? Text(
              'Store balance unavailable: ${error ?? 'no answer from the store'}',
              style: textTheme.bodyMedium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!b.atStore)
                  const Text('Nothing owed to the store yet.')
                else
                  Wrap(
                    spacing: 32,
                    runSpacing: 12,
                    children: [
                      AppFigure(
                        label: 'Charged',
                        value: Formatters.peso(b.total),
                      ),
                      AppFigure(label: 'Paid', value: Formatters.peso(b.paid)),
                      AppFigure(
                        label: 'Balance',
                        value: Formatters.peso(b.balance),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  "From the store's own record at "
                  '${Formatters.dateTime(b.fetchedAt)}. Payments are recorded at '
                  'the store, not here.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
