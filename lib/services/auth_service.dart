import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../dev/demo_accounts.dart';
import '../utils/friendly_error.dart';

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

    if (role == 'coach') {
      await _db.collection('coaches').doc(uid).set({
        'name': name,
        'email': email,
        'inviteCode': _generateInviteCode(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    // Give athletes a starter profile so the sport-selection screen
    // has somewhere to write to.
    if (role == 'athlete') {
      await _db.collection('athletes').doc(uid).set({
        'name': name,
        'sport': null,
        'sports': <String>[],
        'sportGroup': 'other',
        'sportGroups': <String>[],
        'coachUid': null,
        'deviceTier': 'tier3',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    return cred;
  }

  Future<UserCredential> signIn(
      {required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  /// Calls `deleteAccount` (Admin SDK). Confirmation string is required
  /// server-side. Signs out locally after the callable succeeds.
  Future<void> deleteAccount() async {
    if (_auth.currentUser == null) {
      throw Exception('You must be signed in.');
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'deleteAccount',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );

    try {
      await callable.call<Map<String, dynamic>>({'confirm': 'DELETE'});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(friendlyFunctionsMessage(e));
    }

    try {
      await signOut();
    } catch (_) {
      // Auth record is already gone — AuthGate will route to sign-in.
    }
  }

  /// Reads the caller's role from Firestore.
  ///
  /// On Flutter Web there's a brief window right after auth state
  /// changes where Firestore's security-rule evaluation hasn't yet
  /// caught up with the new ID token — a read fired immediately
  /// (like the one main.dart's AuthGate does) can get rejected with
  /// permission-denied even though the rule is logically correct.
  /// This retries with a short backoff instead of failing hard.
  Future<String?> getRole(String uid) async {
    final email = _auth.currentUser?.email?.toLowerCase();
    if (email == DemoAccounts.coachEmail) return 'coach';
    if (email == DemoAccounts.athleteEmail) return 'athlete';

    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        return doc.data()?['role'] as String?;
      } on FirebaseException catch (e) {
        final isLastAttempt = attempt == 3;
        if (e.code == 'permission-denied' && !isLastAttempt) {
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
