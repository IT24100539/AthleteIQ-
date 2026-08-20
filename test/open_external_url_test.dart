import 'package:athleteiq/constants/legal_urls.dart';
import 'package:athleteiq/widgets/privacy_policy_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  late String? launchedUrl;

  setUp(() {
    launchedUrl = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'canLaunch':
          return true;
        case 'launch':
          launchedUrl = call.arguments['url'] as String?;
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('privacy policy URL is a valid https link', () {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'athleteiq.app');
    expect(uri.path, '/privacy');
  });

  testWidgets('Privacy Policy tile launches external URL when tapped', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrivacyPolicyTile(),
        ),
      ),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    expect(launchedUrl, kPrivacyPolicyUrl);
  });
}
