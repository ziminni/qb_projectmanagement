import 'package:flutter/material.dart';

import '../../../data/services/daily_report_rules.dart';

/// Asks the PM for remarks when returning a report.
class DailyReportsReturnDialog extends StatefulWidget {
  const DailyReportsReturnDialog({super.key});

  static Future<String?> show(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const DailyReportsReturnDialog(),
  );

  @override
  State<DailyReportsReturnDialog> createState() =>
      _DailyReportsReturnDialogState();
}

class _DailyReportsReturnDialogState extends State<DailyReportsReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Return report'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _remarks,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Remarks',
              hintText: 'What should the site engineer fix?',
            ),
            validator: DailyReportRules.validateReturnRemarks,
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
              Navigator.of(context).pop(_remarks.text.trim());
            }
          },
          child: const Text('Return'),
        ),
      ],
    );
  }
}
