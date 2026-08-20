import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

String formatAlertTimeAgo(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return '1d ago';
  return '${diff.inDays}d ago';
}

class AthleteAlert {
  final String id;
  final String title;
  final String timeAgo;
  final String type;
  final DateTime timestamp;
  final bool read;

  const AthleteAlert({
    required this.id,
    required this.title,
    required this.timeAgo,
    required this.type,
    required this.timestamp,
    this.read = false,
  });

  Color get color {
    switch (type) {
      case 'approval':
        return AppColors.mint;
      case 'risk_spike':
      case 'pain':
        return AppColors.coral;
      case 'reminder':
      case 'missed_checkin':
      case 'sync_failure':
        return AppColors.amber;
      case 'message':
        return AppColors.textSecondary;
      default:
        return AppColors.mint;
    }
  }

  IconData get icon {
    switch (type) {
      case 'approval':
        return Icons.check_circle_outline;
      case 'risk_spike':
        return Icons.warning_amber_rounded;
      case 'missed_checkin':
        return Icons.notifications_active_outlined;
      case 'sync_failure':
        return Icons.sync_problem_outlined;
      case 'pain':
        return Icons.healing_outlined;
      case 'message':
        return Icons.chat_bubble_outline;
      default:
        return Icons.bolt;
    }
  }

  factory AthleteAlert.fromMap(String id, Map<String, dynamic> map) {
    final timestamp = DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now();
    return AthleteAlert(
      id: id,
      title: map['title'] ?? '',
      timeAgo: formatAlertTimeAgo(timestamp),
      type: map['type'] ?? 'system',
      timestamp: timestamp,
      read: map['read'] ?? false,
    );
  }
}
