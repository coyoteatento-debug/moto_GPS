import 'dart:async';
import 'dart:math';

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

  // Dead reckoning — velocidad y rumbo actuales
  double _speedMs  = 0.0;
  double _bearingR = 0.0; // radianes

  DateTime? _animStartTime;
  Duration  _animDuration = const Duration(milliseconds: 1000);

  Timer? _timer;
  StreamController<SmoothPosition>?  _controller;
  bool _isRunning = false;

  // ── API pública ──────────────────────────────────────

  Stream<SmoothPosition> get positionStream {
    _controller ??= StreamController<SmoothPosition>.broadcast();
    return _controller!.stream;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _controller ??= StreamController<SmoothPosition>.broadcast();
    _timer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _onTick(),
    );
  }

  void updatePosition({
    required double lat,
    required double lng,
    required double heading,
    required double speedMs,
  }) {
    final now = DateTime.now();

    _speedMs  = speedMs;
    _bearingR = heading * pi / 180.0;

    if (_fromLat == null) {
      _fromLat     = lat;
      _fromLng     = lng;
      _fromHeading = heading;
      _toLat       = lat;
      _toLng       = lng;
      _toHeading   = heading;
      _animStartTime = now;
      return;
    }

    // Snapshot de la posición interpolada actual como punto de partida
    final progress = _currentProgress(now);
    _fromLat     = _lerp(_fromLat!, _toLat!, progress);
    _fromLng     = _lerpLng(_fromLng!, _toLng!, progress);
    _fromHeading = _lerpAngle(_fromHeading!, _toHeading!, progress);

    _toLat       = lat;
    _toLng       = lng;
    _toHeading   = heading;

    _animDuration  = _calcDuration(speedMs);
    _animStartTime = now;
  }

  Future<void> stop() async {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    _fromLat = _fromLng = _fromHeading = null;
    _toLat   = _toLng   = _toHeading   = null;
    await _controller?.close();
    _controller = null;
  }

  // ── Ticker a 30fps ───────────────────────────────────

  void _onTick() {
    if (!_isRunning) return;
    if (_fromLat == null || _toLat == null) return;
    if (_controller == null || !(_controller!.hasListener)) return;

    final now = DateTime.now();

    final progress = _currentProgress(now);

    double lat     = _lerp(_fromLat!, _toLat!, progress);
    double lng     = _lerpLng(_fromLng!, _toLng!, progress);
    double heading = _lerpAngle(_fromHeading!, _toHeading!, progress);

    // Dead reckoning — extrapolar posición más allá del target GPS
    // cuando la animación ya completó el 95% y el usuario sigue moviéndose
    if (progress >= 0.95 && _speedMs > 0.5) {
      final extraMs    = now.difference(_animStartTime!).inMilliseconds
                         - _animDuration.inMilliseconds;
      final extraSec   = (extraMs / 1000.0).clamp(0.0, 0.5);
      final distMeters = _speedMs * extraSec;
      const R          = 6371000.0;
      final cosLat     = cos((_toLat ?? lat) * pi / 180); // ← null-safe
      if (cosLat.abs() > 0.001) {                         // ← guard división por cero
        final dLat = (distMeters * cos(_bearingR)) / R;
        final dLng = (distMeters * sin(_bearingR)) / (R * cosLat);
        lat += dLat * 180 / pi;
        lng += dLng * 180 / pi;
      }
    }

    _controller!.add(SmoothPosition(
      latitude:  lat,
      longitude: lng,
      heading:   heading,
    ));
  }

  // ── Helpers matemáticos ──────────────────────────────

  double _currentProgress(DateTime now) {
    if (_animStartTime == null) return 1.0;
    final elapsed = now.difference(_animStartTime!).inMilliseconds;
    final total   = _animDuration.inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  // Ease-out cúbico — arranca rápido y desacelera suavemente
  // Más natural para tracking continuo que ease in-out
  double _easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

  double _lerp(double from, double to, double t) {
    return from + (to - from) * _easeOut(t);
  }

  double _lerpLng(double from, double to, double t) {
    double delta = to - from;
    if (delta > 180)  delta -= 360;
    if (delta < -180) delta += 360;
    return from + delta * _easeOut(t);
  }

  double _lerpAngle(double from, double to, double t) {
    double delta = to - from;
    if (delta > 180)  delta -= 360;
    if (delta < -180) delta += 360;
    return (from + delta * _easeOut(t)) % 360;
  }

  Duration _calcDuration(double speedMs) {
    if (speedMs < 1)  return const Duration(milliseconds: 1500); // quieto
    if (speedMs < 3)  return const Duration(milliseconds: 1200); // peatonal
    if (speedMs < 10) return const Duration(milliseconds: 900);  // ciudad
    if (speedMs < 25) return const Duration(milliseconds: 750);  // carretera
    return const Duration(milliseconds: 600);                    // autopista
  }
}

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
