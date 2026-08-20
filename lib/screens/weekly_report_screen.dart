import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/privacy_settings.dart';
import '../models/weekly_report.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/privacy_redaction.dart';
import '../utils/friendly_error.dart';
import '../utils/weekly_report_text.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';

class WeeklyReportScreen extends StatefulWidget {
  final String athleteUid;
  final String athleteName;

  const WeeklyReportScreen({
    super.key,
    required this.athleteUid,
    required this.athleteName,
  });

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final _fs = FirestoreService();
  int _weekOffset = 0;
  WeeklyReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _fs.getWeeklyReport(widget.athleteUid, weekOffset: _weekOffset);
      if (mounted) {
        setState(() {
          _report = report;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _changeWeek(int delta) {
    setState(() => _weekOffset += delta);
    _load();
  }

  Future<void> _share(WeeklyReport report, PrivacySettings privacy) async {
    final text = formatWeeklyReportText(
      athleteName: widget.athleteName,
      report: report,
      privacy: privacy,
    );
    await Share.share(
      text,
      subject: 'AthleteIQ — ${widget.athleteName} — ${report.weekLabel}',
    );
  }

  void _copyForPrint(WeeklyReport report, PrivacySettings privacy) {
    final text = formatWeeklyReportText(
      athleteName: widget.athleteName,
      report: report,
      privacy: privacy,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied — paste into email or a doc to print')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PrivacySettings>(
      stream: _fs.streamPrivacySettings(widget.athleteUid),
      builder: (context, privacySnap) {
        final privacyBlocked = asyncBody(
          privacySnap,
          heading: 'Could not load this report',
        );
        if (privacyBlocked != null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Week in review'),
              centerTitle: true,
            ),
            body: privacyBlocked,
          );
        }

        final privacy = privacySnap.data ?? PrivacySettings.open;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Week in review'),
            centerTitle: true,
            actions: [
              if (_report != null && !_loading && _error == null) ...[
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _share(_report!, privacy),
                ),
                IconButton(
                  tooltip: 'Copy for print',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () => _copyForPrint(_report!, privacy),
                ),
              ],
            ],
          ),
          body: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.mint))
                : _error != null
                    ? Center(
                        child: EmptyState(
                          icon: Icons.cloud_off_outlined,
                          heading: 'Could not load this week',
                          subtext: _error!,
                          warn: true,
                          actionLabel: 'Retry',
                          onAction: _load,
                        ),
                      )
                    : _buildContent(context, _report!, privacy),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    WeeklyReport report,
    PrivacySettings privacy,
  ) {
    final peakColor = report.peakAcwr != null && report.peakAcwr! > 1.5
        ? AppColors.coral
        : AppColors.textPrimary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _changeWeek(-1),
                icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      report.weekLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      widget.athleteName,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _weekOffset >= 0 ? null : () => _changeWeek(1),
                icon: Icon(
                  Icons.chevron_right,
                  color: _weekOffset >= 0 ? AppColors.textFaint : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Additive LLM narrative — structured rows below remain primary.
          if (report.narrative.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.narrative,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report.narrativeSource == 'llm'
                        ? 'AI summary — grounded in this week\'s logged numbers only.'
                        : 'Summary from logged numbers (AI unavailable).',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          _ReportRow(
            label: 'Sessions completed',
            value: sharedOrHidden(privacy.trainingLogs, '${report.sessionsCompleted}'),
          ),
          _ReportRow(
            label: 'Check-ins logged',
            value: '${report.checkInsLogged}',
          ),
          _ReportRow(
            label: 'Avg sleep',
            value: privacy.wearableData
                ? (report.avgSleepHours == null
                    ? '—'
                    : '${report.avgSleepHours!.toStringAsFixed(1)}h')
                : kPrivacyNotShared,
          ),
          _ReportRow(
            label: 'Avg fatigue',
            value: privacy.dailyFatigueCheckIn
                ? (report.avgFatigue == null
                    ? '—'
                    : '${report.avgFatigue!.toStringAsFixed(1)}/5')
                : kPrivacyNotShared,
          ),
          _ReportRow(
            label: 'Peak ACWR',
            value: sharedOrHidden(
              privacy.trainingLogs,
              report.peakAcwr?.toStringAsFixed(2) ?? '—',
            ),
            valueColor: privacy.trainingLogs ? peakColor : null,
          ),
          _ReportRow(
            label: 'ACWR at week end',
            value: sharedOrHidden(
              privacy.trainingLogs,
              report.endAcwr?.toStringAsFixed(2) ?? '—',
            ),
          ),
          _ReportRow(
            label: 'Total training load',
            value: sharedOrHidden(
              privacy.trainingLogs,
              report.totalTrainingLoad.toStringAsFixed(0),
            ),
          ),
          _ReportRow(
            label: 'Coach adjustments',
            value: '${report.coachAdjustments}',
          ),
          if (report.riskLevel != null)
            _ReportRow(
              label: 'Risk at week end',
              value: report.riskLevel!,
              valueColor: AppColors.forRisk(report.riskLevel!),
            ),

          const SizedBox(height: 24),
          Text(
            'DAILY LOAD',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          if (!privacy.trainingLogs)
            Text(
              'Training logs are not shared with you.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else
            _DailyLoadChart(dailyLoads: report.dailyLoads),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReportRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyLoadChart extends StatelessWidget {
  final List<WeeklyDailyLoad> dailyLoads;

  const _DailyLoadChart({required this.dailyLoads});

  @override
  Widget build(BuildContext context) {
    if (dailyLoads.isEmpty) {
      return Text(
        'No check-ins this week yet.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }

    final maxLoad = dailyLoads.map((d) => d.load).fold<double>(0, (a, b) => a > b ? a : b);
    const chartHeight = 100.0;
    const dow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < dailyLoads.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: maxLoad > 0
                        ? (dailyLoads[i].load / maxLoad) * chartHeight
                        : 4,
                    constraints: const BoxConstraints(minHeight: 4),
                    decoration: BoxDecoration(
                      color: dailyLoads[i].load > 0 ? AppColors.mint : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dow[i % 7],
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
