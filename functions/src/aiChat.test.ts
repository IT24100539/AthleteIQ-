import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  OFF_TOPIC_REPLY,
  generateAnswer,
  isOnTopicQuestion,
} from './aiChat';

describe('isOnTopicQuestion', () => {
  it('allows training / health questions', () => {
    assert.equal(isOnTopicQuestion('Why am I so tired this week?'), true);
    assert.equal(isOnTopicQuestion('What is my risk level?'), true);
    assert.equal(isOnTopicQuestion('How was my sleep and fatigue last week?'), true);
    assert.equal(isOnTopicQuestion('Should I follow the coach recommendation today?'), true);
  });

  it('allows app / product questions', () => {
    assert.equal(isOnTopicQuestion('what is AthleteIQ'), true);
    assert.equal(isOnTopicQuestion('How does this app calculate risk?'), true);
    assert.equal(isOnTopicQuestion('What does Athlete IQ show on my home screen?'), true);
  });

  it('rejects clear off-topic questions', () => {
    assert.equal(isOnTopicQuestion("what's the weather today"), false);
    assert.equal(isOnTopicQuestion('tell me a joke'), false);
    assert.equal(isOnTopicQuestion('Who is the president?'), false);
    assert.equal(isOnTopicQuestion('write me a poem about cats'), false);
    assert.equal(isOnTopicQuestion('good bitcoin stock tips?'), false);
  });

  it('keeps allow-list priority when both could match', () => {
    // Unlikely, but training context should win if somehow mixed.
    assert.equal(
      isOnTopicQuestion('Is my sleep affected by weather during training?'),
      true,
    );
  });
});

describe('generateAnswer topic guard', () => {
  it('returns the decline without needing athlete data', async () => {
    const answer = await generateAnswer("tell me a joke", [], null, 'Soccer', 'Demo');
    assert.equal(answer.source, 'guard');
    assert.equal(answer.text, OFF_TOPIC_REPLY);
  });

  it('returns the decline for weather', async () => {
    const answer = await generateAnswer(
      "what's the weather today",
      [],
      null,
      'Soccer',
      'Demo',
    );
    assert.equal(answer.source, 'guard');
    assert.equal(answer.text, OFF_TOPIC_REPLY);
  });
});
