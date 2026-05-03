import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'background_service.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  final BackgroundService _bg = BackgroundService();

  StreamSubscription<Position>?      _foregroundSub;
  StreamSubscription<LocationData>?  _backgroundSub;
  StreamController<Position>?        _controller;

  bool _isInBackground = false;
  bool _isTracking     = false;

  // ── Stream principal ─────────────────────────────────────────────

  /// Stream unificado — funciona tanto en foreground como en background
  Stream<Position> get positionStream {
    _controller ??= StreamController<Position>.broadcast();
    return _controller!.stream;
  }

  // ── Control del tracking ─────────────────────────────────────────

  /// Inicia el GPS — llama esto cuando el usuario presiona ¡Ir!
  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;
    await _bg.start();
    _startForegroundTracking();
  }

  /// Detiene el GPS completamente
  Future<void> stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;
    await _foregroundSub?.cancel();
    await _backgroundSub?.cancel();
    _foregroundSub = null;
    _backgroundSub = null;
    await _bg.stop();
  }

  /// Llama esto cuando la app va a background (AppLifecycleState.paused)
  Future<void> onAppBackground() async {
    if (!_isTracking || _isInBackground) return;
    _isInBackground = true;

    // Cancela el stream de foreground (geolocator)
    await _foregroundSub?.cancel();
    _foregroundSub = null;

    // Activa el stream del servicio nativo
    _startBackgroundTracking();
  }

  /// Llama esto cuando la app vuelve a foreground (AppLifecycleState.resumed)
  Future<void> onAppForeground() async {
    if (!_isTracking || !_isInBackground) return;
    _isInBackground = false;

    // Cancela el stream nativo
    await _backgroundSub?.cancel();
    _backgroundSub = null;

    // Reactiva geolocator en foreground
    _startForegroundTracking();
  }

  // ── Posición inicial ─────────────────────────────────────────────

  Future<Position?> getInitialPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Streams internos ─────────────────────────────────────────────

  void _startForegroundTracking() {
    _foregroundSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:       LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      (position) => _controller?.add(position),
      onError: (e) => print('[GpsService] Error foreground: $e'),
    );
  }

  void _startBackgroundTracking() {
    _backgroundSub = _bg.locationStream.listen(
      (data) {
        // Convierte LocationData → Position para mantener la misma interfaz
        final position = Position(
          latitude:             data.latitude,
          longitude:            data.longitude,
          speed:                data.speed,
          heading:              data.heading,
          accuracy:             5.0,
          altitude:             0.0,
          altitudeAccuracy:     0.0,
          headingAccuracy:      0.0,
          speedAccuracy:        0.0,
          timestamp:            DateTime.now(),
        );
        _controller?.add(position);
      },
      onError: (e) => print('[GpsService] Error background: $e'),
    );
  }

  // ── Limpieza ─────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopTracking();
    await _controller?.close();
    _controller = null;
  }
}
