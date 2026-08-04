import 'package:flutter/material.dart';
import '../models/checkin.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class CheckInScreen extends StatefulWidget {
  final String athleteUid;
  const CheckInScreen({super.key, required this.athleteUid});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _fs = FirestoreService();

  bool _trainedToday = true;
  double _duration = 45; // minutes
  double _rpe = 5; // 1-10
  double _fatigue = 3; // 1-5
  double _sleep = 7; // hours
  final _notes = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    final checkIn = CheckIn(
      id: '',
      date: DateTime.now(),
      sessionDurationMinutes: _trainedToday ? _duration.round() : null,
      rpe: _trainedToday ? _rpe.round() : null,
      fatigueScore: _fatigue.round(),
      sleepHours: _sleep,
      soreness: _notes.text.isEmpty ? null : _notes.text,
      source: 'manual',
    );
    await _fs.submitCheckIn(widget.athleteUid, checkIn);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily check-in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
              // Section 15.3 — wording changes per sport in the real app
              // by reading the athlete's sportGroup; kept generic here.
              label: 'How hard did that session feel? (RPE)',
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
