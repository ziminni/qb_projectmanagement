import 'package:flutter/material.dart';

import '../../../data/repositories/daily_report_repository.dart';

/// Adds a site photo. Camera capture and upload arrive with file storage;
/// until then the photo is a captioned placeholder.
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

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
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
              'Camera capture is not connected yet; a placeholder photo is '
              'saved with your caption.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
          onPressed: () => Navigator.of(context).pop(
            PhotoDraft(
              fileUrl: 'mock://photos/${DateTime.now().microsecondsSinceEpoch}',
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
