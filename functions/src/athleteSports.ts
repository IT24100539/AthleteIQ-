import { DocumentData } from 'firebase-admin/firestore';
import { SportGroup } from './recommendationEngine';
import { resolveSportGroup } from './riskModel';

export function parseAthleteSports(data: DocumentData | undefined): {
  sports: string[];
  sportGroups: SportGroup[];
  primarySport: string | null;
  primaryGroup: SportGroup;
} {
  const rawSports = data?.sports;
  const sports: string[] = Array.isArray(rawSports)
    ? rawSports.map((s) => String(s).trim()).filter(Boolean)
    : typeof data?.sport === 'string' && data.sport.trim()
      ? [data.sport.trim()]
      : [];

  const rawGroups = data?.sportGroups;
  let sportGroups: SportGroup[] = [];
  if (Array.isArray(rawGroups) && rawGroups.length > 0) {
    sportGroups = rawGroups.map((g) => resolveSportGroup(String(g)));
    if (sports.length > 0 && sportGroups.length !== sports.length) {
      const fallback = resolveSportGroup(data?.sportGroup as string | undefined);
      sportGroups = sports.map((_, i) => sportGroups[i] ?? (i === 0 ? fallback : 'other'));
    }
  } else if (sports.length > 0) {
    const fallback = resolveSportGroup(data?.sportGroup as string | undefined);
    sportGroups = sports.map((_, i) => (i === 0 ? fallback : fallback));
    if (data?.sportGroup) {
      sportGroups[0] = fallback;
    }
  } else if (data?.sportGroup) {
    sportGroups = [resolveSportGroup(data.sportGroup as string)];
  }

  return {
    sports,
    sportGroups,
    primarySport: sports[0] ?? null,
    primaryGroup: sportGroups[0] ?? 'other',
  };
}

/** Today's session sport if logged; otherwise the athlete's primary sport. */
export function wordingSport(
  athleteData: DocumentData | undefined,
  latest?: { sessionSport?: string | null; sessionSportGroup?: string | null },
): { sport: string | null; sportGroup: SportGroup } {
  const parsed = parseAthleteSports(athleteData);
  const sessionName =
    typeof latest?.sessionSport === 'string' && latest.sessionSport.trim()
      ? latest.sessionSport.trim()
      : null;
  const sessionGroup = latest?.sessionSportGroup
    ? resolveSportGroup(latest.sessionSportGroup)
    : null;

  if (sessionName || sessionGroup) {
    const index = sessionName ? parsed.sports.indexOf(sessionName) : -1;
    return {
      sport: sessionName ?? parsed.primarySport,
      sportGroup:
        sessionGroup ??
        (index >= 0 ? parsed.sportGroups[index] : parsed.primaryGroup),
    };
  }

  return {
    sport: parsed.primarySport,
    sportGroup: parsed.primaryGroup,
  };
}

export function sportsLabel(data: DocumentData | undefined): string {
  const { sports, primarySport } = parseAthleteSports(data);
  if (sports.length > 0) return sports.join(', ');
  return primarySport ?? '';
}
