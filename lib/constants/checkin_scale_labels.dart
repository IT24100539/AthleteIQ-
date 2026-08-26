/// Word labels for athlete-facing check-in scales.
/// Stored values stay numeric: fatigue 1–5, session-RPE 1–10.
class CheckinWordChoice {
  final String label;
  final int value;
  const CheckinWordChoice(this.label, this.value);
}

abstract final class CheckinWordScales {
  static const fatigue = [
    CheckinWordChoice('Fresh', 1),
    CheckinWordChoice('Good', 2),
    CheckinWordChoice('Okay', 3),
    CheckinWordChoice('Tired', 4),
    CheckinWordChoice('Exhausted', 5),
  ];

  /// Five words mapped onto Foster session-RPE (duration × 1–10).
  static const rpe = [
    CheckinWordChoice('Very easy', 2),
    CheckinWordChoice('Easy', 4),
    CheckinWordChoice('Moderate', 6),
    CheckinWordChoice('Hard', 8),
    CheckinWordChoice('Max effort', 10),
  ];

  static String fatigueLabel(int value) {
    for (final c in fatigue) {
      if (c.value == value) return c.label;
    }
    return 'Okay';
  }

  static String rpeLabel(int value) {
    for (final c in rpe) {
      if (c.value == value) return c.label;
    }
    CheckinWordChoice closest = rpe.first;
    var best = (value - closest.value).abs();
    for (final c in rpe) {
      final d = (value - c.value).abs();
      if (d < best || (d == best && c.value > closest.value)) {
        best = d;
        closest = c;
      }
    }
    return closest.label;
  }
}
