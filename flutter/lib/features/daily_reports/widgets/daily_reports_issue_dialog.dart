import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/issue.dart';
import '../../../data/repositories/daily_report_repository.dart';
import '../../../data/services/daily_report_rules.dart';

/// Records an issue or delay, e.g. rain/typhoon days lost.
class DailyReportsIssueDialog extends StatefulWidget {
  const DailyReportsIssueDialog({super.key});

  static Future<IssueDraft?> show(BuildContext context) =>
      showDialog<IssueDraft>(
        context: context,
        builder: (_) => const DailyReportsIssueDialog(),
      );

  @override
  State<DailyReportsIssueDialog> createState() =>
      _DailyReportsIssueDialogState();
}

class _DailyReportsIssueDialogState extends State<DailyReportsIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _days = TextEditingController(text: '0');
  IssueType _type = IssueType.delay;
  IssueReason _reason = IssueReason.rainTyphoon;

  @override
  void dispose() {
    _description.dispose();
    _days.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      IssueDraft(
        type: _type,
        reason: _reason,
        description: _description.text.trim(),
        daysLost: InputParsers.amount(_days.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add issue or delay'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<IssueType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in IssueType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<IssueReason>(
                  initialValue: _reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final r in IssueReason.values)
                      DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  onChanged: (v) => setState(() => _reason = v!),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Describe the issue.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _days,
                  decoration: const InputDecoration(
                    labelText: 'Days lost',
                    helperText: 'Supports time-extension requests.',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) =>
                      DailyReportRules.validateDaysLost(InputParsers.amount(v)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
