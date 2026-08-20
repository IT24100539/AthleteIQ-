import 'package:flutter/material.dart';
import '../utils/wearable_sync_status.dart';
import '../widgets/empty_state.dart';

/// Wearable sync failure — copy is the recorded HealthKit / device error,
/// not a fabricated Garmin story.
class SyncFailedScreen extends StatelessWidget {
  final WearableSyncIssue issue;
  final VoidCallback onReconnect;
  final VoidCallback? onReportPain;
  final bool asPage;

  const SyncFailedScreen({
    super.key,
    required this.issue,
    required this.onReconnect,
    this.onReportPain,
    this.asPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyState(
              icon: Icons.watch_rounded,
              heading: '${issue.deviceName} sync failed',
              subtext: issue.message,
              actionLabel: 'Reconnect device',
              onAction: onReconnect,
              warn: true,
            ),
            if (onReportPain != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReportPain,
                icon: const Icon(Icons.healing_outlined, size: 18),
                label: const Text('Report pain instead'),
              ),
            ],
          ],
        ),
      ),
    );

    if (!asPage) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync failed'),
        centerTitle: true,
      ),
      body: body,
    );
  }
}
