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
  const StoreBalanceCard({
    super.key,
    this.balance,
    this.error,
    this.receipts = const [],
    this.onSubmitReceipt,
  });

  final StoreBalance? balance;
  final String? error;
  final List<StorePaymentReceipt> receipts;
  final Future<void> Function({
    required double amount,
    required String referenceNo,
    required String paymentMethod,
    required String notes,
  })? onSubmitReceipt;

  Future<void> _showSubmitDialog(BuildContext context) async {
    final amountCtrl = TextEditingController(
      text: balance != null && balance!.balance > 0
          ? balance!.balance.toStringAsFixed(2)
          : '',
    );
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var method = 'BANK_TRANSFER';
    String? formError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Submit store payment receipt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (formError != null) ...[
                Text(
                  formError!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount (₱)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const [
                  DropdownMenuItem(
                    value: 'BANK_TRANSFER',
                    child: Text('Bank Transfer'),
                  ),
                  DropdownMenuItem(value: 'GCASH', child: Text('GCash')),
                  DropdownMenuItem(value: 'CARD', child: Text('Card')),
                  DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                ],
                onChanged: (v) => setState(() => method = v ?? 'BANK_TRANSFER'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reference / OR number',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim());
                final ref = refCtrl.text.trim();
                if (amt == null || amt <= 0) {
                  setState(() => formError = 'Enter an amount greater than 0.');
                  return;
                }
                if (ref.isEmpty) {
                  setState(() => formError = 'Enter the reference number.');
                  return;
                }
                try {
                  await onSubmitReceipt!(
                    amount: amt,
                    referenceNo: ref,
                    paymentMethod: method,
                    notes: notesCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on Object catch (e) {
                  setState(() => formError = e.toString());
                }
              },
              child: const Text('Submit to store'),
            ),
          ],
        ),
      ),
    );
  }

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
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                      if (b.balance > 0 && onSubmitReceipt != null)
                        OutlinedButton.icon(
                          onPressed: () => _showSubmitDialog(context),
                          icon: const Icon(Icons.upload_file_outlined, size: 18),
                          label: const Text('Submit payment receipt'),
                        ),
                    ],
                  ),
                if (receipts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Submitted store payment receipts',
                    style: textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  for (final r in receipts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${r.referenceNo} (${r.paymentMethod}) — '
                        '${Formatters.peso(r.amount)} · ${r.status}'
                        '${r.approvedAmount != null ? ' (Approved ${Formatters.peso(r.approvedAmount!)})' : ''}'
                        '${r.declineReason.isNotEmpty ? ' — ${r.declineReason}' : ''}',
                        style: textTheme.bodySmall,
                      ),
                    ),
                ],
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
