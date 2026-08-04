import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_chip.dart';
import '../widgets/stat_card.dart';

class CoachDashboardScreen extends StatelessWidget {
  final AthleteProfile athlete;
  const CoachDashboardScreen({super.key, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: Text(athlete.name)),
      body: StreamBuilder<RiskResult?>(
        stream: fs.latestRiskResult(athlete.uid),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No forecast for this athlete yet. AthleteIQ needs about 5 days of '
                  'check-ins before scoring risk or performance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          final isPending = (result.recommendationStatus ?? 'pending') == 'pending';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    RiskChip(level: result.riskLevel),
                    const SizedBox(width: 8),
                    Text('Confidence: ${result.confidence}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'ACWR', value: result.acwr.toStringAsFixed(2))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            label: '7d load', value: result.trainingLoad7d.toStringAsFixed(0))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            label: '28d avg', value: result.trainingLoad28dAvg.toStringAsFixed(0))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: StatCard(label: 'Recovery trend', value: result.recoveryTrend)),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            StatCard(label: 'Performance', value: result.performancePrediction)),
                  ],
                ),
                const SizedBox(height: 16),
                // Explainability Agent output — Section 6 / 13.4.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WHY THIS CALL',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(result.reason),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RECOMMENDATION',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.coral, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(result.recommendation, style: const TextStyle(fontSize: 15)),
                      if (result.recommendationStatus != null && !isPending) ...[
                        const SizedBox(height: 8),
                        Text('Status: ${result.recommendationStatus}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              fs.reviewRecommendation(athlete.uid, decision: 'approved'),
                          child: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              fs.reviewRecommendation(athlete.uid, decision: 'rejected'),
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _showModifyDialog(context, fs, athlete.uid, result),
                    child: const Text('Modify before sending'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showModifyDialog(
    BuildContext context,
    FirestoreService fs,
    String athleteUid,
    RiskResult result,
  ) {
    final controller = TextEditingController(text: result.recommendation);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Modify recommendation'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              fs.reviewRecommendation(
                athleteUid,
                decision: 'modified',
                modifiedText: controller.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Send to athlete'),
          ),
        ],
      ),
    );
  }
}
