import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/private_file_loader.dart';
import '../../../data/models/variation_order.dart';
import '../../../shared/widgets/app_section_card.dart';

/// Photo attachment inputs for creating or editing a variation order.
///
/// Adapts the photo slots to [type]:
/// - [VariationOrderType.additive]: 1 slot (evidence of what is to be added).
/// - [VariationOrderType.deductive]: 1 slot (what is to be removed).
/// - [VariationOrderType.change]: 2 slots (current/existing vs. new/proposed).
///
/// Each slot accepts multiple photos and supports click-to-preview.
class VoPhotoPickerSection extends StatelessWidget {
  const VoPhotoPickerSection({
    super.key,
    required this.type,
    required this.primaryAttachments,
    required this.secondaryAttachments,
    required this.onAddPrimary,
    required this.onRemovePrimary,
    required this.onAddSecondary,
    required this.onRemoveSecondary,
  });

  final VariationOrderType type;
  final List<String> primaryAttachments;
  final List<String> secondaryAttachments;
  final ValueChanged<List<String>> onAddPrimary;
  final ValueChanged<int> onRemovePrimary;
  final ValueChanged<List<String>> onAddSecondary;
  final ValueChanged<int> onRemoveSecondary;

  @override
  Widget build(BuildContext context) {
    final labels = _photoCopy(type);
    final isDesignChange = type == VariationOrderType.change;

    final primarySlot = _PhotoSlotPicker(
      key: const ValueKey('vo-photo-primary'),
      title: labels.primaryTitle,
      hint: labels.primaryHint,
      paths: primaryAttachments,
      onAdd: onAddPrimary,
      onRemove: onRemovePrimary,
    );

    if (!isDesignChange) {
      return primarySlot;
    }

    final secondarySlot = _PhotoSlotPicker(
      key: const ValueKey('vo-photo-secondary'),
      title: labels.secondaryTitle!,
      hint: labels.secondaryHint!,
      paths: secondaryAttachments,
      onAdd: onAddSecondary,
      onRemove: onRemoveSecondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: primarySlot),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: secondarySlot),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primarySlot,
            const SizedBox(height: AppSpacing.md),
            secondarySlot,
          ],
        );
      },
    );
  }
}

/// Read-only photo evidence card shown on Variation Order detail screens
/// (both PM/Foreman and Client portal).
class VoPhotoAttachmentsCard extends StatelessWidget {
  const VoPhotoAttachmentsCard({super.key, required this.vo});

  final VariationOrder vo;

  @override
  Widget build(BuildContext context) {
    if (!vo.hasAttachments) return const SizedBox.shrink();
    final labels = _photoCopy(vo.type);
    final isDesignChange = vo.type == VariationOrderType.change;

    final primarySection = vo.primaryAttachments.isEmpty
        ? null
        : _PhotoGroupView(
            label: labels.primaryTitle,
            paths: vo.primaryAttachments,
          );
    final secondarySection =
        (!isDesignChange || vo.secondaryAttachments.isEmpty)
        ? null
        : _PhotoGroupView(
            label: labels.secondaryTitle!,
            paths: vo.secondaryAttachments,
          );

    if (primarySection == null && secondarySection == null) {
      return const SizedBox.shrink();
    }

    return AppSectionCard(
      title: 'Photo evidence',
      subtitle: isDesignChange
          ? 'Current condition vs. new proposed design (tap any photo to preview)'
          : 'Attached site reference photos (tap any photo to preview)',
      icon: Icons.photo_library_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (primarySection != null &&
              secondarySection != null &&
              constraints.maxWidth >= 560) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: primarySection),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: secondarySection),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?primarySection,
              if (primarySection != null && secondarySection != null)
                const SizedBox(height: AppSpacing.md),
              ?secondarySection,
            ],
          );
        },
      ),
    );
  }
}

