import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'dart:typed_data';
import 'data/models/trip_record.dart';
import 'dart:async';
import 'data/sources/mapbox_api.dart';
import 'data/sources/overpass_api.dart';
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
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/state/map_notifier.dart';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mapboxToken.isEmpty) {                        // ← REEMPLAZA assert
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Error: MAPBOX_TOKEN no configurado.'),
        ),
      ),
    ));
    return;
  }
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
  final Completer<void> _mapReadyCompleter = Completer<void>();
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
  late final TripService _tripService = TripService(_prefsSource, const GeoUtils());
  late final NavigationService _navService =
      NavigationService(MapboxApi(_mapboxToken), const GeoUtils());

  // ── Buscador ──────────────────────────────────────────
  late final MapboxApi _mapboxApi = MapboxApi(_mapboxToken);
  late final OverpassApi _overpassApi = const OverpassApi();
  int _searchToken = 0;
  final TextEditingController _searchController = TextEditingController();

  int _deviationCount = 0;
  DateTime? _lastRecalcTime;
  final List<mapbox.PointAnnotation> _waypointAnnotations = [];
  Timer? _waypointArrivalTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _smoother.start();
    _startSmoothMarker();
    _loadImages();
    _startNightModeTimer();
    _loadTrips();
    _initTts();
    _loadUserAvatar();
    _initSpeech();
    // Diferir hasta que el primer frame esté completamente renderizado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _smoothSub?.cancel();
    _smoother.stop();
    _nightModeTimer?.cancel();
    _waypointArrivalTimer?.cancel();
    WakelockPlus.disable();
    _searchController.dispose();
    _gpsService.dispose();   // ← AGREGADO
    _mapboxApi.dispose();
    _navService.disposeApi();
    super.dispose();
  }

  // ── Imágenes ──────────────────────────────────────────
  Future<void> _pickUserAvatar() async {
    final bytes = await _imageUtils.pickImageFromGallery();
    if (bytes == null) return;
    final circular = await _imageUtils.makeCircularImage(bytes, 70);
    final saved = await _prefsSource.saveAvatar(circular);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imagen muy grande, intenta con una más pequeña'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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

Future<String?> _getBestLocale() async {
  final locales = await _speech.locales();
  for (final preferred in ['es-MX', 'es-US']) {
    if (locales.any((l) => l.localeId == preferred)) return preferred;
  }
  final anySpanish = locales
      .where((l) => l.localeId.startsWith('es'))
      .map((l) => l.localeId)
      .firstOrNull;
  return anySpanish;
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
      localeId:          await _getBestLocale() ?? 'es-MX',
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
    } catch (_) {
      if (token == _searchToken) _n.setSearchResults([]);
    } finally {
      if (token == _searchToken) _n.setSearchLoading(false);
    }
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
  bool _permissionFlowRunning = false;

  Future<void> _requestPermissions() async {
    if (_permissionFlowRunning) return;
    _permissionFlowRunning = true;
    try {
      final granted = await _requestLocationPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Se necesita permiso de ubicación para navegar'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      // Esperar a que el mapa esté completamente listo
      await _mapReadyCompleter.future;
      await _getInitialPosition();
      _startLocationTracking();
    } finally {
      _permissionFlowRunning = false;
    }
  }

  Future<bool> _requestLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      await Future.delayed(const Duration(seconds: 3));
      permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
             permission == LocationPermission.whileInUse;
    }

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
    if (!_mapReadyCompleter.isCompleted) _mapReadyCompleter.complete();
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
      _n.setNavigating(false);
      final record = await _tripService.finishAndSave(
        destination:   _s.selectedPlace?['name'] ?? 'Destino',
        routeCoords:   _s.routeCoordinates,
        existingTrips: _s.trips,
      );
      if (record != null && mounted) {
        _n.setTrips([record, ..._s.trips]);
      }
      _tripService.reset();
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

    final idx       = _geo.findClosestPointIndex(lat, lng, _s.routeCoordinates, lastIdx: _s.currentStepIndex);
    final remaining = _s.routeCoordinates.sublist(idx);
    await _mapService.updateRemainingRoute(mapboxMap!, remaining);
  }

// ── Límite de velocidad ───────────────────────────────
  Future<void> _updateSpeedLimit(double lat, double lng) async {
  final speedAtRequest = _s.currentSpeed;
  final limit = await _speedLimitService.getSpeedLimit(lat, lng);
  if (mounted) _n.setSpeedLimit(limit);

  final status = SpeedStatus.evaluate(speedAtRequest, limit);
  if (status.level == SpeedAlertLevel.danger) {
    _speak('Exceso de velocidad');
  }
}
  
