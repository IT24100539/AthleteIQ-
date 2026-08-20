import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/checkin.dart';
import '../services/firestore_service.dart';
import '../services/training_log_import_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';

/// Beta CSV import for training logs exported from external apps
/// (e.g. TrainingPeaks). Rows are stored as normal daily check-ins.
class ImportTrainingLogScreen extends StatefulWidget {
  final String athleteUid;

  const ImportTrainingLogScreen({super.key, required this.athleteUid});

  @override
  State<ImportTrainingLogScreen> createState() => _ImportTrainingLogScreenState();
}

class _ImportTrainingLogScreenState extends State<ImportTrainingLogScreen> {
  final _fs = FirestoreService();

  String? _fileName;
  TrainingLogImportResult? _preview;
  bool _parsing = false;
  bool _importing = false;

  Future<void> _pickFile() async {
    setState(() {
      _parsing = true;
      _preview = null;
      _fileName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _showError('Could not read file contents.');
        return;
      }

      final text = String.fromCharCodes(bytes);
      final parsed = TrainingLogImportService.parseCsv(text);

      setState(() {
        _fileName = file.name;
        _preview = parsed;
      });
    } catch (e) {
      _showError('Could not open file: $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    if (preview == null || !preview.ok) return;

    setState(() => _importing = true);
    try {
      final count = await _fs.importCheckIns(widget.athleteUid, preview.checkIns);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $count day${count == 1 ? '' : 's'} from CSV '
            '(beta import — same check-in pipeline as manual logs).',
          ),
          backgroundColor: AppColors.mintDark,
        ),
      );
    } on RiskEngineException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final dateFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Import training log'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'BETA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.amber,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Upload a CSV export from TrainingPeaks or another app. '
              'We map rows into the same daily check-in records as manual logs — '
              'no separate import pipeline. Live API sync (Garmin, Whoop) still '
              'needs vendor approval; this is a lower-priority fallback.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'SUPPORTED COLUMNS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Date: date, WorkoutDay · Duration: duration_minutes, TimeTotalInHours · '
            'Optional: rpe, fatigue_score, sleep_hours',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _parsing ? null : _pickFile,
            icon: _parsing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(_parsing ? 'Reading file…' : 'Choose CSV file'),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Text(
              'Selected: $_fileName',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 20),
            Text(
              'Detected: ${preview.detectedFormat}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.mint,
              ),
            ),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...preview.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: AppColors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.amber,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (preview.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...preview.errors.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: AppColors.coral),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.coral,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (preview.hasCheckIns) ...[
              const SizedBox(height: 16),
              Text(
                'PREVIEW · ${preview.checkIns.length} DAYS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < preview.checkIns.length && i < 8; i++)
                      _PreviewRow(
                        checkIn: preview.checkIns[i],
                        dateLabel: dateFmt.format(preview.checkIns[i].date),
                        showDivider: i < preview.checkIns.length - 1 && i < 7,
                      ),
                    if (preview.checkIns.length > 8)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '+ ${preview.checkIns.length - 8} more days',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Imported rows are tagged source=import in check-ins.',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: preview != null && preview.ok && !_importing
                  ? _confirmImport
                  : null,
              child: _importing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mintDark,
                      ),
                    )
                  : const Text('Import into check-ins'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final CheckIn checkIn;
  final String dateLabel;
  final bool showDivider;

  const _PreviewRow({
    required this.checkIn,
    required this.dateLabel,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final mins = checkIn.sessionDurationMinutes ?? 0;
    final rpe = checkIn.rpe ?? 0;
    final load = checkIn.trainingLoad;
    final summary = mins <= 0 && rpe <= 0
        ? 'Rest day'
        : '$mins min · RPE $rpe'
            '${load != null ? ' · load ${load.round()}' : ''}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                summary,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'import',
                  style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}
