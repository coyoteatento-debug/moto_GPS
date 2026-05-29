import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'background_service.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  final BackgroundService _bg = BackgroundService();

  StreamSubscription<Position>? _foregroundSub;
  StreamSubscription<dynamic>? _backgroundSub;
  StreamController<Position>? _controller;

  bool _isInBackground = false;
  bool _isTracking = false;
  Position? _lastPosition;

  // ── Stream principal ─────────────────────────────────────────────

  /// Stream unificado — funciona tanto en foreground como en background
  Stream<Position> get positionStream {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<Position>.broadcast();
    }
    return _controller!.stream;
  }

  // ── Control del tracking ─────────────────────────────────────────

  /// Inicia el GPS
  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;
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

  /// Llama esto cuando la app va a background
  Future<void> onAppBackground() async {
    if (!_isTracking || _isInBackground) return;
    _isInBackground = true;

    await _foregroundSub?.cancel();
    _foregroundSub = null;
    _startBackgroundTracking();
  }

  /// Llama esto cuando la app vuelve a foreground
  Future<void> onAppForeground() async {
    if (!_isTracking || !_isInBackground) return;
    _isInBackground = false;

    await _backgroundSub?.cancel();
    _backgroundSub = null;
    _startForegroundTracking();
  }

  // ── Posición inicial ─────────────────────────────────────────────

  Future<Position?> getInitialPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 10));
        _lastPosition = pos;
        return pos;
      } catch (e) {
        print('[GpsService] getInitialPosition attempt $attempt failed: $e');
        if (attempt == 3) return _lastPosition;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return _lastPosition;
  }

  // ── Streams internos ─────────────────────────────────────────────

  void _startForegroundTracking() {
    _foregroundSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(
      (position) {
        _lastPosition = position;
        if (_controller != null && !_controller!.isClosed) {
          _controller!.add(position);
        }
      },
      onError: (e) => debugPrint('[GpsService] Error foreground: $e'),
    );
  }

  void _startBackgroundTracking() {
    _backgroundSub = _bg.locationStream.listen(
      (data) {
        final position = Position(
          latitude: data.latitude,
          longitude: data.longitude,
          speed: data.speed,
          heading: data.heading,
          accuracy: 5.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
          speedAccuracy: 0.0,
          timestamp: DateTime.now(),
        );
        _lastPosition = position;
        if (_controller != null && !_controller!.isClosed) {
          _controller!.add(position);
        }
      },
      onError: (e) => debugPrint('[GpsService] Error background: $e'),
    );
  }

  // ── Limpieza ─────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopTracking();
    await _bg.stop();
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }
}
