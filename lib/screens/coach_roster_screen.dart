import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/risk_result.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_chip.dart';
import 'coach_dashboard_screen.dart';

class CoachRosterScreen extends StatefulWidget {
  final String coachUid;
  const CoachRosterScreen({super.key, required this.coachUid});

  @override
  State<CoachRosterScreen> createState() => _CoachRosterScreenState();
}

class _CoachRosterScreenState extends State<CoachRosterScreen> {
  final _fs = FirestoreService();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your athletes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search athletes…',
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textFaint),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AthleteProfile>>(
              stream: _fs.rosterForCoach(widget.coachUid),
              builder: (context, snapshot) {
                final roster = (snapshot.data ?? [])
                    .where((a) => a.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();

                if (roster.isEmpty) {
                  return const Center(
                    child: Text(
                      'No athletes yet.\nInvite an athlete and set your uid as their coachUid.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: roster.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final athlete = roster[i];
                    return StreamBuilder<RiskResult?>(
                      stream: _fs.latestRiskResult(athlete.uid),
                      builder: (context, riskSnap) {
                        final level = riskSnap.data?.riskLevel ?? 'LOW';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.surface,
                            child: Text(
                              athlete.name.isNotEmpty ? athlete.name[0] : '?',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                          title: Text(athlete.name),
                          subtitle: Text(athlete.sport ?? 'Sport not set'),
                          trailing: RiskChip(level: level),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CoachDashboardScreen(athlete: athlete),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
