import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'app.dart';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  if (_mapboxToken.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Error: MAPBOX_TOKEN no configurado.')),
      ),
    ));
    return;
  }

  mapbox.MapboxOptions.setAccessToken(_mapboxToken);
  runApp(const MotoGPSApp());
}
