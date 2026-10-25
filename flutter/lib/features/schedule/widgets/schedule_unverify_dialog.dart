import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/todo.dart';

/// Asks the PM for the reason a to-do is being un-verified. Resolves to the
/// reason, or null when cancelled.
class ScheduleUnverifyDialog extends StatefulWidget {
  const ScheduleUnverifyDialog({super.key, required this.todo});

  final Todo todo;

  static Future<String?> show(BuildContext context, Todo todo) =>
      showDialog<String>(
        context: context,
        builder: (_) => ScheduleUnverifyDialog(todo: todo),
      );

  @override
  State<ScheduleUnverifyDialog> createState() => _ScheduleUnverifyDialogState();
}

class _ScheduleUnverifyDialogState extends State<ScheduleUnverifyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Un-verify to-do'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${widget.todo.title}" will stop counting toward progress. '
                'The reason is saved in the audit log.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a reason for un-verifying.'
                    : null,
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
        FilledButton(onPressed: _submit, child: const Text('Un-verify')),
      ],
    );
  }
}
