import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// role must be 'coach' or 'athlete'. This decides which app journey
  /// the router sends the user down (see main.dart) — Section 17.
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;

    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': email,
      'role': role,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Give athletes a starter profile so the sport-selection screen
    // has somewhere to write to.
    if (role == 'athlete') {
      await _db.collection('athletes').doc(uid).set({
        'name': name,
        'sport': null,
        'sportGroup': 'other',
        'coachUid': null,
        'deviceTier': 'tier3',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    return cred;
  }

  Future<UserCredential> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<String?> getRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }
}
