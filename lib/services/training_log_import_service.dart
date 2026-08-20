import '../models/checkin.dart';

/// Result of parsing a CSV training-log export into daily check-ins.
class TrainingLogImportResult {
  final List<CheckIn> checkIns;
  final List<String> warnings;
  final List<String> errors;
  final String detectedFormat;

  const TrainingLogImportResult({
    required this.checkIns,
    required this.warnings,
    required this.errors,
    required this.detectedFormat,
  });

  bool get hasCheckIns => checkIns.isNotEmpty;
  bool get ok => errors.isEmpty && hasCheckIns;
}

/// Parses CSV exports from AthleteIQ templates or common apps (e.g. TrainingPeaks)
/// into [CheckIn] rows that match manual check-ins (same Firestore shape).
class TrainingLogImportService {
  static const importSource = 'import';

  static TrainingLogImportResult parseCsv(String contents) {
    final errors = <String>[];
    final warnings = <String>[];

    final rows = _parseCsvRows(contents);
    if (rows.isEmpty) {
      return const TrainingLogImportResult(
        checkIns: [],
        warnings: [],
        errors: ['File is empty or could not be read as CSV.'],
        detectedFormat: 'unknown',
      );
    }

    final headerRow = rows.first;
    final headerKeys = headerRow.map(_normalizeHeader).toList();
    if (!_looksLikeHeader(headerKeys)) {
      errors.add(
        'First row must be a header with at least a date column '
        '(e.g. date, WorkoutDay).',
      );
      return TrainingLogImportResult(
        checkIns: [],
        warnings: warnings,
        errors: errors,
        detectedFormat: 'unknown',
      );
    }

    final detectedFormat = _detectFormat(headerKeys);
    final dateIdx = _columnIndex(headerKeys, _dateAliases);
    if (dateIdx == null) {
      errors.add('Could not find a date column (date, WorkoutDay, etc.).');
      return TrainingLogImportResult(
        checkIns: [],
        warnings: warnings,
        errors: errors,
        detectedFormat: detectedFormat,
      );
    }

    final durationIdx = _columnIndex(headerKeys, _durationAliases);
    final rpeIdx = _columnIndex(headerKeys, _rpeAliases);
    final fatigueIdx = _columnIndex(headerKeys, _fatigueAliases);
    final sleepIdx = _columnIndex(headerKeys, _sleepAliases);
    final durationHoursIdx = _columnIndex(headerKeys, _durationHoursAliases);

    if (durationIdx == null && durationHoursIdx == null) {
      warnings.add(
        'No duration column found — rest/training days without duration '
        'will be skipped unless RPE is 0.',
      );
    }
    if (rpeIdx == null) {
      warnings.add(
        'No RPE column found — using default RPE 5 for training rows '
        '(add an rpe column for better load accuracy).',
      );
    }

    final byDate = <String, _DayAccumulator>{};
    var skippedRows = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;

      final dateRaw = _cell(row, dateIdx);
      final date = _parseDate(dateRaw);
      if (date == null) {
        skippedRows++;
        continue;
      }
      final dateKey = _dateKey(date);

      final durationMinutes = _parseDurationMinutes(
        row: row,
        minutesIdx: durationIdx,
        hoursIdx: durationHoursIdx,
      );
      final rpe = _parseRpe(_cell(row, rpeIdx));
      final fatigue = _parseFatigue(_cell(row, fatigueIdx));
      final sleep = _parseSleep(_cell(row, sleepIdx));

      final acc = byDate.putIfAbsent(dateKey, () => _DayAccumulator(date: date));

      if (durationMinutes == null && rpe == null) {
        skippedRows++;
        continue;
      }

      final mins = durationMinutes ?? 0;
      final sessionRpe = rpe ?? (mins > 0 ? 5 : 0);

      if (mins <= 0 && sessionRpe <= 0) {
        acc.setRestDay();
      } else {
        acc.addSession(minutes: mins, rpe: sessionRpe);
      }

      if (fatigue != null) acc.fatigueScore = fatigue;
      if (sleep != null) acc.sleepHours = sleep;
    }

    if (skippedRows > 0) {
      warnings.add('Skipped $skippedRows row(s) with missing or invalid data.');
    }

