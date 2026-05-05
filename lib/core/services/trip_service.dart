import '../../core/utils/geo_utils.dart';
import '../../data/models/trip_record.dart';
import '../../data/sources/prefs_source.dart';

class TripService {
  final PrefsSource _prefs;
  final GeoUtils _geo;

  TripService(this._prefs, this._geo);

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
      _accumulatedDistance += _geo.distanceBetween(
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
}
