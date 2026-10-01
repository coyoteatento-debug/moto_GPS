import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'offline_maps_screen.dart';
import 'friends_screen.dart';
import 'auth_screen.dart';
import '../../core/services/auth_service.dart';

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
          ListTile(
            leading: const Icon(Icons.people_outline, color: Colors.white70),
            title: const Text('GPS Interconectado',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Ve a tus amigos en el mapa',
                style: TextStyle(color: Colors.white54)),
            trailing:
                const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () async {
              if (FirebaseAuth.instance.currentUser == null) {
                final loggedIn = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
                if (loggedIn != true) return; // canceló el login
              }
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                );
              }
            },
          ),
          const Divider(color: Colors.white24, height: 1),
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) {
                return ListTile(
                  leading: const Icon(Icons.login, color: Colors.white70),
                  title: const Text('Iniciar sesión',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Solo necesario para GPS Interconectado',
                      style: TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  ),
                );
              }
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    user.email ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Cerrar sesión',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: const Text('Cerrar sesión',
                            style: TextStyle(color: Colors.white)),
                        content: const Text(
                            '¿Seguro que quieres cerrar sesión?',
                            style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Cerrar sesión',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await AuthService().logout();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }
                  },
                ),
              ]);
            },
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
