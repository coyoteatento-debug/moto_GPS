import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/friends_service.dart';
import '../../core/services/group_ride_service.dart';
import '../../data/models/saved_place.dart';
import '../controllers/map_controller.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _friendsService = FriendsService();
  final _groupRideService = GroupRideService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final results = await _friendsService.searchUsers(_searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _sendRequest(Map<String, dynamic> user) async {
    final error = await _friendsService.sendRequest(user['uid'], user['username']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Solicitud enviada a ${user['username']}'),
    ));
  }

  void _showStartRideDialog() {
    final savedPlaces = ref.read(mapControllerProvider).savedPlaces;
    if (savedPlaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Primero guarda un lugar favorito desde el mapa.'),
      ));
      return;
    }
    SavedPlaceRecord? selectedPlace;
    final selectedFriends = <String, String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Iniciar rodada en grupo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Destino:'),
                DropdownButton<SavedPlaceRecord>(
                  isExpanded: true,
                  value: selectedPlace,
                  hint: const Text('Elige un lugar guardado'),
                  items: savedPlaces
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                      .toList(),
                  onChanged: (p) => setDialogState(() => selectedPlace = p),
                ),
                const SizedBox(height: 16),
                const Text('Invitar a:'),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _friendsService.myFriends(),
                  builder: (context, snapshot) {
                    final friends = snapshot.data ?? [];
                    if (friends.isEmpty) {
                      return const Text('No tienes amigos agregados todavía.',
                          style: TextStyle(color: Colors.grey));
                    }
                    return Column(
                      children: friends.map((f) {
                        final uid = f['uid'] as String;
                        final username = f['username'] as String? ?? 'Amigo';
                        return CheckboxListTile(
                          title: Text(username),
                          value: selectedFriends.containsKey(uid),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selectedFriends[uid] = username;
                            } else {
                              selectedFriends.remove(uid);
                            }
                          }),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedPlace == null || selectedFriends.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Elige un destino y al menos un amigo.'),
                  ));
                  return;
                }
                await _groupRideService.createRide(
                  destinationName: selectedPlace!.name,
                  destLat: selectedPlace!.lat,
                  destLng: selectedPlace!.lng,
                  friendUids: selectedFriends.keys.toList(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('GPS Interconectado'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre de usuario',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.blue),
                onPressed: _search,
              ),
            ],
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          ..._searchResults.map((u) => Card(
                color: Colors.grey[900],
                child: ListTile(
                  title: Text(u['username'] ?? '',
                      style: const TextStyle(color: Colors.white)),
                  trailing: TextButton(
                    onPressed: () => _sendRequest(u),
                    child: const Text('Agregar'),
                  ),
                ),
              )),
          const SizedBox(height: 24),
          const Text('Solicitudes recibidas',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _friendsService.incomingRequests(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              if (requests.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No tienes solicitudes pendientes.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: requests
                    .map((r) => Card(
                          color: Colors.grey[900],
                          child: ListTile(
                            title: Text(r['fromUsername'] ?? '',
                                style: const TextStyle(color: Colors.white)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  onPressed: () => _friendsService.acceptRequest(
                                      r['id'], r['fromUid'], r['fromUsername']),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () =>
                                      _friendsService.rejectRequest(r['id']),
                                ),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Mis amigos',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _friendsService.myFriends(),
            builder: (context, snapshot) {
              final friends = snapshot.data ?? [];
              if (friends.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aún no tienes amigos agregados.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: friends
                    .map((f) => Card(
                          color: Colors.grey[900],
                          child: ListTile(
                            leading: const Icon(Icons.person, color: Colors.blue),
                            title: Text(f['username'] ?? '',
                                style: const TextStyle(color: Colors.white)),
                            trailing: IconButton(
                              icon: const Icon(Icons.person_remove,
                                  color: Colors.redAccent),
                              onPressed: () =>
                                  _friendsService.removeFriend(f['uid']),
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showStartRideDialog,
              icon: const Icon(Icons.groups),
              label: const Text('Iniciar rodada en grupo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
