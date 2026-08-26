import 'package:cloud_firestore/cloud_firestore.dart';

/// One day's worth of manually-entered + (optionally) synced data.
/// This is Tier 3 by default — every field here can be filled by hand,
/// per Section 9 of the project spec ("Works With Any Device").
class CheckIn {
  final String id;
  final DateTime date;
  final int? sessionDurationMinutes; // manual or synced
  final int? rpe; // 1-10, manual only
  final int fatigueScore; // 1-5, manual only, required daily
  final double? sleepHours; // manual or synced
  final double? restingHeartRate; // wearable (Tier 1/2) or optional manual (Tier 3)
  final double? hrv; // wearable, or optional manual on Tier 3 — never invented
  final String? soreness; // free text, optional (roadmap: structured)
  final String source; // 'manual' | 'wearable' | 'import'
  /// Which of the athlete's sports this session was for (multi-sport).
  final String? sessionSport;
  final String? sessionSportGroup;
  /// Optional daily step count (Tier 3 manual or Tier 2 device sync).
  final int? steps;

  CheckIn({
    required this.id,
    required this.date,
    this.sessionDurationMinutes,
    this.rpe,
    required this.fatigueScore,
    this.sleepHours,
    this.restingHeartRate,
    this.hrv,
    this.soreness,
    this.source = 'manual',
    this.sessionSport,
    this.sessionSportGroup,
    this.steps,
  });

  /// Session-RPE training load for this entry. Rest days store duration/RPE
  /// as 0, so load is 0 (no training). Legacy null fields also mean no load.
  double? get trainingLoad {
    if (sessionDurationMinutes == null || rpe == null) return null;
    return (sessionDurationMinutes! * rpe!).toDouble();
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'sessionDurationMinutes': sessionDurationMinutes,
        'rpe': rpe,
        'fatigueScore': fatigueScore,
        'sleepHours': sleepHours,
        if (restingHeartRate != null) 'restingHeartRate': restingHeartRate,
        if (hrv != null) 'hrv': hrv,
        'soreness': soreness,
        'source': source,
        if (sessionSport != null) 'sessionSport': sessionSport,
        if (sessionSportGroup != null) 'sessionSportGroup': sessionSportGroup,
        if (steps != null) 'steps': steps,
      };

  factory CheckIn.fromMap(String id, Map<String, dynamic> map) => CheckIn(
        id: id,
        date: (map['date'] as Timestamp).toDate(),
        sessionDurationMinutes: map['sessionDurationMinutes'],
        rpe: map['rpe'],
        fatigueScore: map['fatigueScore'] ?? 3,
        sleepHours: (map['sleepHours'] as num?)?.toDouble(),
        restingHeartRate: (map['restingHeartRate'] as num?)?.toDouble(),
        hrv: (map['hrv'] as num?)?.toDouble(),
        soreness: map['soreness'],
        source: map['source'] ?? 'manual',
        sessionSport: map['sessionSport'] as String?,
        sessionSportGroup: map['sessionSportGroup'] as String?,
        steps: (map['steps'] as num?)?.toInt(),
      );
}
