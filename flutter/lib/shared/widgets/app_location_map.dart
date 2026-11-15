import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';

/// An OpenStreetMap view with the site's pin. When [onPick] is set, tapping
/// the map moves the pin there.
class AppLocationMap extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceSunken),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: pin ?? defaultCenter,
              initialZoom: pin == null ? 10 : zoom,
              onTap: onPick == null ? null : (_, point) => onPick!(point),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (showTiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ph.buildpro.app',
                ),
              if (pin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pin!,
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
              if (showTiles)
                const SimpleAttributionWidget(
                  source: Text('OpenStreetMap contributors'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
