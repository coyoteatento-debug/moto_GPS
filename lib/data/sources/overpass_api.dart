import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OverpassApi {
  const OverpassApi();

  Future<String?> fetchGasolineras(double lat, double lng) async {
    const double radius = 8000;
    final query =
        '[out:json][timeout:40];'
        '('
        'node[amenity=fuel](around:$radius,$lat,$lng);'
        'way[amenity=fuel](around:$radius,$lat,$lng);'
        ');'
        'out center;';

    final uri = Uri.parse('https://overpass-api.de/api/interpreter');

    final client = http.Client();                  // ← AGREGADO
    final http.Response response;
    try {
      response = await client.post(               // ← client.post
        uri,
        headers: {
          'User-Agent': 'MotoGPS/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept':       'application/json',
        },
        body: 'data=${Uri.encodeComponent(query)}',
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () {                            // ← AGREGADO
          client.close();
          throw TimeoutException('Overpass timeout');
        },
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();                              // ← AGREGADO
    }
    if (response.statusCode != 200) return null;
    final List elements;
    try {
      elements = json.decode(response.body)['elements'] as List;
    } catch (_) {
      return null;
    }
    if (elements.isEmpty) return null;

    final features = elements.map((e) {
      final pLat = e['type'] == 'node'
          ? (e['lat'] as num).toDouble()
          : (e['center']?['lat'] as num?)?.toDouble() ?? 0.0;
      final pLng = e['type'] == 'node'
          ? (e['lon'] as num).toDouble()
          : (e['center']?['lon'] as num?)?.toDouble() ?? 0.0;
      if (pLat == 0.0 && pLng == 0.0) return null;
      return {
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': [pLng, pLat]},
        'properties': {
          'name': (e['tags']?['name'] as String?)
              ?? (e['tags']?['brand'] as String?)
              ?? 'Gasolinera',
        },
      };
    }).whereType<Map>().toList();

    if (features.isEmpty) return null;
    return json.encode({'type': 'FeatureCollection', 'features': features});
  }
}
