import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main() => runApp(const MaterialApp(home: MotoGPSApp()));

class MotoGPSApp extends StatefulWidget {
  const MotoGPSApp({super.key});

  @override
  State<MotoGPSApp> createState() => _MotoGPSAppState();
}

class _MotoGPSAppState extends State<MotoGPSApp> {
  MapboxMap? mapboxMap;
  double _currentSpeed = 0.0;

  double _calculateDynamicZoom(double speed) {
    if (speed < 20) return 16.0; 
    if (speed < 80) return 14.0; 
    return 12.0; 
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
    _startLocationTracking();
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
        mapboxMap?.setCamera(CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)).toJson(),
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
          MapWidget(
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
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                  const Text("km/h", style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}