void _checkRouteDeviation(double lat, double lng) {
  if (!_s.navigating || _s.routeCoordinates.isEmpty || _s.isRecalculating) return;

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
    _navService.resetAnnouncements();
    _speedLimitService.clearCache();                // ← AGREGADO
    _n.setSpeedLimit(null);                         // ← AGREGADO

    final destLat = (_s.selectedPlace!['lat'] as num).toDouble();
    final destLng = (_s.selectedPlace!['lng'] as num).toDouble();

    await _getRoute(destLat, destLng, fromWaypointIndex: _s.currentWaypointIndex);
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
  Future<void> _onMapTap(mapbox.MapContentGestureContext context) async {
    if (_s.navigating) return;
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();

    // Modo selección de paradas
    if (_s.isSelectingWaypoints) {
      final index = _s.waypoints.length + 1;
      _n.addWaypoint({
        'lat':     lat,
        'lng':     lng,
        'index':   index,
        'reached': false,
      });
      _addWaypointAnnotation(lat, lng, index);
      return;
    }

    _n.setTappedLocation(lat, lng);
    await _addDestinationMarker(lat, lng);
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
    final lat = _s.tappedLat!;
    final lng = _s.tappedLng!;
    String placeName = 'Destino seleccionado';
    try {
      placeName = await _mapboxApi.reverseGeocode(lat, lng);
    } catch (_) {}
    _n.update((s) => s.copyWith(
      selectedPlace:  {'name': placeName, 'lat': lat, 'lng': lng},
      showTapConfirm: false,
    ));
    await _getRoute(lat, lng);
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

Future<Uint8List> _createWaypointImage(int number) async {
    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fillPaint = ui.Paint()..color = const ui.Color(0xFFFF6F00);
    canvas.drawCircle(const ui.Offset(40, 40), 36, fillPaint);
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const ui.Offset(40, 40), 36, borderPaint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return _s.pinImage ?? Uint8List(0);
    final base = bytes.buffer.asUint8List();

    // Superponer el número usando TextPainter
    final recorder2 = ui.PictureRecorder();
    final canvas2 = ui.Canvas(recorder2);
    final decodedBase = await decodeImageFromList(base);
    canvas2.drawImage(
      decodedBase,
      ui.Offset.zero,
      ui.Paint(),
    );
    decodedBase.dispose();

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color:      Color(0xFFFFFFFF),
          fontSize:   28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas2,
      ui.Offset(
        (size - textPainter.width)  / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture2 = recorder2.endRecording();
    final image2   = await picture2.toImage(size.toInt(), size.toInt());
    final bytes2   = await image2.toByteData(format: ui.ImageByteFormat.png);
    image2.dispose();
    if (bytes2 == null) return _s.pinImage ?? Uint8List(0);
    return bytes2.buffer.asUint8List();
  }

  Future<void> _addWaypointAnnotation(
      double lat, double lng, int index) async {
    if (annotationManager == null) return;
    final img = await _createWaypointImage(index);
    final annotation = await annotationManager!.create(
      mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
            coordinates: mapbox.Position(lng, lat)),
        image: img,
        iconSize: 0.8,
        iconAnchor: mapbox.IconAnchor.CENTER,
      ),
    );
    _waypointAnnotations.add(annotation);
  }

  Future<void> _clearWaypointAnnotations() async {
    if (annotationManager == null) return;
    for (final a in _waypointAnnotations) {
      try { await annotationManager!.delete(a); } catch (_) {}
    }
    _waypointAnnotations.clear();
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
  DateTime _lastUserInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  void _startSmoothMarker() {
    if (_smoothSub != null) {
      _smoothSub!.cancel();                        // ← cancela sub anterior
      _smoothSub = null;                           // ← fuerza re-suscripción
    }
    _smoothSub = _smoother.positionStream.listen((SmoothPosition pos) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.difference(_lastUserInteraction).inMilliseconds < 150) return;
      if (now.difference(_lastMarkerUpdate).inMilliseconds < 33) return;
      _lastMarkerUpdate = now;
      _updateMotoMarker(pos.latitude, pos.longitude, pos.heading);
    });
  }
  
  // ── GPS Tracking ──────────────────────────────────────
  Future<void> _startLocationTracking() async {
    if (_locationSubscription != null) return;
    await _gpsService.startTracking();
    _locationSubscription = _gpsService.positionStream.listen((Position position) async {
      if (!mounted) return;
      final speed = (position.speed < 0 ? 0 : position.speed) * 3.6;
      _n.update((s) => s.copyWith(
        currentSpeed:    speed,
        currentPosition: position,
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
        final idx        = _geo.findClosestPointIndex(position.latitude, position.longitude, _s.routeCoordinates, lastIdx: _s.currentStepIndex);
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
        await _updateRemainingRoute(position.latitude, position.longitude);
        _updateTurnByTurn(position.latitude, position.longitude);
        _checkWaypointArrival(position.latitude, position.longitude);
        _smoother.updatePosition(
          lat:     position.latitude,
          lng:     position.longitude,
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

void _checkWaypointArrival(double lat, double lng) {
    if (_s.waypoints.isEmpty) return;
    if (_s.showWaypointArrival) return;
    final idx = _s.currentWaypointIndex;
    if (idx >= _s.waypoints.length) return;
    final wp  = _s.waypoints[idx];
    final dist = _geo.distanceBetween(
        lat, lng,
        (wp['lat'] as num).toDouble(),
        (wp['lng'] as num).toDouble());
    if (dist <= 40) {
      final num = wp['index'] as int;
      _n.setWaypointArrival('📍 ¡Has llegado a la parada $num!');
      _n.advanceWaypoint();
      _waypointArrivalTimer?.cancel();
      _waypointArrivalTimer = Timer(
        const Duration(seconds: 4),
        () { if (mounted) _n.dismissWaypointArrival(); },
      );
    }
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
  Future<void> _getRoute(double destLat, double destLng,
      {int fromWaypointIndex = 0}) async {
    if (_s.currentPosition == null) return;
    try {
      // Solo los waypoints pendientes
      final pendingWaypoints = _s.waypoints.length > fromWaypointIndex
          ? _s.waypoints.sublist(fromWaypointIndex)
          : <Map<String, dynamic>>[];

      final routes = await _navService.getRoutes(
        originLat: _s.currentPosition!.latitude,
        originLng: _s.currentPosition!.longitude,
        destLat:   destLat,
        destLng:   destLng,
        waypoints: pendingWaypoints,
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

  Future<void> _recreateAnnotationsAfterStyleChange() async {
    if (mapboxMap == null || !mounted) return;
    // El annotationManager queda inválido tras loadStyleURI — recrear
    annotationManager = await mapboxMap!.annotations
        .createPointAnnotationManager();
    motoAnnotation        = null;
    destinationAnnotation = null;

    // Redibujar marcador de moto
    if (_s.currentPosition != null) {
      await _updateMotoMarker(
        _s.currentPosition!.latitude,
        _s.currentPosition!.longitude,
        _s.currentPosition!.heading,
      );
    }
    // Redibujar marcador de destino
    if (_s.selectedPlace != null && _s.pinImage != null) {
      await _addDestinationMarker(
        (_s.selectedPlace!['lat'] as num).toDouble(),
        (_s.selectedPlace!['lng'] as num).toDouble(),
      );
    }
    // Redibujar waypoints
    if (_s.waypoints.isNotEmpty) {
      for (final a in _waypointAnnotations) {  // ← AGREGADO
        try { await annotationManager!.delete(a); } catch (_) {}
      }
      _waypointAnnotations.clear();
      for (final wp in _s.waypoints) {
        await _addWaypointAnnotation(
          (wp['lat'] as num).toDouble(),
          (wp['lng'] as num).toDouble(),
          wp['index'] as int,
        );
      }
    }
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
    await _clearWaypointAnnotations();
    _n.clearWaypoints();
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
    if (_s.navigating) return;
    _n.setNavigating(true);
    _navService.resetAnnouncements(); 
    _deviationCount = 0;              
    _lastRecalcTime = null;           
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
      waypoints:               s.waypoints,
      isSelectingWaypoints:    s.isSelectingWaypoints,
      showWaypointArrival:     s.showWaypointArrival,
      waypointArrivalMessage:  s.waypointArrivalMessage,
      onWaypointModeToggle: () {
        _n.setSelectingWaypoints(!_s.isSelectingWaypoints);
      },
      onWaypointDone: () async {
        _n.setSelectingWaypoints(false);
        if (_s.selectedPlace != null) {
          await _getRoute(
            (_s.selectedPlace!['lat'] as num).toDouble(),
            (_s.selectedPlace!['lng'] as num).toDouble(),
          );
        }
      },
      onWaypointClear: () async {
        await _clearWaypointAnnotations();
        _n.clearWaypoints();
        if (_s.selectedPlace != null) {
          await _getRoute(
            (_s.selectedPlace!['lat'] as num).toDouble(),
            (_s.selectedPlace!['lng'] as num).toDouble(),
          );
        }
      },
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
      onCameraChange:         (state) async {
        if (!_s.isProgrammaticMove) _lastUserInteraction = DateTime.now();
        if (_s.isProgrammaticMove) {
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
  if (mounted) await _recreateAnnotationsAfterStyleChange();
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
        if (mounted) await _recreateAnnotationsAfterStyleChange();
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
        // Solo pasar a background si el tracking ya está activo
        if (_locationSubscription != null) {
          _gpsService.onAppBackground();
        }
        break;
      case AppLifecycleState.inactive:
        // inactive ocurre durante diálogos del sistema — ignorar completamente
        break;
      case AppLifecycleState.resumed:
        _applyNightOrDayStyle();
        final permission = await Geolocator.checkPermission();
        if (!mounted) break;                          // ← AGREGADO
        final hasPermission = permission == LocationPermission.always ||
                              permission == LocationPermission.whileInUse;
        if (!hasPermission) break;
        _startSmoothMarker();
        if (_locationSubscription != null) {
          _gpsService.onAppForeground();
        } else {
          await _mapReadyCompleter.future;
          if (!mounted) break;                        // ← AGREGADO
          await _getInitialPosition();
          if (!mounted) break;                        // ← AGREGADO
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
