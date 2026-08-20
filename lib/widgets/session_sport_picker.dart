import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown on check-in when the athlete has more than one sport.
/// Today's pick drives Section 12.3 / 15.3 wording for that session.
class SessionSportPicker extends StatelessWidget {
  final List<String> sports;
  final String selected;
  final ValueChanged<String> onSelected;

  const SessionSportPicker({
    super.key,
    required this.sports,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (sports.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which sport was today\'s session?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This sets today\'s check-in wording and recommendation template.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in sports)
              ChoiceChip(
                label: Text(name),
                selected: selected == name,
                onSelected: (_) => onSelected(name),
              ),
          ],
        ),
      ],
    );
  }
}
