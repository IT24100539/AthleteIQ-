import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/risk_result.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_chip.dart';
import '../widgets/stat_card.dart';
import 'checkin_screen.dart';

class AthleteHomeScreen extends StatelessWidget {
  final String athleteUid;
  const AthleteHomeScreen({super.key, required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AthleteIQ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<RiskResult?>(
        stream: fs.latestRiskResult(athleteUid),
        builder: (context, snapshot) {
          final result = snapshot.data;

          if (!snapshot.hasData || result == null) {
            // Section — "No data yet" empty state from the wireframe.
            return _EmptyState(
              title: 'Building your first forecast',
              text:
                  'Log a few more days of training and how you feel before AthleteIQ can predict '
                  'performance or risk reliably.',
              buttonLabel: 'Log today',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CheckInScreen(athleteUid: athleteUid)),
              ),
            );
          }

          final isApproved = result.recommendationStatus == 'approved';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF153A30), Color(0xFF0F2A22)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text('THIS WEEK', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      RiskChip(level: result.riskLevel),
                      const SizedBox(height: 10),
                      Text(
                        result.confidence,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: StatCard(
                            label: 'ACWR', value: result.acwr.toStringAsFixed(2))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            label: 'Recovery', value: result.recoveryTrend)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            label: 'Performance', value: result.performancePrediction)),
                  ],
                ),
                const SizedBox(height: 16),
                // Section 17.3 — athlete only ever sees an approved, plain-
                // language recommendation, never a raw unapproved score.
                if (isApproved)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "COACH'S RECOMMENDATION",
                          style: TextStyle(
                              fontSize: 11, color: AppColors.coral, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(result.recommendation),
                        const SizedBox(height: 4),
                        Text(result.reason, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Your coach is reviewing today\'s recommendation. '
                      "You'll see it here once approved.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CheckInScreen(athleteUid: athleteUid)),
                  ),
                  child: const Text("Log today's check-in"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback onTap;

  const _EmptyState({
    required this.title,
    required this.text,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onTap, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
