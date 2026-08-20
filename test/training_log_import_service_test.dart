import 'package:athleteiq/services/training_log_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrainingLogImportService', () {
    test('parses AthleteIQ template CSV', () {
      const csv = '''
date,duration_minutes,rpe,fatigue_score,sleep_hours
2026-08-01,60,7,3,7.5
2026-08-02,0,0,4,8
2026-08-03,90,6,2,
''';

      final result = TrainingLogImportService.parseCsv(csv);

      expect(result.errors, isEmpty);
      expect(result.detectedFormat, 'AthleteIQ template');
      expect(result.checkIns.length, 3);

      final aug1 = result.checkIns.firstWhere(
        (c) => c.date.day == 1 && c.date.month == 8,
      );
      expect(aug1.sessionDurationMinutes, 60);
      expect(aug1.rpe, 7);
      expect(aug1.fatigueScore, 3);
      expect(aug1.sleepHours, 7.5);
      expect(aug1.source, TrainingLogImportService.importSource);

      final aug2 = result.checkIns.firstWhere(
        (c) => c.date.day == 2 && c.date.month == 8,
      );
      expect(aug2.sessionDurationMinutes, 0);
      expect(aug2.rpe, 0);
    });

    test('parses TrainingPeaks-style CSV with hours and default RPE', () {
      const csv = '''
WorkoutDay,WorkoutType,TimeTotalInHours,TSS
2026-07-10,Run,1.5,85
2026-07-11,Bike,2,120
''';

      final result = TrainingLogImportService.parseCsv(csv);

      expect(result.errors, isEmpty);
      expect(result.detectedFormat, 'TrainingPeaks-style');
      expect(result.warnings.any((w) => w.contains('RPE')), isTrue);
      expect(result.checkIns.length, 2);

      final runDay = result.checkIns.firstWhere((c) => c.date.day == 10);
      expect(runDay.sessionDurationMinutes, 90);
      expect(runDay.rpe, 5);
      expect(runDay.trainingLoad, 450);
    });

    test('aggregates multiple sessions on the same day', () {
      const csv = '''
date,duration_minutes,rpe
2026-08-05,30,6
2026-08-05,30,8
''';

      final result = TrainingLogImportService.parseCsv(csv);

      expect(result.errors, isEmpty);
      expect(result.checkIns.length, 1);
      expect(result.checkIns.single.sessionDurationMinutes, 60);
      expect(result.checkIns.single.trainingLoad, 420);
      expect(result.checkIns.single.rpe, 7);
    });

    test('reports error when date column missing', () {
      const csv = '''
duration_minutes,rpe
60,7
''';

      final result = TrainingLogImportService.parseCsv(csv);

      expect(result.checkIns, isEmpty);
      expect(result.errors, isNotEmpty);
    });
  });
}
