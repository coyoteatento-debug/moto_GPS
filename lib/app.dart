import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/screens/map_screen.dart';

class MotoGPSApp extends StatelessWidget {
  const MotoGPSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Moto GPS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            surface: Color(0xFF1A1A1A),
          ),
        ),
        home: const MapScreen(),
      ),
    );
  }
}
