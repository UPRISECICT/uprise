// Stand-in for the `sendPushForNotification` Cloud Function in ../index.js.
// Cloud Functions require the Firebase Blaze (pay-as-you-go) plan to deploy
// at all, even just to enable the required Cloud Build/Artifact Registry
// APIs — this project stays on the free Spark plan instead, so nothing here
// runs as a Firestore trigger. A GitHub Actions cron job
// (.github/workflows/send_push_notifications.yml) runs this script every 5
// minutes instead: it polls for `notifications` docs created since the last
// run and sends the same FCM push for each one. Notifications land within
// one polling interval instead of instantly — a deliberate trade-off to
// avoid needing a credit card on file.
//
// Run manually with: node scripts/send_pending_pushes.js
// Requires FIREBASE_SERVICE_ACCOUNT env var (full service account JSON, as
// a string) to authenticate — see the workflow file for how CI provides it.
const admin = require('firebase-admin');

if (!admin.apps.length) {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.error('FIREBASE_SERVICE_ACCOUNT env var is not set.');
    process.exit(1);
  }
  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(raw)),
  });
}

const db = admin.firestore();
// Single doc, not a collection — there is only ever one "where did we leave
// off" pointer for this whole job.
const cursorRef = db.collection('system').doc('pushCursor');
// First-ever run has no cursor yet — start from a day ago rather than the
// beginning of time, so it doesn't try to push every notification the app
// has ever created.
const DEFAULT_LOOKBACK_MS = 24 * 60 * 60 * 1000;
// Safety cap per run — if this job were ever down for a long stretch, one
// run shouldn't try to push thousands of backlogged notifications at once.
const BATCH_LIMIT = 200;

// Mirrors sendPushForNotification in functions/index.js exactly (portal
// filter, token pruning, message shape) — keep the two in sync if either
// changes.
async function sendPushFor(notifDoc) {
  const notif = notifDoc.data();
  if (!notif || !notif.userId) return true;

  const userRef = db.collection('users').doc(notif.userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return true;
  const userData = userSnap.data();
  const tokens = userData.fcmTokens || [];
  if (tokens.length === 0) return true;

  const role = userData.role || '';
  const isMobileUser = role === 'student' || role === 'guest';
  const portal = notif.portal;
  const mobileVisiblePortal =
      portal === undefined || portal === null || portal === '' || portal === 'student';
  if (isMobileUser && !mobileVisiblePortal) return true;

  const message = {
    notification: {
      title: notif.title || 'UPRISE',
      body: notif.body || '',
    },
    data: {
      type: notif.type || 'general',
      orgId: notif.orgId || '',
      notificationId: notifDoc.id,
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'uprise_notifications',
      },
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    const invalidTokens = [];
    response.responses.forEach((res, idx) => {
      if (!res.success) {
        const code = res.error && res.error.code;
        if (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered') {
          invalidTokens.push(tokens[idx]);
        }
      }
    });
    if (invalidTokens.length > 0) {
      await userRef.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }
    console.log(`Push for ${notifDoc.id}: ${response.successCount}/${tokens.length} succeeded`);
    return true;
  } catch (err) {
    console.error(`Error sending push for ${notifDoc.id}:`, err);
    return false;
  }
}

async function main() {
  const cursorSnap = await cursorRef.get();
  const cursorData = cursorSnap.exists ? cursorSnap.data() : {};
  const lastProcessedAt =
      cursorData.lastProcessedAt
        ? cursorData.lastProcessedAt
        : admin.firestore.Timestamp.fromMillis(Date.now() - DEFAULT_LOOKBACK_MS);
  const lastProcessedId = cursorData.lastProcessedId;

  let query = db.collection('notifications')
      .where('createdAt', '>=', lastProcessedAt)
      .orderBy('createdAt', 'asc')
      .orderBy(admin.firestore.FieldPath.documentId(), 'asc');
  if (lastProcessedId) {
    query = query.startAfter(lastProcessedAt, lastProcessedId);
  } else if (cursorData.lastProcessedAt) {
    query = query.startAfter(lastProcessedAt);
  }
  const snap = await query.limit(BATCH_LIMIT).get();

  if (snap.empty) {
    console.log('No new notifications to push.');
    return;
  }

  let processed = 0;
  for (const doc of snap.docs) {
    const sent = await sendPushFor(doc);
    if (!sent) {
      // Keep the cursor before the failed document so the next scheduled run
      // retries it instead of silently skipping a transient FCM/Firestore error.
      break;
    }
    await cursorRef.set({
      lastProcessedAt: doc.data().createdAt,
      lastProcessedId: doc.id,
    }, { merge: true });
    processed++;
  }

  console.log(`Processed ${processed}/${snap.docs.length} notification(s).`);
}

main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Fatal error:', err);
      process.exit(1);
    });
