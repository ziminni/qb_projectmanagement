import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/document.dart';

class DocumentsUploadInput {
  const DocumentsUploadInput(this.name, this.type, this.fileName);

  final String name;
  final DocumentType type;
  final String fileName;
}

/// Adds a project document. File picking arrives with file storage; until
/// then the file name is typed in and stored as a placeholder.
class DocumentsUploadDialog extends StatefulWidget {
  const DocumentsUploadDialog({super.key});

  static Future<DocumentsUploadInput?> show(BuildContext context) =>
      showDialog<DocumentsUploadInput>(
        context: context,
        builder: (_) => const DocumentsUploadDialog(),
      );

  @override
  State<DocumentsUploadDialog> createState() => _DocumentsUploadDialogState();
}

class _DocumentsUploadDialogState extends State<DocumentsUploadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _file = TextEditingController();
  DocumentType _type = DocumentType.plan;

  @override
  void dispose() {
    _name.dispose();
    _file.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload document'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<DocumentType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  for (final t in DocumentType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _type = t!),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Document name',
                  hintText: 'e.g. Electrical plans E-1 to E-4',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the document name.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _file,
                decoration: const InputDecoration(
                  labelText: 'File',
                  hintText: 'electrical-e1-e4.pdf',
                  helperText:
                      'File upload arrives with storage; type the file name.',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Choose a file.' : null,
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
              Navigator.of(context).pop(
                DocumentsUploadInput(
                  _name.text.trim(),
                  _type,
                  _file.text.trim(),
                ),
              );
            }
          },
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
