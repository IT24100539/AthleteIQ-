import 'package:athleteiq/widgets/info_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:athleteiq/constants/checkin_field_help.dart';

void main() {
  testWidgets('InfoTooltip opens explanation dialog on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InfoTooltip(message: CheckinFieldHelp.fatigue),
        ),
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.text(CheckinFieldHelp.fatigue), findsNothing);

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text(CheckinFieldHelp.fatigue), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text(CheckinFieldHelp.fatigue), findsNothing);
  });

  testWidgets('FieldLabelWithInfo shows label and info button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FieldLabelWithInfo(
            label: 'How do you feel today?',
            infoText: CheckinFieldHelp.fatigue,
          ),
        ),
      ),
    );

    expect(find.text('How do you feel today?'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });
}
