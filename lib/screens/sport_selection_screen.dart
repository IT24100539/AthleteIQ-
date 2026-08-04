import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class SportSelectionScreen extends StatefulWidget {
  final String athleteUid;
  const SportSelectionScreen({super.key, required this.athleteUid});

  @override
  State<SportSelectionScreen> createState() => _SportSelectionScreenState();
}

class _SportSelectionScreenState extends State<SportSelectionScreen> {
  final _fs = FirestoreService();
  String _query = '';
  bool _saving = false;

  static const _groupLabels = {
    SportGroup.endurance: 'Endurance',
    SportGroup.teamContact: 'Team / Contact',
    SportGroup.strengthPower: 'Strength / Power',
    SportGroup.skillPrecision: 'Skill / Precision',
    SportGroup.combat: 'Combat',
    SportGroup.other: 'Other',
  };

  Future<void> _select(SportOption sport) async {
    setState(() => _saving = true);
    await _fs.setSport(widget.athleteUid, sport);
    if (mounted) Navigator.of(context).pushReplacementNamed('/athlete-home');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = kSportOptions
        .where((s) => s.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final grouped = <SportGroup, List<SportOption>>{};
    for (final s in filtered) {
      grouped.putIfAbsent(s.group, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('What do you play?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search sports…',
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textFaint),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final group in grouped.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _groupLabels[group]!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...grouped[group]!.map(
                          (s) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              title: Text(s.name),
                              trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
                              onTap: _saving ? null : () => _select(s),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Section 12.2 — free-text "Other" so no athlete is blocked.
                Card(
                  child: ListTile(
                    title: const Text('Other (not listed)'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
                    onTap: _saving
                        ? null
                        : () => _select(const SportOption('Other', SportGroup.other)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
