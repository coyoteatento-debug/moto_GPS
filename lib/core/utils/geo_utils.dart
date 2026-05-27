import 'dart:math';

class GeoUtils {
  const GeoUtils();

  // ── Distancia entre dos coordenadas (metros) ──────────
  double distanceBetween(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Rumbo entre dos coordenadas (grados) ──────────────
  double bearingBetween(
      double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2 - lng1) * pi / 180;
    final y = sin(dLng) * cos(lat2 * pi / 180);
    final x = cos(lat1 * pi / 180) * sin(lat2 * pi / 180) -
        sin(lat1 * pi / 180) * cos(lat2 * pi / 180) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  int findClosestPointIndex(
      double lat, double lng, List<List<double>> routeCoords,
      {int lastIdx = 0}) {
    if (routeCoords.isEmpty) return 0;

    // Búsqueda local en ventana normal
    final start = (lastIdx - 10).clamp(0, routeCoords.length - 1);
    final end   = (lastIdx + 25).clamp(0, routeCoords.length);
    double minDist = double.infinity;
    int idx = lastIdx;
    for (int i = start; i < end; i++) {
      final d = distanceBetween(
          lat, lng, routeCoords[i][1], routeCoords[i][0]);
      if (d < minDist) {
        minDist = d;
        idx = i;
      }
    }

    // Si el punto más cercano está a más de 200m, hubo un salto de GPS —
    // ampliar ventana de búsqueda antes de hacer búsqueda global
    if (minDist > 200) {
      final wStart = (lastIdx - 50).clamp(0, routeCoords.length - 1); // ← ventana ampliada
      final wEnd   = (lastIdx + 100).clamp(0, routeCoords.length);    // ← ventana ampliada
      for (int i = wStart; i < wEnd; i++) {
        final d = distanceBetween(
            lat, lng, routeCoords[i][1], routeCoords[i][0]);
        if (d < minDist) {
          minDist = d;
          idx = i;
        }
      }
      // Solo búsqueda global si la ventana ampliada tampoco encontró nada cercano
      if (minDist > 200) {                                             // ← AGREGADO
        for (int i = 0; i < routeCoords.length; i++) {
          final d = distanceBetween(
              lat, lng, routeCoords[i][1], routeCoords[i][0]);
          if (d < minDist) {
            minDist = d;
            idx = i;
          }
        }
      }
    }

    return idx;
  }

  // ── Snap del usuario al segmento más cercano ──────────
  List<double> snapToRoute(
      double lat, double lng, List<List<double>> routeCoords) {
    if (routeCoords.length < 2) return [lng, lat];
    double minDist = double.infinity;
    List<double> snapped = [lng, lat];
    final cosLat = cos(lat * pi / 180);           // ← AGREGADO
    for (int i = 0; i < routeCoords.length - 1; i++) {
      final a = routeCoords[i];
      final b = routeCoords[i + 1];
      final abX = (b[0] - a[0]) * cosLat;         // ← cosLat aplicado
      final abY = b[1] - a[1];
      final apX = (lng - a[0]) * cosLat;           // ← cosLat aplicado
      final apY = lat - a[1];
      final ab2 = abX * abX + abY * abY;
      if (ab2 == 0) continue;
      final t = ((apX * abX + apY * abY) / ab2).clamp(0.0, 1.0);
      final pLng = a[0] + t * (b[0] - a[0]);      // ← sin cosLat para el resultado
      final pLat = a[1] + t * (b[1] - a[1]);
      final d = distanceBetween(lat, lng, pLat, pLng);
      if (d < minDist) {
        minDist = d;
        snapped = [pLng, pLat];
      }
    }
    return snapped;
  }

  double distanceToRoute(
      double lat, double lng, List<List<double>> routeCoords) {
    double minDist = double.infinity;
    final cosLat = cos(lat * pi / 180);           // ← AGREGADO
    for (int i = 0; i < routeCoords.length - 1; i++) {
      final a = routeCoords[i];
      final b = routeCoords[i + 1];
      final abX = (b[0] - a[0]) * cosLat;         // ← cosLat aplicado
      final abY = b[1] - a[1];
      final apX = (lng - a[0]) * cosLat;           // ← cosLat aplicado
      final apY = lat - a[1];
      final ab2 = abX * abX + abY * abY;
      if (ab2 == 0) continue;
      final t = ((apX * abX + apY * abY) / ab2).clamp(0.0, 1.0);
      final d = distanceBetween(lat, lng, a[1] + t * (b[1] - a[1]), a[0] + t * (b[0] - a[0]));
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // ── Zoom dinámico según velocidad ─────────────────────
  double calculateDynamicZoom(double speedKmh) {
    if (speedKmh < 20) return 16.0;
    if (speedKmh < 80) return 14.0;
    return 12.0;
  }
}
