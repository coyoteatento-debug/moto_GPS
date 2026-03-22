import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // ✅ Token de Mapbox para mostrar el mapa
  mapbox.MapboxOptions.setAccessToken(
    "pk.eyJ1IjoiY295b3RlYXRlbnRvMjIiLCJhIjoiY21tejd3MjNvMDViOTJycTRhajIyejM4MCJ9.eevGvjW-uA4r3VtYWRliaQ"
  );
  runApp(const MaterialApp(home: MotoGPSApp()));
}

class MotoGPSApp extends StatefulWidget {
  const MotoGPSApp({super.key});
  @override
  State<MotoGPSApp> createState() => _MotoGPSAppState();
}

class _MotoGPSAppState extends State<MotoGPSApp> {
  mapbox.MapboxMap? mapboxMap;
  double _currentSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();  // ✅ Pedir permisos al iniciar
  }

  // ✅ Solicitar permisos de ubicación
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

  void _onMapCreated(mapbox.MapboxMap map) {
    mapboxMap = map;
  }

  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentSpeed = position.speed * 3.6;
        });
        mapboxMap?.setCamera(mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              position.longitude,
              position.latitude,
            ),
          ),
          zoom: _calculateDynamicZoom(_currentSpeed),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          mapbox.MapWidget(
            key: const ValueKey("mapWidget"),
            onMapCreated: _onMapCreated,
          ),
          Positioned(
            bottom: 30,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  Text(
                    "${_currentSpeed.toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text("km/h",
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
