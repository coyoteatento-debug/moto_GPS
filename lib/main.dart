import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'dart:typed_data';
import 'dart:math';
import 'data/models/trip_record.dart';
import 'presentation/widgets/route_painter.dart';
import 'dart:async';
import 'data/sources/mapbox_api.dart';
import 'data/sources/overpass_api.dart';
import 'presentation/widgets/search_modal.dart';
import 'presentation/widgets/trip_book.dart';
import 'presentation/widgets/map_tab.dart';
import 'data/sources/prefs_source.dart';
import 'core/utils/image_utils.dart';
import 'core/utils/geo_utils.dart';
import 'core/services/tts_service.dart';
import 'core/services/map_service.dart';
import 'core/services/gps_service.dart';
import 'core/services/background_service.dart';
import 'core/services/speed_limit_service.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'core/services/smooth_location_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/services/trip_service.dart';
import 'core/services/navigation_service.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/state/map_notifier.dart';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(_mapboxToken.isNotEmpty, 'MAPBOX_TOKEN no configurado. Usa --dart-define=MAPBOX_TOKEN=tu_token');
  mapbox.MapboxOptions.setAccessToken(_mapboxToken);
  runApp(const ProviderScope(
    child: MaterialApp(home: MotoGPSApp()),
  ));
}

class MotoGPSApp extends ConsumerStatefulWidget {
  const MotoGPSApp({super.key});
  @override
  ConsumerState<MotoGPSApp> createState() => _MotoGPSAppState();
}