class _PhotoSlotPicker extends StatelessWidget {
  const _PhotoSlotPicker({
    super.key,
    required this.title,
    required this.hint,
    required this.paths,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String hint;
  final List<String> paths;
  final ValueChanged<List<String>> onAdd;
  final ValueChanged<int> onRemove;

  Future<void> _pickPhotos(BuildContext context) async {
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (files.isEmpty) return;
      final selected = files
          .map((f) => f.path)
          .where((p) => p.isNotEmpty)
          .toList();
      if (selected.isNotEmpty) onAdd(selected);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not attach photos. $e')));
      }
    }
  }

  Future<void> _takePhoto(BuildContext context) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file != null) onAdd([file.path]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not take photo. $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final picker = ImagePicker();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (paths.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: AppRadii.pillAll,
                  ),
                  child: Text(
                    '${paths.length} photo${paths.length == 1 ? '' : 's'}',
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (paths.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (i, path) in paths.indexed)
                  _PhotoTile(
                    path: path,
                    onRemove: () => onRemove(i),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickPhotos(context),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(paths.isEmpty ? 'Add photos' : 'Add more photos'),
              ),
              if (picker.supportsImageSource(ImageSource.camera))
                OutlinedButton.icon(
                  onPressed: () => _takePhoto(context),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Take photo'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoGroupView extends StatelessWidget {
  const _PhotoGroupView({required this.label, required this.paths});

  final String label;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final path in paths) _PhotoTile(path: path),
          ],
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.path, this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  void _openPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _PhotoPreviewDialog(path: path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = _fileName(path);

    return SizedBox(
      width: 156,
      child: Material(
        color: scheme.surface,
        borderRadius: AppRadii.mdAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPreview(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: _VoPhotoImage(path: path),
                    ),
                    if (onRemove != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton.filledTonal(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: 'Remove photo',
                            onPressed: onRemove,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs + 2,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_full_rounded,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreviewDialog extends StatelessWidget {
  const _PhotoPreviewDialog({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fileName(path),
                      style: textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Container(
                color: scheme.surfaceContainerLowest,
                constraints: const BoxConstraints(minHeight: 320),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Center(
                    child: _VoPhotoImage(path: path, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoPhotoImage extends StatelessWidget {
  const _VoPhotoImage({required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(
        Icons.photo_camera_back_outlined,
        size: 32,
        color: AppColors.primary,
      ),
    );
    if (path.isEmpty || path.startsWith('mock://')) {
      return placeholder;
    }
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/api/')) {
      if (getIt.isRegistered<PrivateFileLoader>()) {
        return FutureBuilder<Uint8List>(
          future: getIt<PrivateFileLoader>().bytes(path),
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) return placeholder;
            return Image.memory(
              data,
              fit: fit,
              errorBuilder: (_, _, _) => placeholder,
            );
          },
        );
      }
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (kIsWeb) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

String _fileName(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.endsWith('/') && normalized.length > 1) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final idx = normalized.lastIndexOf('/');
  return idx >= 0 && idx < normalized.length - 1
      ? normalized.substring(idx + 1)
      : normalized;
}

({
  String primaryTitle,
  String primaryHint,
  String? secondaryTitle,
  String? secondaryHint,
})
_photoCopy(VariationOrderType type) => switch (type) {
  VariationOrderType.additive => (
    primaryTitle: 'Photo evidence of work to add',
    primaryHint:
        'Attach one or more photos showing the site area or reference for what is to be added.',
    secondaryTitle: null,
    secondaryHint: null,
  ),
  VariationOrderType.deductive => (
    primaryTitle: 'Photos of work to be removed',
    primaryHint:
        'Attach one or more photos of the existing work or item to be removed.',
    secondaryTitle: null,
    secondaryHint: null,
  ),
  VariationOrderType.change => (
    primaryTitle: 'Current / existing condition',
    primaryHint: 'Photos of what is currently built or what will be changed.',
    secondaryTitle: 'New / proposed design',
    secondaryHint: 'Photos showing the new design or change.',
  ),
};
