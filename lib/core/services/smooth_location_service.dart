import 'dart:async';
import 'dart:math';
import 'package:flutter/scheduler.dart';

/// Interpolador continuo de ubicación a 60fps
/// Elimina los saltos del GPS animando suavemente entre puntos reales
class SmoothLocationService {

  static final SmoothLocationService _instance =
      SmoothLocationService._internal();
  factory SmoothLocationService() => _instance;
  SmoothLocationService._internal();

  // ── Estado interno ───────────────────────────────────

  double? _fromLat;
  double? _fromLng;
  double? _fromHeading;

  double? _toLat;
  double? _toLng;
  double? _toHeading;

  DateTime? _animStartTime;
  Duration  _animDuration = const Duration(milliseconds: 1000);

  Ticker?        _ticker;
  StreamController<SmoothPosition>? _controller;

  bool _isRunning = false;

  // ── API pública ──────────────────────────────────────

  /// Stream continuo de posiciones interpoladas a 60fps
  Stream<SmoothPosition> get positionStream {
    _controller ??= StreamController<SmoothPosition>.broadcast();
    return _controller!.stream;
  }

  /// Inicia el interpolador — llama esto una sola vez al iniciar tracking
  void start(TickerProvider vsync) {
    if (_isRunning) return;
    _isRunning = true;
    _controller ??= StreamController<SmoothPosition>.broadcast();
    _ticker = vsync.createTicker(_onTick)..start();
  }

  /// Alimenta una nueva posición GPS real
  /// Llama esto cada vez que llega una posición del GPS
  void updatePosition({
    required double lat,
    required double lng,
    required double heading,
    required double speedMs,
  }) {
    final now = DateTime.now();

    if (_fromLat == null) {
      // Primera posición — inicializar sin animación
      _fromLat     = lat;
      _fromLng     = lng;
      _fromHeading = heading;
      _toLat       = lat;
      _toLng       = lng;
      _toHeading   = heading;
      _animStartTime = now;
      return;
    }

    // Calcular duración dinámica basada en velocidad
    // A mayor velocidad → animación más rápida para mayor precisión
    final duration = _calcDuration(speedMs);

    // El punto de partida es la posición interpolada actual
    final progress = _currentProgress(now);
    _fromLat     = _lerp(_fromLat!, _toLat!, progress);
    _fromLng     = _lerpLng(_fromLng!, _toLng!, progress);
    _fromHeading = _lerpAngle(_fromHeading!, _toHeading!, progress);

    // El destino es la nueva posición GPS
    _toLat       = lat;
    _toLng       = lng;
    _toHeading   = heading;

    _animDuration  = duration;
    _animStartTime = now;
  }

  /// Detiene el interpolador y libera recursos
  Future<void> stop() async {
    _isRunning = false;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _fromLat = _fromLng = _fromHeading = null;
    _toLat   = _toLng   = _toHeading   = null;
    await _controller?.close();
    _controller = null;
  }

  // ── Ticker a 60fps ───────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_isRunning) return;
    if (_fromLat == null || _toLat == null) return;
    if (_controller == null || !(_controller!.hasListener)) return;

    final now      = DateTime.now();
    final progress = _currentProgress(now);

    final lat     = _lerp(_fromLat!, _toLat!, progress);
    final lng     = _lerpLng(_fromLng!, _toLng!, progress);
    final heading = _lerpAngle(_fromHeading!, _toHeading!, progress);

    _controller!.add(SmoothPosition(
      latitude:  lat,
      longitude: lng,
      heading:   heading,
    ));
  }

  // ── Helpers matemáticos ──────────────────────────────

  /// Progreso actual de la animación entre 0.0 y 1.0
  double _currentProgress(DateTime now) {
    if (_animStartTime == null) return 1.0;
    final elapsed = now.difference(_animStartTime!).inMilliseconds;
    final total   = _animDuration.inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// Interpolación lineal con easing suave (ease in-out)
  double _lerp(double from, double to, double t) {
    final eased = t < 0.5
        ? 2 * t * t
        : 1 - pow(-2 * t + 2, 2) / 2; // ease in-out cuadrático
    return from + (to - from) * eased;
  }

  /// Interpolación de longitud (maneja el cruce del meridiano 180°)
  double _lerpLng(double from, double to, double t) {
    double delta = to - from;
    if (delta > 180)  delta -= 360;
    if (delta < -180) delta += 360;
    final eased = t < 0.5
        ? 2 * t * t
        : 1 - pow(-2 * t + 2, 2) / 2;
    return from + delta * eased;
  }

  /// Interpolación angular — maneja correctamente 359° → 1°
  double _lerpAngle(double from, double to, double t) {
    double delta = to - from;
    if (delta > 180)  delta -= 360;
    if (delta < -180) delta += 360;
    final eased = t < 0.5
        ? 2 * t * t
        : 1 - pow(-2 * t + 2, 2) / 2;
    return (from + delta * eased) % 360;
  }

  /// Duración dinámica según velocidad
  /// Equilibrio entre suavidad y precisión
  Duration _calcDuration(double speedMs) {
    if (speedMs < 2)  return const Duration(milliseconds: 1200); // peatonal
    if (speedMs < 10) return const Duration(milliseconds: 1000); // ciudad
    if (speedMs < 25) return const Duration(milliseconds: 850);  // carretera
    return const Duration(milliseconds: 700);                    // autopista
  }
}

// ── Modelo de posición suavizada ─────────────────────────

class SmoothPosition {
  final double latitude;
  final double longitude;
  final double heading;

  const SmoothPosition({
    required this.latitude,
    required this.longitude,
    required this.heading,
  });
}
