import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Matches the wireframe's `.risk-chip` exactly:
/// font-weight 700, radius 10px, small padding, colored by risk level.
///
/// Contrast: coral / amber / mint on the dark chip backgrounds all clear
/// WCAG 4.5:1. A 1px tinted border keeps the chip readable on `#0B0D0C`.
///
/// `level` is a plain string ("HIGH" | "MEDIUM" | "LOW", case-insensitive)
/// to match AppColors.forRisk()/bgForRisk() signatures already in your
/// theme file — no dependency on a specific enum from models/, so this
/// compiles regardless of how you've modeled risk elsewhere.
class RiskChip extends StatelessWidget {
  final String level;
  final bool large;
  const RiskChip({super.key, required this.level, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forRisk(level);
    final bg = AppColors.bgForRisk(level);
    final label = '${level.toUpperCase()} RISK';
    return Semantics(
      label: label.toLowerCase(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 12 : 8,
          vertical: large ? 6 : 4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: large ? 12 : 11,
            height: 1.2,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Small colored dot used next to risk text in list rows
/// (wireframe `.dot` class — e.g. priority queue, roster rows).
class RiskDot extends StatelessWidget {
  final String level;
  const RiskDot({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.forRisk(level),
        shape: BoxShape.circle,
      ),
    );
  }
}
