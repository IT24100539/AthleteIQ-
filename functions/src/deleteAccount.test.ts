import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  ATHLETE_SUBCOLLECTIONS,
  COACH_SUBCOLLECTIONS,
} from './deleteAccount';

describe('account deletion coverage', () => {
  it('wipes every athlete subcollection the app writes', () => {
    assert.deepEqual([...ATHLETE_SUBCOLLECTIONS].sort(), [
      'aiChat',
      'alerts',
      'checkins',
      'checkinsCoachView',
      'devices',
      'messages',
      'orchestratorTraces',
      'painReports',
      'riskResults',
      'weeklyReports',
    ]);
  });

  it('wipes every coach subcollection the app writes', () => {
    assert.deepEqual([...COACH_SUBCOLLECTIONS].sort(), [
      'alerts',
      'inboxRead',
      'teamSettings',
    ]);
  });
});
