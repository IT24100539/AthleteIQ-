import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/team_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/async_body.dart';
import '../widgets/delete_account_tile.dart';
import '../widgets/privacy_policy_tile.dart';
import '../widgets/theme_mode_tile.dart';
import 'connect_coach_screen.dart';

/// Coach profile & settings — separate from the athlete [ProfileScreen].
class CoachSettingsScreen extends StatefulWidget {
  final String coachUid;

  const CoachSettingsScreen({super.key, required this.coachUid});

  @override
  State<CoachSettingsScreen> createState() => _CoachSettingsScreenState();
}

class _CoachSettingsScreenState extends State<CoachSettingsScreen> {
  final _fs = FirestoreService();
  final _teamNameController = TextEditingController();
  double _sliderValue = TeamSettings.defaultPercent.toDouble();
  bool _initialized = false;
  bool _saving = false;
  String? _inviteCode;
  Timer? _teamNameDebounce;
  TeamSettings? _latestSettings;

  @override
  void initState() {
    super.initState();
    _loadInviteCode();
  }

  @override
  void dispose() {
    _teamNameDebounce?.cancel();
    _teamNameController.dispose();
    super.dispose();
  }

  Future<void> _loadInviteCode() async {
    final code = await _fs.getCoachInviteCode(widget.coachUid);
    if (mounted) setState(() => _inviteCode = code);
  }

  void _copyInviteCode() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  void _syncFromSettings(TeamSettings settings) {
    _latestSettings = settings;
    if (!_initialized) {
      _sliderValue = settings.defaultActionPercent.toDouble();
      _teamNameController.text = settings.teamName;
      _initialized = true;
    }
  }

  Future<void> _persist(TeamSettings settings) async {
    setState(() => _saving = true);
    try {
      await _fs.updateTeamSettings(widget.coachUid, settings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveActionPercent(int percent) async {
    final base = _latestSettings ??
        const TeamSettings(defaultActionPercent: TeamSettings.defaultPercent);
    await _persist(base.copyWith(defaultActionPercent: percent));
  }

  void _onTeamNameChanged(String value) {
    _teamNameDebounce?.cancel();
    _teamNameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final base = _latestSettings ??
          const TeamSettings(defaultActionPercent: TeamSettings.defaultPercent);
      await _persist(base.copyWith(teamName: value.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & settings'),
        centerTitle: true,
      ),
      body: StreamBuilder<TeamSettings>(
        stream: _fs.streamTeamSettings(widget.coachUid),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load settings',
          );
          if (blocked != null) return blocked;

          final settings = snapshot.data ??
              const TeamSettings(defaultActionPercent: TeamSettings.defaultPercent);
          if (snapshot.hasData) {
            _syncFromSettings(settings);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoachProfileHeader(
                    coachUid: widget.coachUid,
                    teamName: settings.teamName,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'TEAM',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _teamNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Team name',
                      hintText: 'e.g. Metro Track Club',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _onTeamNameChanged,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'NOTIFICATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saved to Firestore on this coach account. Push delivery still needs an FCM token at sign-in.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(Icons.notifications_none, color: AppColors.textSecondary, size: 20),
                    title: const Text('Push notifications'),
                    value: settings.notificationsEnabled,
                    activeTrackColor: AppColors.mint,
                    activeThumbColor: AppColors.mintDark,
                    onChanged: _saving
                        ? null
                        : (v) => _persist(settings.copyWith(notificationsEnabled: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(Icons.warning_amber_rounded, color: AppColors.textSecondary, size: 20),
                    title: const Text('Risk spikes'),
                    subtitle: const Text('When an athlete\'s risk level rises', style: TextStyle(fontSize: 12)),
                    value: settings.notifyRiskSpikes && settings.notificationsEnabled,
                    activeTrackColor: AppColors.mint,
                    activeThumbColor: AppColors.mintDark,
                    onChanged: !settings.notificationsEnabled || _saving
                        ? null
                        : (v) => _persist(settings.copyWith(notifyRiskSpikes: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(Icons.event_busy_outlined, color: AppColors.textSecondary, size: 20),
                    title: const Text('Missed check-ins'),
                    subtitle: const Text('No check-in for 2+ days', style: TextStyle(fontSize: 12)),
                    value: settings.notifyMissedCheckIns && settings.notificationsEnabled,
                    activeTrackColor: AppColors.mint,
                    activeThumbColor: AppColors.mintDark,
                    onChanged: !settings.notificationsEnabled || _saving
                        ? null
                        : (v) => _persist(settings.copyWith(notifyMissedCheckIns: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(Icons.healing_outlined, color: AppColors.textSecondary, size: 20),
                    title: const Text('HIGH pain reports'),
                    value: settings.notifyHighPain && settings.notificationsEnabled,
                    activeTrackColor: AppColors.mint,
                    activeThumbColor: AppColors.mintDark,
                    onChanged: !settings.notificationsEnabled || _saving
                        ? null
                        : (v) => _persist(settings.copyWith(notifyHighPain: v)),
                  ),
                  const SizedBox(height: 24),
                  CoachInviteCard(
                    inviteCode: _inviteCode,
                    onCopy: _copyInviteCode,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'APPEARANCE',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const ThemeModeTile(),
                  const SizedBox(height: 24),
                  Text(
                    'TEAM DEFAULTS',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Default action percentage',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When AthleteIQ recommends reducing training load (HIGH risk, generic sport group), '
                    'this is the default volume cut written into the action text. '
                    'Range 10–30%; default 20%.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Container(
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
                        Text(
                          '${_sliderValue.round()}%',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.mint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Load reduction in recommendation wording',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        Slider(
                          value: _sliderValue,
                          min: TeamSettings.minPercent.toDouble(),
                          max: TeamSettings.maxPercent.toDouble(),
                          divisions: TeamSettings.maxPercent - TeamSettings.minPercent,
                          label: '${_sliderValue.round()}%',
                          activeColor: AppColors.mint,
                          onChanged: _saving ? null : (v) => setState(() => _sliderValue = v),
                          onChangeEnd: _saving ? null : (v) => _saveActionPercent(v.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('10%', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            Text('30%', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'LEGAL',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const PrivacyPolicyTile(contentPadding: EdgeInsets.zero),
                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout, color: AppColors.coral, size: 20),
                    title: const Text(
                      'Log out',
                      style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => AuthService().signOut(),
                  ),
                  const DeleteAccountTile(isCoach: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CoachProfileHeader extends StatelessWidget {
  final String coachUid;
  final String teamName;

  const _CoachProfileHeader({
    required this.coachUid,
    required this.teamName,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return FutureBuilder<Map<String, String?>>(
      future: FirestoreService().getUserDisplayName(coachUid),
      builder: (context, snapshot) {
        final name = snapshot.hasError
            ? (user?.displayName ?? 'Coach')
            : (snapshot.data?['name'] ?? 'Coach');
        final email = snapshot.data?['email'] ?? user?.email ?? '';
        final displayTeam = teamName.isNotEmpty ? teamName : 'Your team';

        return Row(
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
                _initials(name),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayTeam,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 4),
                    Text(
                      friendlyError(snapshot.error),
                      style: const TextStyle(fontSize: 11, color: AppColors.coral),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Coach account',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
