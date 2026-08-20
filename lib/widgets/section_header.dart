import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Uppercase small-caps label matching wireframe `.label`
/// (`#6E736F`, 12px, weight 600, 0.06em letter-spacing).
class SectionHeader extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const SectionHeader(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.labelBottom),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.72,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// @deprecated Use [SectionHeader] instead.
typedef CaptionLabel = SectionHeader;
