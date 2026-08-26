import 'dart:async';

import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../services/firestore_service.dart';
import '../constants/checkin_field_help.dart';
import '../theme/app_theme.dart';
import '../utils/athlete_sports.dart';
import '../utils/friendly_error.dart';
import '../utils/stream_fallback.dart';
import '../widgets/info_tooltip.dart';
import '../widgets/manual_resting_hr_field.dart';
import '../widgets/session_sport_picker.dart';
import '../widgets/word_scale_picker.dart';
import '../constants/checkin_scale_labels.dart';

class ManualDailyLogScreen extends StatefulWidget {
  final String athleteUid;

  const ManualDailyLogScreen({super.key, required this.athleteUid});

  @override
  State<ManualDailyLogScreen> createState() => _ManualDailyLogScreenState();
}

class _ManualDailyLogScreenState extends State<ManualDailyLogScreen> {
  final _fs = FirestoreService();
  final _sorenessController = TextEditingController();
  StreamSubscription<AthleteProfile>? _profileSub;
  bool _saving = false;

  bool _trainedToday = true;
  double _durationMinutes = 60;
  int _rpe = 6;
  double _sleepHours = 7.0;
  int _fatigue = 3;
  bool _includeRhr = false;
  double _restingHr = ManualRestingHrField.defaultBpm;
  bool _includeHrv = false;
  double _hrv = ManualHrvField.defaultMs;
  double _steps = 8000;
  String? _deviceTier;
  List<String> _sports = const [];
  List<SportGroup> _sportGroups = const [];
  String? _sessionSport;

  @override
  void initState() {
    super.initState();
    _profileSub = emitOnError(
      _fs.athleteProfile(widget.athleteUid),
      AthleteProfile.fromMap(widget.athleteUid, {}),
    ).listen((profile) {
      if (!mounted) return;
      setState(() {
        _deviceTier = profile.deviceTier;
        _sports = profile.sports;
        _sportGroups = profile.sportGroups;
        _sessionSport ??= profile.sport;
      });
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _sorenessController.dispose();
    super.dispose();
  }

  bool get _isTier3 => _deviceTier == null || _deviceTier == 'tier3';

  Future<void> _saveLog() async {
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final checkIn = CheckIn(
        id: '',
        date: DateTime.now(),
        rpe: _trainedToday ? _rpe : 0,
        sessionDurationMinutes: _trainedToday ? _durationMinutes.round() : 0,
        sleepHours: _sleepHours,
        fatigueScore: _fatigue,
        restingHeartRate:
            _isTier3 && _includeRhr ? _restingHr.roundToDouble() : null,
        hrv: _isTier3 && _includeHrv ? _hrv.roundToDouble() : null,
        steps: _isTier3 ? _steps.round() : null,
        soreness: _sorenessController.text.trim().isEmpty
            ? null
            : _sorenessController.text.trim(),
        source: 'manual',
        sessionSport: _sessionSport,
        sessionSportGroup: groupForSession(
          sports: _sports,
          sportGroups: _sportGroups,
          sessionSport: _sessionSport,
        ).name,
      );

      await _fs.submitCheckIn(widget.athleteUid, checkIn);

      if (_isTier3) {
        await _fs.mergeManualActivityMetrics(
          widget.athleteUid,
          steps: _steps.round(),
        );
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('✓ Today\'s training log saved successfully!'),
          backgroundColor: AppColors.mintDark,
        ),
      );
      nav.pop();
    } on RiskEngineException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Log today'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenEdge,
            AppSpacing.screenEdge,
            AppSpacing.screenEdge,
            AppSpacing.screenEdge + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isTier3) ...[
                const _SectionHeader(
                  title: 'Tier 3 · Manual entry',
                  subtitle:
                      'Without a wearable, enter the recovery and activity data a smartwatch would sync on Tier 1 or 2.',
                ),
                const SizedBox(height: 20),
                const _SubsectionLabel('Recovery & activity'),
                const SizedBox(height: 12),
                _SliderField(
                  label: 'Sleep last night',
                  infoText: CheckinFieldHelp.sleep,
                  value: _sleepHours,
                  min: 4,
                  max: 10,
                  divisions: 12,
                  display: '${_sleepHours.toStringAsFixed(1)} h',
                  onChanged: (v) => setState(() => _sleepHours = v),
                ),
                ManualRestingHrField(
                  include: _includeRhr,
                  bpm: _restingHr,
                  onIncludeChanged: (v) => setState(() => _includeRhr = v),
                  onBpmChanged: (v) => setState(() => _restingHr = v),
                ),
                const SizedBox(height: 16),
                ManualHrvField(
                  include: _includeHrv,
                  ms: _hrv,
                  onIncludeChanged: (v) => setState(() => _includeHrv = v),
                  onMsChanged: (v) => setState(() => _hrv = v),
                ),
                const SizedBox(height: 16),
                _SliderField(
                  label: 'Daily steps',
                  infoText: CheckinFieldHelp.dailySteps,
                  value: _steps,
                  min: 0,
                  max: 25000,
                  divisions: 50,
                  display: '${_steps.round()} steps',
                  onChanged: (v) => setState(() => _steps = v),
                ),
                const SizedBox(height: 24),
                const _SubsectionLabel('Training'),
              ] else
                Text(
                  'Enter today\'s training by hand',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                ),
              const SizedBox(height: 16),

