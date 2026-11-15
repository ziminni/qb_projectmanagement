import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_config.dart';
import '../../../data/repositories/daily_report_repository.dart';

/// Adds a site photo. With the API the picked file's bytes are uploaded and
/// the server checks jpg/png by content; the demo keeps a captioned
/// placeholder.
class DailyReportsPhotoDialog extends StatefulWidget {
  const DailyReportsPhotoDialog({super.key});

  static Future<PhotoDraft?> show(BuildContext context) =>
      showDialog<PhotoDraft>(
        context: context,
        builder: (_) => const DailyReportsPhotoDialog(),
      );

  @override
  State<DailyReportsPhotoDialog> createState() =>
      _DailyReportsPhotoDialogState();
}

class _DailyReportsPhotoDialogState extends State<DailyReportsPhotoDialog> {
  final _caption = TextEditingController();
  Uint8List? _bytes;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add photo'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useApi
                  ? 'Choose the site photo from this machine.'
                  : 'Camera capture is not connected yet; a placeholder photo '
                        'is saved with your caption.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (useApi) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_bytes == null ? 'Choose photo' : 'Replace photo'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Caption',
                hintText: 'e.g. Column formworks, grid B',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // The server stores the file itself, so a caption is not a photo.
          onPressed: useApi && _bytes == null
              ? null
              : () => Navigator.of(context).pop(
                  PhotoDraft(
                    fileUrl: useApi
                        ? null
                        : 'mock://photos/'
                              '${DateTime.now().microsecondsSinceEpoch}',
                    bytes: _bytes,
                    caption: _caption.text.trim().isEmpty
                        ? null
                        : _caption.text.trim(),
                    takenAt: DateTime.now(),
                  ),
                ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
