import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/private_file_loader.dart';

/// Site photo thumbnail. Demo photos (`mock://`) show a placeholder; a stored
/// photo comes from the private API, so it is fetched with the JWT client
/// ([PrivateFileLoader]) instead of `Image.network`, which cannot send one.
class AppPhotoTile extends StatelessWidget {
  const AppPhotoTile({
    super.key,
    this.fileUrl,
    this.bytes,
    this.caption,
    this.subtitle,
    this.onRemove,
  });

  /// The stored photo's URL, when it has one.
  final String? fileUrl;

  /// A photo that is not uploaded yet (picked on this machine).
  final Uint8List? bytes;

  final String? caption;
  final String? subtitle;
  final VoidCallback? onRemove;

  Widget _image(Widget placeholder) {
    final url = fileUrl;
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (url == null || url.isEmpty || url.startsWith('mock://')) {
      return placeholder;
    }
    return FutureBuilder<Uint8List>(
      future: getIt<PrivateFileLoader>().bytes(url),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return placeholder;
        return Image.memory(
          data,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final placeholder = Container(
      color: AppColors.primaryContainer,
      alignment: Alignment.center,
      child: const Icon(
        Icons.photo_camera_back_outlined,
        size: 36,
        color: AppColors.primary,
      ),
    );
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadii.md),
                  ),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _image(placeholder),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove photo',
                      iconSize: 18,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption ?? 'No caption',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
