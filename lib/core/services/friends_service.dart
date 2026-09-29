import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

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
    if (toUid == _uid) return 'No puedes agregarte a ti mismo.';

    final existingFriend = await _db
        .collection('friendships').doc(_uid)
        .collection('friends').doc(toUid).get();
    if (existingFriend.exists) return 'Ya son amigos.';

    final dup = await _db.collection('friendRequests')
        .where('fromUid', isEqualTo: _uid)
        .get();
    final alreadySent = dup.docs.any((d) =>
        d['toUid'] == toUid && d['status'] == 'pending');
    if (alreadySent) return 'Ya le enviaste una solicitud.';

    final myUser = await _db.collection('users').doc(_uid).get();
    final myUsername = myUser.data()?['username'] ?? '';

    await _db.collection('friendRequests').add({
      'fromUid': _uid,
      'fromUsername': myUsername,
      'toUid': toUid,
      'toUsername': toUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  Stream<List<Map<String, dynamic>>> incomingRequests() {
    return _db.collection('friendRequests')
        .where('toUid', isEqualTo: _uid)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['status'] == 'pending')
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  Stream<List<Map<String, dynamic>>> myFriends() {
    return _db.collection('friendships').doc(_uid)
        .collection('friends')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'uid': d.id, ...d.data()})
            .toList());
  }

  Future<void> acceptRequest(
      String requestId, String fromUid, String fromUsername) async {
    final myUser = await _db.collection('users').doc(_uid).get();
    final myUsername = myUser.data()?['username'] ?? '';

    final batch = _db.batch();
    batch.update(
        _db.collection('friendRequests').doc(requestId), {'status': 'accepted'});
    batch.set(
        _db.collection('friendships').doc(_uid).collection('friends').doc(fromUid),
        {'username': fromUsername, 'since': FieldValue.serverTimestamp()});
    batch.set(
        _db.collection('friendships').doc(fromUid).collection('friends').doc(_uid),
        {'username': myUsername, 'since': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> rejectRequest(String requestId) async {
    await _db.collection('friendRequests').doc(requestId)
        .update({'status': 'rejected'});
  }

  Future<void> removeFriend(String friendUid) async {
    final batch = _db.batch();
    batch.delete(_db.collection('friendships').doc(_uid).collection('friends').doc(friendUid));
    batch.delete(_db.collection('friendships').doc(friendUid).collection('friends').doc(_uid));
    await batch.commit();
  }
}
