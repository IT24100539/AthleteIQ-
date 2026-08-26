import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/athlete.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/theme_mode_tile.dart';
import '../widgets/delete_account_tile.dart';
import '../widgets/privacy_policy_tile.dart';
import 'connect_coach_screen.dart';
import 'connect_device_screen.dart';
import 'data_sharing_screen.dart';
import 'import_training_log_screen.dart';
import 'report_pain_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? athleteUid;
  const ProfileScreen({super.key, this.athleteUid});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _fs = FirestoreService();
  bool _notifications = true;

  void _openDeviceSettings() {
    final uid = widget.athleteUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectDeviceScreen(
          athleteUid: uid,
          isFromSettings: true,
        ),
      ),
    );
  }

  void _openDataSharing() {
    final uid = widget.athleteUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataSharingScreen(athleteUid: uid),
      ),
    );
  }

  void _openImportLog() {
    final uid = widget.athleteUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportTrainingLogScreen(athleteUid: uid),
      ),
    );
  }

  void _openReportPain() {
    final uid = widget.athleteUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportPainScreen(athleteUid: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.athleteUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & settings'),
        centerTitle: true,
      ),
      body: StreamBuilder<AthleteProfile>(
        stream: _fs.athleteProfile(uid),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load your profile',
          );
          if (blocked != null) return blocked;

          final profile = snapshot.data;
          final name = (profile?.name ?? '').trim();
          final sport = (profile?.sportsLabel ?? '').trim();
          final hasName = name.isNotEmpty;
          final initials = hasName
              ? name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
              : '?';
          final sportLine = sport.isNotEmpty ? 'Athlete · $sport' : 'Athlete · sport not set';

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              if (!hasName)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: EmptyState(
                    icon: Icons.person_outline,
                    heading: 'Complete your profile',
                    subtext:
                        'Your name is not on this account yet. We will not invent one. Finish sign-up or re-open the app after your athlete profile is created.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.mint.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.mint, width: 1.5),
                        ),
                        child: Text(
                          initials.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.mint,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sportLine,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _CoachConnectionCard(
                  athleteUid: uid,
                  coachUid: profile?.coachUid,
                ),
              ),
              const Divider(height: 24),

              // Settings Rows
              ListTile(
                leading: const Icon(Icons.healing_outlined, color: AppColors.coral, size: 20),
                title: const Text('Report pain'),
                subtitle: const Text(
                  'Flag an injury for coach triage',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
                onTap: _openReportPain,
              ),
              ListTile(
                leading: Icon(Icons.watch_outlined, color: AppColors.textSecondary, size: 20),
                title: const Text('Connected devices'),
                trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
                onTap: _openDeviceSettings,
              ),
              ListTile(
                leading: Icon(Icons.upload_file_outlined, color: AppColors.textSecondary, size: 20),
                title: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Import training log',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'BETA',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Text(
                  'CSV from TrainingPeaks etc.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
                onTap: _openImportLog,
              ),
              SwitchListTile(
                secondary: Icon(Icons.notifications_none, color: AppColors.textSecondary, size: 20),
                title: const Text('Notifications'),
                value: _notifications,
                activeTrackColor: AppColors.mint,
                activeThumbColor: AppColors.mintDark,
                onChanged: (v) => setState(() => _notifications = v),
              ),
              ListTile(
                leading: Icon(Icons.lock_outline, color: AppColors.textSecondary, size: 20),
                title: const Text('Data privacy & sharing'),
                trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
                onTap: _openDataSharing,
              ),
              const PrivacyPolicyTile(),
              const ThemeModeTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.coral, size: 20),
                title: const Text('Log out', style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600)),
                onTap: () => AuthService().signOut(),
              ),
              const DeleteAccountTile(),
            ],
          );
        },
      ),
    );
  }
}

class _CoachConnectionCard extends StatefulWidget {
  final String athleteUid;
  final String? coachUid;

  const _CoachConnectionCard({
    required this.athleteUid,
    required this.coachUid,
  });

  @override
  State<_CoachConnectionCard> createState() => _CoachConnectionCardState();
}

class _CoachConnectionCardState extends State<_CoachConnectionCard> {
  final _fs = FirestoreService();
  bool _disconnecting = false;

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from coach?'),
        content: const Text(
          'Your coach will no longer see you on their roster or receive your training updates. You can reconnect later with their invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _disconnecting = true);
    try {
      await _fs.unlinkAthleteFromCoach(widget.athleteUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from your coach.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.coachUid != null && widget.coachUid!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR COACH',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        if (!linked)
          ConnectCoachForm(athleteUid: widget.athleteUid)
        else
          StreamBuilder<Map<String, String?>>(
            stream: _fs.streamCoachDisplay(widget.coachUid!),
            builder: (context, snap) {
              final coachName = (snap.data?['name'] ?? '').trim();
              final email = (snap.data?['email'] ?? '').trim();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.mint.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.mint),
                          ),
                          child: const Icon(Icons.check, color: AppColors.mint, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                coachName.isEmpty ? 'Coach connected' : coachName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email.isEmpty
                                    ? 'You\'re on this coach\'s roster'
                                    : email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _disconnecting ? null : _disconnect,
                        icon: _disconnecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.link_off, size: 18),
                        label: Text(_disconnecting ? 'Disconnecting…' : 'Disconnect from coach'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
