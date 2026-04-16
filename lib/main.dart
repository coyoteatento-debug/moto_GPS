import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  mapbox.MapboxOptions.setAccessToken(_mapboxToken);
  runApp(const MaterialApp(home: MotoGPSApp()));
}

// ── Modelo de viaje ───────────────────────────────────────
class TripRecord {
  final String destination;
  final double distanceKm;
  final int durationMin;
  final DateTime date;
  final List<List<double>> routeCoords;

  TripRecord({
    required this.destination,
    required this.distanceKm,
    required this.durationMin,
    required this.date,
    this.routeCoords = const [],
  });

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
    'date': date.toIso8601String(),
    'routeCoords': routeCoords,
  };

  factory TripRecord.fromJson(Map<String, dynamic> j) => TripRecord(
    destination: j['destination'],
    distanceKm: (j['distanceKm'] as num).toDouble(),
    durationMin: j['durationMin'],
    date: DateTime.parse(j['date']),
    routeCoords: (j['routeCoords'] as List? ?? [])
        .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
  );
}

class RoutePainter extends CustomPainter {
  final List<List<double>> coords;
  RoutePainter(this.coords);

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    double minLng = coords.map((c) => c[0]).reduce(min);
    double maxLng = coords.map((c) => c[0]).reduce(max);
    double minLat = coords.map((c) => c[1]).reduce(min);
    double maxLat = coords.map((c) => c[1]).reduce(max);

    final rangeX = (maxLng - minLng).abs();
    final rangeY = (maxLat - minLat).abs();
    if (rangeX == 0 || rangeY == 0) return;

    final pad = 12.0;
    final path = Path();
    for (int i = 0; i < coords.length; i++) {
      final x = pad + (coords[i][0] - minLng) / rangeX * (size.width  - pad * 2);
      final y = pad + (maxLat - coords[i][1]) / rangeY * (size.height - pad * 2);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    // Punto inicio (verde) y fin (rojo)
    final start = coords.first;
    final end   = coords.last;
    final sx = pad + (start[0] - minLng) / rangeX * (size.width  - pad * 2);
    final sy = pad + (maxLat - start[1]) / rangeY * (size.height - pad * 2);
    final ex = pad + (end[0]   - minLng) / rangeX * (size.width  - pad * 2);
    final ey = pad + (maxLat - end[1])   / rangeY * (size.height - pad * 2);
    canvas.drawCircle(Offset(sx, sy), 5, Paint()..color = Colors.green);
    canvas.drawCircle(Offset(ex, ey), 5, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class MotoGPSApp extends StatefulWidget {
  const MotoGPSApp({super.key});
  @override
  State<MotoGPSApp> createState() => _MotoGPSAppState();
}

class _MotoGPSAppState extends State<MotoGPSApp> with TickerProviderStateMixin {

  mapbox.MapboxMap? mapboxMap;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? motoAnnotation;
  mapbox.PointAnnotation? destinationAnnotation;
  AnimationController? _markerAnimController;
  double? _lastAnimatedLat;
  double? _lastAnimatedLng;

  Uint8List? pinImage;
  Uint8List? _userAvatarImage;

  double _currentSpeed = 0.0;
  Position? _currentPosition;

  Map<String, dynamic>? _selectedPlace;
  bool _routeDrawn = false;
  bool _navigating = false;
  String _routeDistance = '';
  String _routeDuration = '';

  // ── TTS ───────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  String _lastSpokenInstruction = '';
  
  // ── Turn-by-turn ──────────────────────────────────────
  List<Map<String, dynamic>> _routeSteps = [];
  String _currentInstruction = '';
  double _distanceToNextManeuver = 0.0;
  int _currentStepIndex = 0;

  // ── Buscador ──────────────────────────────────────────
  bool _showSearch = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  final TextEditingController _searchController = TextEditingController();
  
  bool _showTapConfirm = false;
  double? _tappedLat;
  double? _tappedLng;

  List<List<double>> _routeCoordinates = [];

  bool _userIsExploring    = false;
  bool _isSatellite        = false;
  bool _gasolinerasVisible = false;
  List<Map<String, dynamic>> _alternateRoutes = [];
  int _selectedRouteIndex = 0;
  bool _isRecalculating = false;
  int _deviationCount = 0;
  DateTime? _lastRecalcTime;
  
  bool _isProgrammaticMove = false;
  bool _initialLocationSet = false;

  // ── Libro de viajes ───────────────────────────────────
  List<TripRecord> _trips = [];
  DateTime? _tripStartTime;
  double _tripAccumulatedDistance = 0.0;
  Position? _lastTripPosition;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _requestPermissions();
    _loadTrips();
    _initTts();
    _loadUserAvatar();
  }

  @override
  void dispose() {
    _markerAnimController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Imágenes ──────────────────────────────────────────
  Future<Uint8List> _resizeImage(Uint8List data, int targetWidth) async {
    final codec    = await ui.instantiateImageCodec(data, targetWidth: targetWidth);
    final frame    = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

 Future<Uint8List> _makeCircularImage(Uint8List data, int size) async {
    final codec = await ui.instantiateImageCodec(data,
        targetWidth: size, targetHeight: size);
    final frame = await codec.getNextFrame();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    canvas.clipPath(Path()..addOval(rect));
    // Fondo blanco
    canvas.drawRect(rect, paint..color = Colors.white);
    // Imagen
    canvas.drawImageRect(
      frame.image,
      Rect.fromLTWH(0, 0,
          frame.image.width.toDouble(), frame.image.height.toDouble()),
      rect,
      paint,
    );
    // Borde
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _pickUserAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final circular = await _makeCircularImage(bytes, 70);
    // Guardar en SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_avatar', base64Encode(circular));
    setState(() => _userAvatarImage = circular);
    // Eliminar marcador anterior y recrear con avatar
    if (motoAnnotation != null && annotationManager != null) {
      await annotationManager!.delete(motoAnnotation!);
      motoAnnotation = null;
    }
    if (_currentPosition != null) {
      await _updateMotoMarker(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _currentPosition!.heading,
      );
    }
  }

  Future<void> _loadUserAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_avatar');
    if (raw != null) {
      setState(() => _userAvatarImage = base64Decode(raw));
    }
  }
  
  Future<void> _loadImages() async {
    final ByteData pinData  = await rootBundle.load('assets/moto_pin.png');
    final Uint8List pinResized  = await _resizeImage(pinData.buffer.asUint8List(), 120);
    setState(() { pinImage = pinResized; });
  }

  // ── Libro de viajes ───────────────────────────────────
  Future<void> _loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('trip_records');
    if (raw != null) {
      final data = json.decode(raw) as List;
      setState(() {
        _trips = data.map((e) => TripRecord.fromJson(e)).toList();
      });
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('es-MX');
    await _tts.setSpeechRate(0.52);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty || text == _lastSpokenInstruction) return;
    _lastSpokenInstruction = text;
    // Esperar a que termine antes de hablar
     await _tts.speak(text);
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      const types = 'place,locality,neighborhood,address,district';
      final proximity = _currentPosition != null
          ? '&proximity=${_currentPosition!.longitude},${_currentPosition!.latitude}'
          : '';
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/'
          '${Uri.encodeComponent(query)}.json'
          '?access_token=$_mapboxToken'
          '&language=es'
          '&country=MX,US'
          '&types=$types'
          '&limit=7'
          '$proximity';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final features = json.decode(response.body)['features'] as List;
        setState(() {
          _searchResults = features.map((f) {
             // Siempre usar center — es el punto representativo oficial de Mapbox
          final center = f['center'] as List;
          final double lat = (center[1] as num).toDouble();
          final double lng = (center[0] as num).toDouble();

          return {
            'name':      f['text'] as String,
            'full_name': f['place_name'] as String,
            'lat':       lat,
            'lng':       lng,
          };
        }).toList();
        });
      }
    } catch (_) {}
    setState(() => _searchLoading = false);
  }

