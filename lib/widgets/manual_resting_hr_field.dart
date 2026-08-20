import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Optional resting-HR entry for Tier 3 athletes (no wearable).
/// Skip is the default — the value is only written when the athlete opts in.
class ManualRestingHrField extends StatelessWidget {
  final bool include;
  final double bpm;
  final ValueChanged<bool> onIncludeChanged;
  final ValueChanged<double> onBpmChanged;

  static const double minBpm = 40;
  static const double maxBpm = 110;
  static const double defaultBpm = 60;

  const ManualRestingHrField({
    super.key,
    required this.include,
    required this.bpm,
    required this.onIncludeChanged,
    required this.onBpmChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resting heart rate (optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'If you know it, e.g. from checking your pulse. Approximate is fine — skip if you\'re not sure.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Chip(
              label: 'Skip',
              selected: !include,
              onTap: () => onIncludeChanged(false),
            ),
            const SizedBox(width: 12),
            _Chip(
              label: 'I know it',
              selected: include,
              onTap: () => onIncludeChanged(true),
            ),
          ],
        ),
        if (include) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Beats per minute',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                '${bpm.round()} bpm',
                style: const TextStyle(
                  color: AppColors.mint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: bpm.clamp(minBpm, maxBpm),
            min: minBpm,
            max: maxBpm,
            divisions: (maxBpm - minBpm).round(),
            activeColor: AppColors.mint,
            inactiveColor: AppColors.border,
            onChanged: onBpmChanged,
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: selected ? AppColors.mint : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.mintDark : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
