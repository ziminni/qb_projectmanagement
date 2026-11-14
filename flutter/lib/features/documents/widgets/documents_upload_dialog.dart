import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_config.dart';
import '../../../data/models/document.dart';

class DocumentsUploadInput {
  const DocumentsUploadInput(this.name, this.type, this.filePath);

  final String name;
  final DocumentType type;

  /// The file name in the demo; the full path of a real file to upload.
  final String filePath;
}

/// Adds a project document. The API uploads the file itself, so the field
/// takes the file's path on this machine; the demo still stores the name.
class DocumentsUploadDialog extends StatefulWidget {
  const DocumentsUploadDialog({super.key, required this.types});

  /// Sections the uploader may file into.
  final List<DocumentType> types;

  static Future<DocumentsUploadInput?> show(
    BuildContext context, {
    required List<DocumentType> types,
  }) => showDialog<DocumentsUploadInput>(
    context: context,
    builder: (_) => DocumentsUploadDialog(types: types),
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
                  for (final t in widget.types)
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
                decoration: InputDecoration(
                  labelText: useApi ? 'File path' : 'File',
                  hintText: useApi
                      ? '/home/you/plans/electrical-e1-e4.pdf'
                      : 'electrical-e1-e4.pdf',
                  helperText: useApi
                      ? 'Paste the full path; the file is uploaded from this '
                            'machine.'
                      : 'File upload arrives with storage; type the file name.',
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
