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

class CheckInScreen extends StatefulWidget {
  final String athleteUid;
  const CheckInScreen({super.key, required this.athleteUid});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _fs = FirestoreService();
  StreamSubscription<AthleteProfile>? _profileSub;

  bool _trainedToday = true;
  double _duration = 45; // minutes
  int _rpe = 6;
  int _fatigue = 3;
  double _sleep = 7; // hours
  final _notes = TextEditingController();
  bool _saving = false;
  bool _includeRhr = false;
  double _restingHr = ManualRestingHrField.defaultBpm;
  bool _includeHrv = false;
  double _hrv = ManualHrvField.defaultMs;
  String? _deviceTier;
  List<String> _sports = const [];
  List<SportGroup> _sportGroups = const [];
  String? _sessionSport;

  bool get _showManualRhr {
    final tier = _deviceTier;
    if (tier == null) return false;
    return AthleteProfile(
      uid: widget.athleteUid,
      name: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      deviceTier: tier,
    ).allowsManualRestingHr;
  }

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
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final checkIn = CheckIn(
        id: '',
        date: DateTime.now(),
        sessionDurationMinutes: _trainedToday ? _duration.round() : 0,
        rpe: _trainedToday ? _rpe : 0,
        fatigueScore: _fatigue,
        sleepHours: _sleep,
        restingHeartRate:
            _showManualRhr && _includeRhr ? _restingHr.roundToDouble() : null,
        hrv: _showManualRhr && _includeHrv ? _hrv.roundToDouble() : null,
        soreness: _notes.text.isEmpty ? null : _notes.text,
        source: 'manual',
        sessionSport: _sessionSport,
        sessionSportGroup: groupForSession(
          sports: _sports,
          sportGroups: _sportGroups,
          sessionSport: _sessionSport,
        ).name,
      );
      await _fs.submitCheckIn(widget.athleteUid, checkIn);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in saved')),
        );
      }
    } on RiskEngineException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Daily check-in')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenEdge,
          AppSpacing.screenEdge,
          AppSpacing.screenEdge,
          AppSpacing.screenEdge + 24,
        ),
        children: [
          Text('Did you train today?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Yes, I trained'),
                  ),
                  selected: _trainedToday,
                  onSelected: (v) => setState(() => _trainedToday = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Rest day'),
                  selected: !_trainedToday,
                  onSelected: (v) => setState(() => _trainedToday = false),
                ),
              ),
            ],
          ),
          if (_trainedToday && _sports.length > 1) ...[
            const SizedBox(height: 20),
            SessionSportPicker(
              sports: _sports,
              selected: _sessionSport ?? _sports.first,
              onSelected: (name) => setState(() => _sessionSport = name),
            ),
          ],
          if (_trainedToday) ...[
            const SizedBox(height: 20),
            _SliderField(
              label: 'Session duration',
              infoText: CheckinFieldHelp.sessionDuration,
              value: _duration,
              min: 5,
              max: 240,
              divisions: 47,
              display: '${_duration.round()} min',
              onChanged: (v) => setState(() => _duration = v),
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
          const SizedBox(height: 8),
          WordScalePicker(
            label: 'How do you feel today?',
            infoText: CheckinFieldHelp.fatigue,
            choices: CheckinWordScales.fatigue,
            value: _fatigue,
            onSelected: (v) => setState(() => _fatigue = v),
          ),
          _SliderField(
            label: 'Sleep last night',
            infoText: CheckinFieldHelp.sleep,
            value: _sleep,
            min: 0,
            max: 12,
            divisions: 24,
            display: '${_sleep.toStringAsFixed(1)} hrs',
            onChanged: (v) => setState(() => _sleep = v),
          ),
          if (_showManualRhr) ...[
            const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            decoration: const InputDecoration(hintText: 'Any soreness or pain? (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Saving…' : 'Submit check-in'),
          ),
        ],
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.mint,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
