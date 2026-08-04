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

class AthleteProfile {
  final String uid;
  final String name;
  final String? sport;
  final SportGroup sportGroup;
  final String? coachUid;
  final DateTime createdAt;
  final String deviceTier; // 'tier1' | 'tier2' | 'tier3'

  AthleteProfile({
    required this.uid,
    required this.name,
    this.sport,
    this.sportGroup = SportGroup.other,
    this.coachUid,
    required this.createdAt,
    this.deviceTier = 'tier3',
  });

  factory AthleteProfile.fromMap(String uid, Map<String, dynamic> map) => AthleteProfile(
        uid: uid,
        name: map['name'] ?? '',
        sport: map['sport'],
        sportGroup: SportGroup.values.firstWhere(
          (g) => g.name == map['sportGroup'],
          orElse: () => SportGroup.other,
        ),
        coachUid: map['coachUid'],
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        deviceTier: map['deviceTier'] ?? 'tier3',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'sport': sport,
        'sportGroup': sportGroup.name,
        'coachUid': coachUid,
        'createdAt': createdAt.toIso8601String(),
        'deviceTier': deviceTier,
      };
}
