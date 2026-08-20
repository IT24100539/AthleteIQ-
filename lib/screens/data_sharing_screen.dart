import 'package:flutter/material.dart';
import '../models/privacy_settings.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';

class DataSharingScreen extends StatelessWidget {
  final String athleteUid;

  const DataSharingScreen({super.key, required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data sharing'),
        centerTitle: true,
      ),
      body: StreamBuilder<PrivacySettings>(
        stream: fs.streamPrivacySettings(athleteUid),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load sharing settings',
          );
          if (blocked != null) return blocked;

          final settings = snapshot.data ?? PrivacySettings.open;

          void toggleSetting(PrivacySettings updated) {
            fs.updatePrivacySettings(athleteUid, updated);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What your coach sees',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You still log everything for your own recommendations. '
                    'Turning a category off hides it from your coach — they will '
                    'see “Not shared”, not the underlying numbers.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 24),

                  _ConsentTile(
                    title: 'Wearable data',
                    subtitle: 'Heart rate, sleep, HRV',
                    value: settings.wearableData,
                    onChanged: (v) =>
                        toggleSetting(settings.copyWith(wearableData: v)),
                  ),
                  const SizedBox(height: 12),
                  _ConsentTile(
                    title: 'Training logs',
                    subtitle: 'Sessions, duration, intensity',
                    value: settings.trainingLogs,
                    onChanged: (v) =>
                        toggleSetting(settings.copyWith(trainingLogs: v)),
                  ),
                  const SizedBox(height: 12),
                  _ConsentTile(
                    title: 'Injury history',
                    subtitle: 'Past and current injuries',
                    value: settings.injuryHistory,
                    onChanged: (v) =>
                        toggleSetting(settings.copyWith(injuryHistory: v)),
                  ),
                  const SizedBox(height: 12),
                  _ConsentTile(
                    title: 'Daily fatigue check-in',
                    subtitle: 'Your 1–5 self-report',
                    value: settings.dailyFatigueCheckIn,
                    onChanged: (v) =>
                        toggleSetting(settings.copyWith(dailyFatigueCheckIn: v)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ConsentTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.mint,
            activeThumbColor: AppColors.mintDark,
          ),
        ],
      ),
    );
  }
}
