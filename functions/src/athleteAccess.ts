/**
 * Application-level athlete/coach access — same decision Cloud Functions
 * use before they touch Firestore. Rules are a second fence; this is the
 * first. A caller is allowed only as the athlete themself or as the
 * coachUid stored on that athlete's profile (roster membership).
 */

export type AthleteAccessDecision = 'self' | 'coach' | 'denied';

export function athleteAccessDecision(opts: {
  callerUid: string | null | undefined;
  athleteUid: string | null | undefined;
  coachUid: string | null | undefined;
}): AthleteAccessDecision {
  const caller = typeof opts.callerUid === 'string' ? opts.callerUid.trim() : '';
  const athlete = typeof opts.athleteUid === 'string' ? opts.athleteUid.trim() : '';
  if (!caller || !athlete) return 'denied';
  if (caller === athlete) return 'self';
  const coach = typeof opts.coachUid === 'string' ? opts.coachUid.trim() : '';
  if (coach && caller === coach) return 'coach';
  return 'denied';
}

export function canAccessAthlete(opts: {
  callerUid: string | null | undefined;
  athleteUid: string | null | undefined;
  coachUid: string | null | undefined;
}): boolean {
  return athleteAccessDecision(opts) !== 'denied';
}
