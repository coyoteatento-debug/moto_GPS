import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SpeedLimitService {
  static final SpeedLimitService _instance = SpeedLimitService._internal();
  factory SpeedLimitService() => _instance;
  SpeedLimitService._internal();

  int? _lastSpeedLimit;
  double? _lastQueryLat;
  double? _lastQueryLng;
  DateTime? _lastQueryTime;
  bool _isFetching = false;
  // ── Obtener límite de velocidad ──────────────────────

  /// Retorna el límite de velocidad en km/h de la vía más cercana
  /// Retorna null si no hay datos disponibles
  Future<int?> getSpeedLimit(double lat, double lng) async {
    if (_isFetching) return _lastSpeedLimit;
    if (_lastQueryTime != null && _lastQueryLat != null) {
      final elapsed = DateTime.now().difference(_lastQueryTime!).inSeconds;
      final moved   = _distanceBetween(lat, lng, _lastQueryLat!, _lastQueryLng!);
      if (elapsed < 30 && moved < 100) return _lastSpeedLimit;
    }

    _isFetching = true;
    final client = http.Client();
    try {
      final query =
          '[out:json][timeout:10];'
          'way[maxspeed](around:25,$lat,$lng);'
          'out tags 1;';
      final uri = Uri.parse('https://overpass-api.de/api/interpreter');
      final response = await client.post(
        uri,
        headers: {
          'User-Agent':   'MotoGPS/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept':       'application/json',
        },
        body: 'data=${Uri.encodeComponent(query)}',
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          client.close();
          throw TimeoutException('SpeedLimit timeout');
        },
      );
      if (response.statusCode != 200) return _lastSpeedLimit;
      final elements = json.decode(response.body)['elements'] as List;
      if (elements.isEmpty) {
        _lastSpeedLimit = null;
        return null;
      }
      final tags     = elements[0]['tags'] as Map<String, dynamic>?;
      final maxspeed = tags?['maxspeed'] as String?;
      final limit    = _parseSpeedLimit(maxspeed);
      _lastSpeedLimit = limit;
      _lastQueryLat   = lat;
      _lastQueryLng   = lng;
      _lastQueryTime  = DateTime.now();
      return limit;
    } catch (_) {
      return _lastSpeedLimit;
    } finally {
      client.close();
      _isFetching = false;
    }
  }

  /// Limpia el caché — llamar al cancelar ruta
  void clearCache() {
    _lastSpeedLimit = null;
    _lastQueryLat   = null;
    _lastQueryLng   = null;
    _lastQueryTime  = null;
    _isFetching     = false;
  }

  // ── Helpers ──────────────────────────────────────────

  /// Parsea el string de maxspeed a int km/h
  /// Maneja: "50", "50 mph", "ES:urban", "ES:rural", "ES:motorway"
  int? _parseSpeedLimit(String? maxspeed) {
    if (maxspeed == null || maxspeed.isEmpty) return null;

    // Valor numérico directo: "50", "80"
    final direct = int.tryParse(maxspeed.trim());
    if (direct != null) return direct;

    // Valor en mph: "30 mph"
    if (maxspeed.contains('mph')) {
      final mph = int.tryParse(maxspeed.replaceAll('mph', '').trim());
      if (mph != null) return (mph * 1.60934).round();
    }

    // Códigos de zona México/España
    final lower = maxspeed.toLowerCase();
    if (lower.contains('urban'))    return 50;
    if (lower.contains('rural'))    return 90;
    if (lower.contains('motorway')) return 120;
    if (lower.contains('living'))   return 20;
    if (lower.contains('walk'))     return 10;

    return null;
  }

  /// Distancia aproximada en metros entre dos puntos
  double _distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    const toRad = 3.14159265 / 180;
    final dLat = (lat2 - lat1) * toRad;
    final dLng = (lng2 - lng1) * toRad;
    final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(lat1 * toRad) * cos(lat2 * toRad) *
              sin(dLng / 2) * sin(dLng / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ── Estado de alerta de velocidad ────────────────────────

enum SpeedAlertLevel {
  normal,   // dentro del límite
  warning,  // hasta 10km/h sobre el límite
  danger,   // más de 10km/h sobre el límite
}

class SpeedStatus {
  final int? speedLimit;
  final SpeedAlertLevel level;

  const SpeedStatus({
    required this.speedLimit,
    required this.level,
  });

  static SpeedStatus evaluate(double currentSpeed, int? speedLimit) {
    if (speedLimit == null) {
      return const SpeedStatus(
        speedLimit: null,
        level:      SpeedAlertLevel.normal,
      );
    }
    final over = currentSpeed - speedLimit;
    if (over > 10) {
      return SpeedStatus(speedLimit: speedLimit, level: SpeedAlertLevel.danger);
    } else if (over > 0) {
      return SpeedStatus(speedLimit: speedLimit, level: SpeedAlertLevel.warning);
    }
    return SpeedStatus(speedLimit: speedLimit, level: SpeedAlertLevel.normal);
  }
}
