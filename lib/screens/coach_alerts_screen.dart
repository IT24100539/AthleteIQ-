import 'package:flutter/material.dart';

import '../models/athlete.dart';
import '../models/coach_alert.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';
import 'coach_dashboard_screen.dart';

/// Team alerts for every athlete on this coach's roster — reads
/// `coaches/{coachUid}/alerts/` only (no seeded rows).
class CoachAlertsScreen extends StatelessWidget {
  final String coachUid;

  const CoachAlertsScreen({super.key, required this.coachUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<CoachAlert>>(
        stream: fs.streamCoachAlerts(coachUid),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load team alerts',
          );
          if (blocked != null) return blocked;

          final alerts = snapshot.data ?? [];
          if (alerts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No team alerts yet. Risk spikes, missed check-ins, and HIGH pain reports from your roster will appear here after the nightly pipeline runs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, height: 1.45),
                ),
              ),
            );
          }

          return SafeArea(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final alert = alerts[i];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: alert.athleteUid.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CoachDashboardScreen(
                                  athlete: AthleteProfile(
                                    uid: alert.athleteUid,
                                    name: alert.athleteName,
                                    createdAt: alert.timestamp,
                                  ),
                                ),
                              ),
                            );
                          },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: alert.isHighPain || alert.isRiskSpike
                              ? AppColors.coral.withValues(alpha: 0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: alert.color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(alert.icon, color: alert.color, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  alert.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                                if (alert.athleteName.isNotEmpty &&
                                    alert.athleteName != 'Athlete') ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    alert.athleteName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                if (alert.summary.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    alert.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  alert.timeAgo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: alert.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (alert.athleteUid.isNotEmpty)
                            Icon(
                              Icons.chevron_right,
                              color: AppColors.textFaint,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
