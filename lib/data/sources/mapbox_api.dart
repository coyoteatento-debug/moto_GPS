import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MapboxApi {
  final String token;
  final http.Client _client;
  MapboxApi(this.token) : _client = http.Client();

  void dispose() => _client.close();

      // ── Búsqueda de lugares (Search Box API) ──────────────
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    double? proximityLat,
    double? proximityLng,
  }) async {
    if (query.trim().length < 3) return [];
    final proximity = (proximityLat != null && proximityLng != null)
        ? '&proximity=$proximityLng,$proximityLat'
        : '';

    // Caja de ~50km alrededor de la ubicación actual, como filtro
    // duro (proximity solo reordena resultados, no los excluye).
    String bbox = '';
    if (proximityLat != null && proximityLng != null) {
      const delta = 0.45;
      final minLng = proximityLng - delta;
      final maxLng = proximityLng + delta;
      final minLat = proximityLat - delta;
      final maxLat = proximityLat + delta;
      bbox = '&bbox=$minLng,$minLat,$maxLng,$maxLat';
    }

    // Se consultan ambas en paralelo: la local (con bbox, para
    // direcciones/negocios cercanos) y la nacional (sin bbox, para
    // ciudades o municipios lejanos que la caja de ~50km excluiría).
    // Antes, si la búsqueda local encontraba ALGO (aunque fuera una
    // calle con nombre parecido), la nacional nunca se intentaba y
    // la ciudad real quedaba oculta.
    final results = await Future.wait([
      _fetchPlaces(query, proximity, bbox),
      _fetchPlaces(query, proximity, ''),
    ]);
    final local = results[0];
    final national = results[1];

    final merged = <Map<String, dynamic>>[...local];
    for (final place in national) {
      final isDuplicate = merged.any((m) =>
          m['name'] == place['name'] &&
          ((m['lat'] as double) - (place['lat'] as double)).abs() < 0.01 &&
          ((m['lng'] as double) - (place['lng'] as double)).abs() < 0.01);
      if (!isDuplicate) merged.add(place);
    }
    return merged.take(7).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPlaces(
    String query, String proximity, String bbox,
  ) async {
    final url =
        'https://api.mapbox.com/search/searchbox/v1/forward'
        '?q=${Uri.encodeComponent(query)}'
        '&access_token=$token'
        '&language=es'
        '&country=mx'
        '&limit=7'
        '$proximity'
        '$bbox';

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[MapboxApi] searchPlaces status: ${response.statusCode}, body: ${response.body}');
        return [];
      }

      final data = json.decode(response.body);
      final features = data['features'] as List? ?? [];

            return features.map((f) {
              final coords = f['geometry']['coordinates'] as List;
              final props = f['properties'] as Map<String, dynamic>;
              final categories = props['poi_category'] as List?;
              final brands = props['brand'] as List?;
              return {
                'name': props['name'] as String? ?? 'Sin nombre',
                'full_name': (props['full_address'] ?? props['place_formatted'])
                        as String? ?? 'Sin nombre',
                'lat': (coords[1] as num).toDouble(),
                'lng': (coords[0] as num).toDouble(),
                'type': props['feature_type'] as String? ?? '',
                'category': (categories != null && categories.isNotEmpty)
                    ? categories.first as String
                    : null,
                'brand': (brands != null && brands.isNotEmpty)
                    ? brands.first as String
                    : null,
              };
            }).toList();
    } on TimeoutException {
      debugPrint('[MapboxApi] searchPlaces timeout');
      return [];
    } catch (e) {
      debugPrint('[MapboxApi] searchPlaces error: $e');
      return [];
    }
  }

  // ── Reverse geocoding (tap en mapa) ──────────────────
  Future<String> reverseGeocode(double lat, double lng) async {
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?access_token=$token'
        '&language=es&limit=1';

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return 'Destino seleccionado';

      final data = json.decode(response.body);
      final features = data['features'] as List? ?? [];
      if (features.isEmpty) return 'Destino seleccionado';

      return features[0]['place_name'] as String? ?? 'Destino seleccionado';
    } catch (e) {
      debugPrint('[MapboxApi] reverseGeocode error: $e');
      return 'Destino seleccionado';
    }
  }

  // ── Directions (ruta) ─────────────────────────────────
  Future<Map<String, dynamic>?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<Map<String, dynamic>> waypoints = const [],
  }) async {
    // Construir coordenadas: origen → paradas → destino
    final buffer = StringBuffer('$originLng,$originLat');
    for (final wp in waypoints) {
      buffer.write(';${wp['lng']},${wp['lat']}');
    }
    buffer.write(';$destLng,$destLat');
    final coords = buffer.toString();

    final url =
        'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
        '?access_token=$token'
        '&geometries=geojson&steps=true'
        '&language=es&overview=full&continue_straight=true&alternatives=true';

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[MapboxApi] getRoute status: ${response.statusCode}, body: ${response.body}');
        return null;
      }

      return json.decode(response.body) as Map<String, dynamic>;
    } on TimeoutException {
      debugPrint('[MapboxApi] getRoute timeout');
      return null;
    } catch (e) {
      debugPrint('[MapboxApi] getRoute error: $e');
      return null;
    }
  }
}
