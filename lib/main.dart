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

  TripRecord({
    required this.destination,
    required this.distanceKm,
    required this.durationMin,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
    'date': date.toIso8601String(),
  };

  factory TripRecord.fromJson(Map<String, dynamic> j) => TripRecord(
    destination: j['destination'],
    distanceKm: (j['distanceKm'] as num).toDouble(),
    durationMin: j['durationMin'],
    date: DateTime.parse(j['date']),
  );
}

class MotoGPSApp extends StatefulWidget {
  const MotoGPSApp({super.key});
  @override
  State<MotoGPSApp> createState() => _MotoGPSAppState();
}

class _MotoGPSAppState extends State<MotoGPSApp> {

  mapbox.MapboxMap? mapboxMap;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? motoAnnotation;
  mapbox.PointAnnotation? destinationAnnotation;

  Uint8List? pinImage;
  Uint8List? motoImage;

  double _currentSpeed = 0.0;
  Position? _currentPosition;

  Map<String, dynamic>? _selectedPlace;
  bool _routeDrawn = false;
  bool _navigating = false;
  String _routeDistance = '';
  String _routeDuration = '';

  // ── Turn-by-turn ──────────────────────────────────────
  List<Map<String, dynamic>> _routeSteps = [];
  String _currentInstruction = '';
  double _distanceToNextManeuver = 0.0;
  int _currentStepIndex = 0;
  
  bool _showTapConfirm = false;
  double? _tappedLat;
  double? _tappedLng;

  List<List<double>> _routeCoordinates = [];

  bool _userIsExploring   = false;
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
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Imágenes ──────────────────────────────────────────
  Future<Uint8List> _resizeImage(Uint8List data, int targetWidth) async {
    final codec    = await ui.instantiateImageCodec(data, targetWidth: targetWidth);
    final frame    = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _loadImages() async {
    final ByteData pinData  = await rootBundle.load('assets/moto_pin.png');
    final ByteData motoData = await rootBundle.load('assets/moto.png');
    final Uint8List pinResized  = await _resizeImage(pinData.buffer.asUint8List(), 120);
    final Uint8List motoResized = await _resizeImage(motoData.buffer.asUint8List(), 100);
    setState(() { pinImage = pinResized; motoImage = motoResized; });
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

  Future<void> _saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'trip_records',
      json.encode(_trips.map((t) => t.toJson()).toList()),
    );
  }

  void _startTripTracking() {
    _tripStartTime              = DateTime.now();
    _tripAccumulatedDistance    = 0.0;
    _lastTripPosition           = _currentPosition;
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
    final record   = TripRecord(
      destination: _selectedPlace?['name'] ?? 'Destino',
      distanceKm:  double.parse(
          (_tripAccumulatedDistance / 1000).toStringAsFixed(2)),
      durationMin: duration.inMinutes,
      date:        _tripStartTime!,
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
  }

  // ── Estilo de carreteras tipo Riser ───────────────────
  Future<void> _applyCustomRoadStyle() async {
    if (mapboxMap == null) return;
    final style = await mapboxMap!.style;

    final List<Map<String, dynamic>> roadConfig = [
      {
        'layer': 'road-motorway-trunk',
        'color': '#F5820C',
        'width': ['interpolate', ['linear'], ['zoom'], 8, 1.5, 12, 4.0, 16, 10.0, 20, 16.0],
      },
      {
        'layer': 'road-motorway-trunk-case',
        'color': '#C96800',
        'width': ['interpolate', ['linear'], ['zoom'], 8, 2.5, 12, 6.0, 16, 13.0, 20, 20.0],
      },
      {
        'layer': 'road-primary',
        'color': '#FFD600',
        'width': ['interpolate', ['linear'], ['zoom'], 8, 1.0, 12, 3.0, 16, 8.0, 20, 14.0],
      },
      {
        'layer': 'road-primary-case',
        'color': '#D4B000',
        'width': ['interpolate', ['linear'], ['zoom'], 8, 2.0, 12, 5.0, 16, 11.0, 20, 18.0],
      },
      {
        'layer': 'road-secondary-tertiary',
        'color': '#FFE566',
        'width': ['interpolate', ['linear'], ['zoom'], 10, 0.8, 13, 2.0, 16, 6.0, 20, 10.0],
      },
      {
        'layer': 'road-secondary-tertiary-case',
        'color': '#C8B040',
        'width': ['interpolate', ['linear'], ['zoom'], 10, 1.5, 13, 3.5, 16, 8.5, 20, 13.0],
      },
      {
        'layer': 'road-street',
        'color': '#FFFFFF',
        'width': ['interpolate', ['linear'], ['zoom'], 13, 0.5, 16, 3.5, 20, 7.0],
      },
      {
        'layer': 'road-street-low',
        'color': '#FFFFFF',
        'width': ['interpolate', ['linear'], ['zoom'], 13, 0.5, 16, 3.5, 20, 7.0],
      },
      {
        'layer': 'road-street-case',
        'color': '#CCCCCC',
        'width': ['interpolate', ['linear'], ['zoom'], 13, 1.0, 16, 5.5, 20, 10.0],
      },
      {
        'layer': 'road-path',
        'color': '#D9CEBC',
        'width': ['interpolate', ['linear'], ['zoom'], 14, 0.5, 17, 2.0, 20, 4.0],
      },
      {
        'layer': 'road-pedestrian',
        'color': '#EDE8DC',
        'width': ['interpolate', ['linear'], ['zoom'], 14, 0.8, 17, 2.5, 20, 5.0],
      },
    ];

    for (final road in roadConfig) {
      try {
        await style.setStyleLayerProperty(
          road['layer'] as String, 'line-color', json.encode(road['color']),
        );
      } catch (_) {}
      try {
        await style.setStyleLayerProperty(
          road['layer'] as String, 'line-width', json.encode(road['width']),
        );
      } catch (_) {}
    }

    try {
      await style.setStyleLayerProperty(
          'land', 'background-color', json.encode('#F5F0E8'));
    } catch (_) {}
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
      await style.setStyleSourceProperty('route-source', 'data', json.encode({
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': remaining},
      }));
    } catch (_) {}
  }