  Future<void> _selectSearchResult(Map<String, dynamic> place) async {
    final lat = place['lat'] as double;
    final lng = place['lng'] as double;
    setState(() {
      _showSearch = false;
      _searchResults = [];
      _searchController.clear();
      _selectedPlace = place;
    });
    await _addDestinationMarker(lat, lng);
    // Mover cámara al destino SIEMPRE, independiente de si la ruta funciona
    mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        zoom: 12.0, bearing: 0.0, pitch: 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 1200, startDelay: 0),
    );
    await _getRoute(lat, lng);
  }
  
  Future<void> _saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'trip_records',
      json.encode(_trips.map((t) => t.toJson()).toList()),
    );
  }

  void _startTripTracking() {
    _tripStartTime           = DateTime.now();
    _tripAccumulatedDistance = 0.0;
    _lastTripPosition        = _currentPosition;
  }

  void _accumulateTripDistance(Position position) {
    if (_lastTripPosition != null) {
      _tripAccumulatedDistance += _distanceBetween(
        _lastTripPosition!.latitude,
        _lastTripPosition!.longitude,
        position.latitude,
        position.longitude,
      );
    }
    _lastTripPosition = position;
  }

  Future<void> _finishAndSaveTrip() async {
    if (_tripStartTime == null) return;
    final duration = DateTime.now().difference(_tripStartTime!);
    final record = TripRecord(
      destination: _selectedPlace?['name'] ?? 'Destino',
      distanceKm:  double.parse(
          (_tripAccumulatedDistance / 1000).toStringAsFixed(2)),
      durationMin: duration.inMinutes,
      date:        _tripStartTime!,
      routeCoords: List<List<double>>.from(_routeCoordinates), // ← AGREGAR
    );
    setState(() => _trips.insert(0, record));
    await _saveTrips();
    _tripStartTime           = null;
    _tripAccumulatedDistance = 0.0;
    _lastTripPosition        = null;
  }

  // ── Permisos ──────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      await _getInitialPosition();
      _startLocationTracking();
} else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  double _calculateDynamicZoom(double speed) {
    if (speed < 20) return 16.0;
    if (speed < 80) return 14.0;
    return 12.0;
  }

  // ── Mapa ──────────────────────────────────────────────
  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    mapboxMap = map;
    annotationManager = await map.annotations.createPointAnnotationManager();
    await Future.delayed(const Duration(milliseconds: 600));
    await _applyCustomRoadStyle();
  // Centrar en ubicación actual si ya se obtuvo
  if (_currentPosition != null) {
  _isProgrammaticMove = true;
  mapboxMap?.flyTo(
    mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(
        _currentPosition!.longitude, _currentPosition!.latitude,
      )),
      zoom: 15.0, bearing: _currentPosition!.heading, pitch: 0.0,
    ),
    mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
  );
  await _updateMotoMarker(
    _currentPosition!.latitude,
    _currentPosition!.longitude,
    _currentPosition!.heading,
  );
 }
}    
  // ── Estilo de carreteras tipo Riser ───────────────────
  Future<void> _applyCustomRoadStyle() async {
  if (mapboxMap == null) return;
  final style = await mapboxMap!.style;

  // Layer IDs reales de streets-v12 con colores estilo Calimoto iluminados
  final Map<String, String> lineColors = {
    // Autopistas
    'road-motorway':                    '#F5780A',
    'road-motorway-case':               '#C45500',
    'road-motorway-link':               '#F5780A',
    'road-motorway-link-case':          '#C45500',
    // Tronco
    'road-trunk':                       '#F5780A',
    'road-trunk-case':                  '#C45500',
    'road-trunk-link':                  '#F5780A',
    'road-trunk-link-case':             '#C45500',
    // Primarias
    'road-primary':                     '#F7C521',
    'road-primary-case':                '#D4A017',
    'road-primary-link':                '#F7C521',
    // Secundarias
    'road-secondary':                   '#F5D040',
    'road-secondary-case':              '#C8A820',
    'road-secondary-link':              '#F5D040',
    // Terciarias
    'road-tertiary':                    '#F5D040',
    'road-tertiary-case':               '#C8A820',
    // Calles
    'road-street':                      '#FAFAF5',
    'road-street-case':                 '#E0DDD4',
    'road-street-low':                  '#FAFAF5',
    // Secundaria-terciaria combinada
    'road-secondary-tertiary':          '#F5D040',
    'road-secondary-tertiary-case':     '#C8A820',
    // Motorway-trunk combinada
    'road-motorway-trunk':              '#F5780A',
    'road-motorway-trunk-case':         '#C45500',
    // Peatonal y caminos
    'road-pedestrian':                  '#F0EBE0',
    'road-pedestrian-case':             '#E0DDD4',
    'road-path':                        '#E8E2D0',
    'road-path-bg':                     '#E0DDD4',
    // Servicio
    'road-service':                     '#FAFAF5',
    'road-service-case':                '#E0DDD4',
  };

  for (final entry in lineColors.entries) {
    try {
      await style.setStyleLayerProperty(
        entry.key, 'line-color', json.encode(entry.value),
      );
    } catch (_) {}
  }
    
  // Fondo beige cálido
  for (final bg in ['land', 'background', 'landcover']) {
    try {
      await style.setStyleLayerProperty(
        bg, 'background-color', json.encode('#F0EDE4'),
      );
    } catch (_) {}
  }
}

  // ── Utilidades ruta ───────────────────────────────────
  double _distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  int _findClosestPointIndex(double lat, double lng) {
    double minDist = double.infinity;
    int idx = 0;
    for (int i = 0; i < _routeCoordinates.length; i++) {
      final d = _distanceBetween(lat, lng, _routeCoordinates[i][1], _routeCoordinates[i][0]);
      if (d < minDist) { minDist = d; idx = i; }
    }
    return idx;
  }

  List<double> _snapToRoute(double lat, double lng) {
    if (_routeCoordinates.length < 2) return [lng, lat];
    double minDist = double.infinity;
    List<double> snapped = [lng, lat];
    for (int i = 0; i < _routeCoordinates.length - 1; i++) {
      final a = _routeCoordinates[i];
      final b = _routeCoordinates[i + 1];
      final abX = b[0]-a[0]; final abY = b[1]-a[1];
      final apX = lng-a[0];  final apY = lat-a[1];
      final ab2 = abX*abX + abY*abY;
      if (ab2 == 0) continue;
      final t = ((apX*abX + apY*abY) / ab2).clamp(0.0, 1.0);
      final pLng = a[0]+t*abX; final pLat = a[1]+t*abY;
      final d = _distanceBetween(lat, lng, pLat, pLng);
      if (d < minDist) { minDist = d; snapped = [pLng, pLat]; }
    }
    return snapped;
  }

  double _bearingBetween(double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2-lng1)*pi/180;
    final y = sin(dLng)*cos(lat2*pi/180);
    final x = cos(lat1*pi/180)*sin(lat2*pi/180) -
               sin(lat1*pi/180)*cos(lat2*pi/180)*cos(dLng);
    return (atan2(y, x)*180/pi + 360) % 360;
  }

  Future<void> _updateRemainingRoute(double lat, double lng) async {
    if (!_navigating || _routeCoordinates.isEmpty || mapboxMap == null) return;
    final idx = _findClosestPointIndex(lat, lng);
    if (idx >= _routeCoordinates.length - 2) {
      await _finishAndSaveTrip();
      await _cancelRoute();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🏁 ¡Has llegado a tu destino!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ));
      return;
    }
    final remaining = _routeCoordinates.sublist(idx);
    if (remaining.length < 2) return;
    try {
      final style = await mapboxMap!.style;
      await style.setStyleSourceProperty('route-source-0', 'data', json.encode({
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': remaining},
      }));
    } catch (_) {}
  }

