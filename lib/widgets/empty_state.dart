import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_buttons.dart';

/// Centered empty / error placeholder — wireframe `.empty-wrap` screens
/// ("No data yet", "Sync failed", "Not enough data").
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String heading;
  final String subtext;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool warn;

  const EmptyState({
    super.key,
    required this.icon,
    required this.heading,
    required this.subtext,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: warn ? AppColors.riskHighBg : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.emptyIcon),
            ),
            child: Icon(
              icon,
              size: 28,
              color: warn ? AppColors.coral : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            heading,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtext,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            SecondaryButton(
              label: actionLabel!,
              onPressed: onAction,
              expanded: false,
            ),
          ],
          if (secondaryActionLabel != null) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: secondaryActionLabel!,
              onPressed: onSecondaryAction,
              expanded: false,
            ),
          ],
        ],
      ),
    );
  }
}
