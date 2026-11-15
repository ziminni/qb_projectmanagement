import 'package:flutter/material.dart';

/// Asks for a required reason, e.g. when rejecting or disputing something.
/// Resolves to the trimmed reason, or null when cancelled.
class AppReasonDialog extends StatefulWidget {
  const AppReasonDialog({
    super.key,
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.message,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? message;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String label = 'Reason',
    required String confirmLabel,
    String? message,
  }) => showDialog<String>(
    context: context,
    builder: (_) => AppReasonDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      message: message,
    ),
  );

  @override
  State<AppReasonDialog> createState() => _AppReasonDialogState();
}

class _AppReasonDialogState extends State<AppReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message != null) ...[
                Text(widget.message!),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _text,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(labelText: widget.label),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'This is required.'
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
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_text.text.trim());
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
