import 'dart:async';
import 'package:flutter/services.dart';

class BackgroundService {
  static const _methodChannel = MethodChannel('com.coyoteatento.motogps/background');
  static const _eventChannel  = EventChannel('com.coyoteatento.motogps/location');

  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  StreamSubscription? _locationSub;
  StreamController<LocationData>? _controller;

  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod('startService');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BackgroundService] Error al iniciar: ${e.message}');
    }
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stopService');
      await _locationSub?.cancel();
      _locationSub = null;
      await _controller?.close();
      _controller = null;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BackgroundService] Error al detener: ${e.message}');
    }
  }

  Future<void> updateInstruction(String instruction) async {
    try {
      await _methodChannel.invokeMethod(
        'updateInstruction',
        {'instruction': instruction},
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BackgroundService] Error al actualizar instruccion: ${e.message}');
    }
  }

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
          print('[BackgroundService] Error en stream: $error');
        });
    return _controller!.stream;
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
  });

  double get speedKmh => speed * 3.6;

  @override
  String toString() =>
      'LocationData(lat: $latitude, lng: $longitude, '
      'speed: ${speedKmh.toStringAsFixed(1)} km/h, heading: $heading)';
}
