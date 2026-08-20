/// Athlete-controlled coach sharing flags on `athletes/{uid}.privacySettings`.
/// Missing keys default to **shared** (true) so existing athletes keep current
/// coach visibility until they opt out.
class PrivacySettings {
  static const notShared = 'Not shared';

  static const wearableDataKey = 'wearableData';
  static const trainingLogsKey = 'trainingLogs';
  static const injuryHistoryKey = 'injuryHistory';
  static const dailyFatigueCheckInKey = 'dailyFatigueCheckIn';

  /// Heart rate, sleep, HRV (HealthKit or manual sleep on the check-in).
  final bool wearableData;

  /// Sessions, duration, intensity (session-RPE / training load / ACWR).
  final bool trainingLogs;

  /// Pain reports, soreness notes, HIGH-pain roster/alert signals.
  final bool injuryHistory;

  /// Daily 1–5 fatigue self-report.
  final bool dailyFatigueCheckIn;

  const PrivacySettings({
    this.wearableData = true,
    this.trainingLogs = true,
    this.injuryHistory = true,
    this.dailyFatigueCheckIn = true,
  });

  static const open = PrivacySettings();

  bool get allShared =>
      wearableData && trainingLogs && injuryHistory && dailyFatigueCheckIn;

  factory PrivacySettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return PrivacySettings.open;
    return PrivacySettings(
      wearableData: map[wearableDataKey] as bool? ?? true,
      trainingLogs: map[trainingLogsKey] as bool? ?? true,
      injuryHistory: map[injuryHistoryKey] as bool? ?? true,
      dailyFatigueCheckIn: map[dailyFatigueCheckInKey] as bool? ?? true,
    );
  }

  Map<String, bool> toMap() => {
        wearableDataKey: wearableData,
        trainingLogsKey: trainingLogs,
        injuryHistoryKey: injuryHistory,
        dailyFatigueCheckInKey: dailyFatigueCheckIn,
      };

  PrivacySettings copyWith({
    bool? wearableData,
    bool? trainingLogs,
    bool? injuryHistory,
    bool? dailyFatigueCheckIn,
  }) =>
      PrivacySettings(
        wearableData: wearableData ?? this.wearableData,
        trainingLogs: trainingLogs ?? this.trainingLogs,
        injuryHistory: injuryHistory ?? this.injuryHistory,
        dailyFatigueCheckIn: dailyFatigueCheckIn ?? this.dailyFatigueCheckIn,
      );

  /// Coach-facing alert types that must not appear when the matching
  /// category is toggled off.
  bool allowsCoachAlertType(String type) {
    switch (type) {
      case 'pain':
        return injuryHistory;
      case 'sync_failure':
        return wearableData;
      case 'risk_spike':
        return trainingLogs || dailyFatigueCheckIn || wearableData;
      default:
        return true;
    }
  }

  List<String> get withheldLabels {
    final labels = <String>[];
    if (!wearableData) labels.add('wearable data (heart rate, sleep, HRV)');
    if (!trainingLogs) labels.add('training logs (sessions, duration, intensity)');
    if (!injuryHistory) labels.add('injury history (pain reports)');
    if (!dailyFatigueCheckIn) labels.add('daily fatigue check-in');
    return labels;
  }
}
