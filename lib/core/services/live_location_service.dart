import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveLocationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;
  DatabaseReference? get _myRef {
    final uid = _uid;
    return uid == null ? null : _db.ref('liveLocations/$uid');
  }

  bool _sharing = false;
  bool get isSharing => _sharing;

  Future<void> startSharing() async {
    if (_sharing) return;
    final ref = _myRef;
    if (ref == null) return; // sin sesión: no hay nada que compartir
    _sharing = true;
    // Se borra sola si la app se cierra, pierde conexión o se acaba la batería
    await ref.onDisconnect().remove();
  }

  Future<void> stopSharing() async {
    _sharing = false;
    final ref = _myRef;
    if (ref == null) return;
    await ref.onDisconnect().cancel();
    await ref.remove();
  }

  Future<void> updateMyLocation(double lat, double lng, double heading) async {
    if (!_sharing) return;
    final ref = _myRef;
    if (ref == null) return;
    await ref.set({
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Stream<Map<String, dynamic>?> watchFriendLocation(String friendUid) {
    return _db.ref('liveLocations/$friendUid').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      final map = Map<String, dynamic>.from(data as Map);
      final updatedAt = map['updatedAt'];
      if (updatedAt is int) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAt;
        if (ageMs > 90000) return null; // más de 90s sin actualizar: se oculta
      }
      return map;
    });
  }
}
