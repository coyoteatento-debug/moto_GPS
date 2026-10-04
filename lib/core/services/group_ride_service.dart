import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class GroupRideService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<String> myUsername() async {
    final uid = _uid;
    if (uid == null) return 'Yo';
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['username'] as String? ?? 'Yo';
  }
  
  Future<String> createRide({
    required String destinationName,
    required double destLat,
    required double destLng,
    required List<String> friendUids,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Debes iniciar sesión para crear una rodada.');

    final myUser = await _db.collection('users').doc(uid).get();
    final myUsername = myUser.data()?['username'] ?? 'Yo';

    final participants = {uid, ...friendUids}.toList();
    final doc = await _db.collection('groupRides').add({
      'hostUid': uid,
      'hostUsername': myUsername,
      'destinationName': destinationName,
      'destLat': destLat,
      'destLng': destLng,
      'participants': participants,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> endRide(String rideId) async {
    await _db.collection('groupRides').doc(rideId).update({'active': false});
    await _rtdb.ref('groupRideStatus/$rideId').remove();
  }

  Stream<Map<String, dynamic>?> myActiveRide() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(null);
      return _db
          .collection('groupRides')
          .where('participants', arrayContains: user.uid)
          .where('active', isEqualTo: true)
          .snapshots()
          .map((snap) {
        if (snap.docs.isEmpty) return null;
        final doc = snap.docs.first;
        return {'id': doc.id, ...doc.data()};
      });
    });
  }

  Future<void> updateMyStatus(
      String rideId, double lat, double lng, String username, bool moved) async {
    final uid = _uid;
    if (uid == null) return;
    final ref = _rtdb.ref('groupRideStatus/$rideId/$uid');
    final updates = <String, Object?>{
      'lat': lat,
      'lng': lng,
      'username': username,
      'updatedAt': ServerValue.timestamp,
    };
    if (moved) updates['lastMovedAt'] = ServerValue.timestamp;
    await ref.update(updates);
  }

  Stream<Map<String, dynamic>> watchRideStatus(String rideId) {
    return _rtdb.ref('groupRideStatus/$rideId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      return Map<String, dynamic>.from(data as Map);
    });
  }
}
