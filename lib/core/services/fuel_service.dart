import '../../core/utils/geo_utils.dart';
import '../../data/sources/prefs_source.dart';

/// Calcula la autonomía real de gasolina restante en base al
/// kilometraje acumulado desde el último "tanque lleno" marcado
/// por el usuario, contra la autonomía que él mismo configuró.
class FuelService {
  final PrefsSource _prefs;
  final GeoUtils _geo;

  FuelService(this._prefs, this._geo);

  double tankLiters    = 0.0;
  double autonomyKm    = 0.0;
  double kmSinceRefuel = 0.0;

  double? _lastLat;
  double? _lastLng;
  double _lastPersistedKm = 0.0;

  static const double _maxDeltaMeters = 150.0; // ← umbral anti-spike

  bool get isConfigured => autonomyKm > 0;

  double get remainingKm =>
      (autonomyKm - kmSinceRefuel).clamp(0, autonomyKm);

  double get percentRemaining =>
      autonomyKm > 0 ? (remainingKm / autonomyKm).clamp(0.0, 1.0) : 1.0;

  double get litersRemaining => tankLiters * percentRemaining;

  // ── Cargar configuración y estado persistido ──────────
  Future<void> load() async {
    final settings = await _prefs.loadFuelSettings();
    tankLiters    = settings['tankLiters'] ?? 0.0;
    autonomyKm    = settings['autonomyKm'] ?? 0.0;
    kmSinceRefuel = await _prefs.loadFuelKm();
    _lastPersistedKm = kmSinceRefuel;
  }

  Future<void> saveSettings(double liters, double autonomy) async {
    tankLiters = liters;
    autonomyKm = autonomy;
    await _prefs.saveFuelSettings(liters, autonomy);
  }

  Future<void> markRefueled() async {
    kmSinceRefuel    = 0.0;
    _lastPersistedKm = 0.0;
    _lastLat = null;
    _lastLng = null;
    await _prefs.saveFuelKm(0.0);
  }

  // ── Acumular kilometraje recorrido ─────────────────────
  Future<void> accumulate(double lat, double lng) async {
    if (!isConfigured) {
      _lastLat = lat;
      _lastLng = lng;
      return;
    }
    if (_lastLat != null && _lastLng != null) {
      final delta = _geo.distanceBetween(_lastLat!, _lastLng!, lat, lng);
      if (delta <= _maxDeltaMeters) {
        kmSinceRefuel += delta / 1000;
      }
    }
    _lastLat = lat;
    _lastLng = lng;

    // Persistir solo cada ~1km para no saturar SharedPreferences.
    if ((kmSinceRefuel - _lastPersistedKm).abs() >= 1.0) {
      _lastPersistedKm = kmSinceRefuel;
      await _prefs.saveFuelKm(kmSinceRefuel);
    }
  }
}
