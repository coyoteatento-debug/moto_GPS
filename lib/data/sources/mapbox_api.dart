import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapboxApi {
  final String token;
  const MapboxApi(this.token);

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
        '&country=MX,US'
        '&types=$types'
        '&limit=7'
        '$proximity';
    final http.Response response;
    try {
      response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
    if (response.statusCode != 200) return [];
    final features = json.decode(response.body)['features'] as List;
    return features.map((f) {
      final center = f['center'] as List;
      return <String, dynamic>{
        'name':      f['text'] as String,
        'full_name': f['place_name'] as String,
        'lat':       (center[1] as num).toDouble(),
        'lng':       (center[0] as num).toDouble(),
      };
    }).toList();
  }

  // ── Reverse geocoding (tap en mapa) ──────────────────
  Future<String> reverseGeocode(double lat, double lng) async {
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?access_token=$token&language=es&limit=1';
    final http.Response response;
    try {
      response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return 'Destino seleccionado';
    } catch (_) {
      return 'Destino seleccionado';
    }
    if (response.statusCode != 200) return 'Destino seleccionado';
    final features = json.decode(response.body)['features'] as List;
    if (features.isEmpty) return 'Destino seleccionado';
    return features[0]['place_name'] as String;
  }

  // ── Directions (ruta) ─────────────────────────────────
  Future<Map<String, dynamic>?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final url =
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '$originLng,$originLat;$destLng,$destLat'
        '?geometries=geojson&steps=true&access_token=$token'
        '&language=es&overview=full&continue_straight=true&alternatives=true';
    final http.Response response;
    try {
      response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
    final data = json.decode(response.body);
    final routes = data['routes'] as List;
    if (routes.isEmpty) return null;
    return data;
  }
}
