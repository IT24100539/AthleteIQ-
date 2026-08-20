
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'models/athlete.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/local_prefs.dart';
import 'screens/splash_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/sport_selection_screen.dart';
import 'screens/connect_device_screen.dart';
import 'screens/connect_coach_screen.dart';
import 'screens/athlete_main_layout.dart';
import 'screens/coach_main_layout.dart';
import 'services/fcm_service.dart';
import 'dev/demo_accounts.dart';
import 'dev/widget_catalog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Flutter web + IndexedDB persistence + hot restart corrupts the
  // Firestore listen client (INTERNAL ASSERTION FAILED / ID: b815).
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  // Local dev: flutter run -d chrome --dart-define=USE_EMULATOR=true
  if (kDebugMode && const bool.fromEnvironment('USE_EMULATOR')) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
  }

  final themeController = ThemeController();
  await themeController.load();
  runApp(AthleteIQApp(themeController: themeController));
}

class AthleteIQApp extends StatelessWidget {
  final ThemeController themeController;

  const AthleteIQApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: themeController,
      child: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          AppColors.bind(themeController.isDark);
          final overlay = themeController.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: themeController.isDark
                  ? AppPalette.dark.surfaceAlt
                  : AppPalette.light.surfaceAlt,
            ),
            child: MaterialApp(
              title: 'AthleteIQ',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeController.mode,
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                // Do not call TextScaler.clamp() — composing two clamped scalers
                // can make min >= max (Flutter asserts maxScale > minScale).
                final scale = mq.textScaler.scale(1.0).clamp(1.0, 1.6);
                return MediaQuery(
                  data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: kDebugMode && const bool.fromEnvironment('SHOW_WIDGET_CATALOG')
                  ? const WidgetCatalog()
                  : const AuthGate(),
              routes: {
                '/sign-in': (_) => const SignInScreen(),
                if (kDebugMode) '/dev/widgets': (_) => const WidgetCatalog(),
              },
            ),
          );
        },
      ),
    );
  }
}

/// Section 17 — a coach and an athlete are different journeys, not one
/// generic screen. This gate reads the user's role from Firestore right
/// after auth resolves and sends them down the correct path.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  late final Stream<User?> _authStream = _auth.authStateChanges;
  Future<String?>? _roleFuture;
  String? _roleUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        final user = authSnap.data;
        if (user == null) {
          _roleFuture = null;
          _roleUid = null;
          return const SignInScreen();
        }

        if (_roleUid != user.uid) {
          _roleUid = user.uid;
          _roleFuture = _auth.getRole(user.uid);
          FcmService.registerForUser(user.uid);
        }

        return FutureBuilder<String?>(
          future: _roleFuture,
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }

            if (roleSnap.hasError) {
              return const _ProfileLoadError();
            }

            final role = roleSnap.data;

            if (role == null) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No profile found for this account.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The role field is missing in Firestore.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Sign out and try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (role == 'coach') {
              if (kDebugMode && DemoAccounts.isDemoEmail(user.email)) {
                DemoSession.coachUid = user.uid;
              }
              return CoachMainLayout(key: ValueKey('coach-${user.uid}'), coachUid: user.uid);
            }

            if (kDebugMode && DemoAccounts.isDemoEmail(user.email)) {
              DemoSession.athleteUid = user.uid;
            }

            return _AthleteEntry(key: ValueKey('athlete-${user.uid}'), athleteUid: user.uid);
          },
        );
      },
    );
  }
}

class _AthleteEntry extends StatefulWidget {
  final String athleteUid;
  const _AthleteEntry({super.key, required this.athleteUid});

  @override
  State<_AthleteEntry> createState() => _AthleteEntryState();
}

class _AthleteGate {
  final AthleteProfile profile;
  final bool coachConnectSkipped;
  const _AthleteGate({required this.profile, required this.coachConnectSkipped});
}

class _AthleteEntryState extends State<_AthleteEntry> {
  late Future<_AthleteGate> _gateFuture = _load();

  Future<_AthleteGate> _load() async {
    final profile =
        await FirestoreService().getAthleteProfileOnce(widget.athleteUid);
    final skipped = await LocalPrefs.coachConnectSkipped(widget.athleteUid);
    return _AthleteGate(profile: profile, coachConnectSkipped: skipped);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AthleteGate>(
      future: _gateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        if (snapshot.hasError) {
          return const _ProfileLoadError();
        }

        final gate = snapshot.data;
        if (gate == null) {
          return const _ProfileLoadError();
        }
        final profile = gate.profile;
        if (!profile.hasSport) {
          return SportSelectionScreen(athleteUid: widget.athleteUid);
        }
        if (!profile.deviceSetupCompleted) {
          return ConnectDeviceScreen(athleteUid: widget.athleteUid);
        }
        final linked = profile.coachUid != null && profile.coachUid!.isNotEmpty;
        if (!linked && !gate.coachConnectSkipped) {
          return ConnectCoachScreen(
            athleteUid: widget.athleteUid,
            isOnboarding: true,
            onLinked: () => setState(() => _gateFuture = _load()),
          );
        }
        return AthleteMainLayout(athleteUid: widget.athleteUid);
      },
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not load your profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'On Chrome, do a full refresh (Ctrl+Shift+R). '
                'Hot restart leaves Firestore in a bad state.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign out and try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
