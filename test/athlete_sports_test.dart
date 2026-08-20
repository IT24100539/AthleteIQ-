import 'package:athleteiq/models/athlete.dart';
import 'package:athleteiq/models/checkin.dart';
import 'package:athleteiq/utils/athlete_sports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AthleteProfile sports arrays', () {
    test('legacy single sport string still parses', () {
      final profile = AthleteProfile.fromMap('a1', {
        'name': 'Alex',
        'sport': 'Rugby',
        'sportGroup': 'teamContact',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(profile.sports, ['Rugby']);
      expect(profile.sportGroups, [SportGroup.teamContact]);
      expect(profile.sport, 'Rugby');
      expect(profile.hasSport, isTrue);
      expect(profile.sportsLabel, 'Rugby');
    });

    test('sports[] is the source of truth and sport is primary', () {
      final profile = AthleteProfile.fromMap('a1', {
        'name': 'Alex',
        'sports': ['Rugby', 'Weightlifting'],
        'sportGroups': ['teamContact', 'strengthPower'],
        'sport': 'ShouldBeIgnoredIfArrayPresent',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(profile.sports, ['Rugby', 'Weightlifting']);
      expect(profile.sport, 'Rugby');
      expect(profile.sportGroup, SportGroup.teamContact);
      expect(profile.sportsLabel, 'Rugby, Weightlifting');
      expect(profile.toMap()['sports'], ['Rugby', 'Weightlifting']);
      expect(profile.toMap()['sport'], 'Rugby');
    });

    test('empty sports means onboarding is unfinished', () {
      final profile = AthleteProfile.fromMap('a1', {
        'name': 'Alex',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(profile.hasSport, isFalse);
      expect(profile.sport, isNull);
    });
  });

  group('session sport wording', () {
    test('uses the selected session group, not always primary', () {
      expect(
        groupForSession(
          sports: ['Rugby', 'Weightlifting'],
          sportGroups: [SportGroup.teamContact, SportGroup.strengthPower],
          sessionSport: 'Weightlifting',
        ),
        SportGroup.strengthPower,
      );
      expect(
        rpePromptForGroup(SportGroup.strengthPower),
        contains('lifts'),
      );
      expect(
        rpePromptForGroup(SportGroup.teamContact),
        contains('match'),
      );
    });

    test('falls back to primary when session sport is missing', () {
      expect(
        groupForSession(
          sports: ['Rugby', 'Weightlifting'],
          sportGroups: [SportGroup.teamContact, SportGroup.strengthPower],
          sessionSport: null,
        ),
        SportGroup.teamContact,
      );
    });
  });

  test('check-in writes session sport and omits it when unset', () {
    final withSession = CheckIn(
      id: '',
      date: DateTime(2026, 8, 16),
      fatigueScore: 3,
      sessionSport: 'Rugby',
      sessionSportGroup: 'teamContact',
    ).toMap();
    expect(withSession['sessionSport'], 'Rugby');
    expect(withSession['sessionSportGroup'], 'teamContact');

    final without = CheckIn(
      id: '',
      date: DateTime(2026, 8, 16),
      fatigueScore: 3,
    ).toMap();
    expect(without.containsKey('sessionSport'), isFalse);
  });
}