class _MotoGPSAppState extends ConsumerState<MotoGPSApp> 
    with TickerProviderStateMixin, WidgetsBindingObserver {

  MapNotifier get _n => ref.read(mapProvider.notifier);
  MapState    get _s => ref.read(mapProvider);
  mapbox.MapboxMap? mapboxMap;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? motoAnnotation;
  mapbox.PointAnnotation? destinationAnnotation;
  StreamSubscription<Position>? _locationSubscription;

  final TtsService _tts = TtsService();
  final MapService _mapService = MapService();
  final GpsService _gpsService = GpsService();
  final BackgroundService _bgService = BackgroundService();
  final SpeedLimitService _speedLimitService = SpeedLimitService();
  final SmoothLocationService _smoother = SmoothLocationService();
  StreamSubscription<SmoothPosition>? _smoothSub;
  Timer? _nightModeTimer;
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable  = false;
  bool _isListening      = false;
  late final TripService _tripService = TripService(_prefsSource);
  late final NavigationService _navService =
      NavigationService(MapboxApi(_mapboxToken), const GeoUtils());

  // ── Buscador ──────────────────────────────────────────
  late final MapboxApi _mapboxApi = MapboxApi(_mapboxToken);
  late final OverpassApi _overpassApi = const OverpassApi();
  int _searchToken = 0;
  final TextEditingController _searchController = TextEditingController();

  int _deviationCount = 0;
  DateTime? _lastRecalcTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _smoother.start(this);
    _startSmoothMarker();
    _loadImages();
    _startNightModeTimer();
    _requestPermissions();
    _loadTrips();
    _initTts();
    _loadUserAvatar();
    _initSpeech();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _smoothSub?.cancel();
    _smoother.stop();
    _nightModeTimer?.cancel();
    WakelockPlus.disable();
    _searchController.dispose();
    super.dispose();
  }

  // ── Imágenes ──────────────────────────────────────────
  Future<void> _pickUserAvatar() async {
    final bytes = await _imageUtils.pickImageFromGallery();
    if (bytes == null) return;
    final circular = await _imageUtils.makeCircularImage(bytes, 70);
    await _prefsSource.saveAvatar(circular);
    _n.setUserAvatar(circular);
    if (motoAnnotation != null && annotationManager != null) {
      await _mapService.deleteAnnotation(
          annotationManager!, motoAnnotation!);
      motoAnnotation = null;
    }
    if (_s.currentPosition != null) {
      _smoother.updatePosition(
        lat:     _s.currentPosition!.latitude,
        lng:     _s.currentPosition!.longitude,
        heading: _s.currentPosition!.heading,
        speedMs: 0,
      );
    }
  }

  Future<void> _loadUserAvatar() async {
    final bytes = await _prefsSource.loadAvatar();
    if (bytes != null && mounted) _n.setUserAvatar(bytes);
  }
  
  Future<void> _loadImages() async {
    final ByteData pinData   = await rootBundle.load('assets/moto_pin.png');
    final Uint8List pinResized = await _imageUtils.resizeImage(
        pinData.buffer.asUint8List(), 120);
    _n.setPinImage(pinResized);
  }

  // ── Libro de viajes ───────────────────────────────────
  Future<void> _loadTrips() async {
    final trips = await _prefsSource.loadTrips();
    if (mounted) _n.setTrips(trips);
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

  // ── Reconocimiento de voz ─────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
  }

  Future<void> _startVoiceSearch() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconocimiento de voz no disponible'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    // Abrir el modal de búsqueda si no está abierto
    if (!_s.showSearch) {
      _n.update((st) => st.copyWith(showSearch: true));
    }

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            _searchController.text = text;
            _searchPlaces(text);
          }
          setState(() => _isListening = false);
        }
      },
      localeId:          'es-MX',
      listenFor:         const Duration(seconds: 10),
      pauseFor:          const Duration(seconds: 3),
      partialResults:    true,
      cancelOnError:     true,
      listenMode:        ListenMode.confirmation,
    );
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      _n.setSearchResults([]);
      return;
    }
    final token = ++_searchToken;
    _n.setSearchLoading(true);
    try {
      final results = await _mapboxApi.searchPlaces(
        query,
        proximityLat: _s.currentPosition?.latitude,
        proximityLng: _s.currentPosition?.longitude,
      );
      if (token != _searchToken) return;
      _n.setSearchResults(results);
    } catch (_) {}
    if (token == _searchToken) _n.setSearchLoading(false);
  }

  Future<void> _selectSearchResult(Map<String, dynamic> place) async {
    final lat = place['lat'] as double;
    final lng = place['lng'] as double;
    _n.update((s) => s.copyWith(
        showSearch:     false,
        searchResults:  const [],
        selectedPlace:  place,
        showTapConfirm: false,
      ));
      _searchController.clear();
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

  // ── Permisos ──────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final granted = await _requestLocationPermissions();
    if (granted) {
      await _getInitialPosition();
      _startLocationTracking();
    } else {
      // Esperar y reintentar por si el usuario tarda en decidir
      await Future.delayed(const Duration(seconds: 2));
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await _getInitialPosition();
        _startLocationTracking();
      }
    }
  }

  Future<bool> _requestLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
  }

  // ── Mapa ──────────────────────────────────────────────
  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    mapboxMap = map;
    annotationManager = await map.annotations.createPointAnnotationManager();
    await Future.delayed(const Duration(milliseconds: 600));
    await _applyNightOrDayStyle();
    await _applyCustomRoadStyle();
  // Centrar en ubicación actual si ya se obtuvo
  if (_s.currentPosition != null) {
  _n.setIsProgrammaticMove(true);
  mapboxMap?.flyTo(
    mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(
        _s.currentPosition!.longitude, _s.currentPosition!.latitude,
      )),
      zoom: 15.0, bearing: _s.currentPosition!.heading, pitch: 0.0,
    ),
    mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
  );
 _updateMotoMarker(
    _s.currentPosition!.latitude,
    _s.currentPosition!.longitude,
    _s.currentPosition!.heading,
  );
 }
}   

// ── Modo nocturno ─────────────────────────────────────
  bool _isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 6;  // 7pm a 6am = noche
  }

