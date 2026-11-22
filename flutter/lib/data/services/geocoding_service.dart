import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/widgets/app_location_map.dart';

class LocationSuggestion {
  const LocationSuggestion({
    required this.displayName,
    required this.point,
  });

  final String displayName;
  final LatLng point;
}

/// Forward and reverse geocoding via OpenStreetMap Nominatim.
///
/// Automatically skipped in widget tests when [AppLocationMap.showTiles] is false.
class GeocodingService {
  GeocodingService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://nominatim.openstreetmap.org',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {
                'User-Agent': 'QueenBuildersCPMS/1.0 (contact@queenbuilders.ph)',
                'Accept-Language': 'en',
              },
            ),
          );

  final Dio _dio;

  /// Searches for places matching [query], prioritizing the Philippines.
  Future<List<LocationSuggestion>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !AppLocationMap.showTiles) return const [];

    final phResults = await _query(trimmed, countryCodes: 'ph');
    if (phResults.isNotEmpty) return phResults;
    return _query(trimmed);
  }

  Future<List<LocationSuggestion>> _query(
    String query, {
    String? countryCodes,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': '1',
          'limit': '5',
          'countrycodes': ?countryCodes,
        },
      );
      final data = response.data;
      if (data == null) return const [];
      final results = <LocationSuggestion>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final lat = double.tryParse('${raw['lat']}');
        final lon = double.tryParse('${raw['lon']}');
        final name = (raw['display_name'] as String?)?.trim();
        if (lat == null || lon == null || name == null || name.isEmpty) {
          continue;
        }
        results.add(
          LocationSuggestion(
            displayName: name,
            point: LatLng(lat, lon),
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Resolves [point] into a concise human-readable address, or null on failure.
  Future<String?> reverse(LatLng point) async {
    if (!AppLocationMap.showTiles) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'lat': point.latitude.toStringAsFixed(6),
          'lon': point.longitude.toStringAsFixed(6),
          'format': 'json',
          'addressdetails': '1',
        },
      );
      final data = response.data;
      if (data == null) return null;
      final addr = data['address'];
      if (addr is Map) {
        final parts = <String>[
          for (final key in const [
            'road',
            'neighbourhood',
            'suburb',
            'village',
            'quarter',
            'city',
            'town',
            'municipality',
            'state',
          ])
            if (addr[key] is String && (addr[key] as String).trim().isNotEmpty)
              (addr[key] as String).trim(),
        ];
        final deduped = <String>[];
        for (final p in parts) {
          if (!deduped.contains(p)) deduped.add(p);
        }
        if (deduped.isNotEmpty) {
          return deduped.take(4).join(', ');
        }
      }
      final display = (data['display_name'] as String?)?.trim();
      return (display != null && display.isNotEmpty) ? display : null;
    } catch (_) {
      return null;
    }
  }
}
