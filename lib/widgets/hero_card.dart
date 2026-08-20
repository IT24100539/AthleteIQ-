import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The gradient hero box used repeatedly in the wireframe — athlete status
/// card, performance hero, verdict box (`.status-hero`, `.perf-hero`,
/// `.aperf-hero`, `.verdict-box` all use the exact same
/// `linear-gradient(160deg, #153A30, #0F2A22)` recipe with 10px radius).
class HeroGradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HeroGradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
          colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
        ),
      ),
      child: child,
    );
  }
}

/// Round icon badge — matches `.device-icon` / `.notif-icon` / `.carousel-icon`
/// pattern: small rounded-square or circle, mint icon on tinted mint bg.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool circle;
  const IconBadge({super.key, required this.icon, this.size = 40, this.circle = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.12),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: AppColors.mint, size: size * 0.5),
    );
  }
}
