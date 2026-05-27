import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/services/background_service.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/map_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/smooth_location_service.dart';
import '../../core/services/speed_limit_service.dart';
import '../../core/services/trip_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/trip_record.dart';
import '../../data/sources/mapbox_api.dart';
import '../../data/sources/overpass_api.dart';
import '../../data/sources/prefs_source.dart';
import '../../di/providers.dart';
import '../state/map_state.dart';

export '../state/map_state.dart';

final mapControllerProvider = AutoDisposeNotifierProvider<MapController, MapState>(
  () => MapController(),
);

class MapController extends AutoDisposeNotifier<MapState> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;
  mapbox.PointAnnotation? _motoAnnotation;
  mapbox.PointAnnotation? _destinationAnnotation;
  final List<mapbox.PointAnnotation> _waypointAnnotations = [];

  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<SmoothPosition>? _smoothSub;
  Timer? _nightModeTimer;
  Timer? _waypointArrivalTimer;
  final Completer<void> _mapReadyCompleter = Completer();

  int _deviationCount = 0;
  DateTime? _lastRecalcTime;
  DateTime? _lastSpeedLimitCall;
  int _searchToken = 0;
  bool _isListening = false;

  late final String _token;
  late final PrefsSource _prefs;
  late final GeoUtils _geo;
  late final ImageUtils _imageUtils;
  late final TtsService _tts;
  late final MapService _mapService;
  late final GpsService _gpsService;
  late final BackgroundService _bgService;
  late final SpeedLimitService _speedLimitService;
  late final SmoothLocationService _smoother;
  late final TripService _tripService;
  late final NavigationService _navService;
  late final MapboxApi _mapboxApi;
  late final OverpassApi _overpassApi;
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;

  // FIX: Flag para saber si el mapa está listo y las imágenes cargadas
  bool _imagesLoaded = false;
  bool _mapCreated = false;

  @override
  MapState build() {
    _token = ref.read(mapboxTokenProvider);
    _prefs = ref.read(prefsSourceProvider);
    _geo = ref.read(geoUtilsProvider);
    _imageUtils = ref.read(imageUtilsProvider);
    _tts = ref.read(ttsServiceProvider);
    _mapService = ref.read(mapServiceProvider);
    _gpsService = ref.read(gpsServiceProvider);
    _bgService = ref.read(backgroundServiceProvider);
    _speedLimitService = ref.read(speedLimitServiceProvider);
    _smoother = ref.read(smoothLocationServiceProvider);
    _tripService = ref.read(tripServiceProvider);
    _mapboxApi = ref.read(mapboxApiProvider(_token));
    _navService = ref.read(navigationServiceProvider(_token));
    _overpassApi = ref.read(overpassApiProvider);

    ref.onDispose(_onDispose);
    return const MapState();
  }

  Future<void> init() async {
    _smoother.start();
    _startNightModeTimer();
    await _loadTrips();
    await _loadUserAvatar();
    await _loadImages(); // Carga las imágenes primero
    await _initTts();
    await _initSpeech();
  }

  Future<void> _onDispose() async {
    _locationSubscription?.cancel();
    _smoothSub?.cancel();
    _smoother.stop();
    _nightModeTimer?.cancel();
    _waypointArrivalTimer?.cancel();
    await _gpsService.dispose();
    _mapboxApi.dispose();
    _navService.disposeApi();
    await _tts.stop();
    await _bgService.stop();
    await WakelockPlus.disable();
  }

  Future<void> onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    _annotationManager = await map.annotations.createPointAnnotationManager();
    _mapCreated = true;

    await Future.delayed(const Duration(milliseconds: 600));
    await _applyNightOrDayStyle();
    await _applyCustomRoadStyle();

    if (!_mapReadyCompleter.isCompleted) _mapReadyCompleter.complete();

    // FIX: Intentar crear el marcador de moto si ya tenemos posición e imagen
    if (state.currentPosition != null && state.pinImage != null) {
      await _updateMotoMarker(
        state.currentPosition!.latitude,
        state.currentPosition!.longitude,
        state.currentPosition!.heading,
      );
      _flyTo(
        lat: state.currentPosition!.latitude,
        lng: state.currentPosition!.longitude,
        zoom: 15.0,
        bearing: state.currentPosition!.heading,
      );
    }
  }

  bool _permissionFlowRunning = false;

  Future<bool> requestPermissions() async {
    if (_permissionFlowRunning) return false;
    _permissionFlowRunning = true;
    try {
      final granted = await _requestLocationPermissions();
      if (!granted) return false;
      await _mapReadyCompleter.future;
      await _getInitialPosition();
      _startLocationTracking();
      return true;
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

  Future<void> _getInitialPosition() async {
    final position = await _gpsService.getInitialPosition();
    if (position == null) return;

    state = state.copyWith(
      currentPosition: position,
      currentSpeed: position.speed * 3.6,
    );
    state = state.copyWith(initialLocationSet: true);

    _smoother.updatePosition(
      lat: position.latitude,
      lng: position.longitude,
      heading: position.heading,
      speedMs: position.speed < 0 ? 0 : position.speed,
    );

    // FIX: Crear marcador de moto inmediatamente si el mapa ya está listo
    if (_mapCreated && _annotationManager != null && state.pinImage != null) {
      await _updateMotoMarker(position.latitude, position.longitude, position.heading);
    }

    _flyTo(
      lat: position.latitude,
      lng: position.longitude,
      zoom: 15.0,
      bearing: position.heading,
    );
  }

  Future<void> _startLocationTracking() async {
    if (_locationSubscription != null) return;
    await _gpsService.startTracking();
    _locationSubscription = _gpsService.positionStream.listen((Position position) async {
      final speed = (position.speed < 0 ? 0 : position.speed) * 3.6;
      state = state.copyWith(
        currentSpeed: speed,
        currentPosition: position,
      );

      if (!state.navigating) {
        _smoother.updatePosition(
          lat: position.latitude,
          lng: position.longitude,
          heading: position.heading,
          speedMs: position.speed < 0 ? 0 : position.speed,
        );
      }

      final now = DateTime.now();
      if (_lastSpeedLimitCall == null ||
          now.difference(_lastSpeedLimitCall!).inSeconds >= 5) {
        _lastSpeedLimitCall = now;
        await _updateSpeedLimit(position.latitude, position.longitude);
      }

      if (!state.initialLocationSet && _mapboxMap != null) {
        state = state.copyWith(initialLocationSet: true, isProgrammaticMove: true);
        _flyTo(
          lat: position.latitude,
          lng: position.longitude,
          zoom: 15.0,
          bearing: position.heading,
        );
      }

      if (state.navigating && state.routeCoordinates.isNotEmpty) {
        await _handleNavigationUpdate(position);
      } else {
        if (!state.routeDrawn && !state.showTapConfirm && !state.userIsExploring) {
          state = state.copyWith(isProgrammaticMove: true);
          _flyTo(
            lat: position.latitude,
            lng: position.longitude,
            zoom: _geo.calculateDynamicZoom(state.currentSpeed),
            bearing: position.heading,
          );
        }
      }
    });
  }

  Future<void> _handleNavigationUpdate(Position position) async {
    final snapped = _geo.snapToRoute(
      position.latitude, position.longitude, state.routeCoordinates,
    );
    final snappedLng = snapped[0];
    final snappedLat = snapped[1];
    final idx = _geo.findClosestPointIndex(
      position.latitude, position.longitude,
      state.routeCoordinates,
      lastIdx: state.currentStepIndex,
    );

    double bearing = position.heading;
    if (idx < state.routeCoordinates.length - 1) {
      bearing = _geo.bearingBetween(
        state.routeCoordinates[idx][1], state.routeCoordinates[idx][0],
        state.routeCoordinates[idx + 1][1], state.routeCoordinates[idx + 1][0],
      );
    }

    _tripService.accumulate(position.latitude, position.longitude);
    _checkRouteDeviation(position.latitude, position.longitude);
    await _updateRemainingRoute(position.latitude, position.longitude);
    _updateTurnByTurn(position.latitude, position.longitude);
    _checkWaypointArrival(position.latitude, position.longitude);

    _smoother.updatePosition(
      lat: position.latitude,
      lng: position.longitude,
      heading: bearing,
      speedMs: position.speed < 0 ? 0 : position.speed,
    );

    state = state.copyWith(isProgrammaticMove: true);
    _flyTo(
      lat: snappedLat,
      lng: snappedLng,
      zoom: 17.0,
      bearing: bearing,
      pitch: 50.0,
    );
  }

  Future<void> onAppBackground() async {
    if (_locationSubscription != null) {
      _gpsService.onAppBackground();
    }
  }

  Future<void> onAppForeground() async {
    _applyNightOrDayStyle();
    final permission = await Geolocator.checkPermission();
    final hasPermission = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (!hasPermission) return;

    _startSmoothMarker();
    if (_locationSubscription != null) {
      _gpsService.onAppForeground();
    } else {
      await _mapReadyCompleter.future;
      await _getInitialPosition();
      _startLocationTracking();
    }
  }

  DateTime _lastMarkerUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  void _startSmoothMarker() {
    _smoothSub?.cancel();
    _smoothSub = _smoother.positionStream.listen((SmoothPosition pos) {
      final now = DateTime.now();
      if (now.difference(_lastMarkerUpdate).inMilliseconds < 33) return;
      _lastMarkerUpdate = now;
      _updateMotoMarker(pos.latitude, pos.longitude, pos.heading);
    });
  }

  Future<void> _updateMotoMarker(double lat, double lng, double bearing) async {
    final markerImage = state.userAvatarImage ?? state.pinImage;
    if (_annotationManager == null || markerImage == null) {
      print('[MapController] No se puede crear marcador: annotationManager=$_annotationManager, markerImage=${markerImage != null}');
      return;
    }
    _motoAnnotation = await _mapService.updateMotoMarker(
      manager: _annotationManager!,
      current: _motoAnnotation,
      lat: lat,
      lng: lng,
      bearing: bearing,
      markerImage: markerImage,
      isAvatar: state.userAvatarImage != null,
    );
  }

  Future<void> _addDestinationMarker(double lat, double lng) async {
    if (_annotationManager == null || state.pinImage == null) {
      print('[MapController] No se puede crear destino: annotationManager=$_annotationManager, pinImage=${state.pinImage != null}');
      return;
    }
    _destinationAnnotation = await _mapService.updateDestinationMarker(
      manager: _annotationManager!,
      current: _destinationAnnotation,
      lat: lat,
      lng: lng,
      pinImage: state.pinImage!,
    );
  }

  Future<void> _deleteDestinationMarker() async {
    if (_destinationAnnotation != null && _annotationManager != null) {
      await _mapService.deleteAnnotation(_annotationManager!, _destinationAnnotation!);
      _destinationAnnotation = null;
    }
  }

  Future<Uint8List> _createWaypointImage(int number) async {
    try {
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
      if (bytes == null) return state.pinImage ?? Uint8List(0);
      final base = bytes.buffer.asUint8List();

      final recorder2 = ui.PictureRecorder();
      final canvas2 = ui.Canvas(recorder2);
      final decodedBase = await decodeImageFromList(base);
      canvas2.drawImage(decodedBase, ui.Offset.zero, ui.Paint());
      decodedBase.dispose();

      final textPainter = TextPainter(
        text: TextSpan(
          text: '$number',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas2,
        Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
      );

      final picture2 = recorder2.endRecording();
      final image2 = await picture2.toImage(size.toInt(), size.toInt());
      final bytes2 = await image2.toByteData(format: ui.ImageByteFormat.png);
      image2.dispose();
      return bytes2?.buffer.asUint8List() ?? state.pinImage ?? Uint8List(0);
    } catch (e) {
      print('[MapController] Error creando waypoint image: $e');
      return state.pinImage ?? Uint8List(0);
    }
  }

  Future<void> _addWaypointAnnotation(double lat, double lng, int index) async {
    if (_annotationManager == null) return;
    final img = await _createWaypointImage(index);
    final annotation = await _annotationManager!.create(
      mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        image: img,
        iconSize: 0.8,
        iconAnchor: mapbox.IconAnchor.CENTER,
      ),
    );
    _waypointAnnotations.add(annotation);
  }

  Future<void> _clearWaypointAnnotations() async {
    if (_annotationManager == null) return;
    for (final a in _waypointAnnotations) {
      try { await _annotationManager!.delete(a); } catch (_) {}
    }
    _waypointAnnotations.clear();
  }

  Future<Uint8List?> pickUserAvatar() async {
    final bytes = await _imageUtils.pickImageFromGallery();
    if (bytes == null) return null;
    final circular = await _imageUtils.makeCircularImage(bytes, 70);
    final saved = await _prefs.saveAvatar(circular);
    if (!saved) return null;
    state = state.copyWith(userAvatarImage: circular);
    if (_motoAnnotation != null && _annotationManager != null) {
      await _mapService.deleteAnnotation(_annotationManager!, _motoAnnotation!);
      _motoAnnotation = null;
    }
    if (state.currentPosition != null) {
      _smoother.updatePosition(
        lat: state.currentPosition!.latitude,
        lng: state.currentPosition!.longitude,
        heading: state.currentPosition!.heading,
        speedMs: 0,
      );
    }
    return circular;
  }

  Future<void> _loadUserAvatar() async {
    final bytes = await _prefs.loadAvatar();
    if (bytes != null) state = state.copyWith(userAvatarImage: bytes);
  }

  Future<void> _loadImages() async {
    try {
      final ByteData pinData = await rootBundle.load('assets/moto_pin.png');
      final Uint8List pinResized = await _imageUtils.resizeImage(
        pinData.buffer.asUint8List(), 120,
      );
      state = state.copyWith(pinImage: pinResized);
      _imagesLoaded = true;
      print('[MapController] Imagen pin cargada: ${pinResized.length} bytes');
    } catch (e) {
      print('[MapController] Error cargando imagen pin: $e');
    }
  }

  Future<void> _initTts() async {
    await _tts.init();
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<bool> ensureSpeechAvailable() async => _speechAvailable;

    Future<void> _initSpeech() async {
      // Solicitar permiso de micrófono primero
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _speechAvailable = await _speech.initialize();
      } else {
        _speechAvailable = false;
        print('[MapController] Permiso de micrófono denegado');
      }
    }

  Future<String?> getBestSpeechLocale() async {
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

  Future<void> startVoiceSearch({
    required Function(String text) onResult,
    required VoidCallback onListeningStarted,
    required VoidCallback onListeningStopped,
  }) async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      onListeningStopped();
      return;
    }
    _isListening = true;
    onListeningStarted();

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) onResult(text);
          _isListening = false;
          onListeningStopped();
        }
      },
      localeId: await getBestSpeechLocale() ?? 'es-MX',
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  bool get isListening => _isListening;

  Future<void> stopVoiceSearch() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }

  Future<void> searchPlaces(String query) async {
    if (query.trim().length < 3) {
      state = state.copyWith(searchResults: const []);
      return;
    }
    final token = ++_searchToken;
    state = state.copyWith(searchLoading: true);
    try {
      print('[MapController] Buscando: "$query"');
      final results = await _mapboxApi.searchPlaces(
        query,
        proximityLat: state.currentPosition?.latitude,
        proximityLng: state.currentPosition?.longitude,
      );
      print('[MapController] Resultados: ${results.length}');
      if (token != _searchToken) return;
      state = state.copyWith(searchResults: results);
    } catch (e) {
      print('[MapController] Error buscando: $e');
      if (token == _searchToken) state = state.copyWith(searchResults: const []);
    } finally {
      if (token == _searchToken) state = state.copyWith(searchLoading: false);
    }
  }

  Future<void> selectSearchResult(Map<String, dynamic> place) async {
    final lat = place['lat'] as double;
    final lng = place['lng'] as double;
    state = state.copyWith(
      showSearch: false,
      searchResults: const [],
      selectedPlace: place,
      showTapConfirm: false,
    );
    await _addDestinationMarker(lat, lng);
    _flyTo(lat: lat, lng: lng, zoom: 12.0, bearing: 0.0, pitch: 0.0);
    await _getRoute(lat, lng);
  }

  Future<void> onMapTap(double lat, double lng) async {
    if (state.navigating) return;
    if (state.isSelectingWaypoints) {
      final index = state.waypoints.length + 1;
      final newWaypoints = List<Map<String, dynamic>>.from(state.waypoints);
      newWaypoints.add({
        'lat': lat,
        'lng': lng,
        'index': index,
        'reached': false,
      });
      state = state.copyWith(waypoints: newWaypoints);
      await _addWaypointAnnotation(lat, lng, index);
      return;
    }
    state = state.copyWith(
      showTapConfirm: true,
      tappedLat: lat,
      tappedLng: lng,
    );
    await _addDestinationMarker(lat, lng);
    _flyTo(lat: lat, lng: lng, zoom: 16.0, bearing: 0.0, pitch: 0.0);
  }

  Future<void> confirmTappedDestination() async {
    if (state.tappedLat == null || state.tappedLng == null) return;
    final lat = state.tappedLat!;
    final lng = state.tappedLng!;
    String placeName = 'Destino seleccionado';
    try {
      placeName = await _mapboxApi.reverseGeocode(lat, lng);
    } catch (e) {
      print('[MapController] Error reverse geocode: $e');
    }
    state = state.copyWith(
      selectedPlace: {'name': placeName, 'lat': lat, 'lng': lng},
      showTapConfirm: false,
    );
    await _getRoute(lat, lng);
  }

  Future<void> cancelTap() async {
    await _deleteDestinationMarker();
    state = state.copyWith(
      showTapConfirm: false,
      clearTappedLat: true,
      clearTappedLng: true,
    );
  }

  Future<void> _getRoute(double destLat, double destLng, {int fromWaypointIndex = 0}) async {
    if (state.currentPosition == null) {
      print('[MapController] No hay posición actual para calcular ruta');
      return;
    }
    try {
      print('[MapController] Calculando ruta a $destLat, $destLng');

      final pendingWaypoints = state.waypoints.length > fromWaypointIndex
          ? state.waypoints.sublist(fromWaypointIndex)
          : <Map<String, dynamic>>[];

      final routes = await _navService.getRoutes(
        originLat: state.currentPosition!.latitude,
        originLng: state.currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
        waypoints: pendingWaypoints,
      );

      if (routes.isEmpty) {
        print('[MapController] No se encontraron rutas');
        return;
      }

      print('[MapController] Rutas encontradas: ${routes.length}');

      state = state.copyWith(
        routeDrawn: true,
        routeDistance: routes[0].distance,
        routeDuration: routes[0].duration,
        routeCoordinates: routes[0].coords,
        routeSteps: routes[0].steps,
        alternateRoutes: routes.map((r) => {
          'distance': r.distance,
          'duration': r.duration,
          'geometry': r.geometry,
          'coords': r.coords,
          'steps': r.steps,
        }).toList(),
        selectedRouteIndex: 0,
        currentStepIndex: 0,
        currentInstruction: routes[0].steps.isNotEmpty
            ? routes[0].steps[0]['instruction'] as String
            : '',
        distanceToNextManeuver: routes[0].steps.isNotEmpty
            ? routes[0].steps[0]['distance'] as double
            : 0.0,
      );

      // FIX: Dibujar la ruta en el mapa
      await _drawRouteOnMap(routes[0].geometry);

      if (state.currentPosition != null) {
        _smoother.updatePosition(
          lat: state.currentPosition!.latitude,
          lng: state.currentPosition!.longitude,
          heading: state.currentPosition!.heading,
          speedMs: 0,
        );
      }
      _fitRouteBounds(destLat, destLng);
    } catch (e) {
      print('[MapController] Error en _getRoute: $e');
    }
  }

  Future<void> _drawRouteOnMap(Map<String, dynamic> geometry) async {
    if (_mapboxMap == null) {
      print('[MapController] Mapa no listo para dibujar ruta');
      return;
    }
    print('[MapController] Dibujando ruta...');
    await _mapService.drawRouteOnMap(_mapboxMap!, geometry, state.alternateRoutes);
  }

  Future<void> _updateRemainingRoute(double lat, double lng) async {
    if (!state.navigating || state.routeCoordinates.isEmpty || _mapboxMap == null) return;
    if (_navService.hasArrived(lat, lng, state.routeCoordinates)) {
      await _handleArrival();
      return;
    }
    final idx = _geo.findClosestPointIndex(lat, lng, state.routeCoordinates, lastIdx: state.currentStepIndex);
    final remaining = state.routeCoordinates.sublist(idx);
    await _mapService.updateRemainingRoute(_mapboxMap!, remaining);
  }

  Future<void> _handleArrival() async {
    if (!state.navigating) return;
    state = state.copyWith(navigating: false);
    final record = await _tripService.finishAndSave(
      destination: state.selectedPlace?['name'] ?? 'Destino',
      routeCoords: state.routeCoordinates,
      existingTrips: state.trips,
    );
    if (record != null) {
      final newTrips = List<TripRecord>.from(state.trips);
      newTrips.insert(0, record);
      state = state.copyWith(trips: newTrips);
    }
    _tripService.reset();
    await cancelRoute();
  }

  Future<void> selectRoute(int index) async {
    final r = state.alternateRoutes[index];
    final steps = (r['steps'] as List).cast<Map<String, dynamic>>();
    final coords = (r['coords'] as List).map((c) => (c as List).cast<double>()).toList();
    state = state.copyWith(
      selectedRouteIndex: index,
      routeDistance: r['distance'] as String,
      routeDuration: r['duration'] as String,
      routeCoordinates: coords,
      routeSteps: steps,
      currentStepIndex: 0,
      currentInstruction: steps.isNotEmpty ? steps[0]['instruction'] as String : '',
      distanceToNextManeuver: steps.isNotEmpty ? steps[0]['distance'] as double : 0.0,
    );
    if (_mapboxMap != null) {
      await _mapService.highlightRoute(_mapboxMap!, index, state.alternateRoutes.length);
    }
  }

  void _fitRouteBounds(double destLat, double destLng) {
    if (state.currentPosition == null) return;
    final dist = _geo.distanceBetween(
      state.currentPosition!.latitude, state.currentPosition!.longitude,
      destLat, destLng,
    );
    _flyTo(
      lat: (state.currentPosition!.latitude + destLat) / 2,
      lng: (state.currentPosition!.longitude + destLng) / 2,
      zoom: _navService.fitZoom(dist),
      bearing: 0.0,
      pitch: 0.0,
    );
  }

  Future<void> startNavigation() async {
    if (state.navigating) return;
    state = state.copyWith(navigating: true);
    _navService.resetAnnouncements();
    _deviationCount = 0;
    _lastRecalcTime = null;
    await _bgService.start();
    await WakelockPlus.enable();
    _bgService.updateInstruction(
      state.currentInstruction.isNotEmpty
          ? state.currentInstruction
          : 'Iniciando navegacion...',
    );
    if (state.currentPosition != null) {
      _tripService.startTracking(
        state.currentPosition!.latitude,
        state.currentPosition!.longitude,
      );
      _flyTo(
        lat: state.currentPosition!.latitude,
        lng: state.currentPosition!.longitude,
        zoom: 17.0,
        bearing: state.currentPosition!.heading,
        pitch: 50.0,
      );
    }
  }

    Future<void> cancelRoute() async {
      await _clearWaypointAnnotations();
      state = state.copyWith(
        waypoints: const [],
        isSelectingWaypoints: false,
        currentWaypointIndex: 0,
      );
      if (state.navigating) {
        final record = await _tripService.finishAndSave(
          destination: state.selectedPlace?['name'] ?? 'Destino',
          routeCoords: state.routeCoordinates,
          existingTrips: state.trips,
        );
        if (record != null) {
          final newTrips = List<TripRecord>.from(state.trips);
          newTrips.insert(0, record);
          state = state.copyWith(trips: newTrips);
        }
      }
    
      // FIX: Limpiar capas de ruta ANTES de resetear el estado
      if (_mapboxMap != null) {
        await _mapService.clearRouteLayers(_mapboxMap!);
      }
    
      await _deleteDestinationMarker();
      await _tts.stop();
      await _bgService.stop();
      await WakelockPlus.disable();
      _speedLimitService.clearCache();
    
      // FIX: Resetear completamente el estado de ruta
      state = state.copyWith(
        routeDrawn: false,
        navigating: false,
        showTapConfirm: false,
        routeDistance: '',
        routeDuration: '',
        routeCoordinates: const [],
        alternateRoutes: const [],
        routeSteps: const [],
        currentInstruction: '',
        currentStepIndex: 0,
        distanceToNextManeuver: 0.0,
        selectedRouteIndex: 0,
        clearSelectedPlace: true,
        clearTappedLat: true,
        clearTappedLng: true,
        waypoints: const [],
        isSelectingWaypoints: false,
        currentWaypointIndex: 0,
        showWaypointArrival: false,
        waypointArrivalMessage: '',
        speedLimit: null,
        clearSpeedLimit: true,
      );
    }

  void _updateTurnByTurn(double lat, double lng) {
    final update = _navService.updateTurn(
      lat, lng, state.routeSteps, state.currentStepIndex,
    );
    if (update == null) return;
    state = state.copyWith(
      distanceToNextManeuver: update.distanceToManeuver,
      currentStepIndex: update.nextStepIndex,
      currentInstruction: update.nextInstruction,
    );
    if (update.announceText != null) _speak(update.announceText!);
  }

  void _checkRouteDeviation(double lat, double lng) {
    if (!state.navigating || state.routeCoordinates.isEmpty || state.isRecalculating) return;
    if (state.distanceToNextManeuver < 120) return;
    if (_lastRecalcTime != null &&
        DateTime.now().difference(_lastRecalcTime!).inSeconds < 20) return;

    if (_navService.isDeviated(lat, lng, state.routeCoordinates)) {
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
    if (state.selectedPlace == null) return;
    state = state.copyWith(isRecalculating: true);
    _speak('Recalculando ruta');
    _navService.resetAnnouncements();
    _speedLimitService.clearCache();
    _lastSpeedLimitCall = null;
    state = state.copyWith(speedLimit: null, clearSpeedLimit: true);

    final destLat = (state.selectedPlace!['lat'] as num).toDouble();
    final destLng = (state.selectedPlace!['lng'] as num).toDouble();

    await _getRoute(destLat, destLng, fromWaypointIndex: state.currentWaypointIndex);
    state = state.copyWith(isRecalculating: false);
  }

  void _checkWaypointArrival(double lat, double lng) {
    if (state.waypoints.isEmpty) return;
    if (state.showWaypointArrival) return;
    final idx = state.currentWaypointIndex;
    if (idx >= state.waypoints.length) return;
    final wp = state.waypoints[idx];
    final dist = _geo.distanceBetween(
      lat, lng,
      (wp['lat'] as num).toDouble(),
      (wp['lng'] as num).toDouble(),
    );
    if (dist <= 40) {
      final num = wp['index'] as int;
      state = state.copyWith(
        showWaypointArrival: true,
        waypointArrivalMessage: 'Has llegado a la parada $num!',
      );
      state = state.copyWith(currentWaypointIndex: state.currentWaypointIndex + 1);
      _waypointArrivalTimer?.cancel();
      _waypointArrivalTimer = Timer(const Duration(seconds: 4), () {
        state = state.copyWith(
          showWaypointArrival: false,
          waypointArrivalMessage: '',
        );
      });
    }
  }

  void toggleWaypointMode() {
    state = state.copyWith(isSelectingWaypoints: !state.isSelectingWaypoints);
  }

  Future<void> finishWaypointSelection() async {
    state = state.copyWith(isSelectingWaypoints: false);
    if (state.selectedPlace != null) {
      await _getRoute(
        (state.selectedPlace!['lat'] as num).toDouble(),
        (state.selectedPlace!['lng'] as num).toDouble(),
      );
    }
  }

  Future<void> clearWaypointsAndReRoute() async {
    await _clearWaypointAnnotations();
    state = state.copyWith(
      waypoints: const [],
      isSelectingWaypoints: false,
      currentWaypointIndex: 0,
    );
    if (state.selectedPlace != null) {
      await _getRoute(
        (state.selectedPlace!['lat'] as num).toDouble(),
        (state.selectedPlace!['lng'] as num).toDouble(),
      );
    }
  }

  Future<void> _updateSpeedLimit(double lat, double lng) async {
    final speedAtRequest = state.currentSpeed;
    final limit = await _speedLimitService.getSpeedLimit(lat, lng);
    state = state.copyWith(speedLimit: limit);
    final status = SpeedStatus.evaluate(speedAtRequest, limit);
    if (status.level == SpeedAlertLevel.danger) {
      _speak('Exceso de velocidad');
    }
  }

  Future<void> fetchGasolineras() async {
    if (_mapboxMap == null || state.currentPosition == null) return;
    state = state.copyWith(gasolinerasLoading: true);
    try {
      print('[MapController] Buscando gasolineras...');
      final geoJson = await _overpassApi.fetchGasolineras(
        state.currentPosition!.latitude,
        state.currentPosition!.longitude,
      );
      if (geoJson != null) {
        print('[MapController] Gasolineras encontradas, dibujando...');
        await _mapService.updateGasolineraLayer(_mapboxMap!, geoJson);
        state = state.copyWith(gasolinerasVisible: true);
      } else {
        print('[MapController] No se encontraron gasolineras');
      }
    } catch (e) {
      print('[MapController] Error buscando gasolineras: $e');
    }
    state = state.copyWith(gasolinerasLoading: false);
  }

  Future<void> hideGasolineras() async {
    if (_mapboxMap == null) return;
    state = state.copyWith(gasolinerasVisible: false);
    try {
      final style = await _mapboxMap!.style;
      try { await style.removeStyleLayer('gasolineras-layer'); } catch (_) {}
      try { await style.removeStyleLayer('gasolineras-label'); } catch (_) {}
      try { await style.removeStyleSource('gasolineras-source'); } catch (_) {}
    } catch (_) {}
  }

  void toggleGasolineras() {
    if (state.gasolinerasVisible) {
      hideGasolineras();
    } else {
      fetchGasolineras();
    }
  }

  bool _isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 6;
  }

  void _startNightModeTimer() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyNightOrDayStyle());
    _nightModeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _applyNightOrDayStyle(),
    );
  }

  Future<void> _applyNightOrDayStyle() async {
    if (_mapboxMap == null) return;
    if (state.nightModeManual) return;
    final isNight = _isNightTime();
    if (state.isNightMode == isNight) return;
    state = state.copyWith(isNightMode: isNight);
    await _mapboxMap!.loadStyleURI(
      isNight
          ? 'mapbox://styles/mapbox/navigation-night-v1'
          : 'mapbox://styles/mapbox/streets-v12',
    );
    if (!isNight) await _applyCustomRoadStyle();
    await _recreateAnnotationsAfterStyleChange();
  }

  Future<void> toggleNightMode() async {
    final newNight = !state.isNightMode;
    state = state.copyWith(isNightMode: newNight, nightModeManual: true);
    await _mapboxMap?.loadStyleURI(
      newNight
          ? 'mapbox://styles/mapbox/navigation-night-v1'
          : 'mapbox://styles/mapbox/streets-v12',
    );
    if (!newNight) await _applyCustomRoadStyle();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (state.routeDrawn && state.routeCoordinates.isNotEmpty) {
      await _drawRouteOnMap({
        'type': 'LineString',
        'coordinates': state.routeCoordinates,
      });
    }
    await _recreateAnnotationsAfterStyleChange();
  }

  void resetNightModeManual() => state = state.copyWith(nightModeManual: false);

  Future<void> toggleSatellite() async {
    final newValue = !state.isSatellite;
    state = state.copyWith(isSatellite: newValue);
    resetNightModeManual();
    await _mapboxMap?.loadStyleURI(
      newValue
          ? 'mapbox://styles/mapbox/satellite-streets-v12'
          : 'mapbox://styles/mapbox/streets-v12',
    );
    if (!newValue) await _applyCustomRoadStyle();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (state.routeDrawn && state.routeCoordinates.isNotEmpty) {
      await _drawRouteOnMap({
        'type': 'LineString',
        'coordinates': state.routeCoordinates,
      });
    }
    if (state.currentPosition != null && state.gasolinerasVisible) {
      await fetchGasolineras();
    }
    await _recreateAnnotationsAfterStyleChange();
  }

  Future<void> _applyCustomRoadStyle() async {
    if (_mapboxMap == null) return;
    await _mapService.applyCustomRoadStyle(_mapboxMap!);
  }

  Future<void> _recreateAnnotationsAfterStyleChange() async {
    if (_mapboxMap == null) return;
    _annotationManager = await _mapboxMap!.annotations.createPointAnnotationManager();
    _motoAnnotation = null;
    _destinationAnnotation = null;

    if (state.currentPosition != null && state.pinImage != null) {
      await _updateMotoMarker(
        state.currentPosition!.latitude,
        state.currentPosition!.longitude,
        state.currentPosition!.heading,
      );
    }
    if (state.selectedPlace != null && state.pinImage != null) {
      await _addDestinationMarker(
        (state.selectedPlace!['lat'] as num).toDouble(),
        (state.selectedPlace!['lng'] as num).toDouble(),
      );
    }
    if (state.waypoints.isNotEmpty) {
      for (final a in _waypointAnnotations) {
        try { await _annotationManager!.delete(a); } catch (_) {}
      }
      _waypointAnnotations.clear();
      for (final wp in state.waypoints) {
        await _addWaypointAnnotation(
          (wp['lat'] as num).toDouble(),
          (wp['lng'] as num).toDouble(),
          wp['index'] as int,
        );
      }
    }
  }

  Future<void> _loadTrips() async {
    final trips = await _prefs.loadTrips();
    state = state.copyWith(trips: trips);
  }

  void _flyTo({
    required double lat,
    required double lng,
    required double zoom,
    double bearing = 0.0,
    double pitch = 0.0,
    int durationMs = 1000,
  }) {
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
      ),
      mapbox.MapAnimationOptions(duration: durationMs, startDelay: 0),
    );
  }

  void setTabIndex(int i) => state = state.copyWith(currentTabIndex: i);
  void setUserIsExploring(bool v) => state = state.copyWith(userIsExploring: v);
  void setIsProgrammaticMove(bool v) => state = state.copyWith(isProgrammaticMove: v);

  void onCameraChanged() {
    if (!state.isProgrammaticMove) {
      if (!state.userIsExploring) setUserIsExploring(true);
    }
  }

  void recenter() {
    setUserIsExploring(false);
    if (state.currentPosition != null) {
      setIsProgrammaticMove(true);
      _flyTo(
        lat: state.currentPosition!.latitude,
        lng: state.currentPosition!.longitude,
        zoom: _geo.calculateDynamicZoom(state.currentSpeed),
        bearing: state.currentPosition!.heading,
      );
    }
  }
}
