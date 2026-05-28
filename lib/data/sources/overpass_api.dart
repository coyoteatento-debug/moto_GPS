import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OverpassApi {
  const OverpassApi();

  /// Busca gasolineras en un radio de 8km alrededor de la posición
    Future<String?> fetchGasolineras(double lat, double lng) async {
      const radius = 8000; // 8km
    
      // Query más simple y confiable
      final query = """
  [out:json][timeout:15];
  (
    node["amenity"="fuel"](around:$radius,$lat,$lng);
  );
  out body 50;
  """;

     try {
        final response = await http.post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          body: {'data': query},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          print('[OverpassApi] Status error: ${response.statusCode}');
          return null;
        }

        final data = json.decode(response.body);
        final elements = data['elements'] as List? ?? [];
      
        print('[OverpassApi] Elementos raw: ${elements.length}');
      
        if (elements.isEmpty) return null;

        final features = <Map<String, dynamic>>[];
        for (final e in elements) {
          final tags = e['tags'] as Map<String, dynamic>? ?? {};
          final name = tags['name'] ?? tags['brand'] ?? 'Gasolinera';
        
          final elat = (e['lat'] as num?)?.toDouble();
          final elon = (e['lon'] as num?)?.toDouble();
        
          if (elat == null || elon == null) continue;
        
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [elon, elat],
            },
            'properties': {
              'name': name,
            },
          });
        }

        if (features.isEmpty) {
          print('[OverpassApi] No features válidos');
          return null;
        }

        final result = json.encode({
          'type': 'FeatureCollection',
          'features': features,
        });
      
        print('[OverpassApi] GeoJSON generado con ${features.length} gasolineras');
        return result;
      
      } catch (e) {
        print('[OverpassApi] Error: $e');
        return null;
      }
    }
  }
