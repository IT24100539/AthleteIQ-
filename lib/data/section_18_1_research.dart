import '../models/risk_result.dart';

/// Static Section 18.1 baseline citations used when the Knowledge Agent
/// (Phase E3) has not yet written `researchNote` / `researchCitations` on
/// `riskResults/latest` for an athlete.
///
// TODO(E2/E3): Replace this fallback with live Knowledge Agent output once
// every athlete's risk pipeline run consistently attaches retrieved citations.
const List<ResearchCitation> section181StaticCitations = [
  ResearchCitation(
    tag: 'Session-RPE load',
    text:
        'Training load = session duration (minutes) × session RPE (1–10). '
        'Rest days use duration and RPE of 0. Acute load, chronic load, ACWR, '
        'and the Fitness–Fatigue index all consume this same session-RPE number.',
    source: 'Foster et al., 1998/2001 (session-RPE method)',
  ),
  ResearchCitation(
    tag: 'ACWR',
    text:
        'ACWR = 7-day acute training load ÷ (28-day chronic load ÷ 4). '
        'Gabbett (2016) popularized a 0.8–1.3 sweet spot and >1.5 danger zone; '
        'later critiques note the ratio couples numerator and denominator — '
        'treat high ACWR as a conversation flag, not a diagnosis.',
    source: 'Gabbett, Br J Sports Med (2016); Impellizzeri et al. critiques',
  ),
  ResearchCitation(
    tag: 'Fitness–Fatigue',
    text:
        'Banister\'s impulse-response model: each training dose raises slow '
        'fitness (~42-day decay) and fast fatigue (~7-day decay). Performance '
        'index ≈ fitness minus fatigue — a signed read of recovery vs accumulation, '
        'not a race-time forecast.',
    source: 'Banister et al., 1975 (impulse-response training model)',
  ),
];
