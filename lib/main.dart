import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/background_gps_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_map_service.dart';
import 'widgets/permission_gate.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  await OfflineMapService.initialize();
  await ConnectivityService.initialize();
  await BackgroundGpsService.initialize();

  runApp(const MotoGpsApp());
}

class MotoGpsApp extends StatelessWidget {
  const MotoGpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoGPS',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const PermissionGate(
        child: MapScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Colors.orange,
        secondary: Colors.orangeAccent,
        surface: Color(0xFF1A1A1A),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
