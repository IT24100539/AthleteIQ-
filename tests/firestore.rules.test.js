/**
 * Firestore security rules tests — run via:
 *   cd tests && npm install
 *   firebase emulators:exec --config ../firebase.rules-test.json --only firestore "npm test"
 *
 * Requires JDK 21+ for the Firestore emulator.
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'athleteiq-app';
const RULES = fs.readFileSync(
  path.resolve(__dirname, '../firestore.rules'),
  'utf8',
);

const ATHLETE_A = 'athlete-a';
const ATHLETE_B = 'athlete-b';
const COACH_C = 'coach-c';
const COACH_D = 'coach-d';

let testEnv;

function painReportPath(athleteUid, reportId = 'report-1') {
  return `athletes/${athleteUid}/painReports/${reportId}`;
}

function weeklyReportPath(athleteUid, weekId = '2026-08-11') {
  return `athletes/${athleteUid}/weeklyReports/${weekId}`;
}

function teamSettingsPath(coachUid = COACH_C) {
  return `coaches/${coachUid}/teamSettings/default`;
}

function alertPath(athleteUid, alertId = 'alert-1') {
  return `athletes/${athleteUid}/alerts/${alertId}`;
}

function devicePath(athleteUid, deviceId = 'garmin') {
  return `athletes/${athleteUid}/devices/${deviceId}`;
}

function aiChatPath(athleteUid, messageId = 'msg-1') {
  return `athletes/${athleteUid}/aiChat/${messageId}`;
}

function coachMessagePath(athleteUid, messageId = 'msg-1') {
  return `athletes/${athleteUid}/messages/${messageId}`;
}

function checkInPath(athleteUid, id = '2026-08-14') {
  return `athletes/${athleteUid}/checkins/${id}`;
}

function checkInCoachViewPath(athleteUid, id = '2026-08-14') {
  return `athletes/${athleteUid}/checkinsCoachView/${id}`;
}

function athleteViewPath(athleteUid) {
  return `athletes/${athleteUid}/riskResults/athleteView`;
}

async function seedBaseData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await db.collection('users').doc(ATHLETE_A).set({ role: 'athlete' });
    await db.collection('users').doc(ATHLETE_B).set({ role: 'athlete' });
    await db.collection('users').doc(COACH_C).set({ role: 'coach' });
    await db.collection('users').doc(COACH_D).set({ role: 'coach' });

    // Athlete A is on coach C's roster; athlete B is on coach D's roster.
    await db.collection('athletes').doc(ATHLETE_A).set({
      name: 'Athlete A',
      coachUid: COACH_C,
    });
    await db.collection('athletes').doc(ATHLETE_B).set({
      name: 'Athlete B',
      coachUid: COACH_D,
    });

    await db.doc(painReportPath(ATHLETE_A)).set({
      athleteUid: ATHLETE_A,
      date: '2026-08-14',
      areas: [{ location: 'Left knee', severity: 3 }],
    });
    await db.doc(painReportPath(ATHLETE_B)).set({
      athleteUid: ATHLETE_B,
      date: '2026-08-14',
      areas: [{ location: 'Right ankle', severity: 2 }],
    });

    await db.doc(`coaches/${COACH_C}/alerts/alert-1`).set({
      type: 'pain',
      urgency: 'HIGH',
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      title: 'HIGH pain report — Athlete A',
      summary: 'Left knee (5/5)',
      timestamp: '2026-08-14T12:00:00.000Z',
      read: false,
    });

    await db.doc(teamSettingsPath(COACH_C)).set({
      defaultActionPercent: 20,
      updatedAt: '2026-08-14T12:00:00.000Z',
    });

    await db.doc(weeklyReportPath(ATHLETE_A)).set({
      weekStart: '2026-08-11',
      weekEnd: '2026-08-17',
      narrative: 'Test narrative',
      checkInsLogged: 3,
    });

    await db.doc(alertPath(ATHLETE_A)).set({
      title: 'Coach approved your plan',
      type: 'approval',
      timestamp: '2026-08-14T12:00:00.000Z',
      read: false,
    });

    await db.doc(devicePath(ATHLETE_A)).set({
      name: 'Garmin',
      connected: true,
      tier: 'tier1',
    });

    await db.doc(aiChatPath(ATHLETE_A)).set({
      senderUid: ATHLETE_A,
      text: 'Why am I tired?',
      timestamp: '2026-08-14T12:00:00.000Z',
      isAi: false,
    });

    await db.doc(coachMessagePath(ATHLETE_A)).set({
      senderUid: ATHLETE_A,
      senderName: 'Athlete A',
      text: 'Can we talk about tomorrow?',
      timestamp: '2026-08-14T12:00:00.000Z',
      isCoach: false,
    });

    await db.collection('coaches').doc(COACH_C).set({
      inviteCode: 'JOIN-C',
      name: 'Coach C',
    });
    await db.collection('coaches').doc(COACH_D).set({
      inviteCode: 'JOIN-D',
      name: 'Coach D',
    });

    await db.doc(`athletes/${ATHLETE_A}/checkins/2026-08-14`).set({
      date: '2026-08-14',
      sessionDurationMinutes: 45,
      rpe: 6,
      fatigueScore: 3,
    });

    await db.doc(`athletes/${ATHLETE_A}/orchestratorTraces/trace-1`).set({
      action: 'reduce_volume',
      timestamp: '2026-08-14T12:00:00.000Z',
    });
  });
}

async function runTest(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    return true;
  } catch (err) {
    console.error(`  ✗ ${name}`);
    console.error(`    ${err.message}`);
    return false;
  }
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: RULES },
  });

  let passed = 0;
  let failed = 0;

  const test = async (name, fn) => {
    await testEnv.clearFirestore();
    await seedBaseData();
    const ok = await runTest(name, fn);
    if (ok) passed++;
    else failed++;
  };

  console.log('\nFirestore rules tests\n');

  // --- users ---

  await test('user can read own users doc', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(`users/${ATHLETE_A}`).get());
  });

  await test('user CANNOT read another users doc', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(db.doc(`users/${ATHLETE_B}`).get());
  });

  await test('user can create own users doc', async () => {
    const db = testEnv.authenticatedContext('new-user').firestore();
    await assertSucceeds(db.doc('users/new-user').set({ role: 'athlete' }));
  });

  await test('user CANNOT create another users doc', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(db.doc('users/someone-else').set({ role: 'athlete' }));
  });

  await test('user can update fcmToken without changing role', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(
      db.doc(`users/${ATHLETE_A}`).update({ fcmToken: 'token-1' }),
    );
  });

  await test('user CANNOT change own role after signup', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`users/${ATHLETE_A}`).update({ role: 'coach' }),
    );
  });

  // --- coaches (top-level invite lookup) ---

  await test('signed-in athlete can read coach invite doc', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(`coaches/${COACH_C}`).get());
  });

  await test('unsigned caller CANNOT read coaches', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc(`coaches/${COACH_C}`).get());
  });

  await test('coach can create and update own coaches doc', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      db.doc(`coaches/${COACH_C}`).set({ inviteCode: 'JOIN-C2', name: 'Coach C' }),
    );
  });

  await test('coach CANNOT update another coaches doc', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(`coaches/${COACH_D}`).update({ inviteCode: 'HACK' }),
    );
  });

  // --- athletes (profile) ---

  await test('athlete can read own profile', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(`athletes/${ATHLETE_A}`).get());
  });

  await test('assigned coach can read athlete profile', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(`athletes/${ATHLETE_A}`).get());
  });

  await test('assigned coach can list athletes on their roster', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    const qs = await assertSucceeds(
      db.collection('athletes').where('coachUid', '==', COACH_C).get(),
    );
    assert(qs.size >= 1, 'roster query should return linked athletes');
    assert(
      qs.docs.some((d) => d.id === ATHLETE_A),
      'athlete A should appear on coach C roster',
    );
  });

  await test('unrelated coach roster query returns empty (not denied)', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    const qs = await assertSucceeds(
      db.collection('athletes').where('coachUid', '==', COACH_D).get(),
    );
    assert(qs.docs.every((d) => d.id !== ATHLETE_A), 'athlete A is not on coach D roster');
  });

  await test('unrelated coach CANNOT read athlete profile', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(`athletes/${ATHLETE_A}`).get());
  });

  await test('athlete can create own profile', async () => {
    const db = testEnv.authenticatedContext('athlete-new').firestore();
    await assertSucceeds(
      db.doc('athletes/athlete-new').set({ name: 'New Athlete' }),
    );
  });

  await test('athlete can link coachUid once when it was missing', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('athletes/athlete-unlinked').set({
        name: 'Unlinked',
      });
    });
    const db = testEnv.authenticatedContext('athlete-unlinked').firestore();
    await assertSucceeds(
      db.doc('athletes/athlete-unlinked').update({ coachUid: COACH_C }),
    );
  });

  await test('athlete CANNOT steal another coach once already linked', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({ coachUid: COACH_D }),
    );
  });

  await test('athlete can disconnect from coach (coachUid → null)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('athletes/athlete-unlink').set({
        name: 'To Unlink',
        coachUid: COACH_C,
      });
    });
    const db = testEnv.authenticatedContext('athlete-unlink').firestore();
    await assertSucceeds(
      db.doc('athletes/athlete-unlink').update({ coachUid: null }),
    );
  });

  await test('athlete can re-link after disconnect', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('athletes/athlete-relink').set({
        name: 'Relink Test',
        coachUid: COACH_C,
      });
    });
    const db = testEnv.authenticatedContext('athlete-relink').firestore();
    await assertSucceeds(
      db.doc('athletes/athlete-relink').update({ coachUid: null }),
    );
    await assertSucceeds(
      db.doc('athletes/athlete-relink').update({ coachUid: COACH_D }),
    );
  });

  await test('coach CANNOT update athlete profile', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({ name: 'Hijacked' }),
    );
  });

  await test('athlete can update client-owned profile fields', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(
      db.doc(`athletes/${ATHLETE_A}`).update({ name: 'Athlete A renamed' }),
    );
    await assertSucceeds(
      db.doc(`athletes/${ATHLETE_A}`).update({
        sports: ['Running / Athletics'],
        sport: 'Running / Athletics',
        sportGroup: 'endurance',
        sportGroups: ['endurance'],
      }),
    );
    await assertSucceeds(
      db.doc(`athletes/${ATHLETE_A}`).update({
        deviceTier: 'tier2',
        activeDevice: 'Pixel Watch',
        deviceSetupCompleted: true,
      }),
    );
    await assertSucceeds(
      db.doc(`athletes/${ATHLETE_A}`).update({
        privacySettings: {
          wearableData: false,
          trainingLogs: true,
          injuryHistory: true,
          dailyFatigueCheckIn: true,
        },
      }),
    );
  });

  await test('athlete CANNOT write latestPainUrgency on own profile', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({ latestPainUrgency: 'HIGH' }),
    );
  });

  await test('athlete CANNOT write latestPain summary fields on own profile', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({
        latestPainAt: '2026-08-15T12:00:00.000Z',
        latestPainSummary: 'Left knee (5/5)',
        latestPainReportId: 'forged-id',
      }),
    );
  });

  await test('athlete CANNOT mix a legitimate field with latestPainUrgency', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({
        name: 'Athlete A',
        latestPainUrgency: 'HIGH',
      }),
    );
  });

  await test('athlete CANNOT overwrite createdAt', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}`).update({ createdAt: '2000-01-01T00:00:00.000Z' }),
    );
  });

  await test('Admin SDK can write latestPain fields (submitPainReport path)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await assertSucceeds(
        db.doc(`athletes/${ATHLETE_A}`).update({
          latestPainUrgency: 'HIGH',
          latestPainAt: '2026-08-15T12:00:00.000Z',
          latestPainSummary: 'Left knee (5/5)',
          latestPainReportId: 'report-server',
        }),
      );
    });
  });

  // --- checkins ---

  await test('athlete can read and write own checkins', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(`athletes/${ATHLETE_A}/checkins/2026-08-14`).get());
    await assertSucceeds(
      db.doc(`athletes/${ATHLETE_A}/checkins/2026-08-15`).set({
        date: '2026-08-15',
        sessionDurationMinutes: 30,
        rpe: 5,
        fatigueScore: 2,
      }),
    );
  });

  await test('assigned coach CANNOT read raw checkins (mixed document)', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(checkInPath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read a checkins field the athlete has toggled private', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc(`athletes/${ATHLETE_A}`).update({
        privacySettings: { dailyFatigueCheckIn: false },
      });
      await db.doc(checkInPath(ATHLETE_A)).set({
        date: '2026-08-14',
        sessionDurationMinutes: 45,
        rpe: 6,
        fatigueScore: 3,
      });
      // Filtered view omits fatigueScore — even a successful coach read
      // of this doc cannot see the private field.
      await db.doc(checkInCoachViewPath(ATHLETE_A)).set({
        date: '2026-08-14',
        sessionDurationMinutes: 45,
        rpe: 6,
      });
    });
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(checkInPath(ATHLETE_A)).get());
    const view = await assertSucceeds(db.doc(checkInCoachViewPath(ATHLETE_A)).get());
    const data = view.data();
    if (data.fatigueScore != null) {
      throw new Error('checkinsCoachView leaked withheld fatigueScore');
    }
  });

  await test('assigned coach can read checkinsCoachView', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(checkInCoachViewPath(ATHLETE_A)).set({
        date: '2026-08-14',
        sessionDurationMinutes: 45,
        rpe: 6,
        fatigueScore: 3,
      });
    });
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(checkInCoachViewPath(ATHLETE_A)).get());
  });

  await test('client CANNOT write checkinsCoachView (Cloud Function only)', async () => {
    const coach = testEnv.authenticatedContext(COACH_C).firestore();
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      coach.doc(checkInCoachViewPath(ATHLETE_A, '2026-08-16')).set({
        date: '2026-08-16',
        fatigueScore: 1,
      }),
    );
    await assertFails(
      athlete.doc(checkInCoachViewPath(ATHLETE_A, '2026-08-16')).set({
        date: '2026-08-16',
        fatigueScore: 1,
      }),
    );
  });

  await test('assigned coach CANNOT write checkins', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}/checkins/2026-08-16`).set({
        date: '2026-08-16',
        rpe: 1,
      }),
    );
  });

  await test('unrelated coach CANNOT read checkins', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(`athletes/${ATHLETE_A}/checkins/2026-08-14`).get());
  });

  // --- painReports ---

  await test('athlete can read own painReports', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(painReportPath(ATHLETE_A)).get());
  });

  await test('athlete CANNOT read another athlete painReports', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(db.doc(painReportPath(ATHLETE_B)).get());
  });

  await test('coach can read painReports for athlete on their roster', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(painReportPath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read painReports for athlete not on their team', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(painReportPath(ATHLETE_B)).get());
  });

  await test('athlete CANNOT create painReport (callable / Admin SDK only)', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.collection(`athletes/${ATHLETE_A}/painReports`).add({
        athleteUid: ATHLETE_A,
        date: '2026-08-15',
        areas: [{ location: 'Hamstring', severity: 2 }],
      }),
    );
  });

  await test('Admin SDK can create painReport (submitPainReport path)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await assertSucceeds(
        db.collection(`athletes/${ATHLETE_A}/painReports`).add({
          athleteUid: ATHLETE_A,
          date: '2026-08-15T12:00:00.000Z',
          areas: [{ location: 'Hamstring', severity: 2 }],
          urgency: 'MEDIUM',
          urgencySource: 'llm',
        }),
      );
    });
  });

  await test('coach CANNOT create painReport for athlete', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.collection(`athletes/${ATHLETE_A}/painReports`).add({
        athleteUid: ATHLETE_A,
        date: '2026-08-15',
        areas: [{ location: 'Hamstring', severity: 2 }],
      }),
    );
  });

  await test('coach CANNOT delete athlete painReport', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(painReportPath(ATHLETE_A)).delete());
  });

  await test('coach CANNOT read painReports when injuryHistory is off', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`athletes/${ATHLETE_A}`).update({
        privacySettings: { injuryHistory: false },
      });
    });
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(painReportPath(ATHLETE_A)).get());
  });

  // --- alerts ---

  await test('athlete can read own alerts', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(alertPath(ATHLETE_A)).get());
  });

  await test('coach can read alerts for athlete on their roster', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(alertPath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read alerts for athlete not on their team', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(alertPath(ATHLETE_B)).get());
  });

  await test('client CANNOT write alerts (server-only)', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.collection(`athletes/${ATHLETE_A}/alerts`).add({
        title: 'Fake alert',
        type: 'system',
        timestamp: '2026-08-14T12:00:00.000Z',
      }),
    );
  });

  await test('coach can read own coach alerts', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(`coaches/${COACH_C}/alerts/alert-1`).get());
  });

  await test('other coach CANNOT read coach alerts', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(`coaches/${COACH_C}/alerts/alert-1`).get());
  });

  await test('coach CANNOT write own coach alerts (server-only)', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.collection(`coaches/${COACH_C}/alerts`).add({
        type: 'pain',
        urgency: 'HIGH',
        athleteUid: ATHLETE_A,
        title: 'Fake',
        timestamp: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  // --- weeklyReports ---

  await test('athlete can read own weeklyReports', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(db.doc(weeklyReportPath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read weeklyReports (use getWeeklyReport callable)', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(weeklyReportPath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read weeklyReports for athlete not on their team', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(weeklyReportPath(ATHLETE_B)).get());
  });

  await test('client CANNOT write weeklyReports (server-only)', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(weeklyReportPath(ATHLETE_A, '2026-08-18')).set({
        narrative: 'Fake',
        checkInsLogged: 0,
      }),
    );
  });

  // --- teamSettings ---

  await test('coach can read own teamSettings', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(teamSettingsPath(COACH_C)).get());
  });

  await test('other coach CANNOT read teamSettings', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(teamSettingsPath(COACH_C)).get());
  });

  await test('coach can write teamSettings within 10-30%', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      db.doc(teamSettingsPath(COACH_C)).set({
        defaultActionPercent: 25,
        updatedAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  await test('coach CANNOT write teamSettings outside 10-30%', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(teamSettingsPath(COACH_C)).set({
        defaultActionPercent: 40,
      }),
    );
  });

  // --- devices ---

  await test('athlete can write own device connection', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(
      db.doc(devicePath(ATHLETE_A, 'whoop')).set({
        name: 'Whoop',
        connected: true,
        tier: 'tier1',
      }),
    );
  });

  await test('coach CANNOT write athlete device connection', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(devicePath(ATHLETE_A, 'whoop')).set({
        name: 'Whoop',
        connected: true,
      }),
    );
  });

  await test('coach can read athlete device connection on their roster', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(devicePath(ATHLETE_A)).get());
  });

  await test('unrelated coach CANNOT read devices', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(devicePath(ATHLETE_A)).get());
  });

  await test('coach CANNOT read devices when wearableData sharing is off', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`athletes/${ATHLETE_A}`).update({
        privacySettings: { wearableData: false },
      });
    });
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(db.doc(devicePath(ATHLETE_A)).get());
  });

  // --- aiChat ---

  await test('athlete can write own aiChat message', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(
      db.doc(aiChatPath(ATHLETE_A, 'msg-new')).set({
        senderUid: ATHLETE_A,
        text: 'Should I train today?',
        timestamp: '2026-08-14T13:00:00.000Z',
        isAi: false,
      }),
    );
  });

  await test('athlete CANNOT read another athlete aiChat', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(aiChatPath(ATHLETE_B)).set({
        senderUid: ATHLETE_B,
        text: 'Private question',
        timestamp: '2026-08-14T12:00:00.000Z',
        isAi: false,
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(db.doc(aiChatPath(ATHLETE_B)).get());
  });

  await test('coach CANNOT write athlete aiChat', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(aiChatPath(ATHLETE_A, 'coach-msg')).set({
        senderUid: COACH_C,
        text: 'Coach reply',
        timestamp: '2026-08-14T13:00:00.000Z',
        isAi: false,
      }),
    );
  });

  await test('assigned coach can read athlete aiChat', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(db.doc(aiChatPath(ATHLETE_A)).get());
  });

  // --- messages (coach chat) ---

  await test('athlete and assigned coach can read and write coach chat', async () => {
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    const coach = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(athlete.doc(coachMessagePath(ATHLETE_A)).get());
    await assertSucceeds(coach.doc(coachMessagePath(ATHLETE_A)).get());
    await assertSucceeds(
      athlete.doc(coachMessagePath(ATHLETE_A, 'a-reply')).set({
        senderUid: ATHLETE_A,
        senderName: 'Athlete A',
        text: 'Got it',
        timestamp: '2026-08-14T13:00:00.000Z',
        isCoach: false,
      }),
    );
    await assertSucceeds(
      coach.doc(coachMessagePath(ATHLETE_A, 'c-reply')).set({
        senderUid: COACH_C,
        senderName: 'Coach C',
        text: 'Rest tomorrow',
        timestamp: '2026-08-14T13:05:00.000Z',
        isCoach: true,
      }),
    );
  });

  await test('another athlete and unrelated coach CANNOT read or write coach chat', async () => {
    const athleteB = testEnv.authenticatedContext(ATHLETE_B).firestore();
    await assertFails(athleteB.doc(coachMessagePath(ATHLETE_A)).get());
    await assertFails(
      athleteB.doc(coachMessagePath(ATHLETE_A, 'intrusion')).set({
        senderUid: ATHLETE_B,
        senderName: 'Athlete B',
        text: 'Should not appear here',
        timestamp: '2026-08-14T13:00:00.000Z',
        isCoach: false,
      }),
    );

    const unrelatedCoach = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(unrelatedCoach.doc(coachMessagePath(ATHLETE_A)).get());
    await assertFails(
      unrelatedCoach.doc(coachMessagePath(ATHLETE_A, 'coach-intrusion')).set({
        senderUid: COACH_D,
        senderName: 'Coach D',
        text: 'Not on this roster',
        timestamp: '2026-08-14T13:00:00.000Z',
        isCoach: true,
      }),
    );
  });

  // --- inboxRead (coach last-read cursor) ---

  await test('coach can write own inboxRead', async () => {
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      db.doc(`coaches/${COACH_C}/inboxRead/${ATHLETE_A}`).set({
        lastReadAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  await test('other coach CANNOT write inboxRead', async () => {
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(
      db.doc(`coaches/${COACH_C}/inboxRead/${ATHLETE_A}`).set({
        lastReadAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  // --- riskResults / coach approval ---

  const latestPath = `athletes/${ATHLETE_A}/riskResults/latest`;

  async function seedLatest() {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(latestPath).set({
        riskLevel: 'MEDIUM',
        acwr: 1.2,
        recommendation: 'Easy day',
        recommendationStatus: 'pending',
        reason: 'Load climbing',
      });
    });
  }

  await test('assigned coach can read pending riskResults/latest', async () => {
    await seedLatest();
    const coach = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(coach.doc(latestPath).get());
  });

  await test('athlete CANNOT read pending riskResults/latest recommendation', async () => {
    await seedLatest();
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(athlete.doc(latestPath).get());
  });

  await test('athlete can read riskResults/athleteView while latest is pending', async () => {
    await seedLatest();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(athleteViewPath(ATHLETE_A)).set({
        kind: 'athleteView',
        riskLevel: 'MEDIUM',
        acwr: 1.2,
        recommendationStatus: 'pending',
      });
    });
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    const snap = await assertSucceeds(athlete.doc(athleteViewPath(ATHLETE_A)).get());
    if (snap.data().recommendation) {
      throw new Error('athleteView leaked a pending recommendation');
    }
  });

  await test('athlete can read riskResults/latest once recommendation is approved', async () => {
    await seedLatest();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(latestPath).update({
        recommendationStatus: 'approved',
      });
    });
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertSucceeds(athlete.doc(latestPath).get());
  });

  await test('unrelated coach CANNOT read riskResults/latest', async () => {
    await seedLatest();
    const db = testEnv.authenticatedContext(COACH_D).firestore();
    await assertFails(db.doc(latestPath).get());
  });

  await test('coach can approve by updating status, recommendation, reviewedAt', async () => {
    await seedLatest();
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      db.doc(latestPath).update({
        recommendationStatus: 'approved',
        reviewedAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  await test('coach can send a modified recommendation', async () => {
    await seedLatest();
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      db.doc(latestPath).update({
        recommendationStatus: 'modified',
        recommendation: 'Swim 30 min easy',
        reviewedAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  await test('athlete CANNOT approve their own recommendation', async () => {
    await seedLatest();
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(latestPath).update({
        recommendationStatus: 'approved',
        reviewedAt: '2026-08-15T12:00:00.000Z',
      }),
    );
  });

  await test('coach CANNOT update riskLevel or other score fields', async () => {
    await seedLatest();
    const db = testEnv.authenticatedContext(COACH_C).firestore();
    await assertFails(
      db.doc(latestPath).update({
        riskLevel: 'LOW',
      }),
    );
  });

  await test('client CANNOT create riskResults (Cloud Function only)', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}/riskResults/2026-08-15`).set({
        riskLevel: 'LOW',
        acwr: 1.0,
      }),
    );
  });

  // --- orchestratorTraces ---

  await test('athlete and assigned coach can read orchestratorTraces', async () => {
    const athlete = testEnv.authenticatedContext(ATHLETE_A).firestore();
    const coach = testEnv.authenticatedContext(COACH_C).firestore();
    await assertSucceeds(
      athlete.doc(`athletes/${ATHLETE_A}/orchestratorTraces/trace-1`).get(),
    );
    await assertSucceeds(
      coach.doc(`athletes/${ATHLETE_A}/orchestratorTraces/trace-1`).get(),
    );
  });

  await test('client CANNOT write orchestratorTraces', async () => {
    const db = testEnv.authenticatedContext(ATHLETE_A).firestore();
    await assertFails(
      db.doc(`athletes/${ATHLETE_A}/orchestratorTraces/fake`).set({
        action: 'fake',
      }),
    );
  });

  await testEnv.cleanup();

  console.log(`\n${passed} passed, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
