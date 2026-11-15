import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/services/labor_rules.dart';

class LaborCashAdvanceDialog extends StatefulWidget {
  const LaborCashAdvanceDialog({
    super.key,
    required this.line,
    required this.workerName,
  });

  final PayrollLine line;
  final String workerName;

  static Future<double?> show(
    BuildContext context, {
    required PayrollLine line,
    required String workerName,
  }) => showDialog<double>(
    context: context,
    builder: (_) => LaborCashAdvanceDialog(line: line, workerName: workerName),
  );

  @override
  State<LaborCashAdvanceDialog> createState() => _LaborCashAdvanceDialogState();
}

class _LaborCashAdvanceDialogState extends State<LaborCashAdvanceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: InputParsers.amountText(widget.line.cashAdvance),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cash advance · ${widget.workerName}'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _amount,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₱ ',
              helperText: 'Gross pay: ${Formatters.peso(widget.line.grossPay)}',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => LaborRules.validateCashAdvance(
              InputParsers.amount(v) ?? 0,
              widget.line.grossPay,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(InputParsers.amount(_amount.text) ?? 0);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
