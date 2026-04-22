import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:math';
import 'data/models/trip_record.dart';
import 'presentation/widgets/route_painter.dart';
import 'dart:async';
import 'data/sources/mapbox_api.dart';
import 'data/sources/overpass_api.dart';
import 'presentation/widgets/search_modal.dart';
import 'presentation/widgets/trip_book.dart';
import 'data/sources/prefs_source.dart';
import 'core/utils/image_utils.dart';
import 'core/utils/geo_utils.dart';
import 'core/services/tts_service.dart';
import 'core/services/map_service.dart';
import 'dart:convert';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  mapbox.MapboxOptions.setAccessToken(_mapboxToken);
  runApp(const MaterialApp(home: MotoGPSApp()));
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
  StreamSubscription<Position>? _locationSubscription;
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
  final TtsService _tts = TtsService();
  final MapService _mapService = const MapService();
  
  // ── Turn-by-turn ──────────────────────────────────────
  List<Map<String, dynamic>> _routeSteps = [];
  String _currentInstruction = '';
  double _distanceToNextManeuver = 0.0;
  int _currentStepIndex = 0;

  // ── Buscador ──────────────────────────────────────────
  bool _showSearch = false;
  late final MapboxApi _mapboxApi = MapboxApi(_mapboxToken);
  late final OverpassApi _overpassApi = const OverpassApi();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  int _searchToken = 0;
  final TextEditingController _searchController = TextEditingController();
  
  bool _showTapConfirm = false;
  double? _tappedLat;
  double? _tappedLng;

  List<List<double>> _routeCoordinates = [];

  bool _userIsExploring    = false;
  bool _isSatellite        = false;
  bool _gasolinerasVisible = false;
  bool _gasolinerasLoading = false;
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
    _locationSubscription?.cancel();
    _markerAnimController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Imágenes ──────────────────────────────────────────
  Future<void> _pickUserAvatar() async {
    final bytes = await _imageUtils.pickImageFromGallery();
    if (bytes == null) return;
    final circular = await _imageUtils.makeCircularImage(bytes, 70);
    await _prefsSource.saveAvatar(circular);
    setState(() => _userAvatarImage = circular);
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
    final bytes = await _prefsSource.loadAvatar();
    if (bytes != null && mounted) setState(() => _userAvatarImage = bytes);
  }
  
  Future<void> _loadImages() async {
    final ByteData pinData   = await rootBundle.load('assets/moto_pin.png');
    final Uint8List pinResized = await _imageUtils.resizeImage(
        pinData.buffer.asUint8List(), 120);
    setState(() => pinImage = pinResized);
  }

  // ── Libro de viajes ───────────────────────────────────
  Future<void> _loadTrips() async {
    final trips = await _prefsSource.loadTrips();
    if (mounted) setState(() => _trips = trips);
  }
  
  Future<void> _initTts() async {
    await _tts.init();
  }

  final PrefsSource _prefsSource = PrefsSource();
  final ImageUtils _imageUtils = const ImageUtils();
  final GeoUtils _geo = const GeoUtils();

Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    final token = ++_searchToken;
    setState(() => _searchLoading = true);
    try {
      final results = await _mapboxApi.searchPlaces(
        query,
        proximityLat: _currentPosition?.latitude,
        proximityLng: _currentPosition?.longitude,
      );
      if (token != _searchToken) return;
      setState(() => _searchResults = results);
    } catch (_) {}
    if (token == _searchToken) setState(() => _searchLoading = false);
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
    await _prefsSource.saveTrips(_trips);
  }

  void _startTripTracking() {
    _tripStartTime           = DateTime.now();
    _tripAccumulatedDistance = 0.0;
    _lastTripPosition        = _currentPosition;
  }

  void _accumulateTripDistance(Position position) {
    if (_lastTripPosition != null) {
      _tripAccumulatedDistance += _geo.distanceBetween(
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
    await _mapService.applyCustomRoadStyle(mapboxMap!);
  }

  Future<void> _updateRemainingRoute(double lat, double lng) async {
    if (!_navigating || _routeCoordinates.isEmpty || mapboxMap == null) return;
    final idx = _geo.findClosestPointIndex(lat, lng, _routeCoordinates);
    if (idx >= _routeCoordinates.length - 2) {
      if (!_navigating) return;
      await _finishAndSaveTrip();
      await _cancelRoute();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🏁 ¡Has llegado a tu destino!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final remaining = _routeCoordinates.sublist(idx);
    await _mapService.updateRemainingRoute(mapboxMap!, remaining);
  }

// REEMPLAZA todo el método:
void _checkRouteDeviation(double lat, double lng) {
    if (!_navigating || _routeCoordinates.isEmpty || _isRecalculating) return;

    if (_routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length) {
      final loc     = _routeSteps[_currentStepIndex]['location'] as List;
      final stepLat = (loc[1] as num).toDouble();
      final stepLng = (loc[0] as num).toDouble();
      if (_geo.distanceBetween(lat, lng, stepLat, stepLng) < 120) return;
    }

    if (_lastRecalcTime != null &&
        DateTime.now().difference(_lastRecalcTime!).inSeconds < 20) return;

    final minDist = _geo.distanceToRoute(lat, lng, _routeCoordinates);

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
    final distToManeuver = _geo.distanceBetween(lat, lng, stepLat, stepLng);

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
      placeName = await _mapboxApi.reverseGeocode(_tappedLat!, _tappedLng!);
    } catch (_) {}
    setState(() {
      _selectedPlace = {'name': placeName, 'lat': _tappedLat, 'lng': _tappedLng};
      _showTapConfirm = false;
    });
    await _getRoute(_tappedLat!, _tappedLng!);
  }

  Future<void> _cancelTap() async {
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
  try {
    if (motoAnnotation != null) {
      motoAnnotation!.geometry = mapbox.Point(
          coordinates: mapbox.Position(lng, lat));
      motoAnnotation!.iconRotate = _userAvatarImage != null ? 0.0 : bearing;
      await annotationManager!.update(motoAnnotation!);
    } else {
      motoAnnotation = await annotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          image: markerImage,
          iconSize: 1.2,
          iconAnchor: mapbox.IconAnchor.CENTER,
          iconRotate: _userAvatarImage != null ? 0.0 : bearing,
        ),
      );
    }
  } catch (_) {
    // Si el update falla (anotación inválida), forzar recreación
    motoAnnotation = null;
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

    if (_lastAnimatedLat == null || _lastAnimatedLng == null) {
      _lastAnimatedLat = targetLat;
      _lastAnimatedLng = targetLng;
      _updateMotoMarker(targetLat, targetLng, bearing);
      return;
    }
    final dist = _geo.distanceBetween(
      _lastAnimatedLat!, _lastAnimatedLng!, targetLat, targetLng);
    if (dist < 0.5) return;
    if (!mounted) return;
    _markerAnimController?.stop();
    _markerAnimController?.dispose();
    _markerAnimController = null;
    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    final animLat = Tween<double>(begin: fromLat, end: targetLat)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));
    final animLng = Tween<double>(begin: fromLng, end: targetLng)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));

    _markerAnimController!.addListener(() {
      if (!mounted) return;
      final double lat = animLat.value;
      final double lng = animLng.value;
      _updateMotoMarker(lat, lng, bearing);   // ← fire-and-forget, sin guard
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
    _lastAnimatedLat = position.latitude;
    _lastAnimatedLng = position.longitude;
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
     _locationSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,                                    // ← sin filtro de distancia
        intervalDuration: const Duration(milliseconds: 800),  // ← más frecuente
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'MotoGPS activo',
          notificationTitle: 'Navegación en curso',
          enableWakeLock: true,
        ),
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _currentSpeed = (position.speed < 0 ? 0 : position.speed) * 3.6;
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
        final snapped    = _geo.snapToRoute(position.latitude, position.longitude, _routeCoordinates);
        final snappedLng = snapped[0];
        final snappedLat = snapped[1];
        final idx        = _geo.findClosestPointIndex(position.latitude, position.longitude, _routeCoordinates);
        double bearing   = position.heading;
        if (idx < _routeCoordinates.length - 1) {
          bearing = _geo.bearingBetween(
              _routeCoordinates[idx][1], _routeCoordinates[idx][0],
              _routeCoordinates[idx+1][1], _routeCoordinates[idx+1][0]);
        }
        _animateMarkerTo(snappedLat, snappedLng, bearing);
        _accumulateTripDistance(position);
        // Detectar desvío de ruta
        _checkRouteDeviation(position.latitude, position.longitude);
        _updateRemainingRoute(position.latitude, position.longitude);
        _updateTurnByTurn(position.latitude, position.longitude);
          _isProgrammaticMove = true;
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
              zoom: _geo.calculateDynamicZoom(_currentSpeed),
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
    setState(() => _gasolinerasLoading = true);
    try {
      final geoJson = await _overpassApi.fetchGasolineras(lat, lng);
      if (geoJson != null && mounted) {
        await _updateGasolineraLayer(geoJson);
      }
    } catch (_) {}
    if (mounted) setState(() => _gasolinerasLoading = false);
  }

  Future<void> _updateGasolineraLayer(String geoJson) async {
    if (mapboxMap == null) return;
    await _mapService.updateGasolineraLayer(mapboxMap!, geoJson);
  }

  // ── Ruta ──────────────────────────────────────────────
  Future<void> _getRoute(double destLat, double destLng) async {
    if (_currentPosition == null) return;
    try {
      final data = await _mapboxApi.getRoute(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
      );
      if (data != null) {
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
          _lastAnimatedLat = _currentPosition!.latitude;
          _lastAnimatedLng = _currentPosition!.longitude;
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
    if (mapboxMap == null) return;
    await _mapService.drawRouteOnMap(mapboxMap!, geometry, _alternateRoutes);
  }

  void _fitRouteBounds(double destLat, double destLng) {
    if (_currentPosition == null) return;

    // Calcular distancia para ajustar zoom dinámicamente
    final dist = _geo.distanceBetween(
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
    if (mapboxMap != null) await _mapService.clearRouteLayers(mapboxMap!);
    if (destinationAnnotation != null && annotationManager != null) {
      await annotationManager!.delete(destinationAnnotation!);
      destinationAnnotation = null;
    }
     await _tts.stop();
    setState(() {
      _selectedPlace      = null; _routeDrawn      = false; _navigating = false;
      _showTapConfirm     = false; _tappedLat      = null;  _tappedLng  = null;
      _routeDistance      = '';   _routeDuration   = '';    _routeCoordinates = [];
      _alternateRoutes    = [];   _selectedRouteIndex = 0;  // ← limpiar rutas alternas
      _routeSteps         = [];   _currentInstruction = '';
      _currentStepIndex   = 0;    _distanceToNextManeuver = 0.0;
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
    return SearchModal(
      controller: _searchController,
      isLoading: _searchLoading,
      results: _searchResults,
      onChanged: _searchPlaces,
      onClose: () => setState(() {
        _showSearch = false;
        _searchResults = [];
        _searchController.clear();
      }),
      onSelect: _selectSearchResult,
    );
  }
  
  // ── Libro de viajes UI ────────────────────────────────
  Widget _buildTripBook() {
    return TripBook(trips: _trips);
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
                      zoom: _geo.calculateDynamicZoom(_currentSpeed),
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
        // DESPUÉS
if (!_navigating)
  Positioned(
    bottom: 230, right: 16,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,          // ← bloquea tap al mapa
      onTap: () async {
        if (_currentPosition == null) return;
        if (_gasolinerasLoading) return;         // ← evita doble toque durante carga
        if (_gasolinerasVisible) {
          setState(() => _gasolinerasVisible = false);  // ← UI optimista inmediata
          try {
            final style = await mapboxMap!.style;
            try { await style.removeStyleLayer('gasolineras-layer');  } catch (_) {}
            try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}
          } catch (_) {}
        } else {
          setState(() => _gasolinerasVisible = true);   // ← UI optimista inmediata
          await _fetchGasolineras(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
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
        child: _gasolinerasLoading                  // ← indicador mientras carga
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.orange[700],
                ),
              )
            : Icon(
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
                // Restaurar capas tras cambio de estilo
                await Future.delayed(const Duration(milliseconds: 1500));
                if (_routeDrawn && _routeCoordinates.isNotEmpty && mounted) {
                  final geometry = {
                    'type': 'LineString',
                    'coordinates': _routeCoordinates,
                  };
                  await _drawRouteOnMap({'type': 'LineString', 'coordinates': _routeCoordinates});
                }
                if (_currentPosition != null && mounted && _gasolinerasVisible) {
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
                            }
                              // Resaltar ruta seleccionada
                              try {
                                if (mapboxMap != null) {
                                await _mapService.highlightRoute(
                                  mapboxMap!, i, _alternateRoutes.length);
                              }
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
                        zoom: _geo.calculateDynamicZoom(_currentSpeed),
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
