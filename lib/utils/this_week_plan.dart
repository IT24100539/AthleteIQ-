import '../models/checkin.dart';
import '../models/risk_result.dart';
import 'approval_gate.dart';

enum ThisWeekDayKind { rest, trained, notLogged, plan, upcoming }

class ThisWeekDay {
  final DateTime date;
  final String dayLabel;
  final String activity;
  final ThisWeekDayKind kind;

  const ThisWeekDay({
    required this.date,
    required this.dayLabel,
    required this.activity,
    required this.kind,
  });

  bool get isRest => kind == ThisWeekDayKind.rest;
}

const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Monday–Sunday of the calendar week containing [now], from check-ins plus
/// today's released recommendation (approved or modified-and-sent).
/// Days without a log are "Not logged" / "No plan yet" — never invented
/// Rest / Light run rows.
List<ThisWeekDay> buildThisWeekDays({
  required DateTime now,
  required List<CheckIn> checkIns,
  RiskResult? result,
}) {
  final today = _dateOnly(now);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final byDay = <String, CheckIn>{};
  for (final c in checkIns) {
    byDay[_dateKey(c.date)] = c;
  }

  final released = recommendationReleasedToAthlete(result?.recommendationStatus) &&
      (result?.recommendation.trim().isNotEmpty ?? false);
  final planText = released ? _shortPlan(result!.recommendation) : null;

  return [
    for (var i = 0; i < 7; i++)
      _row(
        date: weekStart.add(Duration(days: i)),
        today: today,
        checkIn: byDay[_dateKey(weekStart.add(Duration(days: i)))],
        planText: planText,
      ),
  ];
}

bool thisWeekHasRealData(List<ThisWeekDay> days) {
  return days.any(
    (d) =>
        d.kind == ThisWeekDayKind.rest ||
        d.kind == ThisWeekDayKind.trained ||
        d.kind == ThisWeekDayKind.plan,
  );
}

ThisWeekDay _row({
  required DateTime date,
  required DateTime today,
  required CheckIn? checkIn,
  required String? planText,
}) {
  final dayLabel = _dow[date.weekday - 1];
  final isToday = date == today;
  final isFuture = date.isAfter(today);

  if (checkIn != null) {
    final rest = _isRest(checkIn);
    return ThisWeekDay(
      date: date,
      dayLabel: dayLabel,
      activity: rest ? 'Rest' : _sessionLabel(checkIn),
      kind: rest ? ThisWeekDayKind.rest : ThisWeekDayKind.trained,
    );
  }

  if (isToday && planText != null) {
    return ThisWeekDay(
      date: date,
      dayLabel: dayLabel,
      activity: planText,
      kind: ThisWeekDayKind.plan,
    );
  }

  if (isFuture) {
    return ThisWeekDay(
      date: date,
      dayLabel: dayLabel,
      activity: 'No plan yet',
      kind: ThisWeekDayKind.upcoming,
    );
  }

  return ThisWeekDay(
    date: date,
    dayLabel: dayLabel,
    activity: 'Not logged',
    kind: ThisWeekDayKind.notLogged,
  );
}

bool _isRest(CheckIn c) {
  final mins = c.sessionDurationMinutes ?? 0;
  final rpe = c.rpe ?? 0;
  final load = c.trainingLoad ?? 0;
  return mins == 0 || rpe == 0 || load == 0;
}

String _sessionLabel(CheckIn c) {
  final mins = c.sessionDurationMinutes ?? 0;
  final rpe = c.rpe ?? 0;
  final intensity = rpe <= 3
      ? 'Easy session'
      : rpe <= 6
          ? 'Moderate session'
          : 'Hard session';
  if (mins > 0) return '$intensity · $mins min';
  return intensity;
}

String _shortPlan(String recommendation) {
  final oneLine = recommendation.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= 52) return oneLine;
  return '${oneLine.substring(0, 49).trim()}…';
}
