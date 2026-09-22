#!/usr/bin/env node
/**
 * One-off backfill: clear `fcmTokens` on every `users/*` document.
 *
 * WHY
 * ---
 * Until the AppSignOut change, ~13 of the app's ~15 sign-out call sites went
 * straight to `FirebaseAuth.instance.signOut()` and never removed this
 * device's FCM token from `users/{uid}.fcmTokens`. The device also kept the
 * same token across account switches (`deleteToken()` was never called), so
 * the next account to log in on that handset had the SAME token appended to
 * their array.
 *
 * The result is tokens that are shared between accounts. They cannot heal on
 * their own: `sendPushForNotification` only prunes tokens FCM reports as
 * `invalid-registration-token` / `registration-token-not-registered`, and a
 * shared token is perfectly valid, so it returns success forever and stays.
 *
 * Fixing the code stops NEW cross-links. This script removes the EXISTING
 * ones. Clearing the field is safe: `PushNotificationService.register()` runs
 * on next login and re-adds the correct token for whoever actually logs in.
 *
 * COST
 * ----
 * Every user must open the app once to start receiving pushes again. Anyone
 * who does not log in after this runs gets no push until they do. That is the
 * intended trade: no push is better than another account's push.
 *
 * USAGE
 * -----
 *   cd functions
 *   npm install
 *   # Point at the project's service account:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 *   node scripts/clear_stale_fcm_tokens.js --dry-run   # report only, no writes
 *   node scripts/clear_stale_fcm_tokens.js --apply     # perform the writes
 *
 * Run --dry-run first. It prints how many users hold tokens and, importantly,
 * how many tokens appear on more than one user — that count IS the bug, and it
 * should be 0 the next time you run it.
 */

const args = process.argv.slice(2);
const isApply = args.includes('--apply');
const isDryRun = args.includes('--dry-run');

// Validated before requiring firebase-admin, so a wrong invocation says so
// instead of failing with a module-resolution error.
if (isApply === isDryRun) {
  console.error('Pass exactly one of --dry-run or --apply.');
  process.exit(1);
}

const admin = require('firebase-admin');
admin.initializeApp();

const BATCH_LIMIT = 400; // Firestore caps a batch at 500 writes.

async function main() {
  const db = admin.firestore();
  const snap = await db.collection('users').get();

  let usersWithTokens = 0;
  let totalTokens = 0;
  const owners = new Map(); // token -> [uid, ...]

  snap.forEach((doc) => {
    const tokens = doc.data().fcmTokens;
    if (!Array.isArray(tokens) || tokens.length === 0) return;
    usersWithTokens += 1;
    totalTokens += tokens.length;
    tokens.forEach((t) => {
      if (!owners.has(t)) owners.set(t, []);
      owners.get(t).push(doc.id);
    });
  });

  const shared = [...owners.entries()].filter(([, uids]) => uids.length > 1);

  console.log(`users scanned:            ${snap.size}`);
  console.log(`users holding tokens:     ${usersWithTokens}`);
  console.log(`token entries total:      ${totalTokens}`);
  console.log(`distinct tokens:          ${owners.size}`);
  console.log(`tokens on >1 user:        ${shared.length}   <-- the bug`);

  if (shared.length > 0) {
    console.log('\nsample cross-linked tokens (first 10):');
    shared.slice(0, 10).forEach(([token, uids]) => {
      console.log(`  ...${token.slice(-12)}  ->  ${uids.join(', ')}`);
    });
  }

  if (isDryRun) {
    console.log('\nDry run — nothing written. Re-run with --apply to clear.');
    return;
  }

  const targets = snap.docs.filter((d) => {
    const t = d.data().fcmTokens;
    return Array.isArray(t) && t.length > 0;
  });

  let written = 0;
  for (let i = 0; i < targets.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const doc of targets.slice(i, i + BATCH_LIMIT)) {
      batch.update(doc.ref, {
        fcmTokens: admin.firestore.FieldValue.delete(),
      });
    }
    await batch.commit();
    written += Math.min(BATCH_LIMIT, targets.length - i);
    console.log(`cleared ${written}/${targets.length}`);
  }

  console.log(
    '\nDone. Every user re-registers on their next login. ' +
      'Re-run with --dry-run afterwards; "tokens on >1 user" should be 0.',
  );
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
