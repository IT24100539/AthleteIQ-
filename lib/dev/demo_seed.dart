import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/privacy_settings.dart';
import 'demo_accounts.dart';
import 'demo_data.dart';

/// Creates the demo athlete + coach Auth users (if needed) and writes sample
/// docs the client is allowed to write. Risk, alerts, and weekly reports are
/// function-only in rules — those screens use [DemoOverlay] instead.
class DemoBootstrap {
  static const _helperAppName = 'demo-helper';

  static Future<void> ensureAccountsAndData({required String signInAs}) async {
    assert(signInAs == 'athlete' || signInAs == 'coach');

    final helper = await _helperApp();
    final helperAuth = FirebaseAuth.instanceFor(app: helper);
    final helperDb = FirebaseFirestore.instanceFor(app: helper);
    if (kIsWeb) {
      helperDb.settings = const Settings(persistenceEnabled: false);
    }
    if (kDebugMode && const bool.fromEnvironment('USE_EMULATOR')) {
      try {
        helperAuth.useAuthEmulator('localhost', 9099);
      } catch (_) {}
      try {
        helperDb.useFirestoreEmulator('localhost', 8080);
      } catch (_) {}
    }

    final coachCred = await _signInOrCreate(
      helperAuth,
      email: DemoAccounts.coachEmail,
      password: DemoAccounts.password,
      name: DemoAccounts.coachName,
      role: 'coach',
    );
    final coachUid = coachCred.user!.uid;
    DemoSession.coachUid = coachUid;

    await _writeCoachShell(helperDb, coachUid);

    final defaultAuth = FirebaseAuth.instance;
    final defaultDb = FirebaseFirestore.instance;
    if (defaultAuth.currentUser != null) {
      await defaultAuth.signOut();
    }

    final athleteCred = await _signInOrCreate(
      defaultAuth,
      email: DemoAccounts.athleteEmail,
      password: DemoAccounts.password,
      name: DemoAccounts.athleteName,
      role: 'athlete',
    );
    final athleteUid = athleteCred.user!.uid;
    DemoSession.athleteUid = athleteUid;

    await _trySet(defaultDb.collection('users').doc(athleteUid), {
      'name': DemoAccounts.athleteName,
      'email': DemoAccounts.athleteEmail,
      'role': 'athlete',
      'isDemo': true,
      'demoPeerUid': coachUid,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _trySet(
      defaultDb.collection('athletes').doc(athleteUid),
      DemoData.athleteProfile(athleteUid, coachUid: coachUid).toMap(),
    );

    await _writeAthleteSeed(
      defaultDb,
      athleteUid: athleteUid,
      coachUid: coachUid,
    );

    await _trySet(
      helperDb.collection('users').doc(coachUid),
      {
        'demoPeerUid': athleteUid,
        'isDemo': true,
      },
    );

    if (signInAs == 'coach') {
      await defaultAuth.signOut();
      await defaultAuth.signInWithEmailAndPassword(
        email: DemoAccounts.coachEmail,
        password: DemoAccounts.password,
      );
    }
  }

  static Future<FirebaseApp> _helperApp() async {
    try {
      return Firebase.app(_helperAppName);
    } catch (_) {
      return Firebase.initializeApp(
        name: _helperAppName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  static Future<UserCredential> _signInOrCreate(
    FirebaseAuth auth, {
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      rethrow;
    }
  }

  static Future<void> _writeCoachShell(
    FirebaseFirestore db,
    String coachUid,
  ) async {
    await _trySet(db.collection('users').doc(coachUid), {
      'name': DemoAccounts.coachName,
      'email': DemoAccounts.coachEmail,
      'role': 'coach',
      'isDemo': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _trySet(db.collection('coaches').doc(coachUid), {
      'name': DemoAccounts.coachName,
      'email': DemoAccounts.coachEmail,
      'inviteCode': DemoAccounts.inviteCode,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _writeAthleteSeed(
    FirebaseFirestore db, {
    required String athleteUid,
    required String coachUid,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _trySet(db.collection('users').doc(athleteUid), {
      'name': DemoAccounts.athleteName,
      'email': DemoAccounts.athleteEmail,
      'role': 'athlete',
      'isDemo': true,
      'demoPeerUid': coachUid,
      'createdAt': now,
    });

    final profile = DemoData.athleteProfile(athleteUid, coachUid: coachUid);
    await _trySet(db.collection('athletes').doc(athleteUid), {
      ...profile.toMap(),
      'privacySettings': PrivacySettings.open.toMap(),
    });

    for (final checkIn in DemoData.checkIns()) {
      await _trySet(
        db
            .collection('athletes')
            .doc(athleteUid)
            .collection('checkins')
            .doc(checkIn.id),
        {
          'date': Timestamp.fromDate(checkIn.date),
          'sessionDurationMinutes': checkIn.sessionDurationMinutes,
          'rpe': checkIn.rpe,
          'fatigueScore': checkIn.fatigueScore,
          'sleepHours': checkIn.sleepHours,
          'restingHeartRate': checkIn.restingHeartRate,
          'hrv': checkIn.hrv,
          'soreness': checkIn.soreness,
          'source': checkIn.source,
        },
      );
    }
  }

  static Future<void> _trySet(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    try {
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Demo seed skipped ${ref.path}: $e');
    }
  }
}
