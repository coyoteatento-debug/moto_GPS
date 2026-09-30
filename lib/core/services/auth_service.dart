import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> register(String email, String password, String username) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) return 'Escribe un nombre de usuario.';
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await _db.collection('users').doc(uid).set({
        'username': trimmedUsername,
        'usernameLower': trimmedUsername.toLowerCase(),
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'isPremium': false,
      });
      return null; // sin error
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code, e.message);
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code, e.message);
    }
  }

  Future<void> logout() => _auth.signOut();

  String _mapAuthError(String code, [String? message]) {
    switch (code) {
      case 'email-already-in-use':
        return 'Ese correo ya está registrado.';
      case 'invalid-email':
        return 'Correo inválido.';
      case 'weak-password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      default:
        return 'Error [$code]: ${message ?? "sin detalle"}';
    }
  }
}
