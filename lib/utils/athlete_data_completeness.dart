import '../models/athlete.dart';
import '../models/checkin.dart';

/// Describes what data tier an athlete is on and which signals are missing
/// for the risk pipeline (Section 9 — Works With Any Device).
class AthleteDataCompleteness {
  final String tierLabel;
  final String tierSummary;
  final List<String> missing;

  const AthleteDataCompleteness({
    required this.tierLabel,
    required this.tierSummary,
    required this.missing,
  });

  bool get hasGaps => missing.isNotEmpty;

  static AthleteDataCompleteness analyze(
    AthleteProfile athlete,
    List<CheckIn> recentCheckIns,
  ) {
    final tier = athlete.deviceTier;
    final missing = <String>[];

    final privacy = athlete.privacySettings;
    final hasHrv = privacy.wearableData && recentCheckIns.any((c) => c.hrv != null);
    final hasRhr =
        privacy.wearableData && recentCheckIns.any((c) => c.restingHeartRate != null);
    final hasSleep =
        privacy.wearableData && recentCheckIns.any((c) => c.sleepHours != null);
    final latest = recentCheckIns.isEmpty ? null : recentCheckIns.first;

    late final String tierLabel;
    late final String tierSummary;

    if (!privacy.wearableData) {
      missing.add('Wearable data is not shared with you');
    }

    switch (tier) {
      case 'tier1':
        tierLabel = 'Tier 1 · Full biometrics';
        tierSummary =
            'Apple Watch / Tier-1 wearable — HRV, resting HR, sleep, and load expected.';
        if (privacy.wearableData && !hasHrv) {
          missing.add('HRV not available for this athlete');
        }
        if (privacy.wearableData && !hasRhr) {
          missing.add('Resting heart rate not syncing');
        }
        break;
      case 'tier2':
        tierLabel = 'Tier 2 · Partial wearable';
        tierSummary =
            'Health Connect / Android wearable — heart rate, sleep, and steps may sync; HRV is usually unavailable at this tier.';
        if (privacy.wearableData && !hasRhr) {
          missing.add('Resting heart rate not syncing');
        }
        if (privacy.wearableData && !hasHrv) {
          missing.add('HRV not available for this athlete');
        }
        break;
      default:
        tierLabel = 'Tier 3 · Manual logs';
        tierSummary =
            'Session-RPE and self-reported fatigue only — no wearable biometrics.';
        if (privacy.wearableData) {
          missing.add('HRV not available for this athlete');
          missing.add('Resting heart rate not syncing');
        }
        break;
    }

    if (recentCheckIns.isEmpty) {
      missing.add('No check-ins logged yet');
    } else if (latest != null) {
      final daysSince = DateTime.now().difference(latest.date).inDays;
      if (daysSince >= 2) {
        missing.add('Last check-in $daysSince days ago');
      }
      if (!hasSleep && privacy.wearableData) {
        missing.add('Sleep not recorded in recent check-ins');
      }
    }

    return AthleteDataCompleteness(
      tierLabel: tierLabel,
      tierSummary: tierSummary,
      missing: missing.toSet().toList(),
    );
  }
}
