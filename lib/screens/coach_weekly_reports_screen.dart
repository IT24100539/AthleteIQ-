import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/athlete.dart';
import '../models/privacy_settings.dart';
import '../models/weekly_report.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/privacy_redaction.dart';
import '../utils/friendly_error.dart';
import '../utils/weekly_report_text.dart';
import '../widgets/async_body.dart';
import '../widgets/risk_chip.dart';
import 'weekly_report_screen.dart';

/// Coach hub — one summary card per athlete for the current week,
/// with share and full-report drill-down.
class CoachWeeklyReportsScreen extends StatefulWidget {
  final String coachUid;

  const CoachWeeklyReportsScreen({super.key, required this.coachUid});

  @override
  State<CoachWeeklyReportsScreen> createState() => _CoachWeeklyReportsScreenState();
}

class _CoachWeeklyReportsScreenState extends State<CoachWeeklyReportsScreen> {
  final _fs = FirestoreService();
  final Map<String, _AthleteReportState> _byUid = {};
  List<AthleteProfile> _athletes = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly reports'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh all',
            onPressed: _athletes.isEmpty ? null : () => _loadAll(_athletes, force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<List<AthleteProfile>>(
        stream: _fs.rosterForCoach(widget.coachUid),
        builder: (context, snap) {
          final blocked = asyncBody(
            snap,
            heading: 'Could not load weekly reports',
          );
          if (blocked != null) return blocked;

          final athletes = snap.data ?? [];
          if (athletes.isNotEmpty && !_sameAthleteSet(athletes, _athletes)) {
            _athletes = athletes;
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll(athletes));
          }

          if (athletes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No athletes on your roster yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: athletes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final athlete = athletes[i];
              final state = _byUid[athlete.uid] ?? const _AthleteReportState();
              return _AthleteReportCard(
                athlete: athlete,
                state: state,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WeeklyReportScreen(
                      athleteUid: athlete.uid,
                      athleteName: athlete.name,
                    ),
                  ),
                ),
                onShare: state.report == null
                    ? null
                    : () => _shareReport(
                          athlete.name,
                          state.report!,
                          athlete.privacySettings,
                        ),
                onPrint: state.report == null
                    ? null
                    : () => _showPrintView(
                          context,
                          athlete.name,
                          state.report!,
                          athlete.privacySettings,
                        ),
                onRetry: () => _loadOne(athlete),
              );
            },
          );
        },
      ),
    );
  }

  bool _sameAthleteSet(List<AthleteProfile> a, List<AthleteProfile> b) {
    if (a.length != b.length) return false;
    final ids = a.map((x) => x.uid).toSet();
    return b.every((x) => ids.contains(x.uid));
  }

  Future<void> _loadAll(List<AthleteProfile> athletes, {bool force = false}) async {
    await Future.wait(athletes.map((a) => _loadOne(a, force: force)));
  }

  Future<void> _loadOne(AthleteProfile athlete, {bool force = false}) async {
    final existing = _byUid[athlete.uid];
    if (!force && existing != null && (existing.loading || existing.report != null)) {
      return;
    }
    setState(() {
      _byUid[athlete.uid] = const _AthleteReportState(loading: true);
    });
    try {
      final report = await _fs.getWeeklyReport(athlete.uid);
      if (mounted) {
        setState(() {
          _byUid[athlete.uid] = _AthleteReportState(report: report);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _byUid[athlete.uid] = _AthleteReportState(error: friendlyError(e));
        });
      }
    }
  }

  Future<void> _shareReport(
    String athleteName,
    WeeklyReport report,
    PrivacySettings privacy,
  ) async {
    final text = formatWeeklyReportText(
      athleteName: athleteName,
      report: report,
      privacy: privacy,
    );
    await Share.share(text, subject: 'AthleteIQ — $athleteName — ${report.weekLabel}');
  }

  void _showPrintView(
    BuildContext context,
    String athleteName,
    WeeklyReport report,
    PrivacySettings privacy,
  ) {
    final text = formatWeeklyReportText(
      athleteName: athleteName,
      report: report,
      privacy: privacy,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Print preview — $athleteName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Copy or share this text into email or docs for printing.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report copied — paste into your printer app')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _shareReport(athleteName, report, privacy);
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AthleteReportState {
  final bool loading;
  final WeeklyReport? report;
  final String? error;

  const _AthleteReportState({this.loading = false, this.report, this.error});
}

class _AthleteReportCard extends StatelessWidget {
  final AthleteProfile athlete;
  final _AthleteReportState state;
  final VoidCallback onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onPrint;
  final VoidCallback onRetry;

  const _AthleteReportCard({
    required this.athlete,
    required this.state,
    required this.onOpen,
    this.onShare,
    this.onPrint,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  athlete.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (state.report?.riskLevel != null) RiskChip(level: state.report!.riskLevel!),
            ],
          ),
          const SizedBox(height: 8),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
                ),
              ),
            )
          else if (state.error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.error!,
                  style: TextStyle(color: AppColors.coral.withValues(alpha: 0.9)),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            )
          else if (state.report != null) ...[
            Text(
              state.report!.weekLabel,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            if (state.report!.narrative.isNotEmpty)
              Text(
                state.report!.narrative,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _StatPill(
                  label: 'Sessions',
                  value: sharedOrHidden(
                    athlete.privacySettings.trainingLogs,
                    '${state.report!.sessionsCompleted}',
                  ),
                ),
                _StatPill(
                  label: 'Load',
                  value: sharedOrHidden(
                    athlete.privacySettings.trainingLogs,
                    state.report!.totalTrainingLoad.toStringAsFixed(0),
                  ),
                ),
                _StatPill(
                  label: 'Peak ACWR',
                  value: sharedOrHidden(
                    athlete.privacySettings.trainingLogs,
                    state.report!.peakAcwr?.toStringAsFixed(2) ?? '—',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.report == null && !state.loading ? null : onOpen,
                  child: const Text('Full report'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Share',
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: 'Print / copy',
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}
