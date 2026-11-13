import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/widgets/app_location_map.dart';

/// Wizard step 2: the site's address and its pin on the map.
class ProjectsLocationStep extends StatelessWidget {
  const ProjectsLocationStep({
    super.key,
    required this.location,
    required this.pin,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController location;
  final LatLng? pin;
  final ValueChanged<LatLng> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: location,
          decoration: const InputDecoration(
            labelText: 'Location',
            hintText: 'Barangay, city, province',
            prefixIcon: Icon(Icons.place_outlined),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Enter the location.' : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.infoContainer,
            borderRadius: AppRadii.mdAll,
          ),
          child: Row(
            children: [
              const Icon(Icons.touch_app_outlined, color: AppColors.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  pin == null
                      ? 'Click the map to drop a pin on the site. Scroll or '
                            'pinch to zoom.'
                      : 'Pinned at ${pin!.latitude.toStringAsFixed(5)}, '
                            '${pin!.longitude.toStringAsFixed(5)}. Click '
                            'elsewhere to move it.',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.info),
                ),
              ),
              if (pin != null)
                TextButton(onPressed: onClear, child: const Text('Clear pin')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppLocationMap(pin: pin, onPick: onPick, height: 380),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The pin is optional, but it helps the team and suppliers find '
          'the site.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}
