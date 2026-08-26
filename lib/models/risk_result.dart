/// Mirrors the shape written by the `recalculateRisk` Cloud Function
/// (functions/src/index.ts) into athletes/{uid}/riskResults/latest.
class RiskResult {
  final String riskLevel; // LOW | MEDIUM | HIGH
  final String confidence; // e.g. "Medium (HRV not available)"
  final String reason; // plain-language explanation
  final double acwr;
  final double trainingLoad7d;
  final double trainingLoad28dAvg;
  final String recoveryTrend; // 'improving' | 'stable' | 'worsening'
  final String performancePrediction; // GOOD | AVERAGE | DECLINING
  final String? performanceFrame;
  final String? performanceFrameAxis;
  final String? riskLevelReasoningLLM;
  final String? riskLevelPatternFlag;
  final String? performanceReasoningLLM;
  final String recommendation;
  final String? recommendationStatus; // pending | approved | rejected | modified
  final String? reviewedBy;
  final String? reviewedAt;
  final List<GradedOption> gradedOptions;
  final String? researchNote;
  final List<ResearchCitation> researchCitations;
  final DateTime calculatedAt;
  final bool fatiguePersistent;
  final double? avgFatigue7d;
  final OrchestratorConflict? orchestratorConflict;
  final bool orchestratorSafetyOverride;
  final String? orchestratorSource;
  final String? ruleBasedRecommendation;
  final String? ruleBasedOrchestratorNote;
  final bool? orchestratorAgreedWithRules;

  RiskResult({
    required this.riskLevel,
    required this.confidence,
    required this.reason,
    required this.acwr,
    required this.trainingLoad7d,
    required this.trainingLoad28dAvg,
    required this.recoveryTrend,
    required this.performancePrediction,
    this.performanceFrame,
    this.performanceFrameAxis,
    this.riskLevelReasoningLLM,
    this.riskLevelPatternFlag,
    this.performanceReasoningLLM,
    required this.recommendation,
    this.recommendationStatus,
    this.reviewedBy,
    this.reviewedAt,
    this.gradedOptions = const [],
    this.researchNote,
    this.researchCitations = const [],
    required this.calculatedAt,
    this.fatiguePersistent = false,
    this.avgFatigue7d,
    this.orchestratorConflict,
    this.orchestratorSafetyOverride = false,
    this.orchestratorSource,
    this.ruleBasedRecommendation,
    this.ruleBasedOrchestratorNote,
    this.orchestratorAgreedWithRules,
  });

  String get performanceDisplay =>
      (performanceFrame != null && performanceFrame!.isNotEmpty)
          ? performanceFrame!
          : performancePrediction;

  String get performanceAxisLabel =>
      (performanceFrameAxis != null && performanceFrameAxis!.isNotEmpty)
          ? performanceFrameAxis!
          : 'Performance';

  /// True once the coach has approved or modified-and-sent the plan.
  bool get isReleasedToAthlete {
    final s = (recommendationStatus ?? 'pending').toLowerCase();
    return s == 'approved' || s == 'modified';
  }

  factory RiskResult.fromMap(Map<String, dynamic> map) => RiskResult(
        riskLevel: map['riskLevel'] ?? 'LOW',
        confidence: map['confidence'] ?? '',
        reason: map['reason'] ?? '',
        acwr: (map['acwr'] as num?)?.toDouble() ?? 0,
        trainingLoad7d: (map['trainingLoad7d'] as num?)?.toDouble() ?? 0,
        trainingLoad28dAvg: (map['trainingLoad28dAvg'] as num?)?.toDouble() ?? 0,
        recoveryTrend: map['recoveryTrend'] ?? 'stable',
        performancePrediction: map['performancePrediction'] ?? 'AVERAGE',
        performanceFrame: map['performanceFrame'] as String?,
        performanceFrameAxis: map['performanceFrameAxis'] as String?,
        riskLevelReasoningLLM: map['riskLevelReasoningLLM'] as String?,
        riskLevelPatternFlag: map['riskLevelPatternFlag'] as String?,
        performanceReasoningLLM: map['performanceReasoningLLM'] as String?,
        recommendation: map['recommendation'] ?? '',
        recommendationStatus: map['recommendationStatus'],
        reviewedBy: map['reviewedBy'] as String?,
        reviewedAt: map['reviewedAt'] as String?,
        gradedOptions: _parseGradedOptions(map['gradedOptions']),
        researchNote: map['researchNote'] as String?,
        researchCitations: _parseCitations(map['researchCitations']),
        calculatedAt: DateTime.tryParse(map['calculatedAt'] ?? '') ?? DateTime.now(),
        fatiguePersistent: map['fatiguePersistent'] == true,
        avgFatigue7d: (map['avgFatigue7d'] as num?)?.toDouble(),
        orchestratorConflict: OrchestratorConflict.tryParse(map['orchestratorConflict']),
        orchestratorSafetyOverride: map['orchestratorSafetyOverride'] == true,
        orchestratorSource: map['orchestratorSource'] as String?,
        ruleBasedRecommendation: map['ruleBasedRecommendation'] as String?,
        ruleBasedOrchestratorNote: map['ruleBasedOrchestratorNote'] as String?,
        orchestratorAgreedWithRules: map['orchestratorAgreedWithRules'] as bool?,
      );
}

