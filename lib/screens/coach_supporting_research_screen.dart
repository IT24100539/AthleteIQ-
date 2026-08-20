import 'package:flutter/material.dart';
import '../data/section_18_1_research.dart';
import '../models/athlete.dart';
import '../models/risk_result.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';

/// Supporting research for a coach's athlete — live Knowledge Agent output
/// from `riskResults/latest` when present; otherwise Section 18.1 static citations.
class CoachSupportingResearchScreen extends StatefulWidget {
  final String coachUid;
  final AthleteProfile? athlete;

  const CoachSupportingResearchScreen({
    super.key,
    required this.coachUid,
    this.athlete,
  });

  @override
  State<CoachSupportingResearchScreen> createState() =>
      _CoachSupportingResearchScreenState();
}

class _CoachSupportingResearchScreenState extends State<CoachSupportingResearchScreen> {
  final _fs = FirestoreService();
  AthleteProfile? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.athlete;
  }

  bool _hasKnowledgeAgentOutput(RiskResult? result) {
    if (result == null) return false;
    return result.researchCitations.isNotEmpty ||
        (result.researchNote != null && result.researchNote!.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supporting research'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<AthleteProfile>>(
        stream: _fs.rosterForCoach(widget.coachUid),
        builder: (context, rosterSnap) {
          final rosterBlocked = asyncBody(
            rosterSnap,
            heading: 'Could not load supporting research',
          );
          if (rosterBlocked != null) return rosterBlocked;

          final athletes = rosterSnap.data ?? [];
          if (athletes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Add athletes to your roster to view supporting research.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          final selected = _selected ?? athletes.first;
          if (_selected == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selected = athletes.first);
            });
          }

          return StreamBuilder<RiskResult?>(
            stream: _fs.latestRiskResult(selected.uid),
            builder: (context, riskSnap) {
              final riskBlocked = asyncBody(
                riskSnap,
                heading: 'Could not load research for this athlete',
              );
              if (riskBlocked != null) return riskBlocked;

              final result = riskSnap.data;
              final fromAgent = _hasKnowledgeAgentOutput(result);
              final citations = fromAgent
                  ? result!.researchCitations
                  : section181StaticCitations;
              final note = fromAgent ? result!.researchNote : null;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selected.uid,
                      decoration: const InputDecoration(
                        labelText: 'Athlete',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final a in athletes)
                          DropdownMenuItem(value: a.uid, child: Text(a.name)),
                      ],
                      onChanged: (uid) {
                        if (uid == null) return;
                        setState(() {
                          _selected = athletes.firstWhere((a) => a.uid == uid);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: fromAgent
                            ? AppColors.mint.withValues(alpha: 0.08)
                            : AppColors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: fromAgent
                              ? AppColors.mint.withValues(alpha: 0.35)
                              : AppColors.amber.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        fromAgent
                            ? 'From Knowledge Agent — citations retrieved for ${selected.name}\'s latest risk read (${_formatDate(result!.calculatedAt)}).'
                            : 'No Knowledge Agent output on riskResults/latest yet — showing Section 18.1 baseline citations (session-RPE, ACWR + Gabbett 2016, Banister). Revisit once E2/E3 pipeline runs attach live research.',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                    if (note != null && note.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'RESEARCH NOTE',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mint,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 14, height: 1.45),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'CITATIONS',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final c in citations) ...[
                      _CitationCard(citation: c),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _CitationCard extends StatelessWidget {
  final ResearchCitation citation;

  const _CitationCard({required this.citation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (citation.tag.isNotEmpty)
            Text(
              citation.tag.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.mint,
                letterSpacing: 0.5,
              ),
            ),
          if (citation.tag.isNotEmpty) const SizedBox(height: 6),
          Text(
            citation.text,
            style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textPrimary),
          ),
          if (citation.source.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              citation.source,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
