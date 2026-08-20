class PainArea {
  final String location; // e.g. "Left knee", "Right ankle"
  final int severity; // 1 to 5 scale

  const PainArea({
    required this.location,
    required this.severity,
  });

  factory PainArea.fromMap(Map<String, dynamic> map) => PainArea(
        location: map['location'] ?? '',
        severity: (map['severity'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'location': location,
        'severity': severity,
      };
}

class PainReport {
  final String id;
  final String athleteUid;
  final DateTime date;
  final List<PainArea> areas;
  final String? note;
  final String? urgency; // LOW | MEDIUM | HIGH
  final String? urgencyReason;
  final String? urgencySource; // llm | rules

  const PainReport({
    required this.id,
    required this.athleteUid,
    required this.date,
    required this.areas,
    this.note,
    this.urgency,
    this.urgencyReason,
    this.urgencySource,
  });

  bool get isHigh => (urgency ?? '').toUpperCase() == 'HIGH';

  factory PainReport.fromMap(String id, Map<String, dynamic> map) => PainReport(
        id: id,
        athleteUid: map['athleteUid'] ?? '',
        date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
        areas: (map['areas'] as List<dynamic>?)
                ?.map((a) => PainArea.fromMap(Map<String, dynamic>.from(a)))
                .toList() ??
            [],
        note: map['note'] as String?,
        urgency: map['urgency'] as String?,
        urgencyReason: map['urgencyReason'] as String?,
        urgencySource: map['urgencySource'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'athleteUid': athleteUid,
        'date': date.toIso8601String(),
        'areas': areas.map((a) => a.toMap()).toList(),
        if (note != null) 'note': note,
        if (urgency != null) 'urgency': urgency,
        if (urgencyReason != null) 'urgencyReason': urgencyReason,
        if (urgencySource != null) 'urgencySource': urgencySource,
      };
}
