/// Plain-language help for manual check-in fields (Ask AthleteIQ / risk engine inputs).
abstract final class CheckinFieldHelp {
  static const fatigue =
      'How recovered you feel today, in your own words. '
      'It helps track whether you\'re bouncing back between sessions.';

  static const rpe =
      'How hard this session felt — from very easy to max effort. '
      'This is a real sports-science method (session-RPE) used to measure training load, '
      'and it\'s more accurate than heart rate alone for how hard something actually felt.';

  static const sleep =
      'Hours you slept last night. Sleep is one of the strongest recovery signals we track — '
      'short or inconsistent sleep often shows up in fatigue and risk before you feel it in training.';

  static const sessionDuration =
      'How long your main session lasted, in minutes. Combined with RPE, this calculates training load '
      'using the session-RPE method (duration × effort).';

  static const restingHeartRate =
      'Resting heart rate (bpm) measured when you\'re calm — often first thing in the morning. '
      'It can rise when you\'re stressed, ill, or under-recovered. Approximate is fine.';

  static const dailySteps =
      'Rough daily movement outside formal training. Helps capture overall activity when a wearable '
      'isn\'t syncing steps for you.';

  static const hrv =
      'Heart-rate variability (ms). On a wearable this is usually a morning reading. '
      'If you measured it another way, enter it here — skip if you don\'t have a number.';
}