// REEMPLAZA todo el método:
void _checkRouteDeviation(double lat, double lng) {
    if (!_navigating || _routeCoordinates.isEmpty || _isRecalculating) return;

    if (_routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length) {
      final loc     = _routeSteps[_currentStepIndex]['location'] as List;
      final stepLat = (loc[1] as num).toDouble();
      final stepLng = (loc[0] as num).toDouble();
      if (_distanceBetween(lat, lng, stepLat, stepLng) < 120) return;
    }

    if (_lastRecalcTime != null &&
        DateTime.now().difference(_lastRecalcTime!).inSeconds < 20) return;

    double minDist = double.infinity;
    for (int i = 0; i < _routeCoordinates.length - 1; i++) {
      final a = _routeCoordinates[i];
      final b = _routeCoordinates[i + 1];
      final abX = b[0] - a[0]; final abY = b[1] - a[1];
      final apX = lng  - a[0]; final apY = lat  - a[1];
      final ab2 = abX * abX + abY * abY;
      if (ab2 == 0) continue;
      final t = ((apX * abX + apY * abY) / ab2).clamp(0.0, 1.0);
      final d = _distanceBetween(lat, lng, a[1] + t * abY, a[0] + t * abX);
      if (d < minDist) minDist = d;
    }

    if (minDist > 55) {
      _deviationCount++;
      if (_deviationCount >= 3) {
        _deviationCount = 0;
        _lastRecalcTime = DateTime.now();
        _recalculateRoute(lat, lng);
      }
    } else {
      _deviationCount = 0;
    }
  }

  Future<void> _recalculateRoute(double lat, double lng) async {
    if (_selectedPlace == null) return;
    setState(() => _isRecalculating = true);
    _speak('Recalculando ruta');

    final destLat = (_selectedPlace!['lat'] as num).toDouble();
    final destLng = (_selectedPlace!['lng'] as num).toDouble();

    await _getRoute(destLat, destLng);
    setState(() => _isRecalculating = false);
  }
  
  void _updateTurnByTurn(double lat, double lng) {
    if (_routeSteps.isEmpty || _currentStepIndex >= _routeSteps.length) return;

    final step    = _routeSteps[_currentStepIndex];
    final loc     = step['location'] as List;
    final stepLng = (loc[0] as num).toDouble();
    final stepLat = (loc[1] as num).toDouble();
    final distToManeuver = _distanceBetween(lat, lng, stepLat, stepLng);

    setState(() => _distanceToNextManeuver = distToManeuver);

    // Aviso anticipado a ~150m antes de la maniobra
    if (distToManeuver < 150 && distToManeuver >= 120) {
      final instr = _routeSteps[_currentStepIndex]['instruction'] as String;
      _speak('En 150 metros, $instr');
    }

    // Aviso cercano a ~50m
    if (distToManeuver < 50 && distToManeuver >= 30) {
      final instr = _routeSteps[_currentStepIndex]['instruction'] as String;
      _speak(instr);
    }

    // Avanza al siguiente paso al pasar la maniobra
    if (distToManeuver < 15 && _currentStepIndex < _routeSteps.length - 1) {
      _currentStepIndex++;
      final next = _routeSteps[_currentStepIndex];
      setState(() {
        _currentInstruction     = next['instruction'] as String;
        _distanceToNextManeuver = next['distance'] as double;
      });
      // NO hablar aquí — el aviso vendrá cuando se acerque
    }
  }

  // ── Tap mapa ──────────────────────────────────────────
  void _onMapTap(mapbox.MapContentGestureContext context) {
    if (_navigating) return;
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();
    setState(() { _tappedLat = lat; _tappedLng = lng; _showTapConfirm = true; });
    _addDestinationMarker(lat, lng);
    mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        zoom: 16.0, pitch: 0.0, bearing: 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
    );
  }

  Future<void> _confirmTappedDestination() async {
    if (_tappedLat == null || _tappedLng == null) return;
    String placeName = 'Destino seleccionado';
    try {
      final response = await http.get(Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$_tappedLng,$_tappedLat.json'
        '?access_token=$_mapboxToken&language=es&limit=1',
      ));
      if (response.statusCode == 200) {
        final features = json.decode(response.body)['features'] as List;
        if (features.isNotEmpty) placeName = features[0]['place_name'] as String;
      }
    } catch (_) {}
    setState(() {
      _selectedPlace = {'name': placeName, 'lat': _tappedLat, 'lng': _tappedLng};
      _showTapConfirm = false;
    });
    await _getRoute(_tappedLat!, _tappedLng!);
  }

  void _cancelTap() async {
    if (destinationAnnotation != null && annotationManager != null) {
      await annotationManager!.delete(destinationAnnotation!);
      destinationAnnotation = null;
    }
    setState(() { _showTapConfirm = false; _tappedLat = null; _tappedLng = null; });
  }

  // ── Marcadores ────────────────────────────────────────
  Future<void> _updateMotoMarker(double lat, double lng, double bearing) async {
    final markerImage = _userAvatarImage ?? pinImage;
    if (annotationManager == null || markerImage == null) return;
    // Si ya existe el marcador con avatar, solo actualizar posición/rotación
    if (motoAnnotation != null && _userAvatarImage != null) {
      motoAnnotation!.geometry = mapbox.Point(
          coordinates: mapbox.Position(lng, lat));
      motoAnnotation!.iconRotate = 0.0;
      await annotationManager!.update(motoAnnotation!);
      return;
    }
    if (motoAnnotation == null) {
      motoAnnotation = await annotationManager!.create(mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        image: markerImage, iconSize: 1.2,
        iconAnchor: mapbox.IconAnchor.CENTER,
        iconRotate: _userAvatarImage != null ? 0.0 : bearing,
      ));
    } else {
      motoAnnotation!.geometry = mapbox.Point(coordinates: mapbox.Position(lng, lat));
      motoAnnotation!.iconRotate = bearing;
      await annotationManager!.update(motoAnnotation!);
    }
  }

  Future<void> _addDestinationMarker(double lat, double lng) async {
    if (annotationManager == null) return;
    if (destinationAnnotation != null) {
      await annotationManager!.delete(destinationAnnotation!);
      destinationAnnotation = null;
    }
    destinationAnnotation = await annotationManager!.create(mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      image: pinImage, iconSize: 1.2, iconAnchor: mapbox.IconAnchor.BOTTOM,
    ));
  }

