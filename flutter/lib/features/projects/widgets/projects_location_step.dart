import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../data/services/geocoding_service.dart';
import '../../../shared/widgets/app_location_map.dart';

/// Wizard step 2: the site's address (with live place search) and its pin on
/// the map (with reverse-geocoding when clicking the map).
class ProjectsLocationStep extends StatefulWidget {
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
  State<ProjectsLocationStep> createState() => _ProjectsLocationStepState();
}

class _ProjectsLocationStepState extends State<ProjectsLocationStep> {
  final _geocoder = GeocodingService();
  bool _searching = false;
  bool _resolvingPin = false;
  String? _searchNote;
  List<LocationSuggestion> _suggestions = const [];

  Future<void> _searchLocation() async {
    final query = widget.location.text.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searchNote = 'Type a barangay, city, or landmark first.';
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchNote = null;
    });
    final results = await _geocoder.search(query);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _suggestions = results;
      if (results.isEmpty) {
        _searchNote =
            'No matching place found. Try a broader city/province name, or click directly on the map.';
      }
    });
  }

  void _selectSuggestion(LocationSuggestion s) {
    widget.location.text = s.displayName;
    widget.onPick(s.point);
    setState(() {
      _suggestions = const [];
      _searchNote = null;
    });
  }

  Future<void> _handleMapTap(LatLng point) async {
    widget.onPick(point);
    setState(() {
      _suggestions = const [];
      _searchNote = null;
      _resolvingPin = true;
    });
    final address = await _geocoder.reverse(point);
    if (!mounted) return;
    setState(() => _resolvingPin = false);
    if (address != null && address.isNotEmpty) {
      widget.location.text = address;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'Barangay, city, province',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => _searchLocation(),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the location.'
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: 52,
              child: FilledButton.tonalIcon(
                onPressed: _searching ? null : _searchLocation,
                icon: _searching
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded, size: 18),
                label: const Text('Find on map'),
              ),
            ),
          ],
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, s) in _suggestions.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                    ),
                    title: Text(
                      s.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium,
                    ),
                    onTap: () => _selectSuggestion(s),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_searchNote != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _searchNote!,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
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
                  _resolvingPin
                      ? 'Looking up address for the pinned location…'
                      : widget.pin == null
                      ? 'Search an address above or click the map to drop a '
                            'pin on the site.'
                      : 'Pinned at ${widget.pin!.latitude.toStringAsFixed(5)}, '
                            '${widget.pin!.longitude.toStringAsFixed(5)}. '
                            'Click elsewhere to move it.',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.info),
                ),
              ),
              if (widget.pin != null)
                TextButton(
                  onPressed: widget.onClear,
                  child: const Text('Clear pin'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppLocationMap(pin: widget.pin, onPick: _handleMapTap, height: 380),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Use the + / − buttons on the map to zoom, or click anywhere to drop a pin and auto-fill the address.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}