void _startNightModeTimer() {
    // Verificar inmediatamente al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyNightOrDayStyle();
    });
    // Verificar cada 5 minutos
    _nightModeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _applyNightOrDayStyle(),
    );
  }
  
  Future<void> _applyNightOrDayStyle() async {
    if (mapboxMap == null) return;
    if (_s.nightModeManual) return;  // usuario fijó manualmente, no tocar

    final isNight = _isNightTime();
    if (_s.isNightMode == isNight) return;  // ya está en el modo correcto

    _n.setNightMode(isNight);
    await mapboxMap?.loadStyleURI(
      isNight
          ? 'mapbox://styles/mapbox/navigation-night-v1'
          : 'mapbox://styles/mapbox/streets-v12',
    );
    if (!isNight) await _applyCustomRoadStyle();
  }
  
  // ── Estilo de carreteras tipo Riser ───────────────────
  Future<void> _applyCustomRoadStyle() async {
    if (mapboxMap == null) return;
    await _mapService.applyCustomRoadStyle(mapboxMap!);
  }

  Future<void> _updateRemainingRoute(double lat, double lng) async {
    if (!_s.navigating || _s.routeCoordinates.isEmpty || mapboxMap == null) return;

    if (_navService.hasArrived(lat, lng, _s.routeCoordinates)) {
      if (!_s.navigating) return;
      final record = await _tripService.finishAndSave(
        destination:   _s.selectedPlace?['name'] ?? 'Destino',
        routeCoords:   _s.routeCoordinates,
        existingTrips: _s.trips,
      );
      if (record != null && mounted) {
        _n.setTrips([record, ..._s.trips]);
      }
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

    final idx       = _geo.findClosestPointIndex(lat, lng, _s.routeCoordinates);
    final remaining = _s.routeCoordinates.sublist(idx);
    await _mapService.updateRemainingRoute(mapboxMap!, remaining);
  }

// ── Límite de velocidad ───────────────────────────────
  DateTime? _lastSpeedLimitCheck;

  Future<void> _updateSpeedLimit(double lat, double lng) async {
    // Solo consultar cada 30 segundos para no saturar la API
    if (_lastSpeedLimitCheck != null &&
        DateTime.now().difference(_lastSpeedLimitCheck!).inSeconds < 30) return;
    _lastSpeedLimitCheck = DateTime.now();

    final limit = await _speedLimitService.getSpeedLimit(lat, lng);
    if (mounted) _n.setSpeedLimit(limit);

    // Alerta por voz si excede el límite
    final status = SpeedStatus.evaluate(_s.currentSpeed, limit);
    if (status.level == SpeedAlertLevel.danger) {
      _speak('Exceso de velocidad');
    }
  }
  
void _checkRouteDeviation(double lat, double lng) {
    if (!_s.navigating || _s.routeCoordinates.isEmpty || _s.isRecalculating) return;

    if (_s.routeSteps.isNotEmpty && _s.currentStepIndex < _s.routeSteps.length) {
      final loc     = _s.routeSteps[_s.currentStepIndex]['location'] as List;
      final stepLat = (loc[1] as num).toDouble();
      final stepLng = (loc[0] as num).toDouble();
      if (_geo.distanceBetween(lat, lng, stepLat, stepLng) < 120) return;
    }

    if (_lastRecalcTime != null &&
        DateTime.now().difference(_lastRecalcTime!).inSeconds < 20) return;

    if (_navService.isDeviated(lat, lng, _s.routeCoordinates)) {
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
    if (_s.selectedPlace == null) return;
    _n.setIsRecalculating(true);
    _speak('Recalculando ruta');

    final destLat = (_s.selectedPlace!['lat'] as num).toDouble();
    final destLng = (_s.selectedPlace!['lng'] as num).toDouble();

    await _getRoute(destLat, destLng);
    _n.setIsRecalculating(false);
  }
  
  void _updateTurnByTurn(double lat, double lng) {
    final update = _navService.updateTurn(
        lat, lng, _s.routeSteps, _s.currentStepIndex);
    if (update == null) return;
    _n.updateTurn(
      distance:    update.distanceToManeuver,
      stepIndex:   update.nextStepIndex,
      instruction: update.nextInstruction,
    );
    if (update.announceText != null) _speak(update.announceText!);
  }

  // ── Tap mapa ──────────────────────────────────────────
  void _onMapTap(mapbox.MapContentGestureContext context) {
    if (_s.navigating) return;
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();
    _n.setTappedLocation(lat, lng);
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
    if (_s.tappedLat == null || _s.tappedLng == null) return;
    String placeName = 'Destino seleccionado';
    try {
      placeName = await _mapboxApi.reverseGeocode(_s.tappedLat!, _s.tappedLng!);
    } catch (_) {}
    _n.update((s) => s.copyWith(
      selectedPlace:  {'name': placeName, 'lat': s.tappedLat, 'lng': s.tappedLng},
      showTapConfirm: false,
    ));
    await _getRoute(_s.tappedLat!, _s.tappedLng!);
  }

  Future<void> _cancelTap() async {
    if (destinationAnnotation != null && annotationManager != null) {
      await _mapService.deleteAnnotation(
          annotationManager!, destinationAnnotation!);
      destinationAnnotation = null;
    }
    _n.clearTap();
  }

  // ── Marcadores ────────────────────────────────────────
  Future<void> _updateMotoMarker(
      double lat, double lng, double bearing) async {
    final markerImage = _s.userAvatarImage ?? _s.pinImage;
    if (annotationManager == null || markerImage == null) return;
    motoAnnotation = await _mapService.updateMotoMarker(
      manager:     annotationManager!,
      current:     motoAnnotation,
      lat:         lat,
      lng:         lng,
      bearing:     bearing,
      markerImage: markerImage,
      isAvatar:    _s.userAvatarImage != null,
    );
  }

  Future<void> _addDestinationMarker(double lat, double lng) async {
    if (annotationManager == null || _s.pinImage == null) return;
    destinationAnnotation = await _mapService.updateDestinationMarker(
      manager: annotationManager!,
      current: destinationAnnotation,
      lat:     lat,
      lng:     lng,
      pinImage: _s.pinImage!,
    );
  }

  Future<void> _getInitialPosition() async {
    final position = await _gpsService.getInitialPosition();
    if (position == null || !mounted) return;
  
      _n.update((s) => s.copyWith(
        currentPosition: position,
        currentSpeed:    position.speed * 3.6,
      ));

    _n.setInitialLocationSet(true);
    _smoother.updatePosition(
      lat:     position.latitude,
      lng:     position.longitude,
      heading: position.heading,
      speedMs: position.speed < 0 ? 0 : position.speed,
    );
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
  }

// ── Marcador suavizado a 60fps ────────────────────────
  DateTime _lastMarkerUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  void _startSmoothMarker() {
    _smoothSub = _smoother.positionStream.listen((SmoothPosition pos) {
      if (!mounted) return;

      // Throttle a 15fps — actualizar máximo cada 66ms
      final now = DateTime.now();
      if (now.difference(_lastMarkerUpdate).inMilliseconds < 66) return;
      _lastMarkerUpdate = now;

      _updateMotoMarker(pos.latitude, pos.longitude, pos.heading);
    });
  }
  
  // ── GPS Tracking ──────────────────────────────────────
  Future<void> _startLocationTracking() async {
    await _gpsService.startTracking();
    _locationSubscription = _gpsService.positionStream.listen((Position position) {
      if (!mounted) return;
      final speed = (position.speed < 0 ? 0 : position.speed) * 3.6;
      _n.update((s) => s.copyWith(
        currentSpeed:    speed,
        currentPosition: position,
        userIsExploring: speed > 2 && !s.navigating && !s.routeDrawn
            ? false : s.userIsExploring,
      ));
      if (!_s.navigating) {
        _smoother.updatePosition(
          lat:     position.latitude,
          lng:     position.longitude,
          heading: position.heading,
          speedMs: position.speed < 0 ? 0 : position.speed,
        );
      }
      // Consultar límite de velocidad en background
      _updateSpeedLimit(position.latitude, position.longitude);
      if (!_s.initialLocationSet && mapboxMap != null) {
  _n.setInitialLocationSet(true);
  _n.setIsProgrammaticMove(true);
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

      if (_s.navigating && _s.routeCoordinates.isNotEmpty) {
        final snapped    = _geo.snapToRoute(position.latitude, position.longitude, _s.routeCoordinates);
        final snappedLng = snapped[0];
        final snappedLat = snapped[1];
        final idx        = _geo.findClosestPointIndex(position.latitude, position.longitude, _s.routeCoordinates);
        double bearing   = position.heading;
        if (idx < _s.routeCoordinates.length - 1) {
          bearing = _geo.bearingBetween(
              _s.routeCoordinates[idx][1], _s.routeCoordinates[idx][0],
              _s.routeCoordinates[idx+1][1], _s.routeCoordinates[idx+1][0]);
        }
        _tripService.accumulate(
            position.latitude, position.longitude);
        // Detectar desvío de ruta
        _checkRouteDeviation(position.latitude, position.longitude);
        _updateRemainingRoute(position.latitude, position.longitude);
        _updateTurnByTurn(position.latitude, position.longitude);
        _smoother.updatePosition(
          lat:     snappedLat,
          lng:     snappedLng,
          heading: bearing,
          speedMs: position.speed < 0 ? 0 : position.speed,
        );
          _n.setIsProgrammaticMove(true);
        mapboxMap?.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(snappedLng, snappedLat)),
            zoom: 17.0, bearing: bearing, pitch: 50.0,
          ),
          mapbox.MapAnimationOptions(duration: 900, startDelay: 0),
        );
      } else {
        if (!_s.routeDrawn && !_s.showTapConfirm && !_s.userIsExploring) {
          _n.setIsProgrammaticMove(true);
          mapboxMap?.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(
                  position.longitude, position.latitude)),
              zoom: _geo.calculateDynamicZoom(_s.currentSpeed),
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
    _n.setGasolinerasLoading(true);
    try {
      final geoJson = await _overpassApi.fetchGasolineras(lat, lng);
      if (geoJson != null && mounted) {
        await _updateGasolineraLayer(geoJson);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⛽ Gasolineras cargadas'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Sin gasolineras en el área'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error gasolineras: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    if (mounted) _n.setGasolinerasLoading(false);
  }

  Future<void> _updateGasolineraLayer(String geoJson) async {
    if (mapboxMap == null) return;
    await _mapService.updateGasolineraLayer(mapboxMap!, geoJson);
  }

  // ── Ruta ──────────────────────────────────────────────
  Future<void> _getRoute(double destLat, double destLng) async {
    if (_s.currentPosition == null) return;
    try {
      final routes = await _navService.getRoutes(
        originLat: _s.currentPosition!.latitude,
        originLng: _s.currentPosition!.longitude,
        destLat:   destLat,
        destLng:   destLng,
      );
      if (routes.isEmpty) return;
      _n.setRouteData(
          distance:  routes[0].distance,
          duration:  routes[0].duration,
          coords:    routes[0].coords,
          steps:     routes[0].steps,
          alternates: routes.map((r) => <String, dynamic>{
            'distance': r.distance,
            'duration': r.duration,
            'geometry': r.geometry,
            'coords':   r.coords,
            'steps':    r.steps,
          }).toList(),
        );
      await _drawRouteOnMap(routes[0].geometry);
      // No eliminar el marcador — el smoother lo reposiciona
      if (_s.currentPosition != null) {
        _smoother.updatePosition(
          lat:     _s.currentPosition!.latitude,
          lng:     _s.currentPosition!.longitude,
          heading: _s.currentPosition!.heading,
          speedMs: 0,
        );
      }
      _fitRouteBounds(destLat, destLng);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ruta: $e'),
            backgroundColor: Colors.red),
      );
    }
  }
    
  Future<void> _drawRouteOnMap(Map<String, dynamic> geometry) async {
    if (mapboxMap == null) return;
    await _mapService.drawRouteOnMap(mapboxMap!, geometry, _s.alternateRoutes);
  }

  void _fitRouteBounds(double destLat, double destLng) {
    if (_s.currentPosition == null) return;
    final dist = _geo.distanceBetween(
      _s.currentPosition!.latitude, _s.currentPosition!.longitude,
      destLat, destLng,
    );
    mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(
          (_s.currentPosition!.longitude + destLng) / 2,
          (_s.currentPosition!.latitude  + destLat) / 2,
        )),
        zoom: _navService.fitZoom(dist),
        bearing: 0.0, pitch: 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 1800, startDelay: 0),
    );
  }

  // ── FIX 1: _tts.stop() movido FUERA de setState ───────
  Future<void> _cancelRoute() async {
    if (_s.navigating) {
      final record = await _tripService.finishAndSave(
        destination:  _s.selectedPlace?['name'] ?? 'Destino',
        routeCoords:  _s.routeCoordinates,
        existingTrips: _s.trips,
      );
      if (record != null) _n.setTrips([record, ..._s.trips]);
    }
    if (mapboxMap != null) await _mapService.clearRouteLayers(mapboxMap!);
    if (destinationAnnotation != null && annotationManager != null) {
      await _mapService.deleteAnnotation(
          annotationManager!, destinationAnnotation!);
      destinationAnnotation = null;
    }
     await _tts.stop();
     await _bgService.stop();
     await WakelockPlus.disable();
     _speedLimitService.clearCache();
     _n.setSpeedLimit(null);
     _n.clearRoute();
  }
  
  Future<void> _startNavigation() async {
    _n.setNavigating(true);
    await _bgService.start();
    await WakelockPlus.enable();
    _bgService.updateInstruction(
      _s.currentInstruction.isNotEmpty
          ? _s.currentInstruction
          : 'Iniciando navegacion...',
    );
    if (_s.currentPosition != null) {
      _tripService.startTracking(
        _s.currentPosition!.latitude,
        _s.currentPosition!.longitude,
      );
      mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _s.currentPosition!.longitude, _s.currentPosition!.latitude)),
          zoom: 17.0, bearing: _s.currentPosition!.heading, pitch: 50.0,
        ),
        mapbox.MapAnimationOptions(duration: 1500, startDelay: 0),
      );
    }
  }

  // ── Buscador UI ───────────────────────────────────────
  Widget _buildSearchModal() {
    return SearchModal(
      controller:    _searchController,
      isLoading:     _s.searchLoading,
      results:       _s.searchResults,
      onChanged:     _searchPlaces,
      onClose: () => setState(() {
        _n.clearSearch();
        _searchController.clear();
      }),
      onSelect:      _selectSearchResult,
      onVoiceSearch: _startVoiceSearch,
      isListening:   _isListening,
    );
  }
  
  // ── Libro de viajes UI ────────────────────────────────
  Widget _buildTripBook() {
    return TripBook(trips: _s.trips);
  }
    
  Widget _buildMapTab() {
    final s = _s;
    return MapTab(
      navigating:              s.navigating,
      showSearch:              s.showSearch,
      userIsExploring:         s.userIsExploring,
      isSatellite:             s.isSatellite,
      isNightMode:             s.isNightMode,
      gasolinerasVisible:      s.gasolinerasVisible,
      gasolinerasLoading:      s.gasolinerasLoading,
      routeDrawn:              s.routeDrawn,
      showTapConfirm:          s.showTapConfirm,
      isRecalculating:         s.isRecalculating,
      routeDistance:           s.routeDistance,
      routeDuration:           s.routeDuration,
      currentInstruction:      s.currentInstruction,
      distanceToNextManeuver:  s.distanceToNextManeuver,
      currentSpeed:            s.currentSpeed,
      speedLimit:              s.speedLimit,
      tappedLat:               s.tappedLat,
      tappedLng:               s.tappedLng,
      selectedPlace:           s.selectedPlace,
      alternateRoutes:         s.alternateRoutes,
      selectedRouteIndex:      s.selectedRouteIndex,
      userAvatarImage:         s.userAvatarImage,
      searchController:        _searchController,
      searchLoading:           s.searchLoading,
      searchResults:           s.searchResults,
      onMapCreated:            _onMapCreated,
      onMapTap:                _onMapTap,
      onCameraChange:          (state) async {
        if (s.isProgrammaticMove) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) _n.setIsProgrammaticMove(false);
          });
        } else {
          if (!_s.userIsExploring) _n.setUserIsExploring(true);
        }
      },
      onSearchToggle: () {
        _n.update((st) => st.copyWith(
          showSearch:    !st.showSearch,
          searchResults: !st.showSearch ? const [] : st.searchResults,
        ));
        if (_s.showSearch) _searchController.clear();
      },
      onSearchClose: () {
        _n.clearSearch();
        _searchController.clear();
      },
      onSearchChanged:         _searchPlaces,
      onSearchSelect:          _selectSearchResult,
      onRecenter:              () {
        _n.setUserIsExploring(false);
        if (s.currentPosition != null) {
          _n.setIsProgrammaticMove(true);
          mapboxMap?.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(
                s.currentPosition!.longitude,
                s.currentPosition!.latitude,
              )),
              zoom:    _geo.calculateDynamicZoom(s.currentSpeed),
              bearing: s.currentPosition!.heading,
              pitch:   0.0,
            ),
            mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
          );
        }
      },
      onAvatarPick:            _pickUserAvatar,
      onVoiceSearch:           _startVoiceSearch,
      isListening:             _isListening,
      onGasolinerasToggle: () async {
        if (_s.currentPosition == null || _s.gasolinerasLoading) return;
        if (_s.gasolinerasVisible) {
          _n.setGasolinerasVisible(false);
          try {
            final style = await mapboxMap!.style;
            try { await style.removeStyleLayer('gasolineras-layer');  } catch (_) {}
            try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}
          } catch (_) {}
        } else {
          _n.setGasolinerasVisible(true);
          await _fetchGasolineras(
            _s.currentPosition!.latitude,
            _s.currentPosition!.longitude,
          );
        }
      },
      onNightModeToggle: () async {
  final newNight = !_s.isNightMode;
  _n.setNightMode(newNight, manual: true);
  await mapboxMap?.loadStyleURI(
    newNight
        ? 'mapbox://styles/mapbox/navigation-night-v1'
        : 'mapbox://styles/mapbox/streets-v12',
  );
  if (!newNight) await _applyCustomRoadStyle();
  await Future.delayed(const Duration(milliseconds: 1500));
  if (_s.routeDrawn && _s.routeCoordinates.isNotEmpty && mounted) {
    await _drawRouteOnMap({
      'type': 'LineString',
      'coordinates': _s.routeCoordinates,
    });
  }
},
      onSatelliteToggle: () async {
        final newValue = !_s.isSatellite;
        _n.setSatellite(newValue);
        _n.resetNightModeManual();
        await mapboxMap?.loadStyleURI(
          newValue
              ? 'mapbox://styles/mapbox/satellite-streets-v12'
              : 'mapbox://styles/mapbox/streets-v12',
        );
        if (!newValue) await _applyCustomRoadStyle();
        await Future.delayed(const Duration(milliseconds: 1500));
        if (_s.routeDrawn && _s.routeCoordinates.isNotEmpty && mounted) {
          await _drawRouteOnMap({
            'type': 'LineString',
            'coordinates': _s.routeCoordinates,
          });
        }
        if (_s.currentPosition != null && mounted && _s.gasolinerasVisible) {
          _fetchGasolineras(
            _s.currentPosition!.latitude,
            _s.currentPosition!.longitude,
          );
        }
      },
      onTapConfirm:            _confirmTappedDestination,
      onTapCancel:             _cancelTap,
      onCancelRoute:           _cancelRoute,
      onStartNavigation:       _startNavigation,
      onRouteSelect:           (i) async {
        final r = s.alternateRoutes[i];
        _n.selectRoute(i, _s.alternateRoutes);
        if (mapboxMap != null) {
          await _mapService.highlightRoute(
              mapboxMap!, i, _s.alternateRoutes.length);
        }
      },
    );
  }

