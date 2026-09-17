// One-off maintenance script — NOT deployed, NOT wired into index.js.
//
// Backfills `portal: 'organization'` onto legacy `notifications` docs that
// were written by NotificationService.sendToOrgMembers() before the
// `portal` field existed (see lib/services/notification_service.dart and
// lib/screens/student/student_notifications_screen.dart). Those old docs
// have no `portal` field, so the student notifications screen's
// backward-compatible filter (missing portal = student-facing) still shows
// them to any student who is also tagged to an org via `orgId`.
//
// sendToOrgMembers is only ever called with these `type` values (verified
// by grepping every call site in the repo) — anything else is genuinely
// student-facing and must NOT be touched.
const ORG_BROADCAST_TYPES = [
  "publish_reminder",
  "deadline_reminder",
  "letter_status",
  "proposal_status",
  "proposal_revision",
  "announcement", // sendToOrgMembers's default `type` if ever called without one
];

const PROJECT_ID = "uprise-5eac8";
const BATCH_SIZE = 400; // Firestore batch cap is 500; leave headroom

const path = require("path");
const fs = require("fs");
const admin = require("firebase-admin");

const keyPath = path.join(__dirname, "serviceAccountKey.json");
if (fs.existsSync(keyPath)) {
  admin.initializeApp({
    credential: admin.credential.cert(require(keyPath)),
    projectId: PROJECT_ID,
  });
} else {
  // Falls back to `gcloud auth application-default login --project uprise-5eac8`
  // or a GOOGLE_APPLICATION_CREDENTIALS env var.
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();

async function main() {
  const snap = await db
      .collection("notifications")
      .where("type", "in", ORG_BROADCAST_TYPES)
      .get();

  const stale = snap.docs.filter((doc) => doc.get("portal") === undefined);

  console.log(`Scanned ${snap.size} matching-type doc(s); ${stale.length} need backfill.`);

  let updated = 0;
  for (let i = 0; i < stale.length; i += BATCH_SIZE) {
    const chunk = stale.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {portal: "organization"});
    }
    await batch.commit();
    updated += chunk.length;
    console.log(`  committed ${updated}/${stale.length}`);
  }

  console.log(`Done. Backfilled ${updated} legacy org notification doc(s).`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
