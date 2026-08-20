class TeamSettings {
  final int defaultActionPercent;
  final String teamName;
  final bool notificationsEnabled;
  final bool notifyRiskSpikes;
  final bool notifyMissedCheckIns;
  final bool notifyHighPain;

  const TeamSettings({
    required this.defaultActionPercent,
    this.teamName = '',
    this.notificationsEnabled = true,
    this.notifyRiskSpikes = true,
    this.notifyMissedCheckIns = true,
    this.notifyHighPain = true,
  });

  static const int defaultPercent = 20;
  static const int minPercent = 10;
  static const int maxPercent = 30;

  factory TeamSettings.fromMap(Map<String, dynamic>? map) {
    final raw = (map?['defaultActionPercent'] as num?)?.round() ?? defaultPercent;
    return TeamSettings(
      defaultActionPercent: raw.clamp(minPercent, maxPercent),
      teamName: (map?['teamName'] as String?)?.trim() ?? '',
      notificationsEnabled: map?['notificationsEnabled'] != false,
      notifyRiskSpikes: map?['notifyRiskSpikes'] != false,
      notifyMissedCheckIns: map?['notifyMissedCheckIns'] != false,
      notifyHighPain: map?['notifyHighPain'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'defaultActionPercent': defaultActionPercent,
        'teamName': teamName,
        'notificationsEnabled': notificationsEnabled,
        'notifyRiskSpikes': notifyRiskSpikes,
        'notifyMissedCheckIns': notifyMissedCheckIns,
        'notifyHighPain': notifyHighPain,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  TeamSettings copyWith({
    int? defaultActionPercent,
    String? teamName,
    bool? notificationsEnabled,
    bool? notifyRiskSpikes,
    bool? notifyMissedCheckIns,
    bool? notifyHighPain,
  }) {
    return TeamSettings(
      defaultActionPercent: defaultActionPercent ?? this.defaultActionPercent,
      teamName: teamName ?? this.teamName,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyRiskSpikes: notifyRiskSpikes ?? this.notifyRiskSpikes,
      notifyMissedCheckIns: notifyMissedCheckIns ?? this.notifyMissedCheckIns,
      notifyHighPain: notifyHighPain ?? this.notifyHighPain,
    );
  }
}
