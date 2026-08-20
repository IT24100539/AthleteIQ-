import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'connect_device_screen.dart';

class _PickedSport {
  final String name;
  final SportGroup group;
  final bool isCustom;

  const _PickedSport({
    required this.name,
    required this.group,
    this.isCustom = false,
  });
}

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
  final List<_PickedSport> _selected = [];
  String? _classificationConfidence;
  String? _classificationSource;

  static const _groupLabels = {
    SportGroup.endurance: 'Endurance',
    SportGroup.teamContact: 'Team / Contact',
    SportGroup.strengthPower: 'Strength / Power',
    SportGroup.skillPrecision: 'Skill / Precision',
    SportGroup.combat: 'Combat',
    SportGroup.other: 'Other',
  };

  bool _isSelected(String name) => _selected.any((s) => s.name == name);

  void _toggleListed(SportOption sport) {
    setState(() {
      final index = _selected.indexWhere((s) => s.name == sport.name);
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(_PickedSport(name: sport.name, group: sport.group));
      }
    });
  }

  Future<void> _saveAndContinue() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one sport.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _fs.setSports(
        widget.athleteUid,
        _selected.map((s) => s.name).toList(),
        _selected.map((s) => s.group).toList(),
        classificationConfidence: _classificationConfidence,
        classificationSource: _classificationSource,
      );
      if (mounted) _goToDeviceSetup();
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

  void _goToDeviceSetup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConnectDeviceScreen(athleteUid: widget.athleteUid),
      ),
    );
  }

  Future<void> _showOtherSportDialog() async {
    final controller = TextEditingController();
    final sportText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('What sport do you play?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Pickleball, Cheerleading, Esports…',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.of(ctx).pop(text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (sportText == null || sportText.isEmpty || !mounted) return;

    if (_isSelected(sportText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$sportText is already selected.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _fs.classifyCustomSport(widget.athleteUid, sportText);
      if (!mounted) return;

      final group = parseSportGroup(result['sportGroup']);
      final groupLabel = result['groupLabel'] as String? ?? 'Other';
      final confidence = result['confidence'] as String? ?? 'low';
      final message = confidence == 'high'
          ? 'Added and mapped to $groupLabel recommendations.'
          : 'Added with generic recommendations — we could not confidently map this sport.';

      setState(() {
        _selected.add(_PickedSport(
          name: (result['sport'] as String?)?.trim().isNotEmpty == true
              ? (result['sport'] as String).trim()
              : sportText,
          group: group,
          isCustom: true,
        ));
        _classificationConfidence = confidence;
        _classificationSource = result['source'] as String? ?? 'client_fallback';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search sports…',
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textFaint),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select one or more. The first you pick is your primary sport.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _selected.length; i++)
                      InputChip(
                        label: Text(
                          i == 0
                              ? '${_selected[i].name} · primary'
                              : _selected[i].name,
                        ),
                        onDeleted: _saving
                            ? null
                            : () => setState(() => _selected.removeAt(i)),
                      ),
                  ],
                ),
              ),
            ),
          if (_saving)
            const LinearProgressIndicator(minHeight: 2, color: AppColors.mint),
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
                          (s) {
                            final selected = _isSelected(s.name);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                title: Text(s.name),
                                trailing: Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: selected
                                      ? AppColors.mint
                                      : AppColors.textFaint,
                                ),
                                onTap: _saving ? null : () => _toggleListed(s),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                Card(
                  child: ListTile(
                    title: const Text('Other (not listed)'),
                    subtitle: const Text(
                      'Type another sport — we\'ll map it and add it to your list',
                    ),
                    trailing: Icon(Icons.add, color: AppColors.textFaint),
                    onTap: _saving ? null : _showOtherSportDialog,
                  ),
                ),
                const SizedBox(height: 88),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving || _selected.isEmpty ? null : _saveAndContinue,
              child: Text(
                _selected.isEmpty
                    ? 'Select at least one sport'
                    : _selected.length == 1
                        ? 'Continue'
                        : 'Continue with ${_selected.length} sports',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
