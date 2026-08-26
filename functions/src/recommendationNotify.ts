/**
 * Notify the athlete when a coach first releases a recommendation
 * (approved or modified). In-app alert + FCM. No recommendation text,
 * risk scores, or health metrics in the push payload.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { sendPushToUser } from './nightlyAlerts';
import { isRecommendationReleased } from './privacyViews';

export function shouldNotifyRecommendationRelease(
  before: { recommendationStatus?: unknown } | undefined,
  after: { recommendationStatus?: unknown } | undefined,
): boolean {
  if (!after) return false;
  if (!isRecommendationReleased(after.recommendationStatus)) return false;
  return !isRecommendationReleased(before?.recommendationStatus);
}

export function approvalNotifyCopy(status: unknown): { title: string; body: string } {
  const s = typeof status === 'string' ? status.toLowerCase() : '';
  if (s === 'modified') {
    return {
      title: 'Your coach sent you a training plan',
      body: "Open AthleteIQ to see today's recommendation.",
    };
  }
  return {
    title: 'Your coach approved your training plan',
    body: "Open AthleteIQ to see today's recommendation.",
  };
}

export async function notifyAthleteRecommendationReleased(
  athleteUid: string,
  after: { recommendationStatus?: unknown },
): Promise<void> {
  const copy = approvalNotifyCopy(after.recommendationStatus);
  const now = new Date().toISOString();
  const db = getFirestore();
  await db.collection('athletes').doc(athleteUid).collection('alerts').add({
    type: 'approval',
    title: copy.title,
    timestamp: now,
    timeAgo: 'Just now',
    read: false,
  });
  try {
    await sendPushToUser(athleteUid, copy.title, copy.body, { type: 'approval' });
  } catch (err) {
    logger.warn('approval FCM failed (alert still written)', err);
  }
}
