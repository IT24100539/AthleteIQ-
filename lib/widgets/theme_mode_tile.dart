import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';

/// Dark / light switch used on athlete Profile and coach Settings.
class ThemeModeTile extends StatelessWidget {
  final EdgeInsetsGeometry contentPadding;

  const ThemeModeTile({
    super.key,
    this.contentPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return SwitchListTile(
      contentPadding: contentPadding,
      secondary: Icon(
        theme.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        color: AppColors.textSecondary,
        size: 20,
      ),
      title: const Text('Dark mode'),
      subtitle: Text(
        theme.isDark ? 'On' : 'Off — light appearance',
        style: const TextStyle(fontSize: 12),
      ),
      value: theme.isDark,
      activeTrackColor: AppColors.mint,
      activeThumbColor: AppColors.mintDark,
      onChanged: (v) => theme.setDark(v),
    );
  }
}
