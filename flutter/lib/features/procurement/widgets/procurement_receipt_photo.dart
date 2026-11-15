import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

/// A receipt photo kept on this device until file storage arrives with the
/// backend. Missing files show a placeholder.
class ProcurementReceiptImage extends StatelessWidget {
  const ProcurementReceiptImage({super.key, required this.path, this.height});

  final String path;
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext _, Object _, StackTrace? _) => Container(
      height: height ?? 160,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(Icons.receipt_long_outlined, size: 40),
    );
    final image = kIsWeb
        ? Image.network(path, height: height, errorBuilder: fallback)
        : Image.file(File(path), height: height, errorBuilder: fallback);
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
  }
}

/// Attach a photo of the official receipt from the gallery, files or (on
/// phones) the camera.
class ProcurementReceiptPhotoField extends StatelessWidget {
  const ProcurementReceiptPhotoField({
    super.key,
    required this.path,
    required this.onChanged,
  });

  final String? path;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file != null) onChanged(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not attach photo. $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final picker = ImagePicker();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (path != null) ...[
          ProcurementReceiptImage(path: path!, height: 180),
          const SizedBox(height: AppSpacing.sm),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pick(context, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                path == null ? 'Attach receipt photo' : 'Replace photo',
              ),
            ),
            if (picker.supportsImageSource(ImageSource.camera))
              OutlinedButton.icon(
                onPressed: () => _pick(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
            if (path != null)
              TextButton(
                onPressed: () => onChanged(null),
                child: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }
}
