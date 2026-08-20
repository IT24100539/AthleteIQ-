/// Mirrors `hasStaleOrFailedSync()` in `functions/src/nightlyAlerts.ts`.
/// Do not add new failure kinds here — the Sync failed screen only surfaces
/// these three HealthKit / device states.
class WearableSyncIssue {
  final String deviceId;
  final String deviceName;
  final String message;

  const WearableSyncIssue({
    required this.deviceId,
    required this.deviceName,
    required this.message,
  });
}

const _twoDaysMs = 2 * 24 * 60 * 60 * 1000;

/// Manual Tier 3 metrics and other non-wearable device docs — not HealthKit sync.
bool deviceRequiresWearableSync(String deviceId, Map<String, dynamic> data) {
  if (deviceId == 'manual_tier3') return false;
  if (data['requiresWearableSync'] == false) return false;
  final name = (data['name'] as String?)?.trim().toLowerCase() ?? '';
  if (name == 'manual entry') return false;
  return true;
}

/// First connected device with a recorded `lastSyncError`, a missing
/// `lastSync`, or a `lastSync` older than 2 days — same strings the nightly
/// job writes onto coach/athlete alerts.
WearableSyncIssue? findWearableSyncIssue(
  Map<String, Map<String, dynamic>> devices, {
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).millisecondsSinceEpoch - _twoDaysMs;
  for (final entry in devices.entries) {
    final data = entry.value;
    if (data['connected'] == false) continue;
    if (!deviceRequiresWearableSync(entry.key, data)) continue;

    final name = (data['name'] as String?)?.trim();
    final deviceName = (name != null && name.isNotEmpty) ? name : entry.key;

    final err = (data['lastSyncError'] as String?)?.trim() ?? '';
    if (err.isNotEmpty) {
      return WearableSyncIssue(
        deviceId: entry.key,
        deviceName: deviceName,
        message: err,
      );
    }

    final lastSyncRaw = data['lastSync'] as String?;
    if (lastSyncRaw == null || lastSyncRaw.isEmpty) {
      return WearableSyncIssue(
        deviceId: entry.key,
        deviceName: deviceName,
        message: '${entry.key} has never completed a sync.',
      );
    }
    final lastSync = DateTime.tryParse(lastSyncRaw)?.millisecondsSinceEpoch;
    if (lastSync == null || lastSync < cutoff) {
      return WearableSyncIssue(
        deviceId: entry.key,
        deviceName: deviceName,
        message: '${entry.key} last synced more than 2 days ago.',
      );
    }
  }
  return null;
}

/// Existing `WearableDayMetrics.note` values from `HealthSyncService.readToday`
/// that are real failures (not "no samples today").
bool isWearableReadFailureNote(String? note) {
  if (note == null || note.isEmpty) return false;
  return note.startsWith('Could not read HealthKit') ||
      note.startsWith('HealthKit is only available') ||
      note.startsWith('Could not read Health Connect') ||
      note.startsWith('Health Connect is not installed') ||
      note.startsWith('Health Connect needs an update') ||
      note.startsWith('Wearable sync is only available');
}

/// Back-compat name used by older tests / call sites.
bool isHealthKitReadFailureNote(String? note) =>
    isWearableReadFailureNote(note);
