const functions = require("firebase-functions");
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
  const to = payload.to_email;
  const studentId = payload.student_id;
  const password = payload.password;

  const mailOptions = {
    from: '"UPRISE System 🎓" <' + (process.env.GMAIL_USER || 'noreply@example.com') + '>',
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
    const to = payload.to_email;
    const studentId = payload.student_id;
    const password = payload.password;
    const mailOptions = {
      from: '"UPRISE System 🎓" <' + (process.env.GMAIL_USER || 'noreply@example.com') + '>',
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

// Immediate processing: when a queue doc is created, attempt to send it right away.
// This ensures user-visible credential emails are attempted immediately instead
// of waiting for the 5-minute scheduled job.
exports.onEmailQueued = functions.firestore
  .document('email_queue/{docId}')
  .onCreate(async (snap, context) => {
    const payload = snap.data();
    if (!payload) return null;
    const to = payload.to_email;
    const studentId = payload.student_id;
    const password = payload.password;
    const docRef = snap.ref;

    const mailOptions = {
      from: '"UPRISE System 🎓" <' + (process.env.GMAIL_USER || 'noreply@example.com') + '>',
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