import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';

/// An OpenStreetMap view with the site's pin and desktop-friendly zoom
/// controls. When [onPick] is set, tapping the map moves the pin there.
class AppLocationMap extends StatefulWidget {
  const AppLocationMap({
    super.key,
    this.pin,
    this.onPick,
    this.height = 320,
    this.zoom = 13,
  });

  final LatLng? pin;
  final ValueChanged<LatLng>? onPick;
  final double height;
  final double zoom;

  /// Batangas, where most of the company's sites are.
  static const defaultCenter = LatLng(13.9411, 121.1631);

  /// Tests have no network, so they turn map tiles off.
  static bool showTiles = true;

  @override
  State<AppLocationMap> createState() => _AppLocationMapState();
}

class _AppLocationMapState extends State<AppLocationMap> {
  final _mapController = MapController();

  @override
  void didUpdateWidget(covariant AppLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPin = widget.pin;
    if (newPin != null && newPin != oldWidget.pin) {
      final currentZoom = _mapController.camera.zoom;
      final targetZoom = currentZoom < 14 ? 15.0 : currentZoom;
      _mapController.move(newPin, targetZoom);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final cam = _mapController.camera;
    final next = (cam.zoom + delta).clamp(3.0, 18.0);
    _mapController.move(cam.center, next);
  }

  void _recenter() {
    final target = widget.pin ?? AppLocationMap.defaultCenter;
    final zoom = widget.pin != null ? 15.0 : 10.0;
    _mapController.move(target, zoom);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceSunken),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.pin ?? AppLocationMap.defaultCenter,
                  initialZoom: widget.pin == null ? 10 : widget.zoom,
                  onTap: widget.onPick == null
                      ? null
                      : (_, point) => widget.onPick!(point),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  if (AppLocationMap.showTiles)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ph.queenbuilders.cpms',
                    ),
                  if (widget.pin != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.pin!,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 44,
                            color: AppColors.error,
                            shadows: [
                              Shadow(color: Color(0x55000000), blurRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (AppLocationMap.showTiles)
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                ],
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Material(
                  color: Theme.of(context).colorScheme.surface.withValues(
                    alpha: 0.94,
                  ),
                  elevation: 2,
                  borderRadius: AppRadii.mdAll,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapControlButton(
                        tooltip: 'Zoom in',
                        icon: Icons.add_rounded,
                        onPressed: () => _zoomBy(1),
                      ),
                      const Divider(height: 1, thickness: 1),
                      _MapControlButton(
                        tooltip: 'Zoom out',
                        icon: Icons.remove_rounded,
                        onPressed: () => _zoomBy(-1),
                      ),
                      const Divider(height: 1, thickness: 1),
                      _MapControlButton(
                        tooltip: widget.pin != null
                            ? 'Center on pin'
                            : 'Reset view',
                        icon: Icons.my_location_rounded,
                        onPressed: _recenter,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
