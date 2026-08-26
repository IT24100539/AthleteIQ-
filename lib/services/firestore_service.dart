import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/checkin.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';
import '../models/pain_report.dart';
import '../models/chat_message.dart';
import '../models/athlete_alert.dart';
import '../models/coach_alert.dart';
import '../models/weekly_report.dart';
import '../models/team_settings.dart';
import '../models/privacy_settings.dart';
import '../models/risk_latest.dart';
import '../utils/approval_gate.dart';
import '../utils/combine_latest.dart';
import '../utils/friendly_error.dart';
import '../utils/privacy_redaction.dart';
import '../utils/stream_fallback.dart';
import 'health_sync_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _viewerIsOwner(String athleteUid) =>
      FirebaseAuth.instance.currentUser?.uid == athleteUid;

  Stream<T> _forCoachViewer<T>(
    String athleteUid,
    Stream<T> source,
    T Function(T value, PrivacySettings privacy) redact,
  ) {
    if (_viewerIsOwner(athleteUid)) return source;
    return combineLatest2(source, streamPrivacySettings(athleteUid), redact);
  }

  // ---------- Athlete profile ----------

  /// Writes the full multi-sport list. First entry is primary (`sport` /
  /// `sportGroup` kept in sync for older readers).
  Future<void> setSports(
    String athleteUid,
    List<String> sports,
    List<SportGroup> sportGroups, {
    String? classificationConfidence,
    String? classificationSource,
  }) {
    if (sports.isEmpty) {
      throw Exception('Select at least one sport.');
    }
    final groups = sportGroups.length == sports.length
        ? sportGroups
        : [
            for (var i = 0; i < sports.length; i++)
              i < sportGroups.length
                  ? sportGroups[i]
                  : sportGroupForName(sports[i]),
          ];
    return _db.collection('athletes').doc(athleteUid).update({
      'sports': sports,
      'sportGroups': groups.map((g) => g.name).toList(),
      'sport': sports.first,
      'sportGroup': groups.first.name,
      if (classificationConfidence != null)
        'sportClassificationConfidence': classificationConfidence
      else
        'sportClassificationConfidence': FieldValue.delete(),
      if (classificationSource != null)
        'sportClassificationSource': classificationSource
      else
        'sportClassificationSource': FieldValue.delete(),
    });
  }

  Future<void> setSport(String athleteUid, SportOption sport) {
    return setSports(athleteUid, [sport.name], [sport.group]);
  }

  /// Section 12.2 — classify free-text sport. Does not persist; the
  /// selection screen adds the result to the multi-select list and
  /// writes everything through [setSports].
  Future<Map<String, dynamic>> classifyCustomSport(
    String athleteUid,
    String sportText,
  ) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw Exception('You must be signed in.');
    }

    final name = sportText.trim();
    final callable = FirebaseFunctions.instance.httpsCallable(
      'classifyCustomSport',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'athleteUid': athleteUid,
        'sportText': name,
        'persist': false,
      });
      final data = Map<String, dynamic>.from(result.data);
      data['sport'] ??= name;
      return data;
    } catch (_) {
      return {
        'sport': name,
        'sportGroup': SportGroup.other.name,
        'groupLabel': 'Other',
        'confidence': 'low',
        'source': 'client_fallback',
        'fallback': true,
      };
    }
  }

  Stream<AthleteProfile> athleteProfile(String uid) {
    final live = _db.collection('athletes').doc(uid).snapshots().map((doc) {
      final profile = AthleteProfile.fromMap(uid, doc.data() ?? {});
      if (_viewerIsOwner(uid)) return profile;
      return profile.redactedForCoach();
    });
    return emitOnError(live, AthleteProfile.fromMap(uid, {}));
  }

  /// One-shot read for the auth gate. Avoids the web Watch listener that
  /// can hit FIRESTORE INTERNAL ASSERTION FAILED after a Chrome hot restart.
  Future<AthleteProfile> getAthleteProfileOnce(String uid) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final doc = await _db.collection('athletes').doc(uid).get(
              const GetOptions(source: Source.server),
            );
        final profile = AthleteProfile.fromMap(uid, doc.data() ?? {});
        return _viewerIsOwner(uid) ? profile : profile.redactedForCoach();
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw lastError ?? Exception('Could not load profile.');
  }

  Future<Map<String, String?>> getUserDisplayName(String uid) async {
    return _readPersonDisplay(uid);
  }

  Future<Map<String, String?>> _readPersonDisplay(String uid) async {
    final coachDoc = await _db.collection('coaches').doc(uid).get();
    if (coachDoc.exists) {
      final data = coachDoc.data() ?? {};
      final name = (data['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        return {
          'name': name,
          'email': data['email'] as String?,
        };
      }
    }
    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    return {
      'name': data['name'] as String?,
      'email': data['email'] as String?,
    };
  }

  /// Coach name/email for linked athletes — reads `coaches/{uid}` (world-readable
  /// to signed-in users), not `users/{uid}` which is self-only.
  Stream<Map<String, String?>> streamCoachDisplay(String coachUid) {
    final live = _db.collection('coaches').doc(coachUid).snapshots().map((doc) {
      final data = doc.data() ?? {};
      return {
        'name': data['name'] as String?,
        'email': data['email'] as String?,
      };
    });
    return emitOnError(live, const {'name': null, 'email': null});
  }

  Stream<Map<String, String?>> streamUserDisplayName(String uid) {
    final live = _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? {};
      return {
        'name': data['name'] as String?,
        'email': data['email'] as String?,
      };
    });
    return emitOnError(live, const {'name': null, 'email': null});
  }

  // ---------- Devices & Data Tiers ----------

  Future<void> updateDeviceTier(
    String athleteUid,
    String tier, {
    String? activeDevice,
    bool setupCompleted = true,
  }) {
    return _db.collection('athletes').doc(athleteUid).set({
      'deviceTier': tier,
      'activeDevice': activeDevice,
      'deviceSetupCompleted': setupCompleted,
    }, SetOptions(merge: true));
  }

  Future<void> connectDevice(
    String athleteUid,
    String deviceId,
    Map<String, dynamic> deviceData,
  ) async {
    final batch = _db.batch();
    final deviceRef = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .doc(deviceId);

    batch.set(
        deviceRef,
        {
          ...deviceData,
          'connected': true,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true));

    final profileRef = _db.collection('athletes').doc(athleteUid);
    final tier = deviceData['tier'] ?? 'tier1';
    final deviceName = deviceData['name'] ?? deviceId;

    batch.set(
        profileRef,
        {
          'deviceTier': tier,
          'activeDevice': deviceName,
          'deviceSetupCompleted': true,
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> disconnectDevice(String athleteUid, String deviceId) async {
    final batch = _db.batch();
    final deviceRef = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .doc(deviceId);

    batch.set(
        deviceRef,
        {
          'connected': false,
          'disconnectedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true));

    final profileRef = _db.collection('athletes').doc(athleteUid);
    batch.set(
        profileRef,
        {
          'deviceTier': 'tier3',
          'activeDevice': null,
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> recordDeviceSyncFailure(
    String athleteUid,
    String deviceId,
    String error,
  ) {
    return _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .doc(deviceId)
        .set({
      'lastSyncError': error,
      'lastSyncErrorAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> saveFcmToken(String uid, String token) {
    return _db.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Snapshot of `athletes/{uid}/devices` (one-shot, not a stream).
  Future<Map<String, Map<String, dynamic>>> devicesOnce(String athleteUid) async {
    final snap = await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .get();
    final map = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      map[doc.id] = doc.data();
    }
    return map;
  }

  Stream<Map<String, Map<String, dynamic>>> streamDevices(String athleteUid) {
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .snapshots()
        .map((qs) {
      final map = <String, Map<String, dynamic>>{};
      for (final doc in qs.docs) {
        map[doc.id] = doc.data();
      }
      return map;
    });
    return emitOnError(live, const <String, Map<String, dynamic>>{});
  }

  // ---------- Daily check-in ----------

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

  /// Writes imported historical logs as daily check-ins (same collection +
  /// shape as manual entry), then runs the risk pipeline once.
  Future<int> importCheckIns(String athleteUid, List<CheckIn> checkIns) async {
    if (checkIns.isEmpty) return 0;

    const chunkSize = 450;
    for (var start = 0; start < checkIns.length; start += chunkSize) {
      final end = (start + chunkSize > checkIns.length)
          ? checkIns.length
          : start + chunkSize;
      final batch = _db.batch();
      for (final checkIn in checkIns.sublist(start, end)) {
        final dateKey = _dateKey(checkIn.date);
        final ref = _db
            .collection('athletes')
            .doc(athleteUid)
            .collection('checkins')
            .doc(dateKey);
        batch.set(ref, checkIn.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    }

    await _callRiskEngine(athleteUid);
    return checkIns.length;
  }

  /// Merge HealthKit / Health Connect fields into today's check-in without
  /// overwriting athlete-entered RPE, fatigue, or soreness. HRV is omitted
  /// entirely when the store has no sample for the day (never stored as 0).
  Future<void> mergeWearableCheckIn(
    String athleteUid,
    WearableDayMetrics metrics, {
    String? deviceId,
  }) async {
    if (!metrics.hasAny) return;

    final id = deviceId ?? HealthSyncService.instance.nativeDeviceId;
    final dateKey = _dateKey(DateTime.now());
    final ref = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('checkins')
        .doc(dateKey);
    final existing = await ref.get();
    final data = existing.data() ?? {};

    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(DateTime.now()),
      'source': data['source'] ?? 'wearable',
    };

    if (metrics.sleepHours != null) {
      payload['sleepHours'] =
          double.parse(metrics.sleepHours!.toStringAsFixed(1));
    }
    if (metrics.restingHeartRate != null) {
      payload['restingHeartRate'] =
          double.parse(metrics.restingHeartRate!.toStringAsFixed(0));
    }
    if (metrics.hrv != null) {
      payload['hrv'] = double.parse(metrics.hrv!.toStringAsFixed(1));
    }

    final existingDuration = (data['sessionDurationMinutes'] as num?)?.toInt();
    if (metrics.sessionDurationMinutes != null &&
        (existingDuration == null || existingDuration == 0)) {
      payload['sessionDurationMinutes'] = metrics.sessionDurationMinutes;
    }

    await ref.set(payload, SetOptions(merge: true));

    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .doc(id)
        .set({
      'lastSync': DateTime.now().toIso8601String(),
      'lastSyncError': FieldValue.delete(),
      'metrics': metrics.toDeviceMetricsMap(),
    }, SetOptions(merge: true));

    await _callRiskEngine(athleteUid);
  }

  /// Tier 3 manual step count — stored on a synthetic device doc like
  /// Health Connect metrics (not used by the risk engine today).
  Future<void> mergeManualActivityMetrics(
    String athleteUid, {
    int? steps,
  }) async {
    if (steps == null) return;
    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('devices')
        .doc('manual_tier3')
        .set({
      'name': 'Manual entry',
      'tier': 'tier3',
      'connected': false,
      'requiresWearableSync': false,
      'updatedAt': DateTime.now().toIso8601String(),
      'metrics': {
        'steps': steps,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    }, SetOptions(merge: true));
  }

  /// Invokes `recalculateRisk`. On failure throws [RiskEngineException] with
  /// a user-facing sentence — never an uncaught [FirebaseFunctionsException].
  Future<void> _callRiskEngine(String athleteUid) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const RiskEngineException(
        'Please sign in again, then retry.',
      );
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'recalculateRisk',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    );

    try {
      await callable.call<Map<String, dynamic>>({'athleteUid': athleteUid});
    } on FirebaseFunctionsException catch (e) {
      throw RiskEngineException(friendlyFunctionsMessage(e));
    } on TimeoutException {
      throw const RiskEngineException(
        'Risk update timed out. Your log was saved — the score will refresh shortly.',
      );
    } catch (_) {
      throw const RiskEngineException(
        'Could not update the risk score. Your log was saved — try again in a moment.',
      );
    }
  }

  /// Raw mixed check-ins are athlete-only. Coaches read the filtered copy.
  String _checkInsReadCollection(String athleteUid) =>
      _viewerIsOwner(athleteUid) ? 'checkins' : 'checkinsCoachView';

  CheckIn _parseCheckIn(
    String id,
    Map<String, dynamic> data, {
    required bool coachView,
  }) {
    if (!coachView) return CheckIn.fromMap(id, data);
    // Withheld fatigue is omitted on the server copy; 0 is the coach sentinel.
    return CheckIn.fromMap(id, {
      ...data,
      'fatigueScore': data['fatigueScore'] ?? 0,
    });
  }

  /// Last check-in date only — used by the roster sort, not the full 35-day log.
  Stream<DateTime?> latestCheckInDate(String athleteUid) {
    final coachView = !_viewerIsOwner(athleteUid);
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection(_checkInsReadCollection(athleteUid))
        .orderBy('date', descending: true)
        .limit(1)
        .snapshots()
        .map((qs) {
      if (qs.docs.isEmpty) return null;
      return _parseCheckIn(
        qs.docs.first.id,
        qs.docs.first.data(),
        coachView: coachView,
      ).date;
    });
    return emitOnError(live, null);
  }

  Stream<List<CheckIn>> recentCheckIns(String athleteUid, {int days = 35}) {
    final since = DateTime.now().subtract(Duration(days: days));
    final coachView = !_viewerIsOwner(athleteUid);
    final raw = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection(_checkInsReadCollection(athleteUid))
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('date', descending: true)
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => _parseCheckIn(d.id, d.data(), coachView: coachView))
            .toList());
    return emitOnError(raw, const <CheckIn>[]);
  }

  // ---------- Risk / recommendation ----------

  Stream<RiskLatest> streamRiskLatest(String athleteUid) {
    // Athletes read the server-filtered athleteView (no pending rec).
    // Coaches read the full latest document.
    final docId = _viewerIsOwner(athleteUid) ? 'athleteView' : 'latest';
    final raw = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('riskResults')
        .doc(docId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return const RiskLatest();
      final data = doc.data()!;
      if (data['insufficientData'] == true) {
        return RiskLatest(
          insufficientData: true,
          checkInCount: (data['checkInCount'] as num?)?.toInt() ?? 0,
        );
      }
      return RiskLatest(result: RiskResult.fromMap(data));
    });
    if (_viewerIsOwner(athleteUid)) {
      final gated = raw.map((latest) {
        if (latest.result == null) return latest;
        return RiskLatest(
          result: redactUnreleasedRecommendation(latest.result!),
          insufficientData: latest.insufficientData,
          checkInCount: latest.checkInCount,
        );
      });
      return emitOnError(gated, const RiskLatest());
    }
    final withPrivacy = combineLatest2(raw, streamPrivacySettings(athleteUid),
        (RiskLatest latest, PrivacySettings privacy) {
      if (latest.result == null) return latest;
      return RiskLatest(
        result: redactRiskResultForCoach(latest.result!, privacy),
        insufficientData: latest.insufficientData,
        checkInCount: latest.checkInCount,
      );
    });
    return emitOnError(withPrivacy, const RiskLatest());
  }

  Stream<RiskResult?> latestRiskResult(String athleteUid) {
    return streamRiskLatest(athleteUid).map((latest) => latest.result);
  }

  /// Dated snapshots at `riskResults/{yyyy-MM-dd}` (excludes `latest`).
  Stream<List<RiskHistoryPoint>> streamRiskHistory(String athleteUid) {
    final raw = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('riskResults')
        .where(FieldPath.documentId, isNotEqualTo: 'latest')
        .snapshots()
        .map((qs) {
      final points = <RiskHistoryPoint>[];
      for (final doc in qs.docs) {
        if (doc.id == 'latest' || doc.id == 'athleteView') continue;
        final data = doc.data();
        if (data['kind'] == 'athleteView') continue;
        if (data['insufficientData'] == true) continue;
        if (data['acwr'] == null && data['performancePrediction'] == null) {
          continue;
        }
        points.add(RiskHistoryPoint.fromMap(doc.id, data));
      }
      points.sort((a, b) => a.date.compareTo(b.date));
      return points;
    });
    return emitOnError(
      _forCoachViewer(athleteUid, raw, redactRiskHistoryForCoach),
      const <RiskHistoryPoint>[],
    );
  }

  Future<void> reviewRecommendation(
    String athleteUid, {
    required String decision,
    String? modifiedText,
  }) {
    final coachUid = FirebaseAuth.instance.currentUser?.uid;
    if (coachUid == null) {
      throw StateError('Sign in required to review a recommendation.');
    }
    return _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('riskResults')
        .doc('latest')
        .update({
      'recommendationStatus': decision,
      if (modifiedText != null) 'recommendation': modifiedText,
      'reviewedAt': DateTime.now().toIso8601String(),
      'reviewedBy': coachUid,
    });
  }

  // ---------- Coach roster ----------

  Stream<List<AthleteProfile>> rosterForCoach(String coachUid) {
    final live = _db
        .collection('athletes')
        .where('coachUid', isEqualTo: coachUid)
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => AthleteProfile.fromMap(d.id, d.data()).redactedForCoach())
            .toList());
    return live;
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- Coach team settings (Section 18.4) ----------

  Stream<TeamSettings> streamTeamSettings(String coachUid) {
    final live = _db
        .collection('coaches')
        .doc(coachUid)
        .collection('teamSettings')
        .doc('default')
        .snapshots()
        .map((doc) => TeamSettings.fromMap(doc.data()));
    return emitOnError(live, TeamSettings.fromMap(null));
  }

  Future<void> updateTeamSettings(String coachUid, TeamSettings settings) async {
    final clamped = settings.defaultActionPercent
        .clamp(TeamSettings.minPercent, TeamSettings.maxPercent);
    final payload = settings.copyWith(defaultActionPercent: clamped).toMap();
    await _db
        .collection('coaches')
        .doc(coachUid)
        .collection('teamSettings')
        .doc('default')
        .set(payload, SetOptions(merge: true));
  }

  // ---------- Coach invite ----------

  Future<String?> getCoachInviteCode(String coachUid) async {
    final ref = _db.collection('coaches').doc(coachUid);
    final doc = await ref.get();
    if (doc.exists && doc.data()?['inviteCode'] != null) {
      return doc.data()!['inviteCode'] as String;
    }

    final userDoc = await _db.collection('users').doc(coachUid).get();
    if (userDoc.data()?['role'] != 'coach') {
      return null;
    }

    final code = _generateInviteCode();
    await ref.set({
      'name': userDoc.data()?['name'] ?? '',
      'email': userDoc.data()?['email'] ?? '',
      'inviteCode': code,
      'createdAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    await ref.collection('teamSettings').doc('default').set(
      const TeamSettings(defaultActionPercent: TeamSettings.defaultPercent).toMap(),
      SetOptions(merge: true),
    );
    return code;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().millisecondsSinceEpoch;
    return List.generate(6, (i) => chars[(now + i * 7) % chars.length]).join();
  }

  /// Links the signed-in athlete to a coach by invite code.
  ///
  /// Retries on a transient 'permission-denied' the same way
  /// AuthService.getRole() does: right after auth state changes (e.g. a
  /// user who just signed up or just signed back in), there's a brief
  /// window on Flutter Web where Firestore's security-rule evaluation
  /// hasn't yet caught up with the refreshed ID token. A request fired
  /// in that window can be rejected even though the rule and data are
  /// both correct. Backing off and retrying a few times avoids
  /// surfacing a false error to the user.
  Future<void> linkAthleteToCoach(String athleteUid, String inviteCode) async {
    final normalized = inviteCode.trim().toUpperCase();

    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        final qs = await _db
            .collection('coaches')
            .where('inviteCode', isEqualTo: normalized)
            .limit(1)
            .get();

        if (qs.docs.isEmpty) {
          throw Exception(
              'Invalid invite code. Check with your coach and try again.');
        }

        final athleteRef = _db.collection('athletes').doc(athleteUid);
        final athleteSnap = await athleteRef.get();
        final existingCoach = athleteSnap.data()?['coachUid'];
        if (existingCoach != null &&
            existingCoach.toString().trim().isNotEmpty) {
          throw Exception(
              'You\'re already connected to a coach. Disconnect first if you need to switch.');
        }

        final coachUid = qs.docs.first.id;
        await athleteRef.update({'coachUid': coachUid});

        // Verify the link persisted (helps catch rules / token timing issues).
        final verify = await athleteRef.get(const GetOptions(source: Source.server));
        final linked = verify.data()?['coachUid'];
        if (linked != coachUid) {
          throw Exception(
              'Connection could not be verified. Try again in a moment.');
        }
        return; // success, stop retrying
      } on FirebaseException catch (e) {
        final isLastAttempt = attempt == 3;
        if (e.code == 'permission-denied' && !isLastAttempt) {
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Removes the athlete from their coach's roster. Only the athlete can
  /// disconnect (Firestore rules enforce coachUid → null).
  Future<void> unlinkAthleteFromCoach(String athleteUid) async {
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        await _db
            .collection('athletes')
            .doc(athleteUid)
            .update({'coachUid': null});
        return;
      } on FirebaseException catch (e) {
        final isLastAttempt = attempt == 3;
        if (e.code == 'permission-denied' && !isLastAttempt) {
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
  }

  // ---------- Pain Reports ----------

  /// Writes via `submitPainReport` callable so urgency is classified
  /// server-side. Firestore rules deny direct `painReports` creates.
  Future<Map<String, dynamic>> submitPainReport(
    String athleteUid,
    PainReport report,
  ) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw Exception('You must be signed in.');
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'submitPainReport',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'athleteUid': athleteUid,
        'areas': report.areas.map((a) => a.toMap()).toList(),
        'note': report.note ?? '',
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(friendlyFunctionsMessage(e));
    } on TimeoutException {
      throw Exception(
        'Pain report timed out. Check your connection and try again.',
      );
    } catch (e) {
      throw Exception(friendlyError(e));
    }
  }

  Stream<List<PainReport>> streamPainReports(String athleteUid) {
    Stream<List<PainReport>> query() {
      return _db
          .collection('athletes')
          .doc(athleteUid)
          .collection('painReports')
          .orderBy('date', descending: true)
          .snapshots()
          .map((qs) =>
              qs.docs.map((d) => PainReport.fromMap(d.id, d.data())).toList());
    }

    if (_viewerIsOwner(athleteUid)) {
      return emitOnError(query(), const <PainReport>[]);
    }
    return emitOnError(
      streamPrivacySettings(athleteUid).asyncExpand((privacy) {
        if (!privacy.injuryHistory) {
          return Stream.value(<PainReport>[]);
        }
        return query();
      }),
      const <PainReport>[],
    );
  }

  // ---------- Coach Chat ----------

  Stream<List<ChatMessage>> streamCoachMessages(String athleteUid) {
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => ChatMessage.fromMap(d.id, d.data())).toList());
    return emitOnError(live, const <ChatMessage>[]);
  }

  Future<void> sendCoachMessage(String athleteUid, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final names = await getUserDisplayName(user.uid);
    final msg = ChatMessage(
      id: '',
      senderUid: user.uid,
      senderName: (names['name'] ?? user.displayName ?? 'Athlete').trim(),
      text: text,
      timestamp: DateTime.now(),
      isCoach: false,
      read: false,
    );

    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('messages')
        .add(msg.toMap());
  }

  /// Latest message in `athletes/{uid}/messages/` (or null if the thread is empty).
  Stream<ChatMessage?> streamLatestCoachMessage(String athleteUid) {
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((qs) {
      if (qs.docs.isEmpty) return null;
      final doc = qs.docs.first;
      return ChatMessage.fromMap(doc.id, doc.data());
    });
    return emitOnError(live, null);
  }

  /// Coach last-read cursor for a thread — `coaches/{coachUid}/inboxRead/{athleteUid}`.
  Stream<DateTime?> streamInboxLastRead(String coachUid, String athleteUid) {
    final live = _db
        .collection('coaches')
        .doc(coachUid)
        .collection('inboxRead')
        .doc(athleteUid)
        .snapshots()
        .map((doc) {
      final raw = doc.data()?['lastReadAt'] as String?;
      return DateTime.tryParse(raw ?? '');
    });
    return emitOnError(live, null);
  }

  Future<void> markInboxThreadRead(String coachUid, String athleteUid) {
    return _db
        .collection('coaches')
        .doc(coachUid)
        .collection('inboxRead')
        .doc(athleteUid)
        .set({'lastReadAt': DateTime.now().toIso8601String()}, SetOptions(merge: true));
  }

  /// Coach reply into the same `athletes/{uid}/messages/` collection.
  Future<void> sendCoachReply(String athleteUid, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final names = await getUserDisplayName(user.uid);
    final msg = ChatMessage(
      id: '',
      senderUid: user.uid,
      senderName: (names['name'] ?? user.displayName ?? 'Coach').trim(),
      text: text,
      timestamp: DateTime.now(),
      isCoach: true,
      read: true,
    );

    await _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('messages')
        .add(msg.toMap());

    await markInboxThreadRead(user.uid, athleteUid);
  }

  // ---------- Alerts & Notifications ----------

  /// Week in review — structured stats + grounded LLM narrative (Phase E9).
  Future<WeeklyReport> getWeeklyReport(
    String athleteUid, {
    int weekOffset = 0,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw Exception('You must be signed in.');
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'getWeeklyReport',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'athleteUid': athleteUid,
        'weekOffset': weekOffset,
      });
      final report = WeeklyReport.fromMap(Map<String, dynamic>.from(result.data));
      if (_viewerIsOwner(athleteUid)) return report;
      final privacySnap =
          await _db.collection('athletes').doc(athleteUid).get();
      final privacy = PrivacySettings.fromMap(
        privacySnap.data()?['privacySettings'] as Map<String, dynamic>?,
      );
      return redactWeeklyReportForCoach(report, privacy);
    } catch (e) {
      if (e is FirebaseFunctionsException) {
        throw Exception(friendlyFunctionsMessage(e));
      }
      if (e is TimeoutException) {
        throw Exception(
          'Weekly report timed out. Check your connection and try again.',
        );
      }
      throw Exception(friendlyError(e));
    }
  }

  Stream<List<CoachAlert>> streamCoachAlerts(String coachUid) {
    final raw = _db
        .collection('coaches')
        .doc(coachUid)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => CoachAlert.fromMap(d.id, d.data())).toList());
    return emitOnError(
      combineLatest2(raw, rosterForCoach(coachUid),
          (List<CoachAlert> alerts, List<AthleteProfile> roster) {
        final privacyByUid = {
          for (final a in roster) a.uid: a.privacySettings,
        };
        return alerts.where((alert) {
          final privacy =
              privacyByUid[alert.athleteUid] ?? PrivacySettings.open;
          return privacy.allowsCoachAlertType(alert.type);
        }).toList();
      }),
      const <CoachAlert>[],
    );
  }

  Stream<List<AthleteAlert>> streamAlerts(String athleteUid) {
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => AthleteAlert.fromMap(d.id, d.data())).toList());
    return emitOnError(live, const <AthleteAlert>[]);
  }

  // ---------- Ask AthleteIQ (AI Q&A Engine) ----------

  Stream<List<ChatMessage>> streamAiChat(String athleteUid) {
    final live = _db
        .collection('athletes')
        .doc(athleteUid)
        .collection('aiChat')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((qs) =>
            qs.docs.map((d) => ChatMessage.fromMap(d.id, d.data())).toList());
    return emitOnError(live, const <ChatMessage>[]);
  }

  /// Calls the `askAthleteIQ` Cloud Function. The function writes both the
  /// user question and the grounded AI reply to `athletes/{uid}/aiChat`.
  /// Local rule-based answers are a last-resort fallback if the callable fails.
  Future<void> askAthleteIQ(String athleteUid, String question) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'askAthleteIQ',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      await callable.call<Map<String, dynamic>>({
        'athleteUid': athleteUid,
        'question': question,
      });
    } catch (_) {
      try {
        await _writeLocalFallbackAiChat(user, athleteUid, question);
      } catch (e) {
        throw Exception(friendlyError(e));
      }
    }
  }

  Future<void> _writeLocalFallbackAiChat(
    User user,
    String athleteUid,
    String question,
  ) async {
    final userMsgRef =
        _db.collection('athletes').doc(athleteUid).collection('aiChat').doc();

    final userMsg = ChatMessage(
      id: userMsgRef.id,
      senderUid: user.uid,
      senderName: user.displayName ?? 'Athlete',
      text: question,
      timestamp: DateTime.now(),
      isAi: false,
    );

    await userMsgRef.set(userMsg.toMap());

    final aiAnswer = _generateAiAnswer(question);
    final aiMsgRef =
        _db.collection('athletes').doc(athleteUid).collection('aiChat').doc();

    final aiMsg = ChatMessage(
      id: aiMsgRef.id,
      senderUid: 'athlete_iq_ai',
      senderName: 'AthleteIQ AI',
      text: aiAnswer,
      timestamp: DateTime.now().add(const Duration(milliseconds: 400)),
      isAi: true,
    );

    await aiMsgRef.set(aiMsg.toMap());
  }

  String _generateAiAnswer(String question) {
    const prefix =
        '[Rule-based fallback — askAthleteIQ unavailable. Not the full AI model.] ';
    final q = question.toLowerCase();
    if (q.contains('fatigue') ||
        q.contains('tired') ||
        q.contains('exhausted')) {
      return '${prefix}I can only match keywords offline. Check this athlete\'s recent check-ins and 7-day load in the dashboard — fatigue answers need their logged numbers.';
    } else if (q.contains('train') ||
        q.contains('workout') ||
        q.contains('today') ||
        q.contains('tomorrow')) {
      return '${prefix}Training-day questions need the live askAthleteIQ function and the coach-approved recommendation on riskResults/latest.';
    } else if (q.contains('pain') ||
        q.contains('knee') ||
        q.contains('hurt') ||
        q.contains('sore')) {
      return '${prefix}Pain needs a real check-in and coach review — do not treat this offline reply as medical advice.';
    } else if (q.contains('sleep') || q.contains('recovery')) {
      return '${prefix}Sleep and recovery answers should come from logged check-ins via askAthleteIQ when the Cloud Function is reachable.';
    } else {
      return '${prefix}Ask AthleteIQ is offline. Open the athlete dashboard for ACWR, load, and the approved recommendation.';
    }
  }

  // ---------- Data Sharing Consent ----------

  Future<void> updatePrivacySettings(
      String athleteUid, PrivacySettings settings) {
    return _db.collection('athletes').doc(athleteUid).set({
      'privacySettings': settings.toMap(),
    }, SetOptions(merge: true));
  }

  Stream<PrivacySettings> streamPrivacySettings(String athleteUid) {
    final live = _db.collection('athletes').doc(athleteUid).snapshots().map((doc) {
      return PrivacySettings.fromMap(
        doc.data()?['privacySettings'] as Map<String, dynamic>?,
      );
    });
    return emitOnError(live, PrivacySettings.open);
  }
}
