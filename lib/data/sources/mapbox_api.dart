import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapboxApi {
  final String token;
  final http.Client _client;
  MapboxApi(this.token) : _client = http.Client();

  void dispose() => _client.close();

  // ── Geocoding (buscador) ──────────────────────────────
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    double? proximityLat,
    double? proximityLng,
  }) async {
    if (query.trim().length < 3) return [];
    const types = 'place,locality,neighborhood,address,district';
    final proximity = (proximityLat != null && proximityLng != null)
        ? '&proximity=$proximityLng,$proximityLat'
        : '';
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query)}.json'
        '?access_token=$token'
        '&language=es'
        '&types=$types'
        '&limit=7'
        '$proximity';

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
        final center = f['center'] as List;
        return {
          'name': f['text'] as String? ?? 'Sin nombre',
          'full_name': f['place_name'] as String? ?? 'Sin nombre',
          'lat': (center[1] as num).toDouble(),
          'lng': (center[0] as num).toDouble(),
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
