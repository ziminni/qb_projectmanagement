import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';

/// Site photo thumbnail. Mock photos (`mock://`) show a placeholder until
/// file storage exists; real URLs load over the network.
class AppPhotoTile extends StatelessWidget {
  const AppPhotoTile({
    super.key,
    required this.fileUrl,
    this.caption,
    this.subtitle,
    this.onRemove,
  });

  final String fileUrl;
  final String? caption;
  final String? subtitle;
  final VoidCallback? onRemove;

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
                    child: fileUrl.startsWith('mock://')
                        ? placeholder
                        : Image.network(
                            fileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
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
