import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firestore_service.dart';
import '../services/local_prefs.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/app_buttons.dart';
import '../widgets/hero_card.dart';
import 'athlete_main_layout.dart';

/// After sport/device onboarding, send unlinked athletes to connect-coach.
Future<void> continueAfterDeviceSetup(
  BuildContext context,
  String athleteUid,
) async {
  final profile = await FirestoreService().getAthleteProfileOnce(athleteUid);
  final skipped = await LocalPrefs.coachConnectSkipped(athleteUid);
  final linked = profile.coachUid != null && profile.coachUid!.isNotEmpty;
  if (!context.mounted) return;
  final Widget next = (!linked && !skipped)
      ? ConnectCoachScreen(athleteUid: athleteUid, isOnboarding: true)
      : AthleteMainLayout(athleteUid: athleteUid);
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => next),
  );
}

/// Athlete enters a coach invite code to join a roster.
class ConnectCoachScreen extends StatelessWidget {
  final String athleteUid;
  final bool isOnboarding;
  final VoidCallback? onLinked;

  const ConnectCoachScreen({
    super.key,
    required this.athleteUid,
    this.isOnboarding = false,
    this.onLinked,
  });

  void _finish(BuildContext context) {
    if (onLinked != null) {
      onLinked!();
      return;
    }
    if (isOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AthleteMainLayout(athleteUid: athleteUid),
        ),
      );
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _skip(BuildContext context) async {
    await LocalPrefs.setCoachConnectSkipped(athleteUid);
    if (!context.mounted) return;
    _finish(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !isOnboarding,
        title: const Text(
          'CONNECT COACH',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          if (isOnboarding)
            TextButton(
              onPressed: () => _skip(context),
              child: Text(
                'Skip',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const IconBadge(icon: Icons.groups_outlined, size: 64, circle: true),
            const SizedBox(height: 20),
            Text(
              'Link up with your coach',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Your coach has a 6-character invite code. Enter it here to join their roster so they can review your training and approve recommendations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            ConnectCoachForm(
              athleteUid: athleteUid,
              onLinked: () => _finish(context),
            ),
            if (isOnboarding) ...[
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'I\'ll do this later',
                onPressed: () => _skip(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Invite-code field + Link button. Used on onboarding, the Coach tab,
/// and Profile when the athlete is not linked yet.
class ConnectCoachForm extends StatefulWidget {
  final String athleteUid;
  final VoidCallback? onLinked;

  const ConnectCoachForm({
    super.key,
    required this.athleteUid,
    this.onLinked,
  });

  @override
  State<ConnectCoachForm> createState() => _ConnectCoachFormState();
}

class _ConnectCoachFormState extends State<ConnectCoachForm> {
  final _fs = FirestoreService();
  final _codeController = TextEditingController();
  bool _linking = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the invite code from your coach.')),
      );
      return;
    }
    setState(() => _linking = true);
    try {
      await _fs.linkAthleteToCoach(widget.athleteUid, code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You\'re connected to your coach.')),
      );
      _codeController.clear();
      widget.onLinked?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(8),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _linking ? null : _link(),
          decoration: const InputDecoration(
            labelText: 'Coach invite code',
            hintText: 'e.g. K7M2PQ',
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: _linking ? 'Connecting…' : 'Connect to coach',
          icon: Icons.link,
          isLoading: _linking,
          onPressed: _linking ? null : _link,
        ),
      ],
    );
  }
}

/// How a coach shares their code — used on the roster.
class CoachInviteCard extends StatelessWidget {
  final String? inviteCode;
  final VoidCallback? onCopy;

  const CoachInviteCard({
    super.key,
    required this.inviteCode,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    if (inviteCode == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
        ),
      );
    }

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
          Text(
            'CONNECT ATHLETES',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share this code. Athletes enter it to join your roster.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                inviteCode!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mint,
                  letterSpacing: 2,
                ),
              ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
                tooltip: 'Copy code',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
