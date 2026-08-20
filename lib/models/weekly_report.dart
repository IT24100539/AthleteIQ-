class WeeklyDailyLoad {
  final String date;
  final double load;
  final int fatigue;

  const WeeklyDailyLoad({
    required this.date,
    required this.load,
    required this.fatigue,
  });

  factory WeeklyDailyLoad.fromMap(Map<String, dynamic> map) => WeeklyDailyLoad(
        date: map['date'] ?? '',
        load: (map['load'] as num?)?.toDouble() ?? 0,
        fatigue: (map['fatigue'] as num?)?.toInt() ?? 0,
      );
}

class WeeklyReport {
  final String weekStart;
  final String weekEnd;
  final String weekLabel;
  final int sessionsCompleted;
  final int restDays;
  final int checkInsLogged;
  final double totalTrainingLoad;
  final double? avgSleepHours;
  final double? avgFatigue;
  final double? peakAcwr;
  final double? endAcwr;
  final int coachAdjustments;
  final String? riskLevel;
  final String? recoveryTrend;
  final List<WeeklyDailyLoad> dailyLoads;
  final String narrative;
  final String narrativeSource; // llm | rules

  const WeeklyReport({
    required this.weekStart,
    required this.weekEnd,
    required this.weekLabel,
    required this.sessionsCompleted,
    required this.restDays,
    required this.checkInsLogged,
    required this.totalTrainingLoad,
    this.avgSleepHours,
    this.avgFatigue,
    this.peakAcwr,
    this.endAcwr,
    required this.coachAdjustments,
    this.riskLevel,
    this.recoveryTrend,
    required this.dailyLoads,
    required this.narrative,
    required this.narrativeSource,
  });

  factory WeeklyReport.fromMap(Map<String, dynamic> map) => WeeklyReport(
        weekStart: map['weekStart'] ?? '',
        weekEnd: map['weekEnd'] ?? '',
        weekLabel: map['weekLabel'] ?? '',
        sessionsCompleted: (map['sessionsCompleted'] as num?)?.toInt() ?? 0,
        restDays: (map['restDays'] as num?)?.toInt() ?? 0,
        checkInsLogged: (map['checkInsLogged'] as num?)?.toInt() ?? 0,
        totalTrainingLoad: (map['totalTrainingLoad'] as num?)?.toDouble() ?? 0,
        avgSleepHours: (map['avgSleepHours'] as num?)?.toDouble(),
        avgFatigue: (map['avgFatigue'] as num?)?.toDouble(),
        peakAcwr: (map['peakAcwr'] as num?)?.toDouble(),
        endAcwr: (map['endAcwr'] as num?)?.toDouble(),
        coachAdjustments: (map['coachAdjustments'] as num?)?.toInt() ?? 0,
        riskLevel: map['riskLevel'] as String?,
        recoveryTrend: map['recoveryTrend'] as String?,
        dailyLoads: (map['dailyLoads'] as List<dynamic>?)
                ?.map((d) => WeeklyDailyLoad.fromMap(Map<String, dynamic>.from(d)))
                .toList() ??
            [],
        narrative: map['narrative'] ?? '',
        narrativeSource: map['narrativeSource'] ?? 'rules',
      );
}
