import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;

const String _mapboxToken =
    "pk.eyJ1IjoiY295b3RlYXRlbnRvMjIiLCJhIjoiY21tejd3MjNvMDViOTJycTRhajIyejM4MCJ9.eevGvjW-uA4r3VtYWRliaQ";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  mapbox.MapboxOptions.setAccessToken(_mapboxToken);
  runApp(const MaterialApp(home: MotoGPSApp()));
}

class PlaceItem {
  final String name;
  final double lat;
  final double lng;
  PlaceItem({required this.name, required this.lat, required this.lng});
  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};
  factory PlaceItem.fromJson(Map<String, dynamic> j) =>
      PlaceItem(name: j['name'], lat: j['lat'], lng: j['lng']);
}

class PlaceList {
  String id;
  String name;
  String emoji;
  List<PlaceItem> places;
  PlaceList({required this.id, required this.name, required this.emoji, required this.places});
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'emoji': emoji,
        'places': places.map((p) => p.toJson()).toList(),
      };
  factory PlaceList.fromJson(Map<String, dynamic> j) => PlaceList(
        id: j['id'], name: j['name'], emoji: j['emoji'] ?? '📍',
        places: (j['places'] as List).map((p) => PlaceItem.fromJson(p)).toList(),
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

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  Map<String, dynamic>? _selectedPlace;
  bool _routeDrawn = false;
  bool _navigating = false;
  String _routeDistance = '';
  String _routeDuration = '';

  bool _showTapConfirm = false;
  double? _tappedLat;
  double? _tappedLng;

  List<List<double>> _routeCoordinates = [];
  List<PlaceList> _placeLists = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _poisVisible = true;
  bool _poiLoading  = false;
  String _currentCity = '';
  mapbox.CoordinateBounds? _lastFetchedBounds;

  static const List<Map<String, String>> _poiCategories = [
    {'id': 'fuel',        'query': 'amenity=fuel',        'icon': 'fuel',       'label': 'Gasolineras'},
    {'id': 'restaurant',  'query': 'amenity=restaurant',  'icon': 'restaurant', 'label': 'Restaurantes'},
    {'id': 'hotel',       'query': 'tourism=hotel',       'icon': 'lodging',    'label': 'Hoteles'},
    {'id': 'mall',        'query': 'shop=mall',           'icon': 'shop',       'label': 'Centros comerciales'},
    {'id': 'marketplace', 'query': 'amenity=marketplace', 'icon': 'shop',       'label': 'Plazas comerciales'},
    {'id': 'hospital',    'query': 'amenity=hospital',    'icon': 'hospital',   'label': 'Hospitales'},
  ];

  @override
  void initState() {
    super.initState();
    _loadImages();
    _requestPermissions();
    _loadLists();
  }

  @override
  void dispose() {
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

  Future<void> _loadImages() async {
    final ByteData pinData  = await rootBundle.load('assets/moto_pin.png');
    final ByteData motoData = await rootBundle.load('assets/moto.png');
    final Uint8List pinResized  = await _resizeImage(pinData.buffer.asUint8List(), 120);
    final Uint8List motoResized = await _resizeImage(motoData.buffer.asUint8List(), 100);
    setState(() { pinImage = pinResized; motoImage = motoResized; });
  }

  // ── Listas ────────────────────────────────────────────
  Future<void> _loadLists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('place_lists');
    if (raw != null) {
      final data = json.decode(raw) as List;
      setState(() { _placeLists = data.map((e) => PlaceList.fromJson(e)).toList(); });
    }
  }

  Future<void> _saveLists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('place_lists',
        json.encode(_placeLists.map((l) => l.toJson()).toList()));
  }

  void _createList() {
    final nameController = TextEditingController();
    String selectedEmoji = '📍';
    final emojis = ['📍','⛽','🍽️','🏨','🏍️','🌄','🔧','🎯','⭐','🗺️'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nueva lista'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Nombre de la lista', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Elige un emoji:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: emojis.map((e) => GestureDetector(
                  onTap: () => setS(() => selectedEmoji = e),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: selectedEmoji == e ? Colors.blue[100] : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selectedEmoji == e ? Colors.blue : Colors.transparent),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                setState(() {
                  _placeLists.add(PlaceList(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    emoji: selectedEmoji,
                    places: [],
                  ));
                });
                _saveLists();
                Navigator.pop(ctx);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _addPlaceToList(PlaceItem place) {
    if (_placeLists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Primero crea una lista'),
        action: SnackBarAction(label: 'Crear', onPressed: _createList),
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar a lista'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _placeLists.length,
            itemBuilder: (_, i) {
              final list = _placeLists[i];
              return ListTile(
                leading: Text(list.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(list.name),
                subtitle: Text('${list.places.length} lugares'),
                onTap: () {
                  final exists = list.places.any((p) => p.name == place.name);
                  if (exists) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Este lugar ya está en la lista')));
                    return;
                  }
                  setState(() => list.places.add(place));
                  _saveLists();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ Agregado a "${list.name}"')));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
  }

  void _openList(PlaceList list) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceListScreen(
          placeList: list,
          onNavigate: (place) { Navigator.pop(context); _goToPlace(place.lat, place.lng, place.name); },
          onDelete:   (place) { setState(() => list.places.remove(place)); _saveLists(); },
          onShare:    () => _shareList(list),
          onDeleteList: () { setState(() => _placeLists.remove(list)); _saveLists(); Navigator.pop(context); },
        ),
      ),
    );
  }

  void _shareList(PlaceList list) async {
    final buffer = StringBuffer();
    buffer.writeln('${list.emoji} ${list.name} — MotoGPS\n');
    for (final place in list.places) {
      buffer.writeln('📍 ${place.name}');
      buffer.writeln('https://maps.google.com/?q=${place.lat},${place.lng}\n');
    }
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📋 Lista copiada al portapapeles')));
    }
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
  }

  // ── POIs ──────────────────────────────────────────────
  Future<void> _detectAndLoadCityPOIs() async {
    if (!_poisVisible || mapboxMap == null || _poiLoading) return;
    try {
      final cameraState = await mapboxMap!.getCameraState();
      final bounds = await mapboxMap!.coordinateBoundsForCamera(
        mapbox.CameraOptions(
          center:  cameraState.center,
          zoom:    cameraState.zoom,
          bearing: cameraState.bearing,
          pitch:   cameraState.pitch,
        ),
      );
      if (_lastFetchedBounds != null && _boundsAreSimilar(bounds, _lastFetchedBounds!)) return;
      _lastFetchedBounds = bounds;
      setState(() => _poiLoading = true);
      final swLat = bounds.southwest.coordinates.lat.toDouble();
      final swLng = bounds.southwest.coordinates.lng.toDouble();
      final neLat = bounds.northeast.coordinates.lat.toDouble();
      final neLng = bounds.northeast.coordinates.lng.toDouble();
      if (_currentPosition != null) {
        await _detectCurrentCity(_currentPosition!.latitude, _currentPosition!.longitude);
      }
      await _fetchPOIsForBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _poiLoading = false);
    }
  }

  bool _boundsAreSimilar(mapbox.CoordinateBounds a, mapbox.CoordinateBounds b) {
    const t = 0.01;
    return (a.southwest.coordinates.lat.toDouble() - b.southwest.coordinates.lat.toDouble()).abs() < t &&
           (a.southwest.coordinates.lng.toDouble() - b.southwest.coordinates.lng.toDouble()).abs() < t &&
           (a.northeast.coordinates.lat.toDouble() - b.northeast.coordinates.lat.toDouble()).abs() < t &&
           (a.northeast.coordinates.lng.toDouble() - b.northeast.coordinates.lng.toDouble()).abs() < t;
  }

  Future<void> _detectCurrentCity(double lat, double lng) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?types=place&access_token=$_mapboxToken&language=es&limit=1',
      ));
      if (response.statusCode == 200) {
        final features = (json.decode(response.body)['features'] as List);
        if (features.isNotEmpty && mounted) {
          final city = features[0]['text'] as String;
          if (city != _currentCity) {
            setState(() => _currentCity = city);
            _lastFetchedBounds = null;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchPOIsForBounds({
    required double swLat, required double swLng,
    required double neLat, required double neLng,
  }) async {
    final bbox = '$swLat,$swLng,$neLat,$neLng';
    await Future.wait(_poiCategories.map((category) async {
      final query = '[out:json][timeout:25];\n(\n'
          '  node[${category['query']}]($bbox);\n'
          '  way[${category['query']}]($bbox);\n'
          '  relation[${category['query']}]($bbox);\n'
          ');\nout center;\n';
      try {
        final response = await http.post(
            Uri.parse('https://overpass-api.de/api/interpreter'), body: query);
        if (response.statusCode != 200) return;
        final elements = (json.decode(response.body)['elements'] as List);
        final features = elements.map((e) {
          final pLat = e['type'] == 'node' ? e['lat'] as double : (e['center']?['lat'] as double? ?? 0.0);
          final pLng = e['type'] == 'node' ? e['lon'] as double : (e['center']?['lon'] as double? ?? 0.0);
          return {
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [pLng, pLat]},
            'properties': {
              'name': (e['tags']?['name'] as String?) ?? category['label']!,
              'category': category['id'],
            },
          };
        }).toList();
        await _updatePoiLayer(
          sourceId: 'poi-${category['id']}-source',
          layerId:  'poi-${category['id']}-layer',
          iconName: category['icon']!,
          geoJson:  json.encode({'type': 'FeatureCollection', 'features': features}),
        );
      } catch (_) {}
    }));
  }

  Future<void> _updatePoiLayer({
    required String sourceId, required String layerId,
    required String iconName, required String geoJson,
  }) async {
    if (mapboxMap == null) return;
    try {
      final style = await mapboxMap!.style;
      try { await style.removeStyleLayer(layerId);  } catch (_) {}
      try { await style.removeStyleSource(sourceId); } catch (_) {}
      await style.addSource(mapbox.GeoJsonSource(id: sourceId, data: geoJson));
      await style.addLayer(mapbox.SymbolLayer(
        id: layerId, sourceId: sourceId,
        iconImage: iconName, iconSize: 1.2, iconAllowOverlap: false,
        textField: '{name}', textSize: 10.0,
        textOffset: [0.0, 1.8], textAllowOverlap: false, textOptional: true,
      ));
    } catch (_) {}
  }

  Future<void> _clearPOIs() async {
    if (mapboxMap == null) return;
    try {
      final style = await mapboxMap!.style;
      for (final c in _poiCategories) {
        try { await style.removeStyleLayer('poi-${c['id']}-layer');  } catch (_) {}
        try { await style.removeStyleSource('poi-${c['id']}-source'); } catch (_) {}
      }
      _lastFetchedBounds = null;
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
    final x = cos(lat1*pi/180)*sin(lat2*pi/180) - sin(lat1*pi/180)*cos(lat2*pi/180)*cos(dLng);
    return (atan2(y, x)*180/pi + 360) % 360;
  }

  Future<void> _updateRemainingRoute(double lat, double lng) async {
    if (!_navigating || _routeCoordinates.isEmpty || mapboxMap == null) return;
    final idx = _findClosestPointIndex(lat, lng);
    if (idx >= _routeCoordinates.length - 2) {
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

  // ── Tap mapa ──────────────────────────────────────────
  void _onMapTap(mapbox.MapContentGestureContext context) {
    if (_navigating) return;
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();
    setState(() { _tappedLat = lat; _tappedLng = lng; _showTapConfirm = true; _searchResults = []; });
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
      _searchController.text = placeName;
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
        _updateRemainingRoute(position.latitude, position.longitude);
        mapboxMap?.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(snappedLng, snappedLat)),
            zoom: 17.0, bearing: bearing, pitch: 50.0,
          ),
          mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
        );
      } else {
        _updateMotoMarker(position.latitude, position.longitude, position.heading);
        if (!_routeDrawn && !_showTapConfirm) {
          mapboxMap?.setCamera(mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(position.longitude, position.latitude)),
            zoom: _calculateDynamicZoom(_currentSpeed),
            bearing: position.heading,
          ));
        }
      }
    });
  }

  // ── Búsqueda con bias de posición ─────────────────────
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    String url;
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      const double offset = 0.45;
      url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/'
            '${Uri.encodeComponent(query)}.json'
            '?access_token=$_mapboxToken&language=es&limit=6'
            '&proximity=$lng,$lat'
            '&bbox=${lng-offset},${lat-offset},${lng+offset},${lat+offset}';
    } else {
      url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/'
            '${Uri.encodeComponent(query)}.json'
            '?access_token=$_mapboxToken&language=es&limit=6';
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final features = json.decode(response.body)['features'] as List;
        setState(() {
          _searchResults = features.map((f) {
            final resLng = f['center'][0] as double;
            final resLat = f['center'][1] as double;
            double? distKm;
            if (_currentPosition != null) {
              distKm = _distanceBetween(
                  _currentPosition!.latitude, _currentPosition!.longitude,
                  resLat, resLng) / 1000;
            }
            return {
              'name':    f['place_name'] as String,
              'short':   f['text'] as String,
              'lng':     resLng,
              'lat':     resLat,
              'distKm':  distKm,
            };
          }).toList();
        });
      }
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

  void _goToPlace(double lat, double lng, String name) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _searchResults = []; _searchController.text = name;
      _selectedPlace = {'name': name, 'lat': lat, 'lng': lng};
      _routeDrawn = false; _navigating = false;
      _showTapConfirm = false; _routeCoordinates = [];
    });
    FocusScope.of(context).unfocus();
    await _addDestinationMarker(lat, lng);
    await _getRoute(lat, lng);
  }

  Future<void> _cancelRoute() async {
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
      _searchController.clear();
    });
  }

  void _startNavigation() {
    setState(() => _navigating = true);
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

  // ── BUILD ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.blue[700]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('🏍️ MotoGPS',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Mis listas de lugares',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: _placeLists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('📭', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            const Text('No tienes listas aún',
                                style: TextStyle(color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                                onPressed: _createList,
                                icon: const Icon(Icons.add),
                                label: const Text('Crear lista')),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _placeLists.length,
                        itemBuilder: (_, i) {
                          final list = _placeLists[i];
                          return ListTile(
                            leading: Text(list.emoji, style: const TextStyle(fontSize: 28)),
                            title: Text(list.name,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${list.places.length} lugar${list.places.length == 1 ? '' : 'es'}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: const Icon(Icons.share, color: Colors.blue, size: 20),
                                    onPressed: () => _shareList(list)),
                                const Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                            onTap: () => _openList(list),
                          );
                        },
                      ),
              ),
              if (_placeLists.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _createList,
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva lista'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [

          // ── Mapa ────────────────────────────────────
          SizedBox.expand(
            child: mapbox.MapWidget(
              key: const ValueKey("mapWidget"),
              onMapCreated: _onMapCreated,
              styleUri: mapbox.MapboxStyles.STANDARD,
              onTapListener: _onMapTap,
              cameraOptions: mapbox.CameraOptions(zoom: 15.0, pitch: 0.0),
              onCameraChangeListener: (state) async {
                if (_poisVisible && !_poiLoading) {
                  await _detectAndLoadCityPOIs();
                }
              },
            ),
          ),

          // ── Botón menú ───────────────────────────────
          if (!_navigating)
            Positioned(
              top: 50, left: 16,
              child: GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: const Icon(Icons.menu, color: Colors.black87),
                ),
              ),
            ),

          // ── Botón POIs ───────────────────────────────
          if (!_navigating)
            Positioned(
              top: 108, left: 16,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () async {
                      setState(() => _poisVisible = !_poisVisible);
                      if (_poisVisible) {
                        _lastFetchedBounds = null;
                        await _detectAndLoadCityPOIs();
                      } else {
                        await _clearPOIs();
                      }
                    },
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: _poisVisible ? Colors.blue[700] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: _poiLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.place,
                              color: _poisVisible ? Colors.white : Colors.black54),
                    ),
                  ),
                  if (_currentCity.isNotEmpty && _poisVisible)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(_currentCity,
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                ],
              ),
            ),

          // ── Barra de búsqueda ────────────────────────
          if (!_navigating)
            Positioned(
              top: 50, left: 72, right: 16,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _searchPlaces,
                      decoration: InputDecoration(
                        hintText: '🔍  Buscar lugar...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: _cancelRoute)
                            : const Icon(Icons.search, color: Colors.grey),
                      ),
                    ),
                  ),

                  // ── Resultados de búsqueda ───────────
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place   = _searchResults[index];
                          final distKm  = place['distKm'] as double?;
                          final distText = distKm == null ? ''
                              : distKm < 1
                                  ? '${(distKm * 1000).toStringAsFixed(0)} m'
                                  : '${distKm.toStringAsFixed(1)} km';
                          return ListTile(
                            leading: const Icon(Icons.location_on, color: Colors.blue),
                            title: Text(
                              place['short'] ?? place['name'],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              place['name'],
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (distText.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(distText,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue[700],
                                            fontWeight: FontWeight.w600)),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.bookmark_add_outlined, color: Colors.orange),
                                  onPressed: () => _addPlaceToList(PlaceItem(
                                      name: place['name'], lat: place['lat'], lng: place['lng'])),
                                ),
                              ],
                            ),
                            onTap: () => _goToPlace(place['lat'], place['lng'], place['name']),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // ── Confirmar tap ────────────────────────────
          if (_showTapConfirm && !_navigating)
            Positioned(
              bottom: 30, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 32),
                    const SizedBox(height: 8),
                    const Text('¿Ir a este lugar?',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Lat: ${_tappedLat?.toStringAsFixed(5)}  Lng: ${_tappedLng?.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
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

          // ── Panel ruta ───────────────────────────────
          if (_routeDrawn && !_navigating && !_showTapConfirm)
            Positioned(
              bottom: 30, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedPlace?['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
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
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        if (_selectedPlace != null) {
                          _addPlaceToList(PlaceItem(
                              name: _selectedPlace!['name'],
                              lat:  _selectedPlace!['lat'],
                              lng:  _selectedPlace!['lng']));
                        }
                      },
                      icon: const Icon(Icons.bookmark_add_outlined, color: Colors.orange),
                      label: const Text('Guardar en lista',
                          style: TextStyle(color: Colors.orange)),
                    ),
                    const SizedBox(height: 6),
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
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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

          // ── Panel navegando ──────────────────────────
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
                        color: Colors.black87, borderRadius: BorderRadius.circular(15)),
                    child: Column(
                      children: [
                        Text('${_currentSpeed.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
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

          // ── Velocímetro modo libre ───────────────────
          if (!_navigating && !_routeDrawn && !_showTapConfirm)
            Positioned(
              bottom: 30, left: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.black87, borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text('${_currentSpeed.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                    const Text('km/h', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),

        ],
      ),
    );
  }
}

// ── PlaceListScreen ───────────────────────────────────────
class PlaceListScreen extends StatefulWidget {
  final PlaceList placeList;
  final Function(PlaceItem) onNavigate;
  final Function(PlaceItem) onDelete;
  final VoidCallback onShare;
  final VoidCallback onDeleteList;

  const PlaceListScreen({
    super.key,
    required this.placeList,
    required this.onNavigate,
    required this.onDelete,
    required this.onShare,
    required this.onDeleteList,
  });

  @override
  State<PlaceListScreen> createState() => _PlaceListScreenState();
}

class _PlaceListScreenState extends State<PlaceListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.placeList.emoji} ${widget.placeList.name}'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: widget.onShare),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Eliminar lista'),
                content: Text('¿Eliminar "${widget.placeList.name}"? Esta acción no se puede deshacer.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  ElevatedButton(
                    onPressed: () { Navigator.pop(context); widget.onDeleteList(); },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: widget.placeList.places.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('📭', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('No hay lugares en esta lista',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('Busca un lugar en el mapa y toca 🔖 para guardarlo aquí',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
              ),
            )
          : ListView.separated(
              itemCount: widget.placeList.places.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final place = widget.placeList.places[i];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.location_on, color: Colors.white, size: 18),
                  ),
                  title: Text(place.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${place.lat.toStringAsFixed(4)}, ${place.lng.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.navigation, color: Colors.blue),
                          onPressed: () => widget.onNavigate(place)),
                      IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setState(() => widget.onDelete(place))),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
