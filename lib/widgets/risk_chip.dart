import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RiskChip extends StatelessWidget {
  final String level; // LOW | MEDIUM | HIGH
  const RiskChip({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgForRisk(level),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          color: AppColors.forRisk(level),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
