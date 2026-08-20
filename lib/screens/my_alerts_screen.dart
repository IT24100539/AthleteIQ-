import 'package:flutter/material.dart';
import '../models/athlete_alert.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/wearable_sync_status.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import 'connect_device_screen.dart';
import 'sync_failed_screen.dart';

class MyAlertsScreen extends StatelessWidget {
  final String athleteUid;

  const MyAlertsScreen({super.key, required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<AthleteAlert>>(
        stream: fs.streamAlerts(athleteUid),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load alerts',
          );
          if (blocked != null) return blocked;

          final alerts = snapshot.data ?? [];
          if (alerts.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.notifications_none,
                heading: 'No alerts yet',
                subtext:
                    'Risk spikes, missed check-ins, and sync issues will show up here after they actually happen. This list is empty — nothing is fabricated.',
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
                return InkWell(
                  onTap: alert.type == 'sync_failure'
                      ? () => _openSyncFailed(context, fs)
                      : null,
                  child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
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
                            const SizedBox(height: 4),
                            Text(
                              alert.timeAgo,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

  Future<void> _openSyncFailed(BuildContext context, FirestoreService fs) async {
    final devices = await fs.devicesOnce(athleteUid);
    if (!context.mounted) return;
    final issue = findWearableSyncIssue(devices);
    if (issue == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConnectDeviceScreen(
            athleteUid: athleteUid,
            isFromSettings: true,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncFailedScreen(
          issue: issue,
          asPage: true,
          onReconnect: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ConnectDeviceScreen(
                  athleteUid: athleteUid,
                  isFromSettings: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
