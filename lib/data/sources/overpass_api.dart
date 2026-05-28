import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OverpassApi {
  const OverpassApi();

  Future<String?> fetchGasolineras(double lat, double lng) async {
    // Radio reducido a 500m para prueba - si estás a 300m debería encontrar
    const radius = 500;
    
    final query = """
[out:json][timeout:10];
node["amenity"="fuel"](around:$radius,$lat,$lng);
out body;
""";

    try {
      print('[OverpassApi] Query: $query');
      
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 10));

      print('[OverpassApi] Status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        print('[OverpassApi] Error body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        return null;
      }

      final data = json.decode(response.body);
      final elements = data['elements'] as List? ?? [];
      
      print('[OverpassApi] Elementos encontrados: ${elements.length}');
      
      if (elements.isEmpty) {
        print('[OverpassApi] Sin elementos - ampliando radio a 2000m...');
        // Fallback: intentar con radio mayor
        return _fetchWithLargerRadius(lat, lng);
      }

      final features = elements.map((e) {
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final name = tags['name'] ?? tags['brand'] ?? 'Gasolinera';
        
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [e['lon'], e['lat']],
          },
          'properties': {
            'name': name,
          },
        };
      }).toList();

      final result = json.encode({
        'type': 'FeatureCollection',
        'features': features,
      });
      
      print('[OverpassApi] GeoJSON: ${features.length} features');
      return result;
      
    } on TimeoutException {
      print('[OverpassApi] Timeout');
      return null;
    } catch (e) {
      print('[OverpassApi] Error: $e');
      return null;
    }
  }
  
  Future<String?> _fetchWithLargerRadius(double lat, double lng) async {
    const radius = 2000;
    
    final query = """
[out:json][timeout:10];
node["amenity"="fuel"](around:$radius,$lat,$lng);
out body;
""";

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final elements = data['elements'] as List? ?? [];
      
      if (elements.isEmpty) return null;

      final features = elements.map((e) {
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final name = tags['name'] ?? tags['brand'] ?? 'Gasolinera';
        
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [e['lon'], e['lat']],
          },
          'properties': {'name': name},
        };
      }).toList();

      return json.encode({
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (e) {
      return null;
    }
  }
}
