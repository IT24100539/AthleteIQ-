import 'privacy_settings.dart';

/// The six sport groups from Section 12.2 — new sports get added to this
/// list and assigned a group; no model or screen code changes needed.
enum SportGroup { endurance, teamContact, strengthPower, skillPrecision, combat, other }

class SportOption {
  final String name;
  final SportGroup group;
  const SportOption(this.name, this.group);
}

/// Section 12.2's sport list. Add new sports here only — everything else
/// (check-in wording, recommendation templates) is keyed off the group.
const List<SportOption> kSportOptions = [
  SportOption('Running / Athletics', SportGroup.endurance),
  SportOption('Swimming', SportGroup.endurance),
  SportOption('Cycling', SportGroup.endurance),
  SportOption('Triathlon', SportGroup.endurance),
  SportOption('Rowing', SportGroup.endurance),
  SportOption('Football (Soccer)', SportGroup.teamContact),
  SportOption('Rugby', SportGroup.teamContact),
  SportOption('American Football', SportGroup.teamContact),
  SportOption('Basketball', SportGroup.teamContact),
  SportOption('Hockey', SportGroup.teamContact),
  SportOption('Netball', SportGroup.teamContact),
  SportOption('Volleyball', SportGroup.teamContact),
  SportOption('Cricket', SportGroup.teamContact),
  SportOption('Baseball / Softball', SportGroup.teamContact),
  SportOption('Handball', SportGroup.teamContact),
  SportOption('Weightlifting', SportGroup.strengthPower),
  SportOption('Powerlifting', SportGroup.strengthPower),
  SportOption('CrossFit / Functional Fitness', SportGroup.strengthPower),
  SportOption('Throwing Events', SportGroup.strengthPower),
  SportOption('Badminton', SportGroup.skillPrecision),
  SportOption('Tennis', SportGroup.skillPrecision),
  SportOption('Table Tennis', SportGroup.skillPrecision),
  SportOption('Golf', SportGroup.skillPrecision),
  SportOption('Squash', SportGroup.skillPrecision),
  SportOption('Boxing', SportGroup.combat),
  SportOption('MMA', SportGroup.combat),
  SportOption('Wrestling', SportGroup.combat),
  SportOption('Judo', SportGroup.combat),
  SportOption('Karate', SportGroup.combat),
  SportOption('Taekwondo', SportGroup.combat),
];

SportGroup parseSportGroup(dynamic raw) {
  if (raw is SportGroup) return raw;
  if (raw is String) {
    return SportGroup.values.firstWhere(
      (g) => g.name == raw,
      orElse: () => SportGroup.other,
    );
  }
  return SportGroup.other;
}

/// Listed picker name → group. Custom / unknown names use [fallback].
SportGroup sportGroupForName(String name, {SportGroup fallback = SportGroup.other}) {
  final trimmed = name.trim();
  for (final option in kSportOptions) {
    if (option.name == trimmed) return option.group;
  }
  return fallback;
}

/// Prefer `sports[]`; fall back to legacy single `sport` string.
List<String> parseSportNames(Map<String, dynamic> map) {
  final raw = map['sports'];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final single = map['sport'];
  if (single is String && single.trim().isNotEmpty) {
    return [single.trim()];
  }
  return const [];
}

/// Parallel groups for [names]. Uses `sportGroups[]` when present.
List<SportGroup> parseSportGroups(Map<String, dynamic> map, List<String> names) {
  final raw = map['sportGroups'];
  if (raw is List && raw.isNotEmpty) {
    final parsed = raw.map(parseSportGroup).toList();
    if (names.isEmpty) return parsed;
    if (parsed.length == names.length) return parsed;
    return [
      for (var i = 0; i < names.length; i++)
        i < parsed.length
            ? parsed[i]
            : sportGroupForName(names[i], fallback: parseSportGroup(map['sportGroup'])),
    ];
  }
  if (names.isEmpty) {
    final legacy = map['sportGroup'];
    return legacy == null ? const [] : [parseSportGroup(legacy)];
  }
  final fallback = parseSportGroup(map['sportGroup']);
  return [
    for (var i = 0; i < names.length; i++)
      sportGroupForName(
        names[i],
        fallback: i == 0 ? fallback : SportGroup.other,
      ),
  ];
}

String formatSportsLabel(List<String> sports) => sports.join(', ');

class AthleteProfile {
  final String uid;
  final String name;

  /// Ordered sport names. First entry is primary (legacy `sport`).
  final List<String> sports;

  /// Group for each name in [sports] (same length). First is legacy `sportGroup`.
  final List<SportGroup> sportGroups;

  final String? sportClassificationConfidence;
  final String? sportClassificationSource;
  final String? coachUid;
  final DateTime createdAt;
  final String deviceTier; // 'tier1' | 'tier2' | 'tier3'

