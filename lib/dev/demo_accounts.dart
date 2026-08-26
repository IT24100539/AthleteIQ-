/// Debug-only demo account constants used by seed helpers.
class DemoAccounts {
  static const athleteEmail = 'demo.athlete@athleteiq.app';
  static const coachEmail = 'demo.coach@athleteiq.app';
  static const password = 'Demo1234!';

  static const athleteName = 'Alex Rivera';
  static const coachName = 'Jordan Hale';
  static const inviteCode = 'DEMO26';

  static const athleteSport = 'Running / Athletics';
  static const athleteSportGroup = 'endurance';

  static bool isDemoEmail(String? email) {
    final value = email?.trim().toLowerCase() ?? '';
    return value == athleteEmail || value == coachEmail;
  }
}

/// UIDs filled after [DemoBootstrap.ensureAccountsAndData].
class DemoSession {
  static String? athleteUid;
  static String? coachUid;
}
