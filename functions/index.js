// `/v1`, not the bare package: since firebase-functions 6, the root import is
// the v2 API, which has no `firestore.document()` or `pubsub.schedule()`.
// With the bare require every export below threw at load time, so none of
// these functions — push, reminders, credential emails — could deploy or run.
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// ─────────────────────────────────────────────
//  EMAIL CONFIGURATION
// ─────────────────────────────────────────────
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.GMAIL_USER || "",
    pass: process.env.GMAIL_PASS || "",
  },
});

// ─────────────────────────────────────────────
//  🔔 REAL PUSH NOTIFICATIONS
//  Fires whenever NotificationService (Flutter) writes a `notifications`
//  doc — delivers it as an actual OS/browser push via FCM to every token
//  PushNotificationService (lib/services/push_notification_service.dart)
//  has saved on users/{userId}.fcmTokens, instead of only showing up in
//  the in-app notification bell. Any token FCM reports as dead gets pruned
//  from that array so it isn't retried on every future notification.
// ─────────────────────────────────────────────
exports.sendPushForNotification = functions.firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snap, context) => {
        const notif = snap.data();
        if (!notif || !notif.userId) return null;

        const userRef = admin.firestore().collection('users').doc(notif.userId);
        const userSnap = await userRef.get();
        const tokens = userSnap.exists ? (userSnap.data().fcmTokens || []) : [];
        if (tokens.length === 0) return null;

        const message = {
            notification: {
                title: notif.title || 'UPRISE',
                body: notif.body || '',
            },
            data: {
                type: notif.type || 'general',
                orgId: notif.orgId || '',
                notificationId: context.params.notificationId,
            },
            // Route to the high-importance channel the app creates in
            // PushNotificationService.initialize(), so the push pops up as a
            // heads-up banner instead of landing silently in the tray under
            // FCM's default-importance fallback channel.
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
            console.log(`🔔 Push for ${context.params.notificationId}: ${response.successCount}/${tokens.length} succeeded`);
        } catch (err) {
            console.error('❌ Error sending push notification:', err);
        }
        return null;
    });

// ─────────────────────────────────────────────
//  🚀 AUTO-ADD slotsLeft TO ANY NEW EVENT
//  This runs automatically when ANY event is created
//  (Even from Firebase Console!)
// ─────────────────────────────────────────────
exports.autoAddSlotsLeft = functions.firestore
    .document('events/{eventId}')
    .onCreate(async (snap, context) => {
        const data = snap.data();
        const eventId = context.params.eventId;
        
        console.log(`📝 New event created: ${eventId}`);
        console.log(`📊 Data:`, data);
        
        // Check if slotsLeft is missing
        if (data.slotsLeft === undefined || data.slotsLeft === null) {
            // Use capacity, default to 0 if not set
            const capacity = data.capacity || 0;
            
            // Update the document with slotsLeft
            await snap.ref.update({
                slotsLeft: capacity
            });
            
            console.log(`✅ Added slotsLeft: ${capacity} to event ${eventId}`);
            console.log(`📊 Now showing: ${capacity}/${capacity} slots`);
        } else {
            console.log(`ℹ️ Event ${eventId} already has slotsLeft: ${data.slotsLeft}`);
        }
    });

// ─────────────────────────────────────────────
//  🔄 FIX EXISTING EVENTS (Callable Function)
//  Call this from your app to fix all existing events
// ─────────────────────────────────────────────
exports.fixExistingEvents = functions.https.onCall(async (data, context) => {
    // Security check - must be logged in
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
    }
    
    try {
        const events = await admin.firestore().collection('events').get();
        const batch = admin.firestore().batch();
        let fixedCount = 0;
        let skippedCount = 0;
        
        events.docs.forEach(doc => {
            const d = doc.data();
            // If slotsLeft is missing, add it
            if (d.slotsLeft === undefined || d.slotsLeft === null) {
                const capacity = d.capacity || 0;
                batch.update(doc.ref, { slotsLeft: capacity });
                fixedCount++;
            } else {
                skippedCount++;
            }
        });
        
        if (fixedCount > 0) {
            await batch.commit();
        }
        
        return {
            success: true,
            message: `Fixed ${fixedCount} events, ${skippedCount} already had slotsLeft`
        };
    } catch (error) {
        console.error('❌ Error fixing events:', error);
        return {
            success: false,
            error: error.message
        };
    }
});

