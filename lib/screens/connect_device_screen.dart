import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/health_sync_service.dart';
import '../utils/stream_fallback.dart';
import '../utils/wearable_sync_status.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import 'connect_coach_screen.dart';
import 'import_training_log_screen.dart';

class ConnectDeviceScreen extends StatefulWidget {
  final String athleteUid;
  final bool isFromSettings;

  const ConnectDeviceScreen({
    super.key,
    required this.athleteUid,
    this.isFromSettings = false,
  });

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  final _fs = FirestoreService();
  late final Stream<Map<String, Map<String, dynamic>>> _devicesStream;

  @override
  void initState() {
    super.initState();
    _devicesStream = emitOnError(
      _fs.streamDevices(widget.athleteUid),
      const <String, Map<String, dynamic>>{},
    );
  }

  Future<void> _proceedToDashboard() async {
    if (widget.isFromSettings) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await _fs.updateDeviceTier(widget.athleteUid, 'tier3', setupCompleted: true);
    } catch (e) {
      debugPrint('Skip device setup write failed: $e');
    }
    if (!mounted) return;
    await continueAfterDeviceSetup(context, widget.athleteUid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'CONNECT DEVICE',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
          ),
        ),
        automaticallyImplyLeading: widget.isFromSettings,
        actions: [
          if (!widget.isFromSettings)
            TextButton(
              onPressed: _proceedToDashboard,
              child: Text(
                'Skip',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
        ],
      ),
      body: StreamBuilder<Map<String, Map<String, dynamic>>>(
        stream: _devicesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return kAsyncLoading;
          }

          final devices = snapshot.data ?? {};
          final appleWatch = devices['apple_watch'] ?? {};
          final isAppleWatchConnected = appleWatch['connected'] == true;

          final garmin = devices['garmin'] ?? {};
          final isGarminConnected = garmin['connected'] == true;

          final whoop = devices['whoop'] ?? {};
          final isWhoopConnected = whoop['connected'] == true;

          final otherDevice = devices['other'] ?? {};
          final isOtherConnected = otherDevice['connected'] == true;
          final healthConnect = devices[HealthSyncService.healthConnectDeviceId] ?? {};
          final isHealthConnectConnected = healthConnect['connected'] == true;

          final hasAnyConnected = isAppleWatchConnected ||
              isGarminConnected ||
              isWhoopConnected ||
              isOtherConnected ||
              isHealthConnectConnected;

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect your data',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'So AthleteIQ can track load and recovery automatically.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(height: 24),

                        // 1. APPLE WATCH CARD (TIER 1)
                        _DeviceCard(
                          title: 'Apple Watch',
                          tierLabel: 'TIER 1 · FULL',
                          tierColor: AppColors.mint,
                          tierBg: AppColors.mint.withValues(alpha: 0.12),
                          icon: Icons.watch_outlined,
                          isConnected: isAppleWatchConnected,
                          onTap: () => _openAppleWatchModal(
                            context,
                            isAppleWatchConnected,
                            appleWatch,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. GARMIN CARD (TIER 1)
                        _DeviceCard(
                          title: 'Garmin',
                          tierLabel: 'TIER 1 · FULL',
                          tierColor: AppColors.mint,
                          tierBg: AppColors.mint.withValues(alpha: 0.12),
                          icon: Icons.watch_rounded,
                          isConnected: isGarminConnected,
                          onTap: () => _openGenericDeviceModal(
                            context,
                            deviceId: 'garmin',
                            name: 'Garmin Connect',
                            tier: 'tier1',
                            tierLabel: 'TIER 1 · FULL',
                            isConnected: isGarminConnected,
                            data: garmin,
                            comingSoon: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 3. WHOOP CARD (TIER 1)
                        _DeviceCard(
                          title: 'Whoop',
                          tierLabel: 'TIER 1 · FULL',
                          tierColor: AppColors.mint,
                          tierBg: AppColors.mint.withValues(alpha: 0.12),
                          icon: Icons.monitor_heart_outlined,
                          isConnected: isWhoopConnected,
                          onTap: () => _openGenericDeviceModal(
                            context,
                            deviceId: 'whoop',
                            name: 'Whoop 4.0',
                            tier: 'tier1',
                            tierLabel: 'TIER 1 · FULL',
                            isConnected: isWhoopConnected,
                            data: whoop,
                            comingSoon: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 4. HONOR / REDMI / OTHER (TIER 2)
                        _DeviceCard(
                          title: 'Honor / Redmi / other',
                          tierLabel: 'TIER 2 · PARTIAL',
                          tierColor: AppColors.amber,
                          tierBg: AppColors.amber.withValues(alpha: 0.12),
                          icon: Icons.watch_outlined,
                          isConnected: isHealthConnectConnected || isOtherConnected,
                          onTap: () {
                            if (HealthSyncService.instance.isAndroid) {
                              _openHealthConnectModal(
                                context,
                                isHealthConnectConnected,
                                healthConnect,
                              );
                              return;
                            }
                            _openGenericDeviceModal(
                              context,
                              deviceId: 'other',
                              name: 'Honor / Redmi / Other Smartband',
                              tier: 'tier2',
                              tierLabel: 'TIER 2 · PARTIAL',
                              isConnected: isOtherConnected,
                              data: otherDevice,
                              comingSoon: true,
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // 5. NO DEVICE? TAP HERE (TIER 3 · MANUAL)
                        _ManualEntryCard(
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            await _fs.updateDeviceTier(
                              widget.athleteUid,
                              'tier3',
                              setupCompleted: true,
                            );
                            if (widget.isFromSettings) {
                              nav.pop();
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Switched to Tier 3 Manual mode'),
                                ),
                              );
                            } else {
                              await continueAfterDeviceSetup(
                                context,
                                widget.athleteUid,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _CsvImportCard(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ImportTrainingLogScreen(
                                  athleteUid: widget.athleteUid,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Continue button if connected or onboarding
                if (!widget.isFromSettings)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenEdge),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _proceedToDashboard,
                        child: Text(
                          hasAnyConnected ? 'Continue to Dashboard' : 'Continue with Selected Mode',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Apple Watch Modal Flow ----------
  void _openAppleWatchModal(
    BuildContext context,
    bool isConnected,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppleWatchModal(
        athleteUid: widget.athleteUid,
        isConnected: isConnected,
        deviceData: data,
        isFromSettings: widget.isFromSettings,
      ),
    );
  }

  void _openHealthConnectModal(
    BuildContext context,
    bool isConnected,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppleWatchModal(
        athleteUid: widget.athleteUid,
        isConnected: isConnected,
        deviceData: data,
        isFromSettings: widget.isFromSettings,
        deviceId: HealthSyncService.healthConnectDeviceId,
        displayName: 'Health Connect',
        tier: 'tier2',
      ),
    );
  }

  // ---------- Generic Device Modal (Garmin / Whoop / Other) ----------
  void _openGenericDeviceModal(
    BuildContext context, {
    required String deviceId,
    required String name,
    required String tier,
    required String tierLabel,
    required bool isConnected,
    required Map<String, dynamic> data,
    bool comingSoon = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GenericDeviceModal(
        athleteUid: widget.athleteUid,
        deviceId: deviceId,
        name: name,
        tier: tier,
        tierLabel: tierLabel,
        isConnected: isConnected,
        data: data,
        isFromSettings: widget.isFromSettings,
        comingSoon: comingSoon,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// WIDGET: Device Row Card
// ---------------------------------------------------------------------
class _DeviceCard extends StatelessWidget {
  final String title;
  final String tierLabel;
  final Color tierColor;
  final Color tierBg;
  final IconData icon;
  final bool isConnected;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.title,
    required this.tierLabel,
    required this.tierColor,
    required this.tierBg,
    required this.icon,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected ? AppColors.mint.withValues(alpha: 0.5) : AppColors.border,
          width: isConnected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon Box
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(icon, color: AppColors.textPrimary, size: 22),
                ),
                const SizedBox(width: 14),

                // Name & Tier Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tierBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tierLabel,
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action / Status Badge
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: isConnected
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.mint.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, color: AppColors.mint, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: AppColors.mint,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.mint.withValues(alpha: 0.6),
                              ),
                            ),
                            child: const Text(
                              'Connect',
                              style: TextStyle(
                                color: AppColors.mint,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// WIDGET: CSV Import Card (beta — external app exports)
// ---------------------------------------------------------------------
class _CsvImportCard extends StatelessWidget {
  final VoidCallback onTap;

  const _CsvImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(
                    Icons.upload_file_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Import CSV log',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'BETA · IMPORT',
                              style: TextStyle(
                                color: AppColors.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TrainingPeaks & similar exports — parsed into daily check-ins until live sync is available.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// WIDGET: Manual Entry Card (Tier 3)
// ---------------------------------------------------------------------
class _ManualEntryCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ManualEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'NO DEVICE? TAP HERE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'TIER 3 · MANUAL',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Log training and how you feel manually each day — see the "Manual daily log" screen.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// MODAL: Full Apple Watch Connection Experience
// ---------------------------------------------------------------------
class _AppleWatchModal extends StatefulWidget {
  final String athleteUid;
  final bool isConnected;
  final Map<String, dynamic> deviceData;
  final bool isFromSettings;
  final String deviceId;
  final String displayName;
  final String tier;

  const _AppleWatchModal({
    required this.athleteUid,
    required this.isConnected,
    required this.deviceData,
    required this.isFromSettings,
    this.deviceId = HealthSyncService.appleWatchDeviceId,
    this.displayName = 'Apple Watch',
    this.tier = 'tier1',
  });

  @override
  State<_AppleWatchModal> createState() => _AppleWatchModalState();
}

class _AppleWatchModalState extends State<_AppleWatchModal> {
  final _fs = FirestoreService();
  final _health = HealthSyncService.instance;

  bool _connecting = false;
  int _connectionStep = 0; // 0 idle, 1 permissions, 2 reading, 3 writing, 4 done
  bool _syncing = false;
  String? _error;
  bool _offerHealthConnectInstall = false;

  bool get _isHealthConnect =>
      widget.deviceId == HealthSyncService.healthConnectDeviceId;

  Future<void> _startConnectionProcess() async {
    if (_isHealthConnect) {
      final installed = await _health.isHealthConnectInstalled();
      if (!mounted) return;
      if (!installed) {
        setState(() {
          _offerHealthConnectInstall = true;
          _error =
              'Health Connect is not installed on this phone. Install it from '
              'the Play Store, then return here. Honor, Redmi, Mibro, and '
              'Kieslect data only reaches AthleteIQ after those apps write to Health Connect.';
        });
        return;
      }
    } else if (!_health.isIos) {
      setState(() {
        _error =
            'Apple Watch / HealthKit only works on a physical iPhone. '
            'Run this build on your device from Xcode, not the simulator or Chrome.';
      });
      return;
    }

    setState(() {
      _connecting = true;
      _connectionStep = 1;
      _error = null;
      _offerHealthConnectInstall = false;
    });

    try {
      final granted = await _health.requestPermissions();
      if (!mounted) return;
      if (!granted) {
        final stillMissing = _isHealthConnect &&
            !await _health.isHealthConnectInstalled();
        if (!mounted) return;
        setState(() {
          _connecting = false;
          _connectionStep = 0;
          _offerHealthConnectInstall = stillMissing;
          _error = stillMissing
              ? 'Health Connect is not installed on this phone. Install it from the Play Store, then try again.'
              : (_isHealthConnect
                  ? 'Health Connect permission was denied. Enable Heart Rate, Sleep, Workouts, and Steps for AthleteIQ in Health Connect. HRV is optional on Android and is left blank when the watch does not record it.'
                  : 'HealthKit permission was denied. Enable Heart Rate, HRV, Sleep, '
                      'and Workouts for AthleteIQ in Settings → Health → Data Access.');
        });
        return;
      }

      setState(() => _connectionStep = 2);
      final metrics = await _health.readToday();
      if (!mounted) return;

      if (isWearableReadFailureNote(metrics.note)) {
        setState(() {
          _connecting = false;
          _connectionStep = 0;
          _offerHealthConnectInstall =
              metrics.note!.startsWith('Health Connect is not installed') ||
                  metrics.note!.startsWith('Health Connect needs an update');
          _error = metrics.note;
        });
        return;
      }

      setState(() => _connectionStep = 3);
      final now = DateTime.now().toIso8601String();
      await _fs.connectDevice(widget.athleteUid, widget.deviceId, {
        'name': widget.displayName,
        'tier': widget.tier,
        'connectedAt': widget.deviceData['connectedAt'] ?? now,
        'lastSync': now,
        'metrics': metrics.toDeviceMetricsMap(),
        'permissions': {
          'heartRate': true,
          'hrv': metrics.hrv != null,
          'workouts': true,
          'sleep': true,
          if (_isHealthConnect) 'steps': metrics.steps != null,
        },
      });
      await _fs.mergeWearableCheckIn(
        widget.athleteUid,
        metrics,
        deviceId: widget.deviceId,
      );

      if (!mounted) return;
      setState(() {
        _connectionStep = 4;
        _connecting = false;
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            metrics.hasAny
                ? '${widget.displayName} connected. Today\'s samples written to check-in'
                    '${metrics.hrv == null ? ' (no HRV sample — field omitted).' : '.'}'
                : '${widget.displayName} connected. No samples yet for today — wear the device and tap Sync Now later.',
          ),
          backgroundColor: AppColors.mintDark,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectionStep = 0;
        _error = _isHealthConnect
            ? 'Could not connect Health Connect: $e'
            : 'Could not connect HealthKit: $e';
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final metrics = await _health.syncToday(
        widget.athleteUid,
        deviceId: widget.deviceId,
      );
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            metrics.hasAny
                ? 'Synced ${widget.displayName} into today\'s check-in'
                    '${metrics.hrv == null ? ' (no HRV sample today — field omitted).' : '.'}'
                : '${widget.displayName} returned no samples for today.',
          ),
        ),
      );
    } catch (e) {
      await _fs.recordDeviceSyncFailure(
        widget.athleteUid,
        widget.deviceId,
        e.toString(),
      );
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _error = 'Sync failed: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _fs.disconnectDevice(widget.athleteUid, widget.deviceId);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.displayName} disconnected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.deviceData['metrics'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.watch_outlined, color: AppColors.mint, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.displayName} Integration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isConnected ? AppColors.mint : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isConnected
                              ? (_isHealthConnect
                                  ? 'Connected via Health Connect · Tier 2'
                                  : 'Connected via Apple HealthKit')
                              : (_isHealthConnect
                                  ? 'Tier 2 · Heart rate, sleep, steps · HRV usually unavailable'
                                  : 'Tier 1 · Full Biometrics Sync'),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // IF CONNECTED: SHOW LIVE METRICS & CONTROL
          if (widget.isConnected) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.mint.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SYNCED BIOMETRICS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.mint,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Automated Daily Load',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricBadge(
                        label: _isHealthConnect ? 'HRV' : 'HRV (SDNN)',
                        value: metrics?['hrv'] == null
                            ? '—'
                            : '${metrics!['hrv']} ms',
                        icon: Icons.favorite_border,
                      ),
                      const SizedBox(width: 8),
                      _MetricBadge(
                        label: 'Resting HR',
                        value: metrics?['restingHr'] == null
                            ? '—'
                            : '${metrics!['restingHr']} bpm',
                        icon: Icons.speed_outlined,
                      ),
                      const SizedBox(width: 8),
                      _MetricBadge(
                        label: 'Sleep',
                        value: metrics?['sleepHours'] == null
                            ? '—'
                            : '${metrics!['sleepHours']} hrs',
                        icon: Icons.bedtime_outlined,
                      ),
                    ],
                  ),
                  if (_isHealthConnect) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MetricBadge(
                          label: 'Steps',
                          value: metrics?['steps'] == null
                              ? '—'
                              : '${metrics!['steps']}',
                          icon: Icons.directions_walk_outlined,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: SizedBox()),
                        const SizedBox(width: 8),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.mintDark,
                            ),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _disconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.coral,
                    side: BorderSide(color: AppColors.coral.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              EmptyState(
                icon: Icons.watch_rounded,
                heading: 'Sync failed',
                subtext: _error!,
                warn: true,
              ),
            ],
          ] else if (_connecting) ...[
            // CONNECTING STEP-BY-STEP PROGRESS UI
            Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _StepRow(
                    stepNumber: 1,
                    title: _isHealthConnect
                        ? 'Requesting Health Connect permissions'
                        : 'Requesting Apple HealthKit permissions',
                    active: _connectionStep == 1,
                    done: _connectionStep > 1,
                  ),
                  const SizedBox(height: 12),
                  _StepRow(
                    stepNumber: 2,
                    title: _isHealthConnect
                        ? 'Reading Health Connect samples'
                        : 'Reading HealthKit samples',
                    active: _connectionStep == 2,
                    done: _connectionStep > 2,
                  ),
                  const SizedBox(height: 12),
                  _StepRow(
                    stepNumber: 3,
                    title: 'Writing today\'s check-in (HRV omitted if missing)',
                    active: _connectionStep == 3,
                    done: _connectionStep > 3,
                  ),
                  const SizedBox(height: 12),
                  _StepRow(
                    stepNumber: 4,
                    title: '${widget.displayName} connected',
                    active: _connectionStep == 4,
                    done: _connectionStep > 4,
                  ),
                ],
              ),
            ),
          ] else ...[
            // DISCONNECTED PERMISSION CHECKLIST & AUTHORIZE BUTTON
            Text(
              _isHealthConnect
                  ? 'AthleteIQ reads resting heart rate, sleep, workouts, and steps from Health Connect. Most Android wearables (Honor, Redmi, Mibro, Kieslect) do not record HRV — that field is left blank, never invented. Profile tier is Tier 2 · Partial.'
                  : 'AthleteIQ reads resting heart rate, HRV (SDNN), sleep, and workouts from Apple Health. If the watch has no HRV sample for today, that field is left blank — never invented.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(
              _isHealthConnect
                  ? 'Android will ask for Health Connect access. The Health Connect app must be installed (Play Store). Pair your watch with its vendor app and enable Health Connect sharing there first.'
                  : 'iOS will ask for Health access. You must also add the HealthKit capability in Xcode (see the build guide).',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              EmptyState(
                icon: Icons.watch_rounded,
                heading: 'Sync failed',
                subtext: _error!,
                warn: true,
              ),
            ],
            const SizedBox(height: 20),
            if (_offerHealthConnectInstall) ...[
              ElevatedButton(
                onPressed: () => _health.installHealthConnect(),
                child: const Text('Install Health Connect'),
              ),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: _startConnectionProcess,
              child: Text(
                _isHealthConnect
                    ? 'Authorize & Connect Health Connect'
                    : 'Authorize & Connect Apple Watch',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// HELPER COMPONENTS FOR MODALS
// ---------------------------------------------------------------------
class _MetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricBadge({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: AppColors.mint),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int stepNumber;
  final String title;
  final bool active;
  final bool done;

  const _StepRow({
    required this.stepNumber,
    required this.title,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.mint
                : (active ? AppColors.mint.withValues(alpha: 0.2) : AppColors.surface),
            border: Border.all(
              color: done || active ? AppColors.mint : AppColors.border,
            ),
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: AppColors.mintDark)
              : (active
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint,
                      ),
                    )
                  : Text(
                      '$stepNumber',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    )),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: done || active ? AppColors.textPrimary : AppColors.textMuted,
              fontWeight: done || active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// MODAL: Generic Device Modal (Garmin, Whoop, Tier 2)
// ---------------------------------------------------------------------
class _GenericDeviceModal extends StatefulWidget {
  final String athleteUid;
  final String deviceId;
  final String name;
  final String tier;
  final String tierLabel;
  final bool isConnected;
  final Map<String, dynamic> data;
  final bool isFromSettings;
  final bool comingSoon;

  const _GenericDeviceModal({
    required this.athleteUid,
    required this.deviceId,
    required this.name,
    required this.tier,
    required this.tierLabel,
    required this.isConnected,
    required this.data,
    required this.isFromSettings,
    this.comingSoon = false,
  });

  @override
  State<_GenericDeviceModal> createState() => _GenericDeviceModalState();
}

class _GenericDeviceModalState extends State<_GenericDeviceModal> {
  final _fs = FirestoreService();

  Future<void> _disconnect() async {
    await _fs.disconnectDevice(widget.athleteUid, widget.deviceId);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.name} disconnected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.tierLabel,
                      style: const TextStyle(fontSize: 12, color: AppColors.mint),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.comingSoon
                ? '${widget.name} needs official API access from the vendor before AthleteIQ can sync. That is a business approval step, not something we can fake in the app.'
                : widget.isConnected
                    ? '${widget.name} is actively syncing training load data to AthleteIQ.'
                    : 'Connect your ${widget.name} account to stream activity logs and recovery scores automatically.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (widget.isConnected) ...[
            OutlinedButton(
              onPressed: _disconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.coral,
                side: BorderSide(color: AppColors.coral.withValues(alpha: 0.4)),
              ),
              child: const Text('Disconnect Device'),
            ),
          ] else if (widget.comingSoon) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.riskMedBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Coming soon — Garmin and Whoop require developer API approval. On Android, connect Honor / Redmi / other via Health Connect. On iPhone, use Apple Watch (HealthKit) or log today by hand.',
                style: TextStyle(color: AppColors.amber, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: null,
              child: Text('Connect ${widget.name}'),
            ),
          ],
        ],
      ),
    );
  }
}
