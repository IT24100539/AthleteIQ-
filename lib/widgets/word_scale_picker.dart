import 'package:flutter/material.dart';

import '../constants/checkin_scale_labels.dart';
import '../theme/app_theme.dart';
import 'info_tooltip.dart';
import 'pill_selector.dart';

/// Word chips for fatigue / session effort. The selected [value] is the
/// number stored on the check-in (fatigue 1–5, RPE 2/4/6/8/10).
class WordScalePicker extends StatelessWidget {
  final String label;
  final String? infoText;
  final List<CheckinWordChoice> choices;
  final int value;
  final ValueChanged<int> onSelected;

  const WordScalePicker({
    super.key,
    required this.label,
    this.infoText,
    required this.choices,
    required this.value,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabelWithInfo(
            label: label,
            infoText: infoText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in choices)
                SelectableChip(
                  label: choice.label,
                  selected: value == choice.value,
                  onTap: () => onSelected(choice.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