    final checkIns = byDate.values
        .map(
          (acc) => CheckIn(
            id: '',
            date: acc.date,
            sessionDurationMinutes: acc.sessionDurationMinutes,
            rpe: acc.rpe,
            fatigueScore: acc.fatigueScore,
            sleepHours: acc.sleepHours,
            source: importSource,
          ),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (checkIns.isEmpty && errors.isEmpty) {
      errors.add('No valid training days found in this file.');
    }

    return TrainingLogImportResult(
      checkIns: checkIns,
      warnings: warnings,
      errors: errors,
      detectedFormat: detectedFormat,
    );
  }

  static List<List<String>> _parseCsvRows(String contents) {
    final lines = contents.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final rows = <List<String>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      rows.add(_parseCsvLine(line));
    }
    return rows;
  }

  /// Minimal RFC-style CSV line parser (handles quoted fields).
  static List<String> _parseCsvLine(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  static bool _looksLikeHeader(List<String> headers) {
    return _columnIndex(headers, _dateAliases) != null;
  }

  static String _detectFormat(List<String> headers) {
    if (_columnIndex(headers, ['workoutday', 'workouttype', 'tss']) != null) {
      return 'TrainingPeaks-style';
    }
    if (_columnIndex(headers, ['date', 'durationminutes', 'rpe']) != null) {
      return 'AthleteIQ template';
    }
    return 'Generic CSV';
  }

  static int? _columnIndex(List<String> headers, List<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(headers[i])) return i;
    }
    return null;
  }

  static String _normalizeHeader(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
    final isoMatch = iso.firstMatch(raw);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})');
    final slashMatch = slash.firstMatch(raw);
    if (slashMatch != null) {
      var year = int.parse(slashMatch.group(3)!);
      if (year < 100) year += 2000;
      return DateTime(
        year,
        int.parse(slashMatch.group(1)!),
        int.parse(slashMatch.group(2)!),
      );
    }

    return DateTime.tryParse(raw)?.toLocal();
  }

  static int? _parseDurationMinutes({
    required List<String> row,
    required int? minutesIdx,
    required int? hoursIdx,
  }) {
    final minutesRaw = _cell(row, minutesIdx);
    if (minutesRaw.isNotEmpty) {
      final asDouble = double.tryParse(minutesRaw.replaceAll(',', ''));
      if (asDouble != null) return asDouble.round();
    }

    final hoursRaw = _cell(row, hoursIdx);
    if (hoursRaw.isNotEmpty) {
      final hours = double.tryParse(hoursRaw.replaceAll(',', ''));
      if (hours != null) return (hours * 60).round();
    }
    return null;
  }

  static int? _parseRpe(String raw) {
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw.split('.').first);
    if (value == null || value < 0 || value > 10) return null;
    return value;
  }

  static int? _parseFatigue(String raw) {
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw.split('.').first);
    if (value == null || value < 1 || value > 5) return null;
    return value;
  }

  static double? _parseSleep(String raw) {
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', ''));
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static const _dateAliases = [
    'date',
    'workoutday',
    'day',
    'workoutdate',
  ];

  static const _durationAliases = [
    'durationminutes',
    'durationmin',
    'duration',
    'elapsedtime',
    'elapsedminutes',
    'timeminutes',
    'actualduration',
    'planneddurationinminutes',
  ];

  static const _durationHoursAliases = [
    'timetotalinhours',
    'timehours',
    'durationhours',
    'hours',
  ];

  static const _rpeAliases = [
    'rpe',
    'perceivedexertion',
    'sessionrpe',
    'feel',
  ];

  static const _fatigueAliases = [
    'fatiguescore',
    'fatigue',
    'wellness',
  ];

  static const _sleepAliases = [
    'sleephours',
    'sleep',
    'hoursleep',
  ];
}

class _DayAccumulator {
  final DateTime date;
  int totalMinutes = 0;
  int totalLoad = 0;
  int? sessionDurationMinutes;
  int? rpe;
  int fatigueScore = 3;
  double? sleepHours;
  bool restDay = false;

  _DayAccumulator({required this.date});

  void addSession({required int minutes, required int rpe}) {
    restDay = false;
    totalMinutes += minutes;
    totalLoad += minutes * rpe;
    sessionDurationMinutes = totalMinutes;
    this.rpe = totalMinutes > 0 ? (totalLoad / totalMinutes).round() : rpe;
  }

  void setRestDay() {
    if (totalMinutes == 0) {
      restDay = true;
      sessionDurationMinutes = 0;
      rpe = 0;
    }
  }
}
