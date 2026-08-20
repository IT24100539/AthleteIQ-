import 'package:shared_preferences/shared_preferences.dart';

/// Device-local flags that are not worth a Firestore field.
class LocalPrefs {
  static String _coachSkipKey(String athleteUid) =>
      'athleteiq_coach_connect_skipped_$athleteUid';

  static Future<bool> coachConnectSkipped(String athleteUid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_coachSkipKey(athleteUid)) ?? false;
  }

  static Future<void> setCoachConnectSkipped(String athleteUid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_coachSkipKey(athleteUid), true);
  }
}