void _animateMarkerTo(double targetLat, double targetLng, double bearing) {
    final double fromLat = _lastAnimatedLat ?? targetLat;
    final double fromLng = _lastAnimatedLng ?? targetLng;

    _markerAnimController?.stop();
    _markerAnimController?.dispose();
    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    final animLat = Tween<double>(begin: fromLat, end: targetLat)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));
    final animLng = Tween<double>(begin: fromLng, end: targetLng)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));

    _markerAnimController!.addListener(() {
      _updateMotoMarker(animLat.value, animLng.value, bearing);
    });

    _markerAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _lastAnimatedLat = targetLat;
        _lastAnimatedLng = targetLng;
      }
    });

    _markerAnimController!.forward();
  }

  Future<void> _getInitialPosition() async {
  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
      _currentSpeed = position.speed * 3.6;
    });
    _initialLocationSet = true;
    await _updateMotoMarker(position.latitude, position.longitude, position.heading);
    if (mapboxMap != null) {
      mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
            position.longitude, position.latitude,
          )),
          zoom: 15.0, bearing: position.heading, pitch: 0.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
      );
    }
  } catch (_) {}
}
  
  // ── GPS Tracking ──────────────────────────────────────
  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        intervalDuration: const Duration(milliseconds: 1000),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'MotoGPS activo',
          notificationTitle: 'Navegación en curso',
          enableWakeLock: true,
        ),
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _currentSpeed = position.speed * 3.6;
        _currentPosition = position;
        // Si el usuario se mueve, retomar seguimiento automático
        if (_currentSpeed > 2 && !_navigating && !_routeDrawn) {
          _userIsExploring = false;
        }
      });
      if (!_initialLocationSet && mapboxMap != null) {
  _initialLocationSet = true;
  _isProgrammaticMove = true;
  mapboxMap?.flyTo(
    mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(
        position.longitude, position.latitude,
      )),
      zoom: 15.0, bearing: position.heading, pitch: 0.0,
    ),
    mapbox.MapAnimationOptions(duration: 1200, startDelay: 0),
  );
}

      if (_navigating && _routeCoordinates.isNotEmpty) {
        final snapped    = _snapToRoute(position.latitude, position.longitude);
        final snappedLng = snapped[0];
        final snappedLat = snapped[1];
        final idx        = _findClosestPointIndex(position.latitude, position.longitude);
        double bearing   = position.heading;
        if (idx < _routeCoordinates.length - 1) {
          bearing = _bearingBetween(
              _routeCoordinates[idx][1], _routeCoordinates[idx][0],
              _routeCoordinates[idx+1][1], _routeCoordinates[idx+1][0]);
        }
        _animateMarkerTo(snappedLat, snappedLng, bearing);
        _accumulateTripDistance(position);
        // Detectar desvío de ruta
        _checkRouteDeviation(position.latitude, position.longitude);
        _updateRemainingRoute(position.latitude, position.longitude);
        _updateTurnByTurn(position.latitude, position.longitude);
        mapboxMap?.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(snappedLng, snappedLat)),
            zoom: 17.0, bearing: bearing, pitch: 50.0,
          ),
          mapbox.MapAnimationOptions(duration: 900, startDelay: 0),
        );
      } else {
        _animateMarkerTo(position.latitude, position.longitude, position.heading);
        if (!_routeDrawn && !_showTapConfirm && !_userIsExploring) {
          _isProgrammaticMove = true;
          mapboxMap?.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(
                  position.longitude, position.latitude)),
              zoom: _calculateDynamicZoom(_currentSpeed),
              bearing: position.heading,
              pitch: 0.0,
            ),
            mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
          );
        }
      }
    });
  }

  // ── Gasolineras ───────────────────────────────────────
  Future<void> _fetchGasolineras(double lat, double lng) async {
    if (mapboxMap == null) return;
    const double radius = 8000;
    final query =
        '[out:json][timeout:40];\n'
        '(\n'
        '  node[amenity=fuel](around:$radius,$lat,$lng);\n'
        '  way[amenity=fuel](around:$radius,$lat,$lng);\n'
        ');\n'
        'out center;\n';
    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );
      if (response.statusCode != 200) return;
      final elements = json.decode(response.body)['elements'] as List;
      final features = elements.map((e) {
        final pLat = e['type'] == 'node'
            ? (e['lat'] as num).toDouble()
            : (e['center']?['lat'] as num?)?.toDouble() ?? 0.0;
        final pLng = e['type'] == 'node'
            ? (e['lon'] as num).toDouble()
            : (e['center']?['lon'] as num?)?.toDouble() ?? 0.0;
        if (pLat == 0.0 && pLng == 0.0) return null;
        return {
          'type': 'Feature',
          'geometry': {'type': 'Point', 'coordinates': [pLng, pLat]},
          'properties': {
            'name': (e['tags']?['name'] as String?)
                ?? (e['tags']?['brand'] as String?)
                ?? 'Gasolinera',
          },
        };
      }).whereType<Map>().toList();
      if (!mounted) return;
      await _updateGasolineraLayer(
        json.encode({'type': 'FeatureCollection', 'features': features}),
      );
    } catch (_) {}
  }

  Future<void> _updateGasolineraLayer(String geoJson) async {
    if (mapboxMap == null) return;
    try {
      final style = await mapboxMap!.style;
      try { await style.removeStyleLayer('gasolineras-layer');  } catch (_) {}
      try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}
      await style.addSource(mapbox.GeoJsonSource(
        id: 'gasolineras-source', data: geoJson,
      ));
      await style.addLayer(mapbox.SymbolLayer(
        id:               'gasolineras-layer',
        sourceId:         'gasolineras-source',
        iconImage:        'fuel',
        iconSize:         1.2,
        iconAllowOverlap: false,
        textField:        '{name}',
        textSize:         10.0,
        textOffset:       [0.0, 1.8],
        textAllowOverlap: false,
        textOptional:     true,
      ));
    } catch (_) {}
  }

  // ── Ruta ──────────────────────────────────────────────
  Future<void> _getRoute(double destLat, double destLng) async {
    if (_currentPosition == null) return;
    try {
      final response = await http.get(Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '${_currentPosition!.longitude},${_currentPosition!.latitude};$destLng,$destLat'
        '?geometries=geojson&steps=true&access_token=$_mapboxToken&language=es&overview=full&continue_straight=true&alternatives=true',
      ));
      if (response.statusCode == 200) {
        final data   = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isEmpty) return;
        // Guardar todas las rutas disponibles
        setState(() {
          _alternateRoutes = routes.map<Map<String, dynamic>>((r) => {
            'distance': '${((r['distance'] as num).toDouble()/1000).toStringAsFixed(1)} km',
            'duration': '${((r['duration'] as num).toDouble()/60).round()} min',
            'geometry': r['geometry'],
            'coords': (r['geometry']['coordinates'] as List)
                .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
                .toList(),
            'steps': (r['legs'][0]['steps'] as List)
                .map((s) => {
                      'instruction': (s['maneuver']['instruction'] as String?) ?? '',
                      'distance':    (s['distance'] as num).toDouble(),
                      'location':    s['maneuver']['location'] as List,
                    })
                .toList(),
          }).toList();
          _selectedRouteIndex = 0;
        });
        final route = routes[0];
        final geometry = route['geometry'];
        final coords   = (geometry['coordinates'] as List)
            .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()]).toList();
        setState(() {
          _routeDistance = '${((route['distance'] as num).toDouble()/1000).toStringAsFixed(1)} km';
          _routeDuration = '${((route['duration'] as num).toDouble()/60).round()} min';
          _routeDrawn       = true;
          _routeCoordinates = coords;
          _routeSteps = (route['legs'][0]['steps'] as List)
              .map((s) => {
                    'instruction': (s['maneuver']['instruction'] as String?) ?? '',
                    'distance':    (s['distance'] as num).toDouble(),
                    'location':    s['maneuver']['location'] as List,
                  })
              .toList();
          _currentStepIndex   = 0;
          _currentInstruction = _routeSteps.isNotEmpty
              ? _routeSteps[0]['instruction'] as String : '';
          _distanceToNextManeuver = _routeSteps.isNotEmpty
              ? _routeSteps[0]['distance'] as double : 0.0;
        });
        await _drawRouteOnMap(geometry);
        // Redibujar marcador encima de la ruta
        if (motoAnnotation != null && annotationManager != null) {
          await annotationManager!.delete(motoAnnotation!);
          motoAnnotation = null;
        }
        if (_currentPosition != null) {
          await _updateMotoMarker(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            _currentPosition!.heading,
          );
        }
        _fitRouteBounds(destLat, destLng);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ruta: $e'), backgroundColor: Colors.red),
      );
    }
  }
  Future<void> _drawRouteOnMap(Map<String, dynamic> geometry) async {
    final style = await mapboxMap!.style;
    // Limpiar rutas anteriores
    for (int i = 0; i < 3; i++) {
      try { await style.removeStyleLayer('route-layer-$i'); } catch (_) {}
      try { await style.removeStyleSource('route-source-$i'); } catch (_) {}
    }
    try { await style.removeStyleLayer('route-layer');  } catch (_) {}
    try { await style.removeStyleSource('route-source'); } catch (_) {}

    // Dibujar rutas alternas primero (gris)
    for (int i = 1; i < _alternateRoutes.length; i++) {
      await style.addSource(mapbox.GeoJsonSource(
        id: 'route-source-$i',
        data: json.encode({'type': 'Feature', 'geometry': _alternateRoutes[i]['geometry']}),
      ));
      await style.addLayer(mapbox.LineLayer(
        id: 'route-layer-$i', sourceId: 'route-source-$i',
        lineColor: 0xFF90A4AE, lineWidth: 5.0,
        lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
      ));
    }

    // Dibujar ruta principal (azul) encima
    await style.addSource(mapbox.GeoJsonSource(
      id: 'route-source-0',
      data: json.encode({'type': 'Feature', 'geometry': geometry}),
    ));
    await style.addLayer(mapbox.LineLayer(
      id: 'route-layer-0', sourceId: 'route-source-0',
      lineColor: 0xFF1976D2, lineWidth: 6.0,
      lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
    ));
  }

  void _fitRouteBounds(double destLat, double destLng) {
    if (_currentPosition == null) return;

    // Calcular distancia para ajustar zoom dinámicamente
    final dist = _distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude,
      destLat, destLng,
    );

    // Zoom según distancia total de la ruta
    double zoom;
    if (dist < 5000)        zoom = 13.0;
    else if (dist < 20000)  zoom = 11.0;
    else if (dist < 80000)  zoom = 9.0;
    else if (dist < 200000) zoom = 7.5;
    else                    zoom = 6.0;

    mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(
          (_currentPosition!.longitude + destLng) / 2,
          (_currentPosition!.latitude  + destLat) / 2,
        )),
        zoom: zoom, bearing: 0.0, pitch: 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 1800, startDelay: 0),
    );
  }

  // ── FIX 1: _tts.stop() movido FUERA de setState ───────
  Future<void> _cancelRoute() async {
    if (_navigating) await _finishAndSaveTrip();
    if (mapboxMap != null) {
      try {
        final style = await mapboxMap!.style;
        try { await style.removeStyleLayer('route-layer');  } catch (_) {}
        try { await style.removeStyleSource('route-source'); } catch (_) {}
      } catch (_) {}
    }
    if (destinationAnnotation != null && annotationManager != null) {
      await annotationManager!.delete(destinationAnnotation!);
      destinationAnnotation = null;
    }
    await _tts.stop();
    _lastSpokenInstruction = '';
    setState(() {
      _selectedPlace  = null; _routeDrawn  = false; _navigating = false;
      _showTapConfirm = false; _tappedLat  = null;  _tappedLng  = null;
      _routeDistance  = '';   _routeDuration = '';  _routeCoordinates = [];
    });
  }
  
  void _startNavigation() {
    setState(() => _navigating = true);
    _startTripTracking();
    if (_currentPosition != null) {
      mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _currentPosition!.longitude, _currentPosition!.latitude)),
          zoom: 17.0, bearing: _currentPosition!.heading, pitch: 50.0,
        ),
        mapbox.MapAnimationOptions(duration: 1500, startDelay: 0),
      );
    }
  }

  // ── Buscador UI ───────────────────────────────────────
  Widget _buildSearchModal() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Ciudad, colonia, calle...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    onChanged: _searchPlaces,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() {
                    _showSearch = false;
                    _searchResults = [];
                    _searchController.clear();
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_searchLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else if (_searchResults.isEmpty && _searchController.text.length >= 3)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin resultados', style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final place = _searchResults[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: Colors.blue),
                  title: Text(
                    place['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    place['full_name'] as String,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectSearchResult(place),
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

void _showTripRoute(TripRecord trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.destination,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _tripStat(Icons.straighten, '${trip.distanceKm} km', Colors.blue),
                  const SizedBox(width: 20),
                  _tripStat(Icons.timer_outlined, '${trip.durationMin} min', Colors.orange),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Preview ruta
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: trip.routeCoords.length >= 2
                    ? Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F0E8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CustomPaint(
                            painter: RoutePainter(trip.routeCoords),
                            size: Size.infinite,
                          ),
                        ),
                      )
                    : const Center(
                        child: Text('Sin datos de ruta',
                            style: TextStyle(color: Colors.grey)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ── Libro de viajes UI ────────────────────────────────
  Widget _buildTripBook() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('📒 Libro de viaje'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _trips.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('🏍️', style: TextStyle(fontSize: 52)),
                  SizedBox(height: 12),
                  Text('Aún no tienes viajes',
                      style: TextStyle(fontSize: 17, color: Colors.grey)),
                  SizedBox(height: 6),
                  Text(
                    'Completa una navegación para verlos aquí',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _trips.length,
              itemBuilder: (_, i) {
                final trip    = _trips[i];
                final dateStr =
                    '${trip.date.day.toString().padLeft(2, '0')}/'
                    '${trip.date.month.toString().padLeft(2, '0')}/'
                    '${trip.date.year}  '
                    '${trip.date.hour.toString().padLeft(2, '0')}:'
                    '${trip.date.minute.toString().padLeft(2, '0')}';
                return GestureDetector(
                  onTap: () => _showTripRoute(trip),
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.red, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trip.destination,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _tripStat(Icons.straighten, '${trip.distanceKm} km', Colors.blue),
                            const SizedBox(width: 20),
                            _tripStat(Icons.timer_outlined, '${trip.durationMin} min', Colors.orange),
                            const Spacer(),
                            Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
              },
            ),
    );
  }

  IconData _maneuverIcon(String instruction) {
    final i = instruction.toLowerCase();
    if (i.contains('izquierda')) return Icons.turn_left;
    if (i.contains('derecha'))   return Icons.turn_right;
    if (i.contains('gira'))      return Icons.turn_slight_right;
    if (i.contains('rotonda') || i.contains('redondel')) return Icons.roundabout_left;
    if (i.contains('destino') || i.contains('llegada'))  return Icons.flag;
    if (i.contains('continúa') || i.contains('sigue'))   return Icons.straight;
    return Icons.navigation;
  }
    
  Widget _tripStat(IconData icon, String label, Color color) {
      return Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
    }

  Widget _buildMapTab() {
    return Stack(
      children: [
        // ── Mapa ──────────────────────────────
        SizedBox.expand(
          child: mapbox.MapWidget(
            key: const ValueKey("mapWidget"),
            onMapCreated: _onMapCreated,
            styleUri: 'mapbox://styles/mapbox/streets-v12',
            onTapListener: _onMapTap,
            cameraOptions: mapbox.CameraOptions(zoom: 15.0, pitch: 0.0),
            onCameraChangeListener: (state) async {
              if (_isProgrammaticMove) {
                Future.delayed(const Duration(milliseconds: 1200), () {
                  if (mounted) setState(() => _isProgrammaticMove = false);
                });
              } else {
                if (!_userIsExploring) setState(() => _userIsExploring = true);
              }
            },
          ),
        ),

        // ── Botón búsqueda ────────────────────────
        if (!_navigating)
          Positioned(
            top: 50, right: 16,
            child: GestureDetector(
              onTap: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchResults = [];
                  _searchController.clear();
                }
              }),
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.search, color: Colors.blue, size: 24),
              ),
            ),
          ),

        // ── Modal búsqueda ────────────────────────
        if (_showSearch && !_navigating)
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildSearchModal(),
          ),

        // ── Botón recentrar ────────────────────
        if (_userIsExploring && !_navigating)
          Positioned(
            bottom: 110, right: 16,
            child: GestureDetector(
              onTap: () {
                setState(() => _userIsExploring = false);
                if (_currentPosition != null) {
                  _isProgrammaticMove = true;
                  mapboxMap?.flyTo(
                    mapbox.CameraOptions(
                      center: mapbox.Point(coordinates: mapbox.Position(
                        _currentPosition!.longitude, _currentPosition!.latitude,
                      )),
                      zoom: _calculateDynamicZoom(_currentSpeed),
                      bearing: _currentPosition!.heading,
                      pitch: 0.0,
                    ),
                    mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
                  );
                  _updateMotoMarker(
                   _currentPosition!.latitude,
                   _currentPosition!.longitude,
                   _currentPosition!.heading,
                 );
               }
             },
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.my_location, color: Colors.white, size: 22),
              ),
            ),
          ),

