import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/background_service.dart';
import '../core/services/gps_service.dart';
import '../core/services/map_service.dart';
import '../core/services/navigation_service.dart';
import '../core/services/smooth_location_service.dart';
import '../core/services/speed_limit_service.dart';
import '../core/services/trip_service.dart';
import '../core/services/tts_service.dart';
import '../core/utils/geo_utils.dart';
import '../core/utils/image_utils.dart';
import '../data/sources/mapbox_api.dart';
import '../data/sources/overpass_api.dart';
import '../data/sources/prefs_source.dart';

// ── Token global ─────────────────────────────────────────
final mapboxTokenProvider = Provider<String>((ref) {
  const token = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');
  return token;
});

// ── Servicios core ───────────────────────────────────────
final prefsSourceProvider = Provider<PrefsSource>((ref) => PrefsSource());
final geoUtilsProvider = Provider<<GeoUtils>((ref) => const GeoUtils());
final imageUtilsProvider = Provider<ImageUtils>((ref) => const ImageUtils());
final ttsServiceProvider = Provider<TtsService>((ref) => TtsService());
final mapServiceProvider = Provider<MapService>((ref) => MapService());
final gpsServiceProvider = Provider<GpsService>((ref) => GpsService());
final backgroundServiceProvider = Provider<<BackgroundService>((ref) => BackgroundService());
final speedLimitServiceProvider = Provider<<SpeedLimitService>((ref) => SpeedLimitService());
final smoothLocationServiceProvider = Provider<<SmoothLocationService>((ref) => SmoothLocationService());

final tripServiceProvider = Provider<TripService>((ref) {
  final prefs = ref.read(prefsSourceProvider);
  final geo = ref.read(geoUtilsProvider);
  return TripService(prefs, geo);
});

// ── APIs ───────────────────────────────────────────────
final mapboxApiProvider = Provider.family<MapboxApi, String>((ref, token) {
  return MapboxApi(token);
});

final overpassApiProvider = Provider<<OverpassApi>((ref) => const OverpassApi());

final navigationServiceProvider = Provider.family<<NavigationService, String>((ref, token) {
  final api = ref.read(mapboxApiProvider(token));
  final geo = ref.read(geoUtilsProvider);
  return NavigationService(api, geo);
});
