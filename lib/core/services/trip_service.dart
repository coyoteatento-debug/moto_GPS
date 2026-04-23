import 'dart:math';
import '../../data/models/trip_record.dart';
import '../../data/sources/prefs_source.dart';

class TripService {
  final PrefsSource _prefs;

  TripService(this._prefs);

  DateTime? _startTime;
  double _accumulatedDistance = 0.0;
  double? _lastLat;
  double? _lastLng;

  bool get isTracking => _startTime != null;

  // ── Iniciar tracking ──────────────────────────────────
  void startTracking(double lat, double lng) {
    _startTime           = DateTime.now();
    _accumulatedDistance = 0.0;
    _lastLat             = lat;
    _lastLng             = lng;
  }

  // ── Acumular distancia ────────────────────────────────
  void accumulate(double lat, double lng) {
    if (_lastLat != null && _lastLng != null) {
      _accumulatedDistance += _distanceBetween(
          _lastLat!, _lastLng!, lat, lng);
    }
    _lastLat = lat;
    _lastLng = lng;
  }

  // ── Finalizar y guardar ───────────────────────────────
  Future<TripRecord?> finishAndSave({
    required String destination,
    required List<List<double>> routeCoords,
    required List<TripRecord> existingTrips,
  }) async {
    if (_startTime == null) return null;
    final duration = DateTime.now().difference(_startTime!);
    final record = TripRecord(
      destination: destination,
      distanceKm:  double.parse(
          (_accumulatedDistance / 1000).toStringAsFixed(2)),
      durationMin: duration.inMinutes,
      date:        _startTime!,
      routeCoords: List<List<double>>.from(routeCoords),
    );
    final updated = [record, ...existingTrips];
    await _prefs.saveTrips(updated);
    _reset();
    return record;
  }

  void _reset() {
    _startTime           = null;
    _accumulatedDistance = 0.0;
    _lastLat             = null;
    _lastLng             = null;
  }

  // ── Distancia interna (Haversine) ─────────────────────
  double _distanceBetween(
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
}
