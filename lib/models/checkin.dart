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
  final double? restingHeartRate; // synced only (Tier 1/2)
  final double? hrv; // synced only, Tier 1 only
  final String? soreness; // free text, optional (roadmap: structured)
  final String source; // 'manual' | 'wearable'

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
  });

  /// Session-RPE training load for this entry. Null if no session logged
  /// that day (a rest day still gets a fatigue check-in, but no load).
  double? get trainingLoad {
    if (sessionDurationMinutes == null || rpe == null) return null;
    return sessionDurationMinutes! * rpe!;
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'sessionDurationMinutes': sessionDurationMinutes,
        'rpe': rpe,
        'fatigueScore': fatigueScore,
        'sleepHours': sleepHours,
        'restingHeartRate': restingHeartRate,
        'hrv': hrv,
        'soreness': soreness,
        'source': source,
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
      );
}
