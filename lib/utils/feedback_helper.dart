// lib/utils/feedback_helper.dart
//
// Shared reads and writes for event feedback.
//
// Event feedback lives in TWO collections because of an incomplete migration,
// as org_event_analytics.dart documents: the "rate this event" notification —
// the path most students actually use — writes to the older `feedback`, while
// the event-details form, the standalone feedback screen and the guest form
// write to `event_feedback`. Reading only one of them shows a student an
// incomplete (usually empty) history, so everything here reads both and
// de-duplicates. New writes all go to `event_feedback`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedbackHelper {
  /// The reviewer's display name, for storing on a review they chose to
  /// attribute. Returns `''` when it can't be resolved — callers then omit
  /// `authorName` rather than writing a placeholder.
  static Future<String> currentStudentReviewerName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    final authName = (user.displayName ?? '').trim();
    if (authName.isNotEmpty) return authName;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();
      final d = doc.data() ?? {};
      final full = (d['fullName'] ?? '').toString().trim();
      if (full.isNotEmpty) return full;
      final joined = [
        (d['firstName'] ?? '').toString().trim(),
        (d['lastName'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty).join(' ');
      if (joined.isNotEmpty) return joined;
    } catch (_) {
      // A profile read failure shouldn't block the review — fall through.
    }

    return (user.email ?? '').split('@').first;
  }

  /// Every review [userId] has submitted, keyed by `eventId`.
  ///
  /// Unions both collections. When the same event appears in both, the
  /// `event_feedback` copy wins: it carries the fuller shape (orgId,
  /// organization, isAnonymous) that the legacy documents lack.
  static Future<Map<String, Map<String, dynamic>>> loadMyFeedback(
    String userId,
  ) async {
    if (userId.isEmpty) return {};
    final db = FirebaseFirestore.instance;

    final snapshots = await Future.wait([
      db.collection('feedback').where('userId', isEqualTo: userId).get(),
      db.collection('event_feedback').where('userId', isEqualTo: userId).get(),
    ]);

    final out = <String, Map<String, dynamic>>{};
    // Legacy first so the richer event_feedback documents overwrite it.
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final eventId = (data['eventId'] ?? '').toString();
        if (eventId.isEmpty) continue;
        data['id'] = doc.id;
        data['sourceCollection'] = doc.reference.parent.id;
        out[eventId] = data;
      }
    }
    return out;
  }

  /// Event ids [userId] has already reviewed, across both collections.
  static Future<Set<String>> ratedEventIds(String userId) async =>
      (await loadMyFeedback(userId)).keys.toSet();

  /// Whether this student has already reviewed this event.
  static Future<bool> hasStudentGivenFeedback({
    required String studentId,
    required String eventId,
  }) async {
    if (studentId.isEmpty || eventId.isEmpty) return false;
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db
            .collection('feedback')
            .where('userId', isEqualTo: studentId)
            .where('eventId', isEqualTo: eventId)
            .limit(1)
            .get(),
        db
            .collection('event_feedback')
            .where('userId', isEqualTo: studentId)
            .where('eventId', isEqualTo: eventId)
            .limit(1)
            .get(),
      ]);
      return results.any((r) => r.docs.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// The timestamp a review was submitted, from whichever field its collection
  /// used. Null when the write is still round-tripping its server timestamp.
  static DateTime? submittedAt(Map<String, dynamic> data) {
    final ts = data['submittedAt'] ?? data['timestamp'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  /// The event's title, from whichever field its collection used —
  /// `event_feedback` stores `eventName`, legacy `feedback` stores `eventTitle`.
  static String eventTitle(Map<String, dynamic> data) {
    final name = (data['eventName'] ?? data['eventTitle'] ?? '')
        .toString()
        .trim();
    return name.isEmpty ? 'Event' : name;
  }
}
