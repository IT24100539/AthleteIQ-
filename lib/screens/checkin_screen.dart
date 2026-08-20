import 'dart:async';

import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/athlete_sports.dart';
import '../utils/friendly_error.dart';
import '../utils/stream_fallback.dart';
import '../widgets/manual_resting_hr_field.dart';
import '../widgets/session_sport_picker.dart';

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
  double _rpe = 5; // 1-10
  double _fatigue = 3; // 1-5
  double _sleep = 7; // hours
  final _notes = TextEditingController();
  bool _saving = false;
  bool _includeRhr = false;
  double _restingHr = ManualRestingHrField.defaultBpm;
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
        rpe: _trainedToday ? _rpe.round() : 0,
        fatigueScore: _fatigue.round(),
        sleepHours: _sleep,
        restingHeartRate:
            _showManualRhr && _includeRhr ? _restingHr.roundToDouble() : null,
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
      appBar: AppBar(title: const Text('Daily check-in')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        children: [
          Text('Did you train today?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Yes, I trained'),
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
              value: _duration,
              min: 5,
              max: 240,
              divisions: 47,
              display: '${_duration.round()} min',
              onChanged: (v) => setState(() => _duration = v),
            ),
            _SliderField(
              label: rpePromptForGroup(groupForSession(
                sports: _sports,
                sportGroups: _sportGroups,
                sessionSport: _sessionSport,
              )),
              value: _rpe,
              min: 1,
              max: 10,
              divisions: 9,
              display: _rpe.round().toString(),
              onChanged: (v) => setState(() => _rpe = v),
            ),
          ],
          const SizedBox(height: 8),
          _SliderField(
            label: 'How do you feel today?',
            value: _fatigue,
            min: 1,
            max: 5,
            divisions: 4,
            display: _fatigue.round().toString(),
            onChanged: (v) => setState(() => _fatigue = v),
          ),
          _SliderField(
            label: 'Sleep last night',
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
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
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
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
              Text(display,
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
