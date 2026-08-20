/**
 * Section 18.4 — per-coach team settings (coach-adjustable knobs).
 * Stored at coaches/{coachUid}/teamSettings/default.
 *
 * Note: ACWR thresholds (1.5, 1.3, 0.8) live in riskModel.ts and are
 * intentionally NOT loaded from here — see comment there.
 */

import { getFirestore } from 'firebase-admin/firestore';
import {
  clampActionPercent,
  DEFAULT_ACTION_PERCENT,
} from './recommendationEngine';

export interface TeamSettings {
  defaultActionPercent: number;
}

export async function loadTeamSettings(
  coachUid: string | null | undefined,
): Promise<TeamSettings> {
  if (!coachUid) {
    return { defaultActionPercent: DEFAULT_ACTION_PERCENT };
  }

  const snap = await getFirestore()
    .collection('coaches')
    .doc(coachUid)
    .collection('teamSettings')
    .doc('default')
    .get();

  if (!snap.exists) {
    return { defaultActionPercent: DEFAULT_ACTION_PERCENT };
  }

  return {
    defaultActionPercent: clampActionPercent(snap.data()?.defaultActionPercent),
  };
}
