import '../utils/geo_utils.dart';
import '../../data/sources/mapbox_api.dart';

class RouteData {
  final String distance;
  final String duration;
  final Map<String, dynamic> geometry;
  final List<List<double>> coords;
  final List<Map<String, dynamic>> steps;

  const RouteData({
    required this.distance,
    required this.duration,
    required this.geometry,
    required this.coords,
    required this.steps,
  });
}

class NavigationService {
  final MapboxApi  _api;
  final GeoUtils   _geo;

  NavigationService(this._api, this._geo);
  
  // ── Obtener rutas ─────────────────────────────────────
  Future<List<RouteData>> getRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final data = await _api.getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    if (data == null) return [];
    final routes = data['routes'] as List;
    return routes.map<RouteData>((r) {
      final coords = (r['geometry']['coordinates'] as List)
          .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
          .toList();
      final steps = (r['legs'][0]['steps'] as List)
          .map((s) => <String, dynamic>{
                'instruction': (s['maneuver']['instruction'] as String?) ?? '',
                'distance':    (s['distance'] as num).toDouble(),
                'location':    s['maneuver']['location'] as List,
              })
          .toList();
      return RouteData(
        distance: '${((r['distance'] as num).toDouble() / 1000).toStringAsFixed(1)} km',
        duration: '${((r['duration'] as num).toDouble() / 60).round()} min',
        geometry: r['geometry'] as Map<String, dynamic>,
        coords:   coords,
        steps:    steps,
      );
    }).toList();
  }

  // ── Calcular zoom para encuadre ───────────────────────
  double fitZoom(double distanceMeters) {
    if (distanceMeters < 5000)        return 13.0;
    if (distanceMeters < 20000)       return 11.0;
    if (distanceMeters < 80000)       return 9.0;
    if (distanceMeters < 200000)      return 7.5;
    return 6.0;
  }

  // ── Detectar desvío ───────────────────────────────────
  bool isDeviated(
    double lat,
    double lng,
    List<List<double>> routeCoords, {
    double thresholdMeters = 55,
  }) {
    if (routeCoords.isEmpty) return false;
    final dist = _geo.distanceToRoute(lat, lng, routeCoords);
    return dist > thresholdMeters;
  }

  // ── Actualizar turno actual ───────────────────────────
  TurnUpdate? updateTurn(
    double lat,
    double lng,
    List<Map<String, dynamic>> steps,
    int currentStepIndex,
  ) {
    if (steps.isEmpty || currentStepIndex >= steps.length) return null;

    final step    = steps[currentStepIndex];
    final loc     = step['location'] as List;
    final stepLng = (loc[0] as num).toDouble();
    final stepLat = (loc[1] as num).toDouble();
    final dist    = _geo.distanceBetween(lat, lng, stepLat, stepLng);

    String? announceText;
    if (dist < 150 && dist >= 120) {
      announceText = 'En 150 metros, ${step['instruction']}';
    } else if (dist < 50 && dist >= 30) {
      announceText = step['instruction'] as String;
    }

    // Avanzar al siguiente paso
    int nextIndex = currentStepIndex;
    String? nextInstruction;
    double? nextDistance;
    if (dist < 15 && currentStepIndex < steps.length - 1) {
      nextIndex       = currentStepIndex + 1;
      nextInstruction = steps[nextIndex]['instruction'] as String;
      nextDistance    = steps[nextIndex]['distance'] as double;
    }
    
    return TurnUpdate(
      distanceToManeuver: dist,
      announceText:       announceText,
      nextStepIndex:      nextIndex,
      nextInstruction:    nextInstruction ?? step['instruction'] as String,
      nextDistance:       nextDistance   ?? dist,
    );
  }

  // ── Verificar llegada ─────────────────────────────────
  bool hasArrived(
    double lat,
    double lng,
    List<List<double>> routeCoords,
  ) {
    if (routeCoords.isEmpty) return false;
    final idx = _geo.findClosestPointIndex(lat, lng, routeCoords);
    return idx >= routeCoords.length - 2;
  }
}

class TurnUpdate {
  final double distanceToManeuver;
  final String? announceText;
  final int nextStepIndex;
  final String nextInstruction;
  final double nextDistance;

  const TurnUpdate({
    required this.distanceToManeuver,
    required this.announceText,
    required this.nextStepIndex,
    required this.nextInstruction,
    required this.nextDistance,
  });
}