// ─────────────────────────────────────────────
//  📊 GET EVENT STATS (Callable Function)
//  Call this to check how many events need fixing
// ─────────────────────────────────────────────
exports.getEventStats = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
    }
    
    try {
        const events = await admin.firestore().collection('events').get();
        let total = 0;
        let missingSlotsLeft = 0;
        let hasSlotsLeft = 0;
        let totalCapacity = 0;
        
        events.docs.forEach(doc => {
            const d = doc.data();
            total++;
            totalCapacity += (d.capacity || 0);
            
            if (d.slotsLeft === undefined || d.slotsLeft === null) {
                missingSlotsLeft++;
            } else {
                hasSlotsLeft++;
            }
        });
        
        return {
            success: true,
            totalEvents: total,
            eventsMissingSlotsLeft: missingSlotsLeft,
            eventsWithSlotsLeft: hasSlotsLeft,
            totalCapacity: totalCapacity
        };
    } catch (error) {
        return {
            success: false,
            error: error.message
        };
    }
});

// ─────────────────────────────────────────────
//  EXISTING EMAIL FUNCTIONS (Your original code)
// ─────────────────────────────────────────────

// Function for sending org credentials (for your existing admin screen)
exports.sendOrgCredentials = functions.https.onCall(async (data, context) => {
  // Security check - must be logged in
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }

  const { adviserEmail, orgName, username, password } = data;

  const mailOptions = {
    from: '"UPRISE System 🎓" <claudinejoysanjose@gmail.com>',
    to: adviserEmail,
    subject: `UPRISE – Login Credentials para sa ${orgName}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 500px; margin: auto;">
        <h2 style="color: #2c3e50;">Welcome to UPRISE!</h2>
        <p>Ang inyong organisasyon na <strong>${orgName}</strong> ay naka-register na sa sistema.</p>
        <hr/>
        <p><strong>Username:</strong> ${username}</p>
        <p><strong>Password:</strong> ${password}</p>
        <hr/>
        <p style="color: red;">⚠️ Palitan ang password pagkatapos mag-login.</p>
        <p>– UPRISE System, BulSU</p>
      </div>
    `,
  };

  try {
    await transporter.sendMail(mailOptions);
    return { success: true, message: "Email sent!" };
  } catch (error) {
    console.error("Error sending email:", error);
    throw new functions.https.HttpsError("internal", "Failed to send email.");
  }
});

// Optional: Test function to verify everything works
exports.testEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  
  const testEmail = data.testEmail || context.auth.token.email;
  
  const mailOptions = {
    from: '"UPRISE System 🎓" <claudinejoysanjose@gmail.com>',
    to: testEmail,
    subject: "✅ UPRISE Email Test",
    html: `
      <h2>Email System Test Successful!</h2>
      <p>Your UPRISE email system is working correctly.</p>
      <p>Tested at: ${new Date().toLocaleString()}</p>
      <p>You can now send credentials to users.</p>
    `
  };
  
  await transporter.sendMail(mailOptions);
  return { success: true, message: `Test email sent to ${testEmail}` };
});

// Shared by processQueuedEmail / processEmailQueue / onEmailQueued — builds
// the outgoing mail from an email_queue payload. Guest credential queue
// items (type: 'guest_credentials', written by
// external_account.dart's _queueGuestCredentialEmail) use guest_name /
// university instead of student_id — without this branch they fell through
// to the student-shaped subject/body with an undefined student ID.
function buildQueuedEmailMailOptions(payload) {
  const from = '"UPRISE System 🎓" <' + (process.env.GMAIL_USER || 'noreply@example.com') + '>';
  const to = payload.to_email;
  const password = payload.password;

  if (payload.type === 'guest_credentials') {
    const guestName = payload.guest_name || 'Guest';
    const isBulSUan = payload.classification === 'BulSUan';
    const detailsHtml = isBulSUan
      ? `<p><strong>College:</strong> ${payload.college || ''}</p>
        <p><strong>Year Level:</strong> ${payload.year_level || ''}</p>
        <p><strong>Section:</strong> ${payload.section || ''}</p>`
      : (payload.university ? `<p><strong>University/Affiliation:</strong> ${payload.university}</p>` : '');
    return {
      from: from,
      to: to,
      subject: `UPRISE – Guest Account Credentials for ${guestName}`,
      html: `<div style="font-family: Arial, sans-serif; max-width:500px; margin:auto;">
        <h2>UPRISE – Guest Account Approved</h2>
        <p>Your guest account has been approved.</p>
        <p><strong>Name:</strong> ${guestName}</p>
        ${detailsHtml}
        <p><strong>Email:</strong> ${to}</p>
        <p><strong>Temporary Password:</strong> ${password}</p>
        <p>Please change your password after first login.</p>
      </div>`
    };
  }

  const studentId = payload.student_id;
  return {
    from: from,
    to: to,
    subject: `UPRISE – Student Credentials for ${studentId}`,
    html: `<div style="font-family: Arial, sans-serif; max-width:500px; margin:auto;">
      <h2>UPRISE – Account Created</h2>
      <p>Your account has been created.</p>
      <p><strong>Student ID:</strong> ${studentId}</p>
      <p><strong>Password:</strong> ${password}</p>
      <p>Please change your password after first login.</p>
    </div>`
  };
}

