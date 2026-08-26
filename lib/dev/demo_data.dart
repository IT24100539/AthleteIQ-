import '../models/athlete.dart';
import '../models/athlete_alert.dart';
import '../models/chat_message.dart';
import '../models/checkin.dart';
import '../models/coach_alert.dart';
import '../models/pain_report.dart';
import '../models/privacy_settings.dart';
import '../models/risk_result.dart';
import '../models/team_settings.dart';
import '../models/weekly_report.dart';
import 'demo_accounts.dart';

/// Sample records used to seed debug demo accounts into Firestore.
class DemoData {
  static DateTime _day(int daysAgo, {int hour = 12}) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysAgo));
    return DateTime(d.year, d.month, d.day, hour);
  }

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static AthleteProfile athleteProfile(String athleteUid, {String? coachUid}) {
    return AthleteProfile(
      uid: athleteUid,
      name: DemoAccounts.athleteName,
      sport: DemoAccounts.athleteSport,
      sportGroup: SportGroup.endurance,
      sportClassificationConfidence: 'high',
      sportClassificationSource: 'demo',
      coachUid: coachUid ?? DemoSession.coachUid,
      createdAt: _day(40),
      deviceTier: 'tier1',
      deviceSetupCompleted: true,
      activeDevice: 'Apple Watch',
      latestPainUrgency: 'MEDIUM',
      latestPainAt: _day(1, hour: 18),
      latestPainSummary: 'Left calf (3/5)',
      privacySettings: PrivacySettings.open,
    );
  }

  static TeamSettings teamSettings() => const TeamSettings(
        defaultActionPercent: 20,
        teamName: 'Demo Track Club',
      );

  static List<CheckIn> checkIns() {
    const loads = <(int minutes, int rpe, int fatigue, double sleep, double rhr, double hrv, bool rest)>[
      (50, 6, 3, 7.4, 52, 68, false),
      (0, 0, 2, 8.1, 50, 74, true),
      (65, 7, 3, 7.0, 53, 62, false),
      (40, 5, 2, 7.6, 51, 70, false),
      (70, 8, 4, 6.4, 55, 55, false),
      (0, 0, 3, 7.8, 52, 66, true),
      (55, 6, 3, 7.2, 53, 64, false),
      (45, 5, 2, 7.9, 51, 71, false),
      (80, 7, 4, 6.8, 54, 58, false),
      (0, 0, 2, 8.0, 50, 73, true),
      (50, 6, 3, 7.3, 52, 67, false),
      (35, 4, 2, 7.7, 51, 69, false),
      (60, 7, 3, 7.1, 53, 63, false),
      (48, 6, 3, 7.5, 52, 66, false),
    ];
    return [
      for (var i = 0; i < loads.length; i++)
        CheckIn(
          id: dateKey(_day(loads.length - 1 - i)),
          date: _day(loads.length - 1 - i),
          sessionDurationMinutes: loads[i].$7 ? 0 : loads[i].$1,
          rpe: loads[i].$7 ? 0 : loads[i].$2,
          fatigueScore: loads[i].$3,
          sleepHours: loads[i].$4,
          restingHeartRate: loads[i].$5,
          hrv: loads[i].$6,
          soreness: loads[i].$3 >= 4 ? 'Left calf tightness' : null,
          source: i.isEven ? 'wearable' : 'manual',
        ),
    ];
  }

  static RiskResult riskResult() {
    return RiskResult(
      riskLevel: 'MEDIUM',
      confidence: 'High (HRV + sleep available)',
      reason:
          '7-day load is up versus the 28-day baseline (ACWR 1.18). Sleep dipped after the harder session two days ago; HRV is still in a normal band.',
      acwr: 1.18,
      trainingLoad7d: 1860,
      trainingLoad28dAvg: 1570,
      recoveryTrend: 'stable',
      performancePrediction: 'AVERAGE',
      performanceFrame: 'Hold quality, do not stack another hard day',
      performanceFrameAxis: 'Readiness',
      riskLevelReasoningLLM:
          'Load is moderately elevated, not a spike. Pair today with aerobic work and a full night of sleep.',
      riskLevelPatternFlag: 'acwr_elevated',
      performanceReasoningLLM:
          'Freshness is adequate for technique work. Avoid a second key session until tomorrow.',
      recommendation:
          'Easy aerobic 40–50 min. Keep RPE at 4–5. No intervals. Sleep 8 hours tonight.',
      recommendationStatus: 'approved',
      gradedOptions: const [
        GradedOption(
          tier: 'Conservative',
          action: 'Rest or 30 min walk / mobility only',
          reason: 'Clears residual fatigue from the last quality session.',
        ),
        GradedOption(
          tier: 'Moderate',
          action: 'Easy aerobic 40–50 min at RPE 4–5',
          reason: 'Maintains volume without stacking intensity.',
        ),
        GradedOption(
          tier: 'Minimal change',
          action: 'Planned session as written, cap RPE at 6',
          reason: 'ACWR is still inside the typical 0.8–1.3 band.',
        ),
      ],
      researchNote:
          'Acute:chronic workload ratio near 1.2 is associated with a modest rise in injury risk versus 0.8–1.0, especially when sleep is short.',
      researchCitations: const [
        ResearchCitation(
          tag: 'ACWR',
          text:
              'Rapid weekly load spikes (ACWR above ~1.5) are linked with higher injury incidence in endurance and team-sport cohorts.',
          source: 'Gabbett, BJSM',
        ),
        ResearchCitation(
          tag: 'Sleep',
          text:
              'Restricted sleep reduces next-day recovery markers and raises perceived exertion for the same external load.',
          source: 'Fullagar et al.',
        ),
      ],
      calculatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      fatiguePersistent: false,
      avgFatigue7d: 2.9,
      orchestratorSafetyOverride: false,
      orchestratorSource: 'demo',
      ruleBasedRecommendation: 'Easy aerobic 40–50 min. Keep RPE at 4–5.',
      ruleBasedOrchestratorNote: 'Rules and demo overlay agree on an easy day.',
      orchestratorAgreedWithRules: true,
    );
  }

  static List<RiskHistoryPoint> riskHistory() {
    const rows = <(double acwr, String perf, String recovery, String risk, double load7, double load28, double fatigue)>[
      (0.92, 'GOOD', 'improving', 'LOW', 1420, 1540, 2.4),
      (0.95, 'GOOD', 'stable', 'LOW', 1480, 1545, 2.5),
      (1.01, 'AVERAGE', 'stable', 'LOW', 1560, 1550, 2.6),
      (1.04, 'AVERAGE', 'stable', 'LOW', 1610, 1555, 2.7),
      (1.08, 'AVERAGE', 'stable', 'MEDIUM', 1680, 1560, 2.8),
      (1.05, 'AVERAGE', 'improving', 'LOW', 1640, 1562, 2.6),
      (1.11, 'AVERAGE', 'stable', 'MEDIUM', 1720, 1565, 2.9),
      (1.09, 'AVERAGE', 'stable', 'MEDIUM', 1700, 1566, 2.8),
      (1.14, 'AVERAGE', 'worsening', 'MEDIUM', 1780, 1568, 3.1),
      (1.10, 'AVERAGE', 'stable', 'MEDIUM', 1740, 1569, 2.9),
      (1.16, 'AVERAGE', 'stable', 'MEDIUM', 1820, 1570, 3.0),
      (1.13, 'AVERAGE', 'improving', 'MEDIUM', 1790, 1570, 2.8),
      (1.17, 'AVERAGE', 'stable', 'MEDIUM', 1840, 1570, 2.9),
      (1.18, 'AVERAGE', 'stable', 'MEDIUM', 1860, 1570, 2.9),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        RiskHistoryPoint(
          id: dateKey(_day(rows.length - 1 - i)),
          date: _day(rows.length - 1 - i),
          acwr: rows[i].$1,
          performancePrediction: rows[i].$2,
          performanceFrame: rows[i].$2 == 'GOOD'
              ? 'Green for quality work'
              : 'Hold quality, do not stack another hard day',
          performanceFrameAxis: 'Readiness',
          recoveryTrend: rows[i].$3,
          riskLevel: rows[i].$4,
          trainingLoad7d: rows[i].$5,
          trainingLoad28dAvg: rows[i].$6,
          avgFatigue7d: rows[i].$7,
        ),
    ];
  }

  static Map<String, Map<String, dynamic>> devices() {
    final now = DateTime.now().toIso8601String();
    return {
      'apple_watch': {
        'name': 'Apple Watch',
        'tier': 'tier1',
        'connected': true,
        'connectedAt': _day(12).toIso8601String(),
        'lastSync': now,
        'updatedAt': now,
        'metrics': {
          'restingHeartRate': 52,
          'hrv': 66,
          'sleepHours': 7.5,
        },
        'permissions': {
          'heartRate': true,
          'hrv': true,
          'workouts': true,
          'sleep': true,
        },
      },
      'garmin': {
        'name': 'Garmin',
        'connected': false,
        'tier': 'tier1',
      },
      'whoop': {
        'name': 'Whoop',
        'connected': false,
        'tier': 'tier1',
      },
    };
  }

  static List<ChatMessage> aiChat(String athleteUid) {
    return [
      ChatMessage(
        id: 'demo-ai-1',
        senderUid: athleteUid,
        senderName: DemoAccounts.athleteName,
        text: 'Should I run intervals today? My calf felt tight yesterday.',
        timestamp: _day(0, hour: 8),
        isAi: false,
      ),
      ChatMessage(
        id: 'demo-ai-2',
        senderUid: 'athlete_iq_ai',
        senderName: 'AthleteIQ AI',
        text:
            'Your 7-day load is up (ACWR 1.18) and the coach-approved plan is an easy aerobic day. Skip intervals. If the calf is still a 3/5 or more after the warmup, stop and message Jordan.',
        timestamp: _day(0, hour: 8).add(const Duration(minutes: 1)),
        isAi: true,
      ),
    ];
  }

  static List<ChatMessage> coachMessages(String athleteUid, String coachUid) {
    return [
      ChatMessage(
        id: 'demo-msg-1',
        senderUid: athleteUid,
        senderName: DemoAccounts.athleteName,
        text: 'Calf is a 3/5 after yesterday. Want me to still do the workout?',
        timestamp: _day(1, hour: 19),
        isCoach: false,
        read: true,
      ),
      ChatMessage(
        id: 'demo-msg-2',
        senderUid: coachUid,
        senderName: DemoAccounts.coachName,
        text:
            'Keep today easy — 40 to 50 minutes, no speed. Ice after if it tightens. I approved that plan on your dashboard.',
        timestamp: _day(1, hour: 19).add(const Duration(minutes: 22)),
        isCoach: true,
        read: true,
      ),
      ChatMessage(
        id: 'demo-msg-3',
        senderUid: athleteUid,
        senderName: DemoAccounts.athleteName,
        text: 'Got it — easy run this morning. Will check in after.',
        timestamp: _day(0, hour: 7),
        isCoach: false,
        read: false,
      ),
    ];
  }

  static List<PainReport> painReports(String athleteUid) {
    return [
      PainReport(
        id: 'demo-pain-1',
        athleteUid: athleteUid,
        date: _day(1, hour: 18),
        areas: const [PainArea(location: 'Left calf', severity: 3)],
        note: 'Tightened in the last 2 km. No sharp pain.',
        urgency: 'MEDIUM',
        urgencyReason: 'Single area at 3/5, still able to train easy.',
        urgencySource: 'demo',
      ),
    ];
  }

  static List<AthleteAlert> athleteAlerts() {
    return [
      AthleteAlert(
        id: 'demo-alert-1',
        title: 'Jordan approved your training plan',
        timeAgo: '2h ago',
        type: 'approval',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        read: false,
      ),
      AthleteAlert(
        id: 'demo-alert-2',
        title: 'New message from Jordan Hale',
        timeAgo: '1d ago',
        type: 'message',
        timestamp: _day(1, hour: 19),
        read: true,
      ),
    ];
  }

  static List<CoachAlert> coachAlerts(String athleteUid) {
    return [
      CoachAlert(
        id: 'demo-coach-alert-1',
        type: 'pain',
        urgency: 'MEDIUM',
        athleteUid: athleteUid,
        athleteName: DemoAccounts.athleteName,
        title: 'Pain report — ${DemoAccounts.athleteName}',
        summary: 'Left calf (3/5)',
        reportId: 'demo-pain-1',
        timestamp: _day(1, hour: 18),
        read: false,
      ),
      CoachAlert(
        id: 'demo-coach-alert-2',
        type: 'risk_spike',
        urgency: 'MEDIUM',
        athleteUid: athleteUid,
        athleteName: DemoAccounts.athleteName,
        title: 'ACWR trending up — ${DemoAccounts.athleteName}',
        summary: 'ACWR 1.18 · 7-day load 1860',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        read: false,
      ),
    ];
  }

  static WeeklyReport weeklyReport() {
    final start = _day(6);
    final end = _day(0);
    return WeeklyReport(
      weekStart: dateKey(start),
      weekEnd: dateKey(end),
      weekLabel: 'This week',
      sessionsCompleted: 5,
      restDays: 2,
      checkInsLogged: 7,
      totalTrainingLoad: 1860,
      avgSleepHours: 7.4,
      avgFatigue: 2.9,
      peakAcwr: 1.18,
      endAcwr: 1.18,
      coachAdjustments: 1,
      riskLevel: 'MEDIUM',
      recoveryTrend: 'stable',
      dailyLoads: [
        for (final c in checkIns().where((e) => e.date.isAfter(start.subtract(const Duration(hours: 1)))))
          WeeklyDailyLoad(
            date: dateKey(c.date),
            load: c.trainingLoad ?? 0,
            fatigue: c.fatigueScore,
          ),
      ],
      narrative:
          'Alex logged 5 sessions and 2 rest days. Load rose modestly (ACWR 1.18) after the quality work mid-week. Sleep averaged 7.4 hours. The approved plan for today is easy aerobic volume — no intervals — while the left calf settles.',
      narrativeSource: 'demo',
    );
  }
}