  /// Tier 3 has no wearable — resting HR may be entered on the daily check-in.
  /// Tier 1/2 get it from the device, so the manual field stays hidden.
  bool get allowsManualRestingHr =>
      deviceTier != 'tier1' && deviceTier != 'tier2';
  final bool deviceSetupCompleted;
  final String? activeDevice;
  final String? latestPainUrgency;
  final DateTime? latestPainAt;
  final String? latestPainSummary;
  final PrivacySettings privacySettings;

  AthleteProfile({
    required this.uid,
    required this.name,
    String? sport,
    List<String>? sports,
    SportGroup sportGroup = SportGroup.other,
    List<SportGroup>? sportGroups,
    this.sportClassificationConfidence,
    this.sportClassificationSource,
    this.coachUid,
    required this.createdAt,
    this.deviceTier = 'tier3',
    this.deviceSetupCompleted = false,
    this.activeDevice,
    this.latestPainUrgency,
    this.latestPainAt,
    this.latestPainSummary,
    this.privacySettings = PrivacySettings.open,
  })  : sports = _coerceSports(sports, sport),
        sportGroups = _coerceGroups(sports, sport, sportGroups, sportGroup);

  /// Primary / first-listed sport. Null when onboarding is unfinished.
  String? get sport => sports.isEmpty ? null : sports.first;

  /// Primary sport group (first-listed). Used when no session sport is set.
  SportGroup get sportGroup =>
      sportGroups.isEmpty ? SportGroup.other : sportGroups.first;

  bool get hasSport => sports.isNotEmpty;

  String get sportsLabel => formatSportsLabel(sports);

  /// Drop injury-summary fields when the athlete is not sharing them.
  AthleteProfile redactedForCoach() {
    if (privacySettings.injuryHistory) return this;
    return AthleteProfile(
      uid: uid,
      name: name,
      sports: sports,
      sportGroups: sportGroups,
      sportClassificationConfidence: sportClassificationConfidence,
      sportClassificationSource: sportClassificationSource,
      coachUid: coachUid,
      createdAt: createdAt,
      deviceTier: deviceTier,
      deviceSetupCompleted: deviceSetupCompleted,
      activeDevice: activeDevice,
      latestPainUrgency: null,
      latestPainAt: null,
      latestPainSummary: null,
      privacySettings: privacySettings,
    );
  }

  factory AthleteProfile.fromMap(String uid, Map<String, dynamic> map) {
    final names = parseSportNames(map);
    return AthleteProfile(
      uid: uid,
      name: map['name'] ?? '',
      sports: names,
      sportGroups: parseSportGroups(map, names),
      sportClassificationConfidence: map['sportClassificationConfidence'] as String?,
      sportClassificationSource: map['sportClassificationSource'] as String?,
      coachUid: map['coachUid'],
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      deviceTier: map['deviceTier'] ?? 'tier3',
      deviceSetupCompleted: map['deviceSetupCompleted'] ?? false,
      activeDevice: map['activeDevice'],
      latestPainUrgency: map['latestPainUrgency'] as String?,
      latestPainAt: map['latestPainAt'] != null
          ? DateTime.tryParse(map['latestPainAt'] as String)
          : null,
      latestPainSummary: map['latestPainSummary'] as String?,
      privacySettings: PrivacySettings.fromMap(
        map['privacySettings'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'sports': sports,
        'sportGroups': sportGroups.map((g) => g.name).toList(),
        'sport': sport,
        'sportGroup': sportGroup.name,
        if (sportClassificationConfidence != null)
          'sportClassificationConfidence': sportClassificationConfidence,
        if (sportClassificationSource != null)
          'sportClassificationSource': sportClassificationSource,
        'coachUid': coachUid,
        'createdAt': createdAt.toIso8601String(),
        'deviceTier': deviceTier,
        'deviceSetupCompleted': deviceSetupCompleted,
        'activeDevice': activeDevice,
        if (latestPainUrgency != null) 'latestPainUrgency': latestPainUrgency,
        if (latestPainAt != null) 'latestPainAt': latestPainAt!.toIso8601String(),
        if (latestPainSummary != null) 'latestPainSummary': latestPainSummary,
        'privacySettings': privacySettings.toMap(),
      };

  static List<String> _coerceSports(List<String>? sports, String? sport) {
    if (sports != null && sports.isNotEmpty) {
      return sports.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    final single = sport?.trim();
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  static List<SportGroup> _coerceGroups(
    List<String>? sports,
    String? sport,
    List<SportGroup>? sportGroups,
    SportGroup sportGroup,
  ) {
    final names = _coerceSports(sports, sport);
    if (sportGroups != null && sportGroups.isNotEmpty) {
      if (names.isEmpty || sportGroups.length == names.length) {
        return List<SportGroup>.from(sportGroups);
      }
      return [
        for (var i = 0; i < names.length; i++)
          i < sportGroups.length
              ? sportGroups[i]
              : sportGroupForName(names[i], fallback: sportGroup),
      ];
    }
    if (names.isEmpty) return const [];
    return [
      for (var i = 0; i < names.length; i++)
        sportGroupForName(names[i], fallback: i == 0 ? sportGroup : SportGroup.other),
    ];
  }
}
