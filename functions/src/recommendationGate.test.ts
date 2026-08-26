import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { isRecommendationReleased } from './privacyViews';
import {
  approvalNotifyCopy,
  shouldNotifyRecommendationRelease,
} from './recommendationNotify';

describe('Human Approval Step — release gate', () => {
  it('only approved and modified reach the athlete', () => {
    assert.equal(isRecommendationReleased('pending'), false);
    assert.equal(isRecommendationReleased('rejected'), false);
    assert.equal(isRecommendationReleased('llm'), false);
    assert.equal(isRecommendationReleased('orchestrator'), false);
    assert.equal(isRecommendationReleased(undefined), false);
    assert.equal(isRecommendationReleased('approved'), true);
    assert.equal(isRecommendationReleased('modified'), true);
    assert.equal(isRecommendationReleased('APPROVED'), true);
  });
});

describe('Human Approval Step — athlete notification', () => {
  it('notifies when pending becomes approved or modified', () => {
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'pending' },
        { recommendationStatus: 'approved' },
      ),
      true,
    );
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'pending' },
        { recommendationStatus: 'modified' },
      ),
      true,
    );
  });

  it('notifies when rejected is later released', () => {
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'rejected' },
        { recommendationStatus: 'approved' },
      ),
      true,
    );
  });

  it('does not notify on pipeline pending writes or already-released updates', () => {
    assert.equal(
      shouldNotifyRecommendationRelease(undefined, { recommendationStatus: 'pending' }),
      false,
    );
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'approved' },
        { recommendationStatus: 'approved' },
      ),
      false,
    );
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'approved' },
        { recommendationStatus: 'modified' },
      ),
      false,
    );
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'pending' },
        { recommendationStatus: 'rejected' },
      ),
      false,
    );
  });

  it('push copy names the approval without recommendation or health data', () => {
    const approved = approvalNotifyCopy('approved');
    assert.match(approved.title, /approved/i);
    assert.equal(approved.body.includes('ACWR'), false);
    assert.equal(approved.body.toLowerCase().includes('recommendation'), true);

    const modified = approvalNotifyCopy('modified');
    assert.match(modified.title, /sent you/i);
  });
});

describe('Human Approval Step — release gate', () => {
  it('only approved and modified reach the athlete', () => {
    assert.equal(isRecommendationReleased('pending'), false);
    assert.equal(isRecommendationReleased('rejected'), false);
    assert.equal(isRecommendationReleased('llm'), false);
    assert.equal(isRecommendationReleased('orchestrator'), false);
    assert.equal(isRecommendationReleased(undefined), false);
    assert.equal(isRecommendationReleased('approved'), true);
    assert.equal(isRecommendationReleased('modified'), true);
    assert.equal(isRecommendationReleased('APPROVED'), true);
  });
});
