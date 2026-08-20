import 'package:flutter/material.dart';
import '../models/pain_report.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/empty_state.dart';

class ReportPainScreen extends StatefulWidget {
  final String athleteUid;

  const ReportPainScreen({super.key, required this.athleteUid});

  @override
  State<ReportPainScreen> createState() => _ReportPainScreenState();
}

class _ReportPainScreenState extends State<ReportPainScreen> {
  final _fs = FirestoreService();
  final _notesController = TextEditingController();
  bool _saving = false;

  // Intentionally empty — do not seed demo rows (Left knee / Right ankle).
  final List<PainArea> _areas = [];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _addAreaDialog() {
    final locationController = TextEditingController();
    int selectedSeverity = 2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Add Pain Area', style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: locationController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Lower back, Shoulder, Hamstring',
                ),
              ),
              const SizedBox(height: 16),
              Text('Severity (1 to 5)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final lvl = i + 1;
                  final active = lvl <= selectedSeverity;
                  return SizedBox(
                    width: 48,
                    height: 48,
                    child: InkWell(
                    onTap: () => setDialogState(() => selectedSeverity = lvl),
                    customBorder: const CircleBorder(),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? AppColors.coral : AppColors.surfaceAlt,
                        border: Border.all(color: active ? AppColors.coral : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$lvl',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? AppColors.mintDark : AppColors.textMuted,
                        ),
                      ),
                    ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final loc = locationController.text.trim();
                if (loc.isNotEmpty) {
                  setState(() {
                    _areas.add(PainArea(location: loc, severity: selectedSeverity));
                  });
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Add Area'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_areas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one body area before submitting.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final report = PainReport(
        id: '',
        athleteUid: widget.athleteUid,
        date: DateTime.now(),
        areas: _areas,
        note: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      final result = await _fs.submitPainReport(widget.athleteUid, report);
      final urgency = (result['urgency'] as String?) ?? 'MEDIUM';

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Pain report sent. Coach triage flag: $urgency — this is not a diagnosis.',
          ),
          backgroundColor: AppColors.mintDark,
        ),
      );
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
      appBar: AppBar(
        title: const Text('Report pain'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Flag anything that hurts — separate from general fatigue',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 24),

              if (_areas.isEmpty) ...[
                const EmptyState(
                  icon: Icons.healing_outlined,
                  heading: 'No body areas added',
                  subtext:
                      'This form starts empty. Add where it hurts — we do not pre-fill example injuries.',
                ),
                const SizedBox(height: 20),
              ],

              for (int index = 0; index < _areas.length; index++) ...[
                _PainRow(
                  area: _areas[index],
                  onSeverityChanged: (newSev) {
                    setState(() {
                      _areas[index] = PainArea(
                        location: _areas[index].location,
                        severity: newSev,
                      );
                    });
                  },
                  onRemove: () {
                    setState(() => _areas.removeAt(index));
                  },
                ),
                const SizedBox(height: 12),
              ],

              Material(
                color: Colors.transparent,
                child: InkWell(
                onTap: _addAreaDialog,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
                  child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, color: AppColors.mint, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        _areas.isEmpty ? 'Add a body area' : 'Add another area',
                        style: const TextStyle(
                          color: AppColors.mint,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What happened, when it started, what makes it worse…',
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'AthleteIQ flags urgency as a triage aid for your coach — '
                  'LOW, MEDIUM, or HIGH. This is not a medical diagnosis. '
                  'Significant, worsening, or unexplained pain should be checked '
                  'by a medical professional.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submitReport,
                  child: Text(_saving ? 'Sending…' : 'Submit pain report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PainRow extends StatelessWidget {
  final PainArea area;
  final ValueChanged<int> onSeverityChanged;
  final VoidCallback onRemove;

  const _PainRow({
    required this.area,
    required this.onSeverityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: AppColors.coral, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              area.location,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Row(
            children: List.generate(5, (i) {
              final lvl = i + 1;
              final active = lvl <= area.severity;
              return SizedBox(
                width: 40,
                height: 48,
                child: InkWell(
                onTap: () => onSeverityChanged(lvl),
                customBorder: const CircleBorder(),
                child: Center(
                  child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.coral : AppColors.border,
                  ),
                ),
                ),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textFaint, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
