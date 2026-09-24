import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_record.dart';
import '../models/poi_record.dart';

class PrefsSource {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── Avatar ────────────────────────────────────────────
  Future<bool> saveAvatar(Uint8List bytes) async {
    final prefs   = await _instance;
    final encoded = base64Encode(bytes);
    if (encoded.length > 800000) return false;
    return await prefs.setString('user_avatar', encoded);
  }

  Future<Uint8List?> loadAvatar() async {
    final prefs = await _instance;
    final raw = prefs.getString('user_avatar');
    if (raw == null) return null;
    return base64Decode(raw);
  }

  // ── Viajes ────────────────────────────────────────────
  Future<void> saveTrips(List<TripRecord> trips) async {
    final prefs   = await _instance;
    final limited = trips.take(50).toList();
    final encoded = json.encode(
      limited
          .map((t) =>
              t.routeCoords.length > 100 ? t.toJsonCompact() : t.toJson())
          .toList(),
    );
    await prefs.setString('trip_records', encoded);
  }

    Future<List<TripRecord>> loadTrips() async {
    final prefs = await _instance;
    final raw = prefs.getString('trip_records');
    if (raw == null) return [];
    final data = json.decode(raw) as List;
    return data.map((e) => TripRecord.fromJson(e)).toList();
  }

  // ── Combustible ───────────────────────────────────────
  Future<void> saveFuelSettings(double tankLiters, double autonomyKm) async {
    final prefs = await _instance;
    await prefs.setDouble('fuel_tank_liters', tankLiters);
    await prefs.setDouble('fuel_autonomy_km', autonomyKm);
  }

  Future<Map<String, double>> loadFuelSettings() async {
    final prefs = await _instance;
    return {
      'tankLiters': prefs.getDouble('fuel_tank_liters') ?? 0.0,
      'autonomyKm': prefs.getDouble('fuel_autonomy_km') ?? 0.0,
    };
  }

  Future<void> saveFuelKm(double km) async {
    final prefs = await _instance;
    await prefs.setDouble('fuel_km_since_refuel', km);
  }

  Future<double> loadFuelKm() async {
    final prefs = await _instance;
    return prefs.getDouble('fuel_km_since_refuel') ?? 0.0;
  }

    // ── Puntos guardados por voz (peligro / punto de interés) ──
  Future<void> savePois(List<PoiRecord> pois) async {
    final prefs = await _instance;
    final limited = pois.take(200).toList();
    await prefs.setString(
        'poi_records', json.encode(limited.map((p) => p.toJson()).toList()));
  }

  Future<List<PoiRecord>> loadPois() async {
    final prefs = await _instance;
    final raw = prefs.getString('poi_records');
    if (raw == null) return [];
    final data = json.decode(raw) as List;
    return data.map((e) => PoiRecord.fromJson(e)).toList();
  }

  // ── Mapas sin conexión ──────────────────────────────────
  Future<void> saveOfflineRegions(List<Map<String, String>> regions) async {
    final prefs = await _instance;
    await prefs.setString('offline_regions', json.encode(regions));
  }

  Future<List<Map<String, String>>> loadOfflineRegions() async {
    final prefs = await _instance;
    final raw = prefs.getString('offline_regions');
    if (raw == null) return [];
    final data = json.decode(raw) as List;
    return data.map((e) => Map<String, String>.from(e)).toList();
  }
}