  void _updateTurnByTurn(double lat, double lng) {
  if (_routeSteps.isEmpty || _currentStepIndex >= _routeSteps.length) return;

  final step     = _routeSteps[_currentStepIndex];
  final loc      = step['location'] as List;
  final stepLng  = (loc[0] as num).toDouble();
  final stepLat  = (loc[1] as num).toDouble();
  final distToManeuver = _distanceBetween(lat, lng, stepLat, stepLng);

  setState(() => _distanceToNextManeuver = distToManeuver);

  // Avanza al siguiente paso si estás a menos de 30 m
  if (distToManeuver < 30 && _currentStepIndex < _routeSteps.length - 1) {
    _currentStepIndex++;
    final next = _routeSteps[_currentStepIndex];
    setState(() {
      _currentInstruction     = next['instruction'] as String;
      _distanceToNextManeuver = next['distance'] as double;
    });
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
    if (annotationManager == null || motoImage == null) return;
    if (motoAnnotation == null) {
      motoAnnotation = await annotationManager!.create(mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        image: motoImage, iconSize: 1.2,
        iconAnchor: mapbox.IconAnchor.CENTER, iconRotate: bearing,
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

  // ── GPS Tracking ──────────────────────────────────────
  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 2),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() { _currentSpeed = position.speed * 3.6; _currentPosition = position; });

      if (!_initialLocationSet) {
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
        Future.delayed(const Duration(milliseconds: 2000), () {
          _fetchGasolineras(position.latitude, position.longitude);
        });
        return;
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
        _updateMotoMarker(snappedLat, snappedLng, bearing);
        _accumulateTripDistance(position);
        _updateRemainingRoute(position.latitude, position.longitude);
        _updateTurnByTurn(position.latitude, position.longitude);
        mapboxMap?.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(snappedLng, snappedLat)),
            zoom: 17.0, bearing: bearing, pitch: 50.0,
          ),
          mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
        );
      } else {
        _updateMotoMarker(position.latitude, position.longitude, position.heading);
        if (!_routeDrawn && !_showTapConfirm && !_userIsExploring) {
          _isProgrammaticMove = true;
          mapboxMap?.setCamera(mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(
                position.longitude, position.latitude)),
            zoom: _calculateDynamicZoom(_currentSpeed),
            bearing: position.heading,
          ));
        }
      }
    });
  }

  // ── Gasolineras ───────────────────────────────────────
  Future<void> _fetchGasolineras(double lat, double lng) async {
    if (mapboxMap == null) return;
    const double radius = 8000;
    final query =
        '[out:json][timeout:25];\n'
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
        '?geometries=geojson&access_token=$_mapboxToken&language=es&overview=full',
      ));
      if (response.statusCode == 200) {
        final data   = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isEmpty) return;
        final route    = routes[0];
        final geometry = route['geometry'];
        final coords   = (geometry['coordinates'] as List)
            .map((c) => [c[0] as double, c[1] as double]).toList();
        setState(() {
          _routeDistance    = '${((route['distance'] as double)/1000).toStringAsFixed(1)} km';
          _routeDuration    = '${((route['duration'] as double)/60).round()} min';
          _routeDrawn       = true;
          _routeCoordinates = coords;
        });
        await _drawRouteOnMap(geometry);
        _fitRouteBounds(destLat, destLng);
      }
    } catch (_) {}
  }

  Future<void> _drawRouteOnMap(Map<String, dynamic> geometry) async {
    final style = await mapboxMap!.style;
    try { await style.removeStyleLayer('route-layer');  } catch (_) {}
    try { await style.removeStyleSource('route-source'); } catch (_) {}
    await style.addSource(mapbox.GeoJsonSource(
        id: 'route-source',
        data: json.encode({'type': 'Feature', 'geometry': geometry})));
    await style.addLayer(mapbox.LineLayer(
      id: 'route-layer', sourceId: 'route-source',
      lineColor: 0xFF1976D2, lineWidth: 6.0,
      lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
    ));
  }

  void _fitRouteBounds(double destLat, double destLng) {
    if (_currentPosition == null) return;
    mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(
          (_currentPosition!.longitude + destLng) / 2,
          (_currentPosition!.latitude  + destLat) / 2,
        )),
        zoom: 12.0, bearing: 0.0, pitch: 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 1500, startDelay: 0),
    );
  }

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
    setState(() {
      _selectedPlace = null; _routeDrawn = false; _navigating = false;
      _showTapConfirm = false; _tappedLat = null; _tappedLng = null;
      _routeDistance = ''; _routeDuration = ''; _routeCoordinates = [];
    });
  }