/// Stored copy of `describeOrchestratorConflict()` from recommendationEngine.ts.
/// `present` is the only signal the dashboard uses to show the conflict screen.
class OrchestratorConflict {
  final bool present;
  final String kind;
  final String winner;
  final String winnerLabel;
  final String why;
  final String riskLevel;
  final String performancePrediction;
  final String? actionWon;
  final String? ruleBasedAction;
  final bool safetyOverride;
  final bool agreedWithRules;
  final String? source;

  const OrchestratorConflict({
    required this.present,
    required this.kind,
    required this.winner,
    required this.winnerLabel,
    required this.why,
    required this.riskLevel,
    required this.performancePrediction,
    this.actionWon,
    this.ruleBasedAction,
    this.safetyOverride = false,
    this.agreedWithRules = true,
    this.source,
  });

  static OrchestratorConflict? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return OrchestratorConflict(
      present: map['present'] == true,
      kind: map['kind'] ?? 'none',
      winner: map['winner'] ?? 'aligned',
      winnerLabel: map['winnerLabel'] ?? 'Aligned',
      why: map['why'] ?? '',
      riskLevel: map['riskLevel'] ?? 'LOW',
      performancePrediction: map['performancePrediction'] ?? 'AVERAGE',
      actionWon: map['actionWon'] as String?,
      ruleBasedAction: map['ruleBasedAction'] as String?,
      safetyOverride: map['safetyOverride'] == true,
      agreedWithRules: map['agreedWithRules'] != false,
      source: map['source'] as String?,
    );
  }
}

/// Section 16.3 — Conservative / Moderate / Minimal change.
class GradedOption {
  final String tier;
  final String action;
  final String reason;

  const GradedOption({
    required this.tier,
    required this.action,
    required this.reason,
  });

  factory GradedOption.fromMap(Map<String, dynamic> map) => GradedOption(
        tier: map['tier'] ?? '',
        action: map['action'] ?? '',
        reason: map['reason'] ?? '',
      );
}

List<GradedOption> _parseGradedOptions(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => GradedOption.fromMap(Map<String, dynamic>.from(m)))
      .where((o) => o.action.isNotEmpty)
      .toList();
}

class ResearchCitation {
  final String tag;
  final String text;
  final String source;

  const ResearchCitation({
    required this.tag,
    required this.text,
    required this.source,
  });

  factory ResearchCitation.fromMap(Map<String, dynamic> map) => ResearchCitation(
        tag: map['tag'] ?? '',
        text: map['text'] ?? '',
        source: map['source'] ?? '',
      );
}

List<ResearchCitation> _parseCitations(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => ResearchCitation.fromMap(Map<String, dynamic>.from(m)))
      .where((c) => c.text.isNotEmpty)
      .toList();
}

/// One day's stored (or reconstructed) risk snapshot for trend charts.
class RiskHistoryPoint {
  final String id;
  final DateTime date;
  final double acwr;
  final String performancePrediction; // GOOD | AVERAGE | DECLINING
  final String? performanceFrame;
  final String? performanceFrameAxis;
  final String recoveryTrend;
  final String riskLevel;
  final double trainingLoad7d;
  final double trainingLoad28dAvg;
  final double? avgFatigue7d;
  final bool fatiguePersistent;

  const RiskHistoryPoint({
    required this.id,
    required this.date,
    required this.acwr,
    required this.performancePrediction,
    this.performanceFrame,
    this.performanceFrameAxis,
    required this.recoveryTrend,
    required this.riskLevel,
    required this.trainingLoad7d,
    required this.trainingLoad28dAvg,
    this.avgFatigue7d,
    this.fatiguePersistent = false,
  });

  /// 0 = DECLINING, 1 = AVERAGE, 2 = GOOD — for the forecast line chart.
  double get performanceY {
    switch (performancePrediction.toUpperCase()) {
      case 'GOOD':
        return 2;
      case 'DECLINING':
        return 0;
      default:
        return 1;
    }
  }

  factory RiskHistoryPoint.fromMap(String id, Map<String, dynamic> map) {
    final calculated = DateTime.tryParse(map['calculatedAt'] ?? '');
    final fromId = DateTime.tryParse(id);
    return RiskHistoryPoint(
      id: id,
      date: fromId ?? calculated ?? DateTime.now(),
      acwr: (map['acwr'] as num?)?.toDouble() ?? 0,
      performancePrediction: map['performancePrediction'] ?? 'AVERAGE',
      performanceFrame: map['performanceFrame'] as String?,
      performanceFrameAxis: map['performanceFrameAxis'] as String?,
      recoveryTrend: map['recoveryTrend'] ?? 'stable',
      riskLevel: map['riskLevel'] ?? 'LOW',
      trainingLoad7d: (map['trainingLoad7d'] as num?)?.toDouble() ?? 0,
      trainingLoad28dAvg: (map['trainingLoad28dAvg'] as num?)?.toDouble() ?? 0,
      avgFatigue7d: (map['avgFatigue7d'] as num?)?.toDouble(),
      fatiguePersistent: map['fatiguePersistent'] == true,
    );
  }

  factory RiskHistoryPoint.fromLatest(RiskResult latest) => RiskHistoryPoint(
        id: _dateKey(latest.calculatedAt),
        date: latest.calculatedAt,
        acwr: latest.acwr,
        performancePrediction: latest.performancePrediction,
        performanceFrame: latest.performanceFrame,
        performanceFrameAxis: latest.performanceFrameAxis,
        recoveryTrend: latest.recoveryTrend,
        riskLevel: latest.riskLevel,
        trainingLoad7d: latest.trainingLoad7d,
        trainingLoad28dAvg: latest.trainingLoad28dAvg,
      );
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
