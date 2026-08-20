import 'package:flutter/material.dart';
import '../models/risk_latest.dart';
import '../widgets/empty_state.dart';

/// Coach view when `riskResults/latest` is missing or `{ insufficientData: true }`.
/// Shows real check-in progress — never a placeholder risk score.
class NotEnoughDataScreen extends StatelessWidget {
  final int checkInCount;
  final DateTime? joinedAt;

  const NotEnoughDataScreen({
    super.key,
    required this.checkInCount,
    this.joinedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.person_outline,
        heading: 'No forecast for this athlete yet',
        subtext: notEnoughDataSubtext(
          checkInCount: checkInCount,
          joinedAt: joinedAt,
        ),
      ),
    );
  }
}
