import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/background_gps_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_map_service.dart';
import 'widgets/permission_gate.dart';
import 'screens/map_screen.dart';

// ═══════════════════════════════════════════════════════
// PUNTO DE ENTRADA
// Orden de inicialización es CRÍTICO:
//  1. WidgetsFlutterBinding
//  2. OfflineMapService  (necesita filesystem listo)
//  3. ConnectivityService
//  4. BackgroundGpsService
//  5. runApp
// ═══════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación libre (portrait en config, landscape en moto)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Forzar tema oscuro a nivel de sistema (barra de estado)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Inicializar servicios en orden
  await OfflineMapService.initialize();
  await ConnectivityService.initialize();
  await BackgroundGpsService.initialize();

  runApp(const MotoGpsApp());
}

// ═══════════════════════════════════════════════════════
// APP RAÍZ
// ═══════════════════════════════════════════════════════
class MotoGpsApp extends StatelessWidget {
  const MotoGpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoGPS',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      // PermissionGate bloquea la app hasta tener todos los permisos
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
        background: Color(0xFF0D0D0D),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.white),
        bodySmall: TextStyle(color: Colors.white70),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    );
  }
}
