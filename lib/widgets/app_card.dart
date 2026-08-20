import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// General-purpose card matching every `background:#1C1F1D; border:1px solid
/// #2A2E2B; border-radius:7-8px` box in the wireframe (device-card,
/// rec-box, acwr-box, factor, chart-box, report-summary, etc. all share
/// this same visual recipe — one widget covers all of them).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: card,
    );
  }
}

/// Small uppercase caption label — matches wireframe `.label`
/// (0.06em letter-spacing, uppercase, muted, bold, 12px equivalent).
class CaptionLabel extends StatelessWidget {
  final String text;
  const CaptionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// A section heading with optional trailing action, used above every card
/// group (e.g. "Recent training", "Athletes needing review").
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}