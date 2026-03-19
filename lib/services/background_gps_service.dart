import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

// ═══════════════════════════════════════════════════════
// PUNTO DE ENTRADA DEL SERVICIO
// DEBE ser función top-level (no método de clase)
// Se ejecuta en un Isolate separado — sin acceso al UI
// ═══════════════════════════════════════════════════════
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  // Requerido para usar plugins Flutter dentro del isolate
  DartPluginRegistrant.ensureInitialized();

  // Configurar como Foreground Service en Android
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  // Escuchar comando de parada desde la UI
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // ─────────────────────────────────────────────────
  // LOOP PRINCIPAL: Captura GPS cada 3 segundos
  // Intervalo de 3s es buen balance entre precisión y batería
  // Para rutas de moto (60-120 km/h):
  //   3s × 90km/h = 75 metros entre puntos — suficiente
  // ─────────────────────────────────────────────────
  Timer.periodic(const Duration(seconds: 3), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!await service.isForegroundService()) return;
    }

    try {
     final Position position = await Geolocator.getCurrentPosition(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    timeLimit: Duration(seconds: 5),
  ),
);

      final double speedKmh = (position.speed * 3.6).clamp(0.0, 350.0);

      // Enviar posición a la UI mediante invoke
      service.invoke('updateLocation', {
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed,       // m/s (raw de GPS)
        'speedKmh': speedKmh,          // km/h (calculado)
        'heading': position.heading,   // grados 0-360
        'accuracy': position.accuracy, // metros de precisión
        'altitude': position.altitude, // metros sobre nivel del mar
        'timestamp': position.timestamp.toIso8601String(),
      });

      // Actualizar la notificación persistente del sistema
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: '🏍️ MotoGPS — Tracking activo',
          content: 'Velocidad: ${speedKmh.toStringAsFixed(0)} km/h'
              '  |  Precisión: ±${position.accuracy.toStringAsFixed(0)} m',
        );
      }
    } on TimeoutException {
      service.invoke('gpsError', {'error': 'Timeout esperando señal GPS'});
    } catch (e) {
      service.invoke('gpsError', {'error': e.toString()});
    }
  });
}

// ═══════════════════════════════════════════════════════
// iOS Background handler (requerido aunque solo uses Android)
// ═══════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ═══════════════════════════════════════════════════════
// CLASE PRINCIPAL DEL SERVICIO
// ═══════════════════════════════════════════════════════
class BackgroundGpsService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  // ─────────────────────────────────────────────────
  // INICIALIZAR — Llamar en main() antes de runApp()
  // ─────────────────────────────────────────────────
  static Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        isForegroundMode: true,
        autoStart: false,
        notificationChannelId: 'motogps_tracking',
        initialNotificationTitle: '🏍️ MotoGPS',
        initialNotificationContent: 'Listo para iniciar tracking GPS',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onBackgroundServiceStart,
        onBackground: onIosBackground,
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // INICIAR TRACKING
  // Devuelve true si el servicio arrancó correctamente
  // ─────────────────────────────────────────────────
  static Future<bool> startTracking() async {
    final isRunning = await _service.isRunning();
    if (isRunning) return true;
    return await _service.startService();
  }

  // ─────────────────────────────────────────────────
  // DETENER TRACKING
  // ─────────────────────────────────────────────────
  static Future<void> stopTracking() async {
    _service.invoke('stopService');
  }

  // ─────────────────────────────────────────────────
  // STREAM: Posiciones GPS en tiempo real
  // Escuchar desde la UI con StreamBuilder o listen()
  // ─────────────────────────────────────────────────
  static Stream<Map<String, dynamic>?> get locationStream {
    return _service
        .on('updateLocation')
        .map((event) => event as Map<String, dynamic>?);
  }

  // ─────────────────────────────────────────────────
  // STREAM: Errores GPS
  // ─────────────────────────────────────────────────
  static Stream<Map<String, dynamic>?> get errorStream {
    return _service
        .on('gpsError')
        .map((event) => event as Map<String, dynamic>?);
  }

  // ─────────────────────────────────────────────────
  // VERIFICAR si el servicio está activo
  // ─────────────────────────────────────────────────
  static Future<bool> get isRunning => _service.isRunning();
}
