import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_parsers.dart';
import '../../data/models/payment_method.dart';
import 'app_date_field.dart';

class AppPaymentInput {
  const AppPaymentInput({
    required this.amount,
    required this.paidOn,
    required this.method,
    this.referenceNo,
  });

  final double amount;
  final DateTime paidOn;
  final PaymentMethod method;
  final String? referenceNo;
}

/// Records a payment against a balance; used for supplier payables and
/// client billing payments.
class AppPaymentDialog extends StatefulWidget {
  const AppPaymentDialog({
    super.key,
    required this.title,
    required this.balance,
    required this.validateAmount,
  });

  final String title;
  final double balance;
  final String? Function(double? amount) validateAmount;

  static Future<AppPaymentInput?> show(
    BuildContext context, {
    required String title,
    required double balance,
    required String? Function(double? amount) validateAmount,
  }) => showDialog<AppPaymentInput>(
    context: context,
    builder: (_) => AppPaymentDialog(
      title: title,
      balance: balance,
      validateAmount: validateAmount,
    ),
  );

  @override
  State<AppPaymentDialog> createState() => _AppPaymentDialogState();
}

class _AppPaymentDialogState extends State<AppPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: InputParsers.amountText(widget.balance),
  );
  final _reference = TextEditingController();
  DateTime _paidOn = DateTime.now();
  PaymentMethod _method = PaymentMethod.bankTransfer;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AppPaymentInput(
        amount: InputParsers.amount(_amount.text)!,
        paidOn: _paidOn,
        method: _method,
        referenceNo: InputParsers.optional(_reference.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Balance: ${Formatters.peso(widget.balance)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) => widget.validateAmount(InputParsers.amount(v)),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDateField(
                label: 'Paid on',
                value: _paidOn,
                hasError: false,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDate: _paidOn,
                  );
                  if (d != null) setState(() => _paidOn = d);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: [
                  for (final m in PaymentMethod.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => setState(() => _method = m!),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(
                  labelText: 'Reference no. (optional)',
                  hintText: 'OR, check or transfer number',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record payment')),
      ],
    );
  }
}
