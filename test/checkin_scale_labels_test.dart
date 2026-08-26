import 'package:athleteiq/constants/checkin_scale_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fatigue words map to 1–5 without showing numbers', () {
    expect(CheckinWordScales.fatigue.map((c) => c.label).toList(), [
      'Fresh',
      'Good',
      'Okay',
      'Tired',
      'Exhausted',
    ]);
    expect(CheckinWordScales.fatigue.map((c) => c.value).toList(), [1, 2, 3, 4, 5]);
    expect(CheckinWordScales.fatigueLabel(1), 'Fresh');
    expect(CheckinWordScales.fatigueLabel(5), 'Exhausted');
  });

  test('effort words map onto session-RPE 2/4/6/8/10', () {
    expect(CheckinWordScales.rpe.map((c) => c.label).toList(), [
      'Very easy',
      'Easy',
      'Moderate',
      'Hard',
      'Max effort',
    ]);
    expect(CheckinWordScales.rpe.map((c) => c.value).toList(), [2, 4, 6, 8, 10]);
    expect(CheckinWordScales.rpeLabel(6), 'Moderate');
    expect(CheckinWordScales.rpeLabel(5), 'Moderate');
  });
}