_routeSteps = (route['legs'][0]['steps'] as List)
    .map((s) => {
          'instruction': (s['maneuver']['instruction'] as String?) ?? '',
          'distance':    (s['distance'] as num).toDouble(),
          'location':    s['maneuver']['location'] as List,
        })
    .toList();
_currentStepIndex   = 0;
_currentInstruction = _routeSteps.isNotEmpty
    ? _routeSteps[0]['instruction'] as String
    : '';
_distanceToNextManeuver = _routeSteps.isNotEmpty
    ? _routeSteps[0]['distance'] as double
    : 0.0;
  
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
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trip.destination,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _tripStat(Icons.straighten,
                                '${trip.distanceKm} km', Colors.blue),
                            const SizedBox(width: 20),
                            _tripStat(Icons.timer_outlined,
                                '${trip.durationMin} min', Colors.orange),
                            const Spacer(),
                            Text(dateStr,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _tripStat(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
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
              onTap: (i) => setState(() => _currentTabIndex = i),
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
      body: _currentTabIndex == 1
          ? _buildTripBook()
          : Stack(
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
                                _currentPosition!.longitude,
                                _currentPosition!.latitude,
                              )),
                              zoom: _calculateDynamicZoom(_currentSpeed),
                              bearing: _currentPosition!.heading,
                              pitch: 0.0,
                            ),
                            mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
                          );
                        }
                      },
                      child: Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 8,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.my_location,
                            color: Colors.white, size: 22),
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
                            color: Colors.black26, blurRadius: 10,
                            offset: Offset(0, 4))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.red, size: 32),
                          const SizedBox(height: 8),
                          const Text('¿Ir a este lugar?',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            'Lat: ${_tappedLat?.toStringAsFixed(5)}  '
                            'Lng: ${_tappedLng?.toStringAsFixed(5)}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _cancelTap,
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  label: const Text('Cancelar',
                                      style: TextStyle(color: Colors.red)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _confirmTappedDestination,
                                  icon: const Icon(Icons.directions,
                                      color: Colors.white),
                                  label: const Text('Trazar ruta',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
                            color: Colors.black26, blurRadius: 10,
                            offset: Offset(0, 4))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedPlace?['name'] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions_bike,
                                  color: Colors.blue, size: 18),
                              const SizedBox(width: 6),
                              Text('$_routeDistance  •  $_routeDuration',
                                  style: TextStyle(
                                      color: Colors.grey[700], fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _cancelRoute,
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  label: const Text('Cancelar',
                                      style: TextStyle(color: Colors.red)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _startNavigation,
                                  icon: const Icon(Icons.navigation,
                                      color: Colors.white),
                                  label: const Text('¡Ir!',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
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
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Text('km/h',
                                  style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _cancelRoute,
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text('Salir',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
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
          const Icon(Icons.navigation, color: Colors.white, size: 32),
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
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold),
                          ),
                          const Text('km/h',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),

              ],
            ),
    );
  }
}
