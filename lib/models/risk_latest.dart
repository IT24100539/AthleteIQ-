import '../models/risk_result.dart';

/// Parsed `athletes/{uid}/riskResults/latest`.
///
/// The pipeline writes `{ insufficientData: true, checkInCount: N }` instead
/// of a score when there are fewer than [calibrationCheckIns] check-ins.
class RiskLatest {
  static const calibrationCheckIns = 5;

  final RiskResult? result;
  final bool insufficientData;
  final int checkInCount;

  const RiskLatest({
    this.result,
    this.insufficientData = false,
    this.checkInCount = 0,
  });

  bool get hasCalibratedScore => result != null && !insufficientData;
}

String calibrationProgressLabel(int checkInCount, {int needed = RiskLatest.calibrationCheckIns}) {
  final n = checkInCount < 0 ? 0 : checkInCount;
  return '$n of $needed check-ins needed to calibrate';
}

String notEnoughDataSubtext({
  required int checkInCount,
  DateTime? joinedAt,
  DateTime? now,
}) {
  final parts = <String>[];
  if (joinedAt != null) {
    final days = (now ?? DateTime.now()).difference(joinedAt).inDays;
    if (days <= 0) {
      parts.add('This athlete joined today.');
    } else if (days == 1) {
      parts.add('This athlete joined 1 day ago.');
    } else {
      parts.add('This athlete joined $days days ago.');
    }
  }
  parts.add(
    'AthleteIQ needs about ${RiskLatest.calibrationCheckIns} days of training '
    'history before scoring risk or performance.',
  );
  parts.add(calibrationProgressLabel(checkInCount));
  return parts.join(' ');
}
