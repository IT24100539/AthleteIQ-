import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'firestore_service.dart';
import '../utils/friendly_error.dart';
import '../utils/wearable_sync_status.dart';

/// Real HealthKit (iOS) and Health Connect (Android) reads.
///
/// Same write path on both platforms: resting HR, HRV (if present), sleep
/// hours, and workout duration into `athletes/{uid}/checkins/{YYYY-MM-DD}`
/// without overwriting athlete-entered RPE / fatigue / soreness.
/// Missing HRV is omitted — never written as 0 (Tier 2 Android watches
/// usually have no HRV).
class HealthSyncService {
  HealthSyncService._();
  static final HealthSyncService instance = HealthSyncService._();

  final Health _health = Health();
  final FirestoreService _fs = FirestoreService();
  bool _configured = false;

  static const appleWatchDeviceId = 'apple_watch';
  static const healthConnectDeviceId = 'health_connect';

  static const _iosTypes = <HealthDataType>[
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.WORKOUT,
  ];

  /// Android Health Connect types. HRV is RMSSD (not SDNN) and is requested
  /// separately so a missing HRV permission cannot block heart rate / sleep.
  static const _androidCoreTypes = <HealthDataType>[
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.WORKOUT,
    HealthDataType.STEPS,
  ];

  static const _androidHrvTypes = <HealthDataType>[
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];

  bool get isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Either native health store. Chrome / desktop return false.
  bool get isSupported => isIos || isAndroid;

  String get nativeDeviceId =>
      isAndroid ? healthConnectDeviceId : appleWatchDeviceId;

  /// Profile `deviceTier` for the native store: Apple Watch is Tier 1,
  /// Health Connect Android wearables are Tier 2 (no HRV expected).
  String get nativeDeviceTier => isAndroid ? 'tier2' : 'tier1';

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Android only. `null` on iOS / web.
  Future<HealthConnectSdkStatus?> healthConnectSdkStatus() async {
    if (!isAndroid) return null;
    try {
      return await _health.getHealthConnectSdkStatus();
    } catch (e, st) {
      debugPrint('Health Connect SDK status failed: $e\n$st');
      return HealthConnectSdkStatus.sdkUnavailable;
    }
  }

  Future<bool> isHealthConnectInstalled() async {
    if (!isAndroid) return true;
    final status = await healthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  /// Opens the Play Store listing for Health Connect.
  Future<void> installHealthConnect() async {
    if (!isAndroid) return;
    await _health.installHealthConnect();
  }

  String? _healthConnectUnavailableNote(HealthConnectSdkStatus? status) {
    if (status == null || status == HealthConnectSdkStatus.sdkAvailable) {
      return null;
    }
    if (status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
      return 'Health Connect needs an update. Open the Play Store, update '
          'Health Connect, then try again.';
    }
    return 'Health Connect is not installed on this phone. Install it from '
        'the Play Store, then return here to connect your wearable.';
  }

  List<HealthDataType> get _readTypes {
    if (isAndroid) {
      return [..._androidCoreTypes, ..._androidHrvTypes];
    }
    return _iosTypes;
  }

  /// Shows the HealthKit or Health Connect permission sheet. Returns false
  /// if denied, unsupported, or Health Connect is missing.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;

    if (isAndroid) {
      final status = await healthConnectSdkStatus();
      if (status != HealthConnectSdkStatus.sdkAvailable) return false;
    }

    await _ensureConfigured();
    try {
      if (isAndroid) {
        final coreGranted = await _health.requestAuthorization(
          _androidCoreTypes,
          permissions: List<HealthDataAccess>.filled(
            _androidCoreTypes.length,
            HealthDataAccess.READ,
          ),
        );
        if (!coreGranted) return false;
        // HRV is optional on Tier 2. Never fail the whole connect for it.
        try {
          await _health.requestAuthorization(
            _androidHrvTypes,
            permissions: const [HealthDataAccess.READ],
          );
        } catch (e, st) {
          debugPrint('Health Connect HRV permission skipped: $e\n$st');
        }
        return true;
      }

      return await _health.requestAuthorization(
        _iosTypes,
        permissions: List<HealthDataAccess>.filled(
          _iosTypes.length,
          HealthDataAccess.READ,
        ),
      );
    } catch (e, st) {
      debugPrint('Health permission request failed: $e\n$st');
      return false;
    }
  }

  /// Pull today's samples and merge them into that day's check-in.
  /// Missing HRV is omitted — never written as 0.
  Future<WearableDayMetrics> syncToday(
    String athleteUid, {
    String? deviceId,
  }) async {
    final id = deviceId ?? nativeDeviceId;
    try {
      final metrics = await readToday();
      if (isWearableReadFailureNote(metrics.note)) {
        await _fs.recordDeviceSyncFailure(athleteUid, id, metrics.note!);
        return metrics;
      }
      await _fs.mergeWearableCheckIn(athleteUid, metrics, deviceId: id);
      return metrics;
    } on RiskEngineException {
      rethrow;
    } catch (e) {
      await _fs.recordDeviceSyncFailure(athleteUid, id, e.toString());
      rethrow;
    }
  }

  /// If a native wearable is marked connected, sync on app open / resume.
  Future<WearableDayMetrics?> syncIfWatchConnected(String athleteUid) async {
    if (!isSupported) return null;
    final devices = await _fs.devicesOnce(athleteUid);
    final id = nativeDeviceId;
    final row = devices[id];
    if (row == null || row['connected'] != true) return null;
    return syncToday(athleteUid, deviceId: id);
  }

