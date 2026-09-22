import 'dart:async';
import 'dart:convert';
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

    final local = await _fetchPlaces(query, proximity, bbox);
    if (local.isNotEmpty) return local;

    // Fallback: sin bbox, pero restringido a México — por si el
    // lugar buscado está en otra ciudad del país.
    return _fetchPlaces(query, proximity, '');
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
        print('[MapboxApi] searchPlaces status: ${response.statusCode}, body: ${response.body}');
        return [];
      }

      final data = json.decode(response.body);
      final features = data['features'] as List? ?? [];

      return features.map((f) {
        final coords = f['geometry']['coordinates'] as List;
        final props = f['properties'] as Map<String, dynamic>;
        return {
          'name': props['name'] as String? ?? 'Sin nombre',
          'full_name': (props['full_address'] ?? props['place_formatted'])
                  as String? ?? 'Sin nombre',
          'lat': (coords[1] as num).toDouble(),
          'lng': (coords[0] as num).toDouble(),
        };
      }).toList();
    } on TimeoutException {
      print('[MapboxApi] searchPlaces timeout');
      return [];
    } catch (e) {
      print('[MapboxApi] searchPlaces error: $e');
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
      print('[MapboxApi] reverseGeocode error: $e');
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
        print('[MapboxApi] getRoute status: ${response.statusCode}, body: ${response.body}');
        return null;
      }

      return json.decode(response.body) as Map<String, dynamic>;
    } on TimeoutException {
      print('[MapboxApi] getRoute timeout');
      return null;
    } catch (e) {
      print('[MapboxApi] getRoute error: $e');
      return null;
    }
  }
}
