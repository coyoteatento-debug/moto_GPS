import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OverpassApi {
  const OverpassApi();

  /// Busca gasolineras en un radio de 8km alrededor de la posición
  Future<String?> fetchGasolineras(double lat, double lng) async {
    // Radio de búsqueda: 8km (antes era implícito y podía ser enorme)
    const radius = 8000;

    // Query optimizado: solo amenity=fuel, limitado a 50 resultados
    final query = """
      [out:json][timeout:15];
      (
        node["amenity"="fuel"](around:$radius,$lat,$lng);
        way["amenity"="fuel"](around:$radius,$lat,$lng);
      );
      out center tags 50;
    """;

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print('[OverpassApi] Status: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final elements = data['elements'] as List? ?? [];

      if (elements.isEmpty) {
        print('[OverpassApi] No gasolineras encontradas en radio ${radius}m');
        return null;
      }

      final features = elements.map((e) {
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final name = tags['name'] ?? tags['brand'] ?? 'Gasolinera';

        double elat, elng;
        if (e['type'] == 'node') {
          elat = (e['lat'] as num).toDouble();
          elng = (e['lon'] as num).toDouble();
        } else {
          final center = e['center'] as Map<String, dynamic>?;
          elat = (center?['lat'] as num?)?.toDouble() ?? lat;
          elng = (center?['lon'] as num?)?.toDouble() ?? lng;
        }

        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [elng, elat],
          },
          'properties': {
            'name': name,
            'brand': tags['brand'] ?? '',
          },
        };
      }).toList();

      return json.encode({
        'type': 'FeatureCollection',
        'features': features,
      });
    } on TimeoutException {
      print('[OverpassApi] Timeout después de 15s');
      return null;
    } catch (e) {
      print('[OverpassApi] Error: $e');
      return null;
    }
  }
}
