import 'package:flutter_test/flutter_test.dart';
import 'package:athleteiq/theme/app_theme.dart';

void main() {
  test('AppColors.forRisk returns expected colors', () {
    expect(AppColors.forRisk('HIGH'), AppColors.coral);
    expect(AppColors.forRisk('MEDIUM'), AppColors.amber);
    expect(AppColors.forRisk('LOW'), AppColors.mint);
  });
}
