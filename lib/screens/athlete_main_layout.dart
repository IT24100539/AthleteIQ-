import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/health_sync_service.dart';
import '../utils/friendly_error.dart';
import 'athlete_home_screen.dart';
import 'training_calendar_screen.dart';
import 'ask_athlete_iq_screen.dart';
import 'message_coach_screen.dart';
import 'profile_screen.dart';

class AthleteMainLayout extends StatefulWidget {
  final String athleteUid;
  final int initialTab;

  const AthleteMainLayout({
    super.key,
    required this.athleteUid,
    this.initialTab = 0,
  });

  @override
  State<AthleteMainLayout> createState() => _AthleteMainLayoutState();
}

class _AthleteMainLayoutState extends State<AthleteMainLayout>
    with WidgetsBindingObserver {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    _syncWatch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncWatch();
  }

  Future<void> _syncWatch() async {
    try {
      await HealthSyncService.instance.syncIfWatchConnected(widget.athleteUid);
    } on RiskEngineException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      debugPrint('Wearable app-open sync failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AthleteHomeScreen(athleteUid: widget.athleteUid),
      TrainingCalendarScreen(athleteUid: widget.athleteUid),
      AskAthleteIQScreen(athleteUid: widget.athleteUid),
      MessageCoachScreen(athleteUid: widget.athleteUid),
      ProfileScreen(athleteUid: widget.athleteUid),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded, size: 20),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded, size: 20),
              label: 'Trends',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology_outlined, size: 20),
              label: 'Ask AI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline, size: 20),
              label: 'Coach',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline, size: 20),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
