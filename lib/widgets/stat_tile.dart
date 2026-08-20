import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum StatTrend { up, down, neutral }

/// Compact stat display — wireframe `.stat` boxes (ACWR, sleep, load, etc.)
/// with an optional trend arrow beside the value.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final StatTrend? trend;
  final Color? valueColor;
  final bool compact;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.valueColor,
    this.compact = false,
  });

  Color _trendColor() {
    switch (trend) {
      case StatTrend.up:
        return AppColors.coral;
      case StatTrend.down:
        return AppColors.mint;
      case StatTrend.neutral:
      case null:
        return AppColors.textMuted;
    }
  }

  IconData? _trendIcon() {
    switch (trend) {
      case StatTrend.up:
        return Icons.arrow_upward_rounded;
      case StatTrend.down:
        return Icons.arrow_downward_rounded;
      case StatTrend.neutral:
        return Icons.remove_rounded;
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trendIcon = _trendIcon();

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 10 : 14,
        horizontal: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          compact ? AppRadius.cardSmall : AppRadius.card,
        ),
        border: compact ? null : Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    color: valueColor ?? AppColors.textPrimary,
                    fontSize: compact ? 16 : 20,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              if (trendIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trendIcon, size: 14, color: _trendColor()),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