// ── Ciclo de vida ─────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _gpsService.onAppBackground();
        break;
      case AppLifecycleState.resumed:
        _gpsService.onAppForeground();
        _applyNightOrDayStyle();
        final permission = await Geolocator.checkPermission();
        final hasPermission = permission == LocationPermission.always ||
                              permission == LocationPermission.whileInUse;
        if (hasPermission && _s.currentPosition == null) {
          await _getInitialPosition();
          _startLocationTracking();
        }
        break;
      default:
        break;
    }
  }

  // ── BUILD ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mapProvider);
    return Scaffold(
      bottomNavigationBar: s.navigating
          ? null
          : BottomNavigationBar(
              currentIndex: s.currentTabIndex,
              onTap: (i) {
                _n.setTabIndex(i);
                if (i == 0 && s.currentPosition != null) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _n.setIsProgrammaticMove(true);
                    mapboxMap?.flyTo(
                      mapbox.CameraOptions(
                        center: mapbox.Point(coordinates: mapbox.Position(
                          s.currentPosition!.longitude,
                          s.currentPosition!.latitude,
                        )),
                        zoom: _geo.calculateDynamicZoom(s.currentSpeed),
                        bearing: s.currentPosition!.heading,
                        pitch: 0.0,
                      ),
                      mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
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
        index: s.currentTabIndex,
        children: [
          _buildMapTab(),   // índice 0 — Mapa
          _buildTripBook(), // índice 1 — Libro de viaje
        ],
      ),
    );
  }
}