// Callable function to process a single queued email
exports.processQueuedEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in.');
  }
  const docId = data.docId;
  if (!docId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing docId');
  }
  const docRef = admin.firestore().collection('email_queue').doc(docId);
  const snap = await docRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Queue item not found');
  }
  const payload = snap.data();
  const mailOptions = buildQueuedEmailMailOptions(payload);

  try {
    await transporter.sendMail(mailOptions);
    await docRef.delete();
    return { success: true };
  } catch (err) {
    console.error('Error processing queued email', err);
    await docRef.update({ attempts: (payload.attempts || 0) + 1, lastError: err.toString(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    throw new functions.https.HttpsError('internal', 'Failed to send email');
  }
});

// Scheduled function to process queued emails periodically
exports.processEmailQueue = functions.pubsub.schedule('every 5 minutes').onRun(async (context) => {
  const q = await admin.firestore().collection('email_queue').where('attempts', '<', 5).orderBy('createdAt').limit(20).get();
  const results = { processed: 0, failed: 0 };
  for (const doc of q.docs) {
    const payload = doc.data();
    const mailOptions = buildQueuedEmailMailOptions(payload);
    try {
      await transporter.sendMail(mailOptions);
      await doc.ref.delete();
      results.processed++;
    } catch (err) {
      console.error('Queue send failed for', doc.id, err);
      await doc.ref.update({ attempts: (payload.attempts || 0) + 1, lastError: err.toString(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      results.failed++;
    }
  }
  return results;
});

// ─────────────────────────────────────────────
//  ⏰ DAILY ORG REMINDERS (Scheduled)
//  Mirrors org_dashboard.dart's _checkReminders() (unpublished-event +
//  report-deadline reminders), which only ran client-side when an org
//  happened to open their dashboard, throttled to roughly once per 20h.
//  An org that didn't log in for a while got no reminder at all, right
//  when it mattered most. This runs once a day server-side instead, so
//  the reminders fire regardless of whether anyone opens the app.
// ─────────────────────────────────────────────
const DAY_MS = 24 * 60 * 60 * 1000;
const EVENT_NEAR_WINDOW_MS = 3 * DAY_MS;
const DEADLINE_NEAR_WINDOW_MS = 3 * DAY_MS;
const REMINDER_COOLDOWN_MS = 20 * 60 * 60 * 1000;

function cooldownElapsed(lastTs) {
  if (!lastTs) return true;
  return Date.now() - lastTs.toDate().getTime() > REMINDER_COOLDOWN_MS;
}

// Mirrors NotificationService._isEnabledFor (lib/services/notification_service.dart)
// so this scheduled job respects the same per-account mute toggle the app writes to.
async function isNotificationsEnabledFor(uid) {
  try {
    const doc = await admin.firestore()
      .collection('users').doc(uid)
      .collection('settings').doc('notifications')
      .get();
    const data = doc.data();
    if (!data) return true;
    return data.push_notifications !== false;
  } catch (e) {
    return true;
  }
}

// Mirrors NotificationService.sendToOrgMembers
async function sendToOrgMembers(orgId, title, body, type, extraData) {
  const membersSnap = await admin.firestore()
    .collection('users')
    .where('orgId', '==', orgId)
    .get();

  const enabledFlags = await Promise.all(
    membersSnap.docs.map((doc) => isNotificationsEnabledFor(doc.id))
  );

  const batch = admin.firestore().batch();
  membersSnap.docs.forEach((doc, i) => {
    if (!enabledFlags[i]) return;
    const ref = admin.firestore().collection('notifications').doc();
    batch.set(ref, {
      userId: doc.id,
      orgId: orgId,
      title: title,
      body: body,
      type: type,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: extraData || {},
    });
  });
  await batch.commit();
}

async function checkUnpublishedEventReminders(orgId) {
  const snap = await admin.firestore()
    .collection('event_proposals')
    .where('orgId', '==', orgId)
    .where('status', '==', 'approved')
    .get();

  const now = Date.now();
  for (const doc of snap.docs) {
    const data = doc.data();
    const publishedEventId = (data.publishedEventId || '').toString();
    if (publishedEventId) continue;

    const eventDate = data.date && data.date.toDate ? data.date.toDate() : null;
    if (!eventDate) continue;
    const msUntil = eventDate.getTime() - now;
    if (msUntil > EVENT_NEAR_WINDOW_MS || msUntil < 0) continue;

    if (!cooldownElapsed(data.lastPublishReminderAt)) continue;

    const title = (data.title || 'Your event').toString();
    const daysUntil = Math.floor(msUntil / DAY_MS);
    const daysLabel = daysUntil <= 0 ? 'today' : `in ${daysUntil} day${daysUntil === 1 ? '' : 's'}`;

    await sendToOrgMembers(
      orgId,
      'Event not yet published',
      `"${title}" is happening ${daysLabel} and still hasn't been published to students. Publish it from Event Proposals.`,
      'publish_reminder',
      { proposalId: doc.id }
    );
    await doc.ref.update({ lastPublishReminderAt: admin.firestore.FieldValue.serverTimestamp() });
  }
}

async function checkReportDeadlineReminders(orgId) {
  const eventsSnap = await admin.firestore()
    .collection('events')
    .where('orgId', '==', orgId)
    .where('status', '==', 'approved')
    .get();

  const now = Date.now();
  const finishedEvents = [];
  eventsSnap.docs.forEach((doc) => {
    const d = doc.data();
    const date = d.date && d.date.toDate ? d.date.toDate() : null;
    if (!date || date.getTime() >= now) return;
    finishedEvents.push({ id: doc.id, title: (d.title || 'Untitled Event').toString(), date: date });
  });
  if (finishedEvents.length === 0) return;

  const orgRef = admin.firestore().collection('organizations').doc(orgId);
  const orgDoc = await orgRef.get();
  const orgData = orgDoc.data() || {};

  async function checkOne(key, label) {
    const lastSentField = `last${key[0].toUpperCase()}${key.substring(1)}DeadlineReminderAt`;
    if (!cooldownElapsed(orgData[lastSentField])) return;

    const overrideDocs = await Promise.all(
      finishedEvents.map((ev) =>
        admin.firestore().collection('report_deadline_overrides').doc(`${orgId}_${ev.id}_${key}`).get()
      )
    );

    const withDeadlines = [];
    finishedEvents.forEach((ev, i) => {
      const overrideData = overrideDocs[i].data();
      const overrideDeadline = overrideData && overrideData.deadline ? overrideData.deadline.toDate() : null;
      const deadline = overrideDeadline || new Date(ev.date.getTime() + 7 * DAY_MS);
      const msUntil = deadline.getTime() - now;
      if (msUntil > DEADLINE_NEAR_WINDOW_MS || msUntil < 0) return;
      withDeadlines.push({ id: ev.id, title: ev.title, msUntil: msUntil });
    });
    if (withDeadlines.length === 0) return;

    const reportSnaps = await Promise.all(
      withDeadlines.map((ev) =>
        admin.firestore().collection('reports')
          .where('orgId', '==', orgId)
          .where('eventId', '==', ev.id)
          .where('type', '==', key)
          .limit(1)
          .get()
      )
    );

    for (let i = 0; i < withDeadlines.length; i++) {
      if (!reportSnaps[i].empty) continue;
      const ev = withDeadlines[i];
      const daysUntil = Math.floor(ev.msUntil / DAY_MS);
      const daysLabel = daysUntil <= 0 ? 'today' : `in ${daysUntil} day${daysUntil === 1 ? '' : 's'}`;
      await sendToOrgMembers(
        orgId,
        `${label} report deadline approaching`,
        `The ${label} report deadline for "${ev.title}" is ${daysLabel}. Submit it from Reports if you haven't already.`,
        'deadline_reminder'
      );
      await orgRef.update({ [lastSentField]: admin.firestore.FieldValue.serverTimestamp() });
      return;
    }
  }

  await checkOne('financial', 'Financial');
  await checkOne('accomplishment', 'Accomplishment');
}

exports.dailyOrgReminders = functions.pubsub
  .schedule('0 8 * * *')
  .timeZone('Asia/Manila')
  .onRun(async (context) => {
    const orgsSnap = await admin.firestore().collection('organizations').get();
    for (const orgDoc of orgsSnap.docs) {
      try {
        await checkUnpublishedEventReminders(orgDoc.id);
        await checkReportDeadlineReminders(orgDoc.id);
      } catch (e) {
        console.error(`Reminder check failed for org ${orgDoc.id}:`, e);
      }
    }
    return null;
  });

// Immediate processing: when a queue doc is created, attempt to send it right away.
// This ensures user-visible credential emails are attempted immediately instead
// of waiting for the 5-minute scheduled job.
exports.onEmailQueued = functions.firestore
  .document('email_queue/{docId}')
  .onCreate(async (snap, context) => {
    const payload = snap.data();
    if (!payload) return null;
    const docRef = snap.ref;
    const mailOptions = buildQueuedEmailMailOptions(payload);

    try {
      await transporter.sendMail(mailOptions);
      await docRef.delete();
      console.log('Queued email sent and removed:', docRef.id);
      return { success: true };
    } catch (err) {
      console.error('Immediate queue send failed for', docRef.id, err);
      await docRef.update({ attempts: (payload.attempts || 0) + 1, lastError: err.toString(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      return null;
    }
  });