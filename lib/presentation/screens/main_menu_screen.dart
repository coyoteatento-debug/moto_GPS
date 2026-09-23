import 'package:flutter/material.dart';
import 'offline_maps_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Menú principal'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.white70),
            title: const Text('Mapas sin conexión',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Descarga tu zona para usarla sin señal',
                style: TextStyle(color: Colors.white54)),
            trailing:
                const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineMapsScreen()),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Más ajustes próximamente...',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
