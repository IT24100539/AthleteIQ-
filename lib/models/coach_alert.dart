import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'athlete_alert.dart';

class CoachAlert {
  final String id;
  final String type; // pain | risk_spike | missed_checkin | sync_failure
  final String urgency; // LOW | MEDIUM | HIGH
  final String athleteUid;
  final String athleteName;
  final String title;
  final String summary;
  final String? reportId;
  final DateTime timestamp;
  final bool read;

  const CoachAlert({
    required this.id,
    required this.type,
    required this.urgency,
    required this.athleteUid,
    required this.athleteName,
    required this.title,
    required this.summary,
    this.reportId,
    required this.timestamp,
    this.read = false,
  });

  bool get isHighPain =>
      type == 'pain' && urgency.toUpperCase() == 'HIGH';

  bool get isRiskSpike => type == 'risk_spike';

  Color get color {
    if (isHighPain || isRiskSpike) return AppColors.coral;
    switch (type) {
      case 'missed_checkin':
      case 'sync_failure':
        return AppColors.amber;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get icon {
    switch (type) {
      case 'pain':
        return Icons.healing_outlined;
      case 'risk_spike':
        return Icons.warning_amber_rounded;
      case 'missed_checkin':
        return Icons.notifications_active_outlined;
      case 'sync_failure':
        return Icons.sync_problem_outlined;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  String get timeAgo => formatAlertTimeAgo(timestamp);

  factory CoachAlert.fromMap(String id, Map<String, dynamic> map) => CoachAlert(
        id: id,
        type: map['type'] ?? 'pain',
        urgency: map['urgency'] ?? 'MEDIUM',
        athleteUid: map['athleteUid'] ?? '',
        athleteName: map['athleteName'] ?? 'Athlete',
        title: map['title'] ?? '',
        summary: map['summary'] ?? '',
        reportId: map['reportId'] as String?,
        timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
        read: map['read'] ?? false,
      );
}
