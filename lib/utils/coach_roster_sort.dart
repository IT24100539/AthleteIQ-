import '../models/athlete.dart';
import '../models/risk_result.dart';

int coachRiskSortRank(String? riskLevel) {
  switch ((riskLevel ?? 'LOW').toUpperCase()) {
    case 'HIGH':
      return 0;
    case 'MEDIUM':
      return 1;
    default:
      return 2;
  }
}

/// Priority queue logic for the roster — pending approval, HIGH risk, or HIGH pain.
bool athleteNeedsReview(AthleteProfile athlete, RiskResult? risk) {
  if ((athlete.latestPainUrgency ?? '').toUpperCase() == 'HIGH') return true;
  if (risk == null) return false;
  if (risk.riskLevel.toUpperCase() == 'HIGH') return true;
  if ((risk.recommendationStatus ?? 'pending') == 'pending') return true;
  return false;
}

int countAthletesNeedingReview(
  List<AthleteProfile> athletes,
  Map<String, RiskResult?> riskByUid,
) {
  return athletes.where((a) => athleteNeedsReview(a, riskByUid[a.uid])).length;
}

List<AthleteProfile> sortCoachRoster(
  List<AthleteProfile> athletes,
  Map<String, RiskResult?> riskByUid,
  Map<String, DateTime?> lastCheckInByUid,
) {
  final sorted = List<AthleteProfile>.from(athletes);
  sorted.sort((a, b) {
    final riskA = coachRiskSortRank(riskByUid[a.uid]?.riskLevel);
    final riskB = coachRiskSortRank(riskByUid[b.uid]?.riskLevel);
    if (riskA != riskB) return riskA.compareTo(riskB);

    final checkInA = lastCheckInByUid[a.uid];
    final checkInB = lastCheckInByUid[b.uid];
    if (checkInA == null && checkInB == null) return 0;
    if (checkInA == null) return 1;
    if (checkInB == null) return -1;
    return checkInB.compareTo(checkInA);
  });
  return sorted;
}