              const _FieldLabel('Did you train today?'),
              const SizedBox(height: 10),
              Row(
                children: [
                  _OptionChip(
                    label: 'Yes',
                    selected: _trainedToday,
                    onTap: () => setState(() => _trainedToday = true),
                  ),
                  const SizedBox(width: 12),
                  _OptionChip(
                    label: 'Rest day',
                    selected: !_trainedToday,
                    onTap: () => setState(() => _trainedToday = false),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_trainedToday && _sports.length > 1) ...[
                SessionSportPicker(
                  sports: _sports,
                  selected: _sessionSport ?? _sports.first,
                  onSelected: (name) => setState(() => _sessionSport = name),
                ),
                const SizedBox(height: 24),
              ],

              if (_trainedToday) ...[
                _SliderField(
                  label: 'Session duration',
                  infoText: CheckinFieldHelp.sessionDuration,
                  value: _durationMinutes,
                  min: 5,
                  max: 240,
                  divisions: 47,
                  display: '${_durationMinutes.round()} min',
                  onChanged: (v) => setState(() => _durationMinutes = v),
                ),
                WordScalePicker(
                  label: rpePromptForGroup(groupForSession(
                    sports: _sports,
                    sportGroups: _sportGroups,
                    sessionSport: _sessionSport,
                  )),
                  infoText: CheckinFieldHelp.rpe,
                  choices: CheckinWordScales.rpe,
                  value: _rpe,
                  onSelected: (v) => setState(() => _rpe = v),
                ),
              ],

              if (!_isTier3) ...[
                _SliderField(
                  label: 'Sleep last night',
                  infoText: CheckinFieldHelp.sleep,
                  value: _sleepHours,
                  min: 4,
                  max: 10,
                  divisions: 12,
                  display: '${_sleepHours.toStringAsFixed(1)} h',
                  onChanged: (v) => setState(() => _sleepHours = v),
                ),
              ],

              const SizedBox(height: 8),
              WordScalePicker(
                label: 'How do you feel today?',
                infoText: CheckinFieldHelp.fatigue,
                choices: CheckinWordScales.fatigue,
                value: _fatigue,
                onSelected: (v) => setState(() => _fatigue = v),
              ),

              TextField(
                controller: _sorenessController,
                scrollPadding: const EdgeInsets.only(bottom: 120),
                decoration: const InputDecoration(
                  labelText: 'Soreness or pain notes (optional)',
                  hintText: 'e.g. tight calves, left knee niggle',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveLog,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mintDark,
                          ),
                        )
                      : const Icon(Icons.check, size: 20),
                  label: Text(_saving ? 'Saving…' : 'Save today\'s log'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SubsectionLabel extends StatelessWidget {
  final String text;
  const _SubsectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final String? infoText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    this.infoText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabelWithInfo(
                  label: label,
                  infoText: infoText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  color: AppColors.mint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.mint,
            inactiveColor: AppColors.border,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: selected ? AppColors.mint : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.mintDark : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