// ── Botón avatar ───────────────────────
        if (!_navigating && !_showSearch)
          Positioned(
            top: 106, right: 16,
            child: GestureDetector(
              onTap: _pickUserAvatar,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                  image: _userAvatarImage != null
                      ? DecorationImage(
                          image: MemoryImage(_userAvatarImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.white,
                ),
                child: _userAvatarImage == null
                    ? const Icon(Icons.person_add, color: Colors.blue, size: 22)
                    : null,
              ),
            ),
          ),

// ── Botón gasolineras ──────────────────
        if (!_navigating)
          Positioned(
            bottom: 230, right: 16,
            child: GestureDetector(
              onTap: () async {
                if (_currentPosition == null) return;
                if (_gasolinerasVisible) {
                  // Ocultar — remover layer
                  try {
                    final style = await mapboxMap!.style;
                    try { await style.removeStyleLayer('gasolineras-layer');  } catch (_) {}
                    try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}
                  } catch (_) {}
                  setState(() => _gasolinerasVisible = false);
                } else {
                  // Mostrar
                  await _fetchGasolineras(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  );
                  setState(() => _gasolinerasVisible = true);
                }
              },
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: _gasolinerasVisible ? Colors.orange[700] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(
                  Icons.local_gas_station,
                  color: _gasolinerasVisible ? Colors.white : Colors.orange[700],
                  size: 24,
                ),
              ),
            ),
          ),
        
