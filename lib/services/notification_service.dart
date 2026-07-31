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

  // Send a single notification to a specific user
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    String orgId = '',
    String orgName = '',
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
    });
  }

  // Send a notification to all members of an organization
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
    final adminsSnap =
        await _db.collection('users').where('role', isEqualTo: 'admin').get();

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
      });
    }
    await batch.commit();
  }

  // Send an event notification to all registered attendees
  static Future<void> sendEventNotification({
    required String eventId,
    required String orgId,
    required String title,
    required String body,
    String type = 'event',
  }) async {
    final attendeesSnap = await _db
        .collection('events')
        .doc(eventId)
        .collection('attendees')
        .get();

    final enabledFlags = await Future.wait(
      attendeesSnap.docs.map((doc) => _isEnabledFor(doc.id)),
    );

    final batch = _db.batch();
    for (var i = 0; i < attendeesSnap.docs.length; i++) {
      if (!enabledFlags[i]) continue;
      final doc = attendeesSnap.docs[i];
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'userId': doc.id,
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
    await _db
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
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
  // `.orderBy('createdAt')` with the `.where('userId', ...)` filter — that
  // pairing needs a composite Firestore index that isn't deployed for this
  // collection, and without it the query throws FAILED_PRECONDITION on
  // every load. Callers must sort client-side by `createdAt` themselves.
  static Stream<QuerySnapshot> notificationsStream(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(200)
        .snapshots();
  }
}
