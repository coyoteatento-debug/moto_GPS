import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puente entre Flutter y LocationForegroundService (Android nativo)
/// Usa MethodChannel para enviar comandos y EventChannel para recibir GPS
class BackgroundService {
  static const _methodChannel = MethodChannel('com.example.moto_gps/background');
  static const _eventChannel  = EventChannel('com.example.moto_gps/location');

  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  StreamSubscription? _locationSub;
  StreamController<LocationData>? _controller;

  // ── Control del servicio ─────────────────────────────────────────

  /// Inicia el ForegroundService con la notificación GPS
  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod('startService');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      debugPrint('[BackgroundService] Error al iniciar: ${e.message}');
    }
  }

  /// Detiene el ForegroundService
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stopService');
      await _locationSub?.cancel();
      _locationSub = null;
      await _controller?.close();
      _controller = null;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      debugPrint('[BackgroundService] Error al detener: ${e.message}');
    }
  }

  /// Actualiza el texto de la notificación persistente
  Future<void> updateInstruction(String instruction) async {
    try {
      await _methodChannel.invokeMethod(
        'updateInstruction',
        {'instruction': instruction},
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      debugPrint('[BackgroundService] Error al actualizar instrucción: ${e.message}');
    }
  }

  // ── Stream de ubicación ──────────────────────────────────────────

  /// Stream que emite LocationData cuando el servicio está activo en background
  Stream<LocationData> get locationStream {
    _controller ??= StreamController<LocationData>.broadcast();

    _locationSub ??= _eventChannel
        .receiveBroadcastStream()
        .listen((dynamic data) {
          if (data is Map) {
            _controller?.add(LocationData(
              latitude:  (data['latitude']  as num).toDouble(),
              longitude: (data['longitude'] as num).toDouble(),
              speed:     (data['speed']     as num).toDouble(),
              heading:   (data['heading']   as num).toDouble(),
            ));
          }
        }, onError: (dynamic error) {
          debugPrint('[BackgroundService] Error en stream: $error');
        });

    return _controller!.stream;
  }
}

// ── Modelo de datos GPS ──────────────────────────────────────────────

class LocationData {
  final double latitude;
  final double longitude;
  final double speed;    // m/s
  final double heading;  // grados 0-360

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
  });

  /// Velocidad en km/h
  double get speedKmh => speed * 3.6;

  @override
  String toString() =>
      'LocationData(lat: $latitude, lng: $longitude, '
      'speed: ${speedKmh.toStringAsFixed(1)} km/h, heading: $heading°)';
}
