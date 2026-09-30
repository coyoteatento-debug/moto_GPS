import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveLocationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;
  DatabaseReference get _myRef => _db.ref('liveLocations/$_uid');

  bool _sharing = false;
  bool get isSharing => _sharing;

  Future<void> startSharing() async {
    if (_sharing) return;
    _sharing = true;
    // Se borra sola si la app se cierra, pierde conexión o se acaba la batería
    await _myRef.onDisconnect().remove();
  }

  Future<void> stopSharing() async {
    _sharing = false;
    await _myRef.onDisconnect().cancel();
    await _myRef.remove();
  }

  Future<void> updateMyLocation(double lat, double lng, double heading) async {
    if (!_sharing) return;
    await _myRef.set({
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
      return Map<String, dynamic>.from(data as Map);
    });
  }
}