// ── Botón satélite ─────────────────────
        if (!_navigating)
          Positioned(
            bottom: 170, right: 16,
            child: GestureDetector(
              onTap: () async {
                setState(() => _isSatellite = !_isSatellite);
                await mapboxMap?.loadStyleURI(
                  _isSatellite
                      ? 'mapbox://styles/mapbox/satellite-streets-v12'
                      : 'mapbox://styles/mapbox/streets-v12',
                );
                if (!_isSatellite) await _applyCustomRoadStyle();
                // Restaurar gasolineras tras cambio de estilo
                await Future.delayed(const Duration(milliseconds: 1500));
                if (_currentPosition != null && mounted) {
                  _fetchGasolineras(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  );
                }
              },   
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: _isSatellite ? Colors.blue[700] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(Icons.satellite_alt,
                    color: _isSatellite ? Colors.white : Colors.blue, size: 24),
              ),
            ),
          ),
        
        // ── Confirmar tap ──────────────────────
        if (_showTapConfirm && !_navigating)
          Positioned(
            bottom: 30, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(
                    color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  const Text('¿Ir a este lugar?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${_tappedLat?.toStringAsFixed(5)}  '
                    'Lng: ${_tappedLng?.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _cancelTap,
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _confirmTappedDestination,
                          icon: const Icon(Icons.directions, color: Colors.white),
                          label: const Text('Trazar ruta',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

// ── Selector rutas alternas ────────────
                if (_routeDrawn && !_navigating && _alternateRoutes.length > 1)
                  Positioned(
                    bottom: 185, left: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(
                            color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(_alternateRoutes.length, (i) {
                          final r = _alternateRoutes[i];
                          final selected = i == _selectedRouteIndex;
                          return GestureDetector(
                            onTap: () async {
                              setState(() {
                                _selectedRouteIndex     = i;
                                _routeDistance          = r['distance'];
                                _routeDuration          = r['duration'];
                                _routeCoordinates       = List<List<double>>.from(r['coords']);
                                _routeSteps             = List<Map<String,dynamic>>.from(r['steps']);
                                _currentStepIndex       = 0;
                                _currentInstruction     = _routeSteps.isNotEmpty
                                    ? _routeSteps[0]['instruction'] as String : '';
                                _distanceToNextManeuver = _routeSteps.isNotEmpty
                                    ? _routeSteps[0]['distance'] as double : 0.0;
                              });
                              // Resaltar ruta seleccionada
                              try {
                                final style = await mapboxMap!.style;
                                for (int j = 0; j < _alternateRoutes.length; j++) {
                                  await style.setStyleLayerProperty(
                                    'route-layer-$j', 'line-color',
                                    json.encode(j == i ? '#1976D2' : '#90A4AE'),
                                  );
                                  await style.setStyleLayerProperty(
                                    'route-layer-$j', 'line-width',
                                    json.encode(j == i ? 6.0 : 4.0),
                                  );
                                }
                              } catch (_) {}
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected ? Colors.blue[700] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Ruta ${i + 1}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: selected ? Colors.white : Colors.grey,
                                          fontWeight: FontWeight.w600)),
                                  Text(r['distance'],
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: selected ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold)),
                                  Text(r['duration'],
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: selected ? Colors.white70 : Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
        
        // ── Panel ruta ─────────────────────────
        if (_routeDrawn && !_navigating && !_showTapConfirm)
          Positioned(
            bottom: 30, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(
                    color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedPlace?['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.directions_bike, color: Colors.blue, size: 18),
                      const SizedBox(width: 6),
                      Text('$_routeDistance  •  $_routeDuration',
                          style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _cancelRoute,
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _startNavigation,
                          icon: const Icon(Icons.navigation, color: Colors.white),
                          label: const Text('¡Ir!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // ── Panel navegando ────────────────────
        if (_navigating)
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    children: [
                      Text(
                        '${_currentSpeed.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                      ),
                      const Text('km/h', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _cancelRoute,
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text('Salir', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

// ── Banner recalculando ─────────────────
                if (_navigating && _isRecalculating)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                      color: Colors.orange[700],
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Recalculando ruta...',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
        
        // ── Banner instrucción turn-by-turn ─────────────────
        if (_navigating && _currentInstruction.isNotEmpty)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(_maneuverIcon(_currentInstruction), color: Colors.white, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentInstruction,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _distanceToNextManeuver >= 1000
                              ? '${(_distanceToNextManeuver / 1000).toStringAsFixed(1)} km'
                              : '${_distanceToNextManeuver.toStringAsFixed(0)} m',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Velocímetro modo libre ─────────────
        if (!_navigating && !_routeDrawn && !_showTapConfirm)
          Positioned(
            bottom: 30, left: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  Text(
                    '${_currentSpeed.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                  const Text('km/h', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── BUILD ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _navigating
          ? null
          : BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (i) {
                setState(() => _currentTabIndex = i);
                if (i == 0 && _currentPosition != null) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _isProgrammaticMove = true;
                    mapboxMap?.flyTo(
                      mapbox.CameraOptions(
                        center: mapbox.Point(coordinates: mapbox.Position(
                          _currentPosition!.longitude,
                          _currentPosition!.latitude,
                        )),
                        zoom: _calculateDynamicZoom(_currentSpeed),
                        bearing: _currentPosition!.heading,
                        pitch: 0.0,
                      ),
                      mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
                    );
                    _updateMotoMarker(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                      _currentPosition!.heading,
                    );
                  });
                }
              },
              backgroundColor: Colors.black87,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined),
                  activeIcon: Icon(Icons.map),
                  label: 'Mapa',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book_outlined),
                  activeIcon: Icon(Icons.menu_book),
                  label: 'Libro de viaje',
                ),
              ],
            ),
      // ── FIX 2: cierre correcto de IndexedStack y Scaffold ──
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildMapTab(),   // índice 0 — Mapa
          _buildTripBook(), // índice 1 — Libro de viaje
        ],
      ),
    );
  }
}
