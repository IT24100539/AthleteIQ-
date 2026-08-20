import 'package:flutter/material.dart';
import '../widgets/empty_state.dart';

/// Athlete just onboarded — no check-ins yet. Wireframe "No data yet".
class NoDataYetScreen extends StatelessWidget {
  final VoidCallback onLogCheckIn;
  final VoidCallback onConnectDevice;

  const NoDataYetScreen({
    super.key,
    required this.onLogCheckIn,
    required this.onConnectDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.show_chart_rounded,
        heading: 'No data yet',
        subtext:
            'Start with a check-in (how you felt and what you trained) or connect '
            'a wearable for sleep and heart rate. AthleteIQ will not invent a '
            'forecast until you have logged days.',
        actionLabel: 'Log a check-in',
        onAction: onLogCheckIn,
        secondaryActionLabel: 'Connect a device',
        onSecondaryAction: onConnectDevice,
      ),
    );
  }
}
