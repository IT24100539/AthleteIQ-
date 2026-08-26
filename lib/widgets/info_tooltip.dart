import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small "?" control that opens a compact in-place explanation (no route push).
class InfoTooltip extends StatelessWidget {
  final String message;
  final String? title;

  const InfoTooltip({
    super.key,
    required this.message,
    this.title,
  });

  Future<void> _showPopover(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: title != null
              ? Text(
                  title!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                )
              : null,
          titlePadding: title != null
              ? const EdgeInsets.fromLTRB(20, 20, 20, 0)
              : EdgeInsets.zero,
          contentPadding: EdgeInsets.fromLTRB(20, title != null ? 8 : 20, 20, 8),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'More information',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPopover(context),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Center(
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label row with an optional trailing [InfoTooltip].
class FieldLabelWithInfo extends StatelessWidget {
  final String label;
  final String? infoText;
  final String? infoTitle;
  final TextStyle? style;

  const FieldLabelWithInfo({
    super.key,
    required this.label,
    this.infoText,
    this.infoTitle,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = style ??
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: Text(label, style: textStyle)),
        if (infoText != null)
          InfoTooltip(message: infoText!, title: infoTitle),
      ],
    );
  }
}
