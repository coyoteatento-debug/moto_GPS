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
  // ── Umbrales de anuncio TTS ───────────────────────────
  static const double kAnnounceEarlyDist  = 150.0; // anuncio temprano (m)
  static const double kAnnounceEarlyMin   = 120.0; // mínimo para anuncio temprano
  static const double kAnnounceFinalDist  =  50.0; // anuncio final (m)
  static const double kAnnounceFinalMin   =  30.0; // mínimo para anuncio final
  static const double kAdvanceStepDist    =  15.0; // avanzar al siguiente paso
  
  final MapboxApi  _api;
  final GeoUtils   _geo;

  NavigationService(this._api, this._geo);
  
  // ── Obtener rutas ─────────────────────────────────────
  Future<List<RouteData>> getRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<Map<String, dynamic>> waypoints = const [],
  }) async {
    final data = await _api.getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat:   destLat,
      destLng:   destLng,
      waypoints: waypoints,
    );
    if (data == null) return [];
    final routes = data['routes'] as List;
    return routes.map<RouteData>((r) {
      final coords = (r['geometry']['coordinates'] as List)
          .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
          .toList();
      final legs = r['legs'] as List;
      final steps = legs
          .expand((leg) => leg['steps'] as List)
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
  int _lastAnnouncedStep  = -1;
  bool _announcedEarly    = false;
  bool _announcedFinal    = false;

  void resetAnnouncements() {  // ← AGREGADO
    _lastAnnouncedStep = -1;
    _announcedEarly    = false;
    _announcedFinal    = false;
  }

  TurnUpdate? updateTurn(
    double lat,
    double lng,
    List<Map<String, dynamic>> steps,
    int currentStepIndex,
  ) {
    if (steps.isEmpty || currentStepIndex >= steps.length) return null;

    // Resetear flags cuando cambia el paso
    if (currentStepIndex != _lastAnnouncedStep) {
      _lastAnnouncedStep = currentStepIndex;
      _announcedEarly    = false;
      _announcedFinal    = false;
    }

    final step    = steps[currentStepIndex];
    final loc     = step['location'] as List;
    final stepLng = (loc[0] as num).toDouble();
    final stepLat = (loc[1] as num).toDouble();
    final dist    = _geo.distanceBetween(lat, lng, stepLat, stepLng);

    String? announceText;
    if (dist < 150 && dist >= 120 && !_announcedEarly) {
      _announcedEarly = true;
      announceText = 'En 150 metros, ${step['instruction']}';
    } else if (dist < 50 && dist >= 30 && !_announcedFinal) {
      _announcedFinal = true;
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
    );

  // ── Verificar llegada ─────────────────────────────────
  bool hasArrived(
    double lat,
    double lng,
    List<List<double>> routeCoords, {
    double maxDistanceMeters = 35,               // ← umbral de llegada
  }) {
    if (routeCoords.isEmpty) return false;
    final idx = _geo.findClosestPointIndex(lat, lng, routeCoords,
        lastIdx: (routeCoords.length - 10).clamp(0, routeCoords.length - 1));
    if (idx < routeCoords.length - 2) return false; // ← aún lejos en índice
    final last    = routeCoords.last;
    final distEnd = _geo.distanceBetween(
        lat, lng, last[1], last[0]);
    return distEnd <= maxDistanceMeters;            // ← valida distancia real
  }

  void disposeApi() => _api.dispose();
}

class TurnUpdate {
  final double distanceToManeuver;
  final String? announceText;
  final int nextStepIndex;
  final String nextInstruction;

  const TurnUpdate({
    required this.distanceToManeuver,
    required this.announceText,
    required this.nextStepIndex,
    required this.nextInstruction,
  });
}
