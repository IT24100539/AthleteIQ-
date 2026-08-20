import 'dart:math' as math;

import 'package:athleteiq/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double relativeLuminance(Color c) {
  double lin(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a);
  final l2 = relativeLuminance(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('RiskChip contrast on dark surfaces', () {
    test('HIGH coral on riskHighBg meets 4.5:1', () {
      expect(
        contrastRatio(AppColors.coral, AppColors.riskHighBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('MEDIUM amber on riskMedBg meets 4.5:1', () {
      expect(
        contrastRatio(AppColors.amber, AppColors.riskMedBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('LOW mint on riskLowBg meets 4.5:1', () {
      expect(
        contrastRatio(AppColors.mint, AppColors.riskLowBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('chip colors remain readable on the app background', () {
      expect(
        contrastRatio(AppColors.coral, AppColors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(AppColors.mint, AppColors.background),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('mintDark on coral (inbox NEW badge) meets 4.5:1', () {
      expect(
        contrastRatio(AppColors.mintDark, AppColors.coral),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