  Future<WearableDayMetrics> readToday() async {
    if (kIsWeb) {
      return WearableDayMetrics.empty(
        note: isAndroid
            ? 'Health Connect only works on a physical Android phone, not Chrome.'
            : 'HealthKit is only available on a physical iPhone.',
      );
    }
    if (!isSupported) {
      return WearableDayMetrics.empty(
        note: 'Wearable sync is only available on a physical iPhone or Android phone.',
      );
    }

    if (isAndroid) {
      final status = await healthConnectSdkStatus();
      final note = _healthConnectUnavailableNote(status);
      if (note != null) {
        return WearableDayMetrics.empty(note: note);
      }
    }

    await _ensureConfigured();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final sleepWindowStart = startOfToday.subtract(const Duration(hours: 12));

    List<HealthDataPoint> points = [];
    try {
      points = await _health.getHealthDataFromTypes(
        types: _readTypes,
        startTime: sleepWindowStart,
        endTime: now,
      );
    } on UnsupportedError catch (e) {
      debugPrint('Health store unavailable: $e');
      return WearableDayMetrics.empty(
        note: isAndroid
            ? 'Health Connect is not installed on this phone. Install it from '
                'the Play Store, then return here to connect your wearable.'
            : 'Could not read HealthKit: $e',
      );
    } catch (e, st) {
      debugPrint('Health read failed: $e\n$st');
      return WearableDayMetrics.empty(
        note: isAndroid
            ? 'Could not read Health Connect: $e'
            : 'Could not read HealthKit: $e',
      );
    }

    final rhrSamples = <double>[];
    final hrvSamples = <double>[];
    var sleepAsleepMinutes = 0.0;
    var sleepSessionMinutes = 0.0;
    var workoutMinutes = 0;
    var stepCount = 0.0;

    for (final p in points) {
      switch (p.type) {
        case HealthDataType.RESTING_HEART_RATE:
          if (!p.dateFrom.isBefore(startOfToday)) {
            final v = _numeric(p);
            if (v != null && v > 0) rhrSamples.add(v);
          }
        case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
          if (!p.dateFrom.isBefore(startOfToday)) {
            final v = _numeric(p);
            if (v != null && v > 0) hrvSamples.add(v);
          }
        case HealthDataType.SLEEP_ASLEEP:
          sleepAsleepMinutes +=
              p.dateTo.difference(p.dateFrom).inSeconds / 60.0;
        case HealthDataType.SLEEP_SESSION:
          final span = p.dateTo.difference(p.dateFrom).inSeconds / 60.0;
          if (span > 0) {
            sleepSessionMinutes += span;
          } else {
            final v = _numeric(p);
            if (v != null && v > 0) sleepSessionMinutes += v;
          }
        case HealthDataType.WORKOUT:
          if (!p.dateFrom.isBefore(startOfToday)) {
            workoutMinutes += p.dateTo.difference(p.dateFrom).inMinutes;
          }
        case HealthDataType.STEPS:
          if (!p.dateFrom.isBefore(startOfToday)) {
            final v = _numeric(p);
            if (v != null && v > 0) stepCount += v;
          }
        default:
          break;
      }
    }

    final sleepMinutes =
        sleepSessionMinutes > 0 ? sleepSessionMinutes : sleepAsleepMinutes;

    return WearableDayMetrics(
      restingHeartRate: rhrSamples.isEmpty
          ? null
          : rhrSamples.reduce((a, b) => a + b) / rhrSamples.length,
      hrv: hrvSamples.isEmpty
          ? null
          : hrvSamples.reduce((a, b) => a + b) / hrvSamples.length,
      sleepHours: sleepMinutes > 0 ? sleepMinutes / 60.0 : null,
      sessionDurationMinutes: workoutMinutes > 0 ? workoutMinutes : null,
      steps: stepCount > 0 ? stepCount.round() : null,
    );
  }

  double? _numeric(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) return value.numericValue.toDouble();
    return null;
  }
}

class WearableDayMetrics {
  final double? restingHeartRate;
  final double? hrv;
  final double? sleepHours;
  final int? sessionDurationMinutes;
  final int? steps;
  final String? note;

  const WearableDayMetrics({
    this.restingHeartRate,
    this.hrv,
    this.sleepHours,
    this.sessionDurationMinutes,
    this.steps,
    this.note,
  });

  factory WearableDayMetrics.empty({String? note}) =>
      WearableDayMetrics(note: note);

  bool get hasAny =>
      restingHeartRate != null ||
      hrv != null ||
      sleepHours != null ||
      sessionDurationMinutes != null ||
      steps != null;

  Map<String, dynamic> toDeviceMetricsMap() => {
        if (hrv != null) 'hrv': double.parse(hrv!.toStringAsFixed(1)),
        if (restingHeartRate != null)
          'restingHr': double.parse(restingHeartRate!.toStringAsFixed(0)),
        if (sleepHours != null)
          'sleepHours': double.parse(sleepHours!.toStringAsFixed(1)),
        if (sessionDurationMinutes != null)
          'workoutMinutes': sessionDurationMinutes,
        if (steps != null) 'steps': steps,
      };
}
