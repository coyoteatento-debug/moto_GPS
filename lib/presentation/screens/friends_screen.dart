import 'package:flutter/material.dart';
import '../../core/services/friends_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendsService = FriendsService();
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
        ],
      ),
    );
  }
}
