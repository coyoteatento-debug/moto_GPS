import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FriendsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final snap = await _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: q)
        .where('usernameLower', isLessThan: '$q\uf8ff')
        .limit(10)
        .get();
    return snap.docs
        .where((d) => d.id != _uid)
        .map((d) => {'uid': d.id, ...d.data()})
        .toList();
  }

  Future<String?> sendRequest(String toUid, String toUsername) async {
    final uid = _uid;
    if (uid == null) return 'Debes iniciar sesión.';
    if (toUid == uid) return 'No puedes agregarte a ti mismo.';

    final existingFriend = await _db
        .collection('friendships').doc(uid)
        .collection('friends').doc(toUid).get();
    if (existingFriend.exists) return 'Ya son amigos.';

    final dup = await _db.collection('friendRequests')
        .where('fromUid', isEqualTo: uid)
        .get();
    final alreadySent = dup.docs.any((d) =>
        d['toUid'] == toUid && d['status'] == 'pending');
    if (alreadySent) return 'Ya le enviaste una solicitud.';

    // Si la otra persona ya me había mandado una solicitud a mí,
    // no crear una cruzada: simplemente aceptar la de ella.
    final reverse = await _db.collection('friendRequests')
        .where('fromUid', isEqualTo: toUid)
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (reverse.docs.isNotEmpty) {
      await acceptRequest(reverse.docs.first.id, toUid, toUsername);
      return '¡$toUsername ya te había agregado! Ahora son amigos.';
    }

    final myUser = await _db.collection('users').doc(uid).get();
    final myUsername = myUser.data()?['username'] ?? '';

    await _db.collection('friendRequests').add({
      'fromUid': uid,
      'fromUsername': myUsername,
      'toUid': toUid,
      'toUsername': toUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  Stream<List<Map<String, dynamic>>> incomingRequests() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('friendRequests')
        .where('toUid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['status'] == 'pending')
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  Stream<List<Map<String, dynamic>>> myFriends() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('friendships').doc(uid)
        .collection('friends')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'uid': d.id, ...d.data()})
            .toList());
  }

  Future<void> acceptRequest(
      String requestId, String fromUid, String fromUsername) async {
    final uid = _uid;
    if (uid == null) return;
    final myUser = await _db.collection('users').doc(uid).get();
    final myUsername = myUser.data()?['username'] ?? '';

    final batch = _db.batch();
    batch.update(
        _db.collection('friendRequests').doc(requestId), {'status': 'accepted'});
    batch.set(
        _db.collection('friendships').doc(uid).collection('friends').doc(fromUid),
        {'username': fromUsername, 'since': FieldValue.serverTimestamp()});
    batch.set(
        _db.collection('friendships').doc(fromUid).collection('friends').doc(uid),
        {'username': myUsername, 'since': FieldValue.serverTimestamp()});
    await batch.commit();

    // Espejo mínimo en Realtime Database, solo para que las reglas de
    // seguridad de liveLocations puedan verificar la amistad.
    await _rtdb.ref('friendships/$uid/$fromUid').set(true);
    await _rtdb.ref('friendships/$fromUid/$uid').set(true);
  }

  Future<void> rejectRequest(String requestId) async {
    await _db.collection('friendRequests').doc(requestId)
        .update({'status': 'rejected'});
  }

  Future<void> removeFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) return;
    final batch = _db.batch();
    batch.delete(_db.collection('friendships').doc(uid).collection('friends').doc(friendUid));
    batch.delete(_db.collection('friendships').doc(friendUid).collection('friends').doc(uid));
    await batch.commit();

    await _rtdb.ref('friendships/$uid/$friendUid').remove();
    await _rtdb.ref('friendships/$friendUid/$uid').remove();
  }
}
