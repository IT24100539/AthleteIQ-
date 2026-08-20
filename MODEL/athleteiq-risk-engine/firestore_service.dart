import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/checkin.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';

/// CHANGED FROM CLOUD FUNCTIONS:
/// This used to call `FirebaseFunctions.instance.httpsCallable('recalculateRisk')`,
/// which requires the Blaze billing plan. It now calls the same logic running
/// as a free FastAPI service (see athleteiq_backend_free/ folder + its README
/// for deployment). Same auth guarantee is preserved: the backend verifies
/// the athlete's real Firebase ID token server-side, so a client still can't
/// spoof another user's uid or self-approve a recommendation.
///
/// Set this to your real Render URL after deploying (Step 3 of that README).
const String kRiskEngineBaseUrl = 'https://athleteiq-risk-engine.onrender.com';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------- Athlete profile ----------

  Future<void> setSport(String athleteUid, SportOption sport) {
    return _db.collection('athletes').doc(athleteUid).update({
      'sport': sport.name,
      'sportGroup': sport.group.name,
    });
  }

  Stream<AthleteProfile> athleteProfile(String uid) {
    return _db.collection('athletes').doc(uid).snapshots().map(
          (doc) => AthleteProfile.fromMap(uid, doc.data() ?? {}),
        );
  }

  // ---------- Daily check-in ----------

  /// Writes today's check-in, then calls the risk engine (now a free
  /// FastAPI service instead of a Cloud Function) to recalculate
  /// Training Load / ACWR / Risk / Recommendation server-side.
  Future<void> submitCheckIn(String athleteUid, CheckIn checkIn) async {
    final dateKey = _dateKey(checkIn.date);
    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('checkins')
        .doc(dateKey)
        .set(checkIn.toMap(), SetOptions(merge: true));

    await _callRiskEngine(athleteUid);
  }

  /// Calls POST /recalculate-risk on the free backend, with the caller's
  /// real Firebase ID token attached — this is what lets the backend
  /// verify identity the same way Cloud Functions' `request.auth` did.
  Future<void> _callRiskEngine(String athleteUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to submit a check-in.');
    }
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$kRiskEngineBaseUrl/recalculate-risk'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'athleteUid': athleteUid}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Risk engine error (${response.statusCode}): ${response.body}',
      );
    }
  }

  Stream<List<CheckIn>> recentCheckIns(String athleteUid, {int days = 35}) {
    final since = DateTime.now().subtract(Duration(days: days));
    return _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('checkins')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('date', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => CheckIn.fromMap(d.id, d.data())).toList());
  }

  // ---------- Risk / recommendation ----------

  Stream<RiskResult?> latestRiskResult(String athleteUid) {
    return _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('riskResults')
        .doc('latest')
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          if (data['insufficientData'] == true) return null;
          return RiskResult.fromMap(data);
        });
  }

  /// Section 6 / 17.1 — only a coach calls this. Firestore rules (see
  /// firestore.rules) also enforce this server-side, not just in the UI.
  Future<void> reviewRecommendation(
    String athleteUid, {
    required String decision, // 'approved' | 'rejected' | 'modified'
    String? modifiedText,
  }) {
    return _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('riskResults')
        .doc('latest')
        .update({
      'recommendationStatus': decision,
      if (modifiedText != null) 'recommendation': modifiedText,
      'reviewedAt': DateTime.now().toIso8601String(),
    });
  }

  // ---------- Coach roster ----------

  Stream<List<AthleteProfile>> rosterForCoach(String coachUid) {
    return _db
        .collection('athletes')
        .where('coachUid', isEqualTo: coachUid)
        .snapshots()
        .map((qs) => qs.docs.map((d) => AthleteProfile.fromMap(d.id, d.data())).toList());
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- Coach invite ----------

  Future<String?> getCoachInviteCode(String coachUid) async {
    final ref = _db.collection('coaches').doc(coachUid);
    final doc = await ref.get();
    if (doc.exists && doc.data()?['inviteCode'] != null) {
      return doc.data()!['inviteCode'] as String;
    }

    final userDoc = await _db.collection('users').doc(coachUid).get();
    if (userDoc.data()?['role'] != 'coach') return null;

    final code = _generateInviteCode();
    await ref.set({
      'name': userDoc.data()?['name'] ?? '',
      'email': userDoc.data()?['email'] ?? '',
      'inviteCode': code,
      'createdAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    return code;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().millisecondsSinceEpoch;
    return List.generate(6, (i) => chars[(now + i * 7) % chars.length]).join();
  }

  /// Links an athlete to a coach using the coach's 6-character invite code.
  Future<void> linkAthleteToCoach(String athleteUid, String inviteCode) async {
    final normalized = inviteCode.trim().toUpperCase();
    final qs = await _db
        .collection('coaches')
        .where('inviteCode', isEqualTo: normalized)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) {
      throw Exception('Invalid invite code. Check with your coach and try again.');
    }

    final coachUid = qs.docs.first.id;
    await _db.collection('athletes').doc(athleteUid).update({'coachUid': coachUid});
  }
}
