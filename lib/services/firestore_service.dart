import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/checkin.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  /// Writes today's check-in, then calls the Cloud Function that
  /// recalculates Training Load / ACWR / Risk / Recommendation.
  /// The write-then-call pattern keeps the math server-side (Section 13)
  /// so it can't be spoofed from the client and stays consistent between
  /// the athlete and coach views.
  Future<void> submitCheckIn(String athleteUid, CheckIn checkIn) async {
    final dateKey = _dateKey(checkIn.date);
    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('checkins')
        .doc(dateKey)
        .set(checkIn.toMap(), SetOptions(merge: true));

    await _functions.httpsCallable('recalculateRisk').call({'athleteUid': athleteUid});
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
        .map((doc) => doc.exists ? RiskResult.fromMap(doc.data()!) : null);
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
}
