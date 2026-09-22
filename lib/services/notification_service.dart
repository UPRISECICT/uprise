import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final _db = FirebaseFirestore.instance;

  // Respects the recipient's `users/{uid}/settings/notifications` document
  // (the same doc org_settings.dart / student settings write to). Users who
  // never opened settings have no doc yet, so default to enabled.
  static Future<bool> _isEnabledFor(String userId) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('notifications')
          .get();
      final data = doc.data();
      if (data == null) return true;
      return (data['push_notifications'] ?? true) as bool;
    } catch (_) {
      return true;
    }
  }

  // Send a single notification to a specific user.
  //
  // [portal] tags which surface the notification belongs to so each portal
  // can filter to its own notifications. Values used today:
  //   'student'      – student-facing (default when omitted / null)
  //   'organization' – org-portal-facing
  //   'admin'        – admin-dashboard-facing
  // Existing documents without a portal field are treated as student-facing
  // by the student screen's client-side filter, so backfilling old rows is
  // not required.
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    String orgId = '',
    String orgName = '',
    String? portal,
    Map<String, dynamic>? data,
  }) async {
    if (!await _isEnabledFor(userId)) return;
    await _db.collection('notifications').add({
      'userId': userId,
      'orgId': orgId,
      'orgName': orgName,
      'title': title,
      'body': body,
      'type': type,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'data': data ?? {},
      if (portal != null) 'portal': portal,
    });
  }

  // Send a notification to just the org's own login account (role: 'org'),
  // not every member/officer tagged to it — used for private 1:1 messages,
  // where sendToOrgMembers's broadcast-to-everyone-tagged-to-this-org
  // behavior would leak a student's private message preview to every other
  // member and officer of the org via their own notification feed.
  static Future<void> sendToOrgAccount({
    required String orgId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    final snap = await _db
        .collection('users')
        .where('orgId', isEqualTo: orgId)
        .where('role', isEqualTo: 'org')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;
    await sendToUser(
      userId: snap.docs.first.id,
      title: title,
      body: body,
      type: type,
      orgId: orgId,
      data: data,
      portal: 'organization',
    );
  }

  // Send a notification to all members of an organization.
  // Tagged portal: 'organization' so student screens can filter them out.
  static Future<void> sendToOrgMembers({
    required String orgId,
    required String title,
    required String body,
    String type = 'announcement',
    Map<String, dynamic>? data,
  }) async {
    final membersSnap = await _db
        .collection('users')
        .where('orgId', isEqualTo: orgId)
        .get();

    final enabledFlags = await Future.wait(
      membersSnap.docs.map((doc) => _isEnabledFor(doc.id)),
    );

    final batch = _db.batch();
    for (var i = 0; i < membersSnap.docs.length; i++) {
      if (!enabledFlags[i]) continue;
      final doc = membersSnap.docs[i];
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'userId': doc.id,
        'orgId': orgId,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'data': data ?? {},
        'portal': 'organization',
      });
    }
    await batch.commit();
  }

  // Send a notification to every admin account. Admin notifications are
  // queried per-uid (see admin_dashboard.dart), so an org action that any
  // admin needs to see (a new submission, a resubmission, etc.) has to be
  // fanned out to each admin individually rather than sent once.
  static Future<void> sendToAllAdmins({
    required String title,
    required String body,
    String type = 'general',
    String orgId = '',
    Map<String, dynamic>? data,
  }) async {
    final adminsSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    final enabledFlags = await Future.wait(
      adminsSnap.docs.map((doc) => _isEnabledFor(doc.id)),
    );

    final batch = _db.batch();
    for (var i = 0; i < adminsSnap.docs.length; i++) {
      if (!enabledFlags[i]) continue;
      final doc = adminsSnap.docs[i];
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'userId': doc.id,
        'orgId': orgId,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'data': data ?? {},
        'portal': 'admin',
      });
    }
    await batch.commit();
  }

  // Send an event notification to everyone registered for an event.
  //
  // Reads the top-level `registrations` collection (`userId` + `eventId`).
  // This previously read an `events/{eventId}/attendees` subcollection that
  // nothing in the app has ever written to, so it silently resolved to zero
  // recipients — the method had no call sites, so that never surfaced.
  //
  // No `portal` field is set: absent means student-facing, matching the
  // filter in student_notifications_screen.dart and the Cloud Function.
  //
  // Note the campus-wide "new event published" broadcast and the pre-event
  // reminders are NOT sent from here — they run server-side in
  // functions/index.js (notifyStudentsOfNewEvent / studentEventReminders),
  // so a fan-out can't be left half-written by a browser tab closing.
  static Future<void> sendEventNotification({
    required String eventId,
    required String orgId,
    required String title,
    required String body,
    String type = 'event',
  }) async {
    final regsSnap = await _db
        .collection('registrations')
        .where('eventId', isEqualTo: eventId)
        .get();

    // One student could conceivably hold two registration rows; don't
    // notify them twice.
    final uids = regsSnap.docs
        .map((doc) => (doc.data()['userId'] ?? '').toString())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList();
    if (uids.isEmpty) return;

    final enabledFlags = await Future.wait(uids.map(_isEnabledFor));

    final batch = _db.batch();
    for (var i = 0; i < uids.length; i++) {
      if (!enabledFlags[i]) continue;
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'userId': uids[i],
        'orgId': orgId,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'data': {'eventId': eventId},
      });
    }
    await batch.commit();
  }

  // Mark a notification as read
  static Future<void> markAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  // Mark all notifications as read for a user
  static Future<void> markAllAsRead(String userId) async {
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // Stream unread notification count for a user
  static Stream<int> unreadCountStream(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // Stream notifications for a user. Deliberately NOT combining
  // `.orderBy('createdAt')` with the `.where('userId', ...)` filter, because
  // that pairing needs a composite index and the query throws
  // FAILED_PRECONDITION on every load without it. Callers must sort
  // client-side by `createdAt` themselves.
  //
  // The index IS declared in firestore.indexes.json (`notifications`:
  // userId ASC + createdAt DESC). Once `firebase deploy --only
  // firestore:indexes` has actually been run against the project, the
  // orderBy can move back into the query here and every caller's
  // client-side sort can go.
  static Stream<QuerySnapshot> notificationsStream(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(200)
        .snapshots();
  }
}