import 'package:athleteiq/constants/checkin_field_help.dart';
import 'package:athleteiq/theme/app_theme.dart';
import 'package:athleteiq/widgets/info_tooltip.dart';
import 'package:athleteiq/widgets/responsive_chart_frame.dart';
import 'package:athleteiq/widgets/risk_chip.dart';
import 'package:athleteiq/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _smallPhone = Size(360, 640);

Widget _phoneApp(Widget home) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: const MediaQueryData(size: _smallPhone),
      child: home,
    ),
  );
}

void main() {
  testWidgets('FieldLabelWithInfo + long RPE label does not overflow at 360px',
      (tester) async {
    await tester.binding.setSurfaceSize(_smallPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phoneApp(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: FieldLabelWithInfo(
                    label: 'How hard did training or the match feel? (RPE)',
                    infoText: CheckinFieldHelp.rpe,
                  ),
                ),
                Text('10'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('three StatCards in a row fit a 360px phone', (tester) async {
    await tester.binding.setSurfaceSize(_smallPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phoneApp(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: StatCard(label: 'ACWR', value: '1.62')),
                SizedBox(width: 8),
                Expanded(child: StatCard(label: 'Recovery', value: 'worsening')),
                SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Match + readiness',
                    value: 'DECLINING',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('roster-style wrap of chips does not overflow at 360px',
      (tester) async {
    await tester.binding.setSurfaceSize(_smallPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phoneApp(
        Scaffold(
          body: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 20,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(child: Text('AB')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Athlete with a very long name $i'),
                          const Text(
                            'Soccer / Midfielder · Last log 12 days ago',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text('REVIEW'),
                              Text('PAIN'),
                              RiskChip(level: 'HIGH'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ResponsiveChartFrame shrinks below maxHeight on a 360px phone',
      (tester) async {
    await tester.binding.setSurfaceSize(_smallPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phoneApp(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: ResponsiveChartFrame(
              maxHeight: 260,
              minHeight: 150,
              builder: (context, size) {
                return ColoredBox(
                  color: Colors.teal,
                  child: Text('${size.height.round()}'),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final box = tester.renderObject<RenderBox>(find.byType(ResponsiveChartFrame));
    expect(box.size.height, lessThanOrEqualTo(260));
    expect(box.size.height, greaterThanOrEqualTo(150));
    expect(box.size.width, lessThanOrEqualTo(360));
  });

  testWidgets('pain-row two-line layout fits 360px', (tester) async {
    await tester.binding.setSurfaceSize(_smallPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phoneApp(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on_outlined),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Left hamstring near the insertion',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.close),
                    ],
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (_) => const Expanded(child: SizedBox(height: 48, width: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
