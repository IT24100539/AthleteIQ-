import '../models/athlete.dart';

export '../models/athlete.dart' show
    formatSportsLabel,
    parseSportGroup,
    parseSportGroups,
    parseSportNames,
    sportGroupForName;

/// Section 15.3 — check-in RPE prompt keyed off today's session group.
String rpePromptForGroup(SportGroup group) {
  switch (group) {
    case SportGroup.endurance:
      return 'How hard did that session feel? (RPE)';
    case SportGroup.teamContact:
      return 'How hard did training or the match feel? (RPE)';
    case SportGroup.strengthPower:
      return 'How hard did the lifts feel? (RPE)';
    case SportGroup.skillPrecision:
      return 'How hard did practice or match play feel? (RPE)';
    case SportGroup.combat:
      return 'How hard did drilling or sparring feel? (RPE)';
    case SportGroup.other:
      return 'How hard did that session feel? (RPE)';
  }
}

SportGroup groupForSession({
  required List<String> sports,
  required List<SportGroup> sportGroups,
  required String? sessionSport,
}) {
  final name = sessionSport?.trim();
  if (name != null && name.isNotEmpty) {
    final index = sports.indexOf(name);
    if (index >= 0 && index < sportGroups.length) {
      return sportGroups[index];
    }
    return sportGroupForName(name);
  }
  return sportGroups.isEmpty ? SportGroup.other : sportGroups.first;
}
