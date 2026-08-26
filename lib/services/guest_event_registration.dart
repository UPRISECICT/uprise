// lib/services/guest_event_registration.dart
//
// Guest self-registration for events.
//
// Guests could always *see* public events but never sign up for one — their
// `registrations` rows were created org-side (QR check-in, manual forms).
// This is the missing client half, and it deliberately mirrors the student
// transaction in student_events_screen.dart rather than inventing a second
// registration protocol.
//
// Two things make guest registration different from student registration:
//
//  1. **Keying.** Every existing guest reader queries `registrations` by
//     `email` + `isGuest == true` (guest_registered_events_screen.dart,
//     guest_home_screen.dart, guest_feedback_screen.dart), while the org
//     portal branches on `isGuest`. Students are keyed by `userId`. The write
//     here carries *both* so neither side needs changing.
//
//  2. **Eligibility.** Guests are gated by classification, not by course or
//     org membership. `classificationAllowsAudience` is enforced here at the
//     write — not just in the browse filter — so reaching this code by direct
//     navigation can't get an Outsider into a BulSUan-only event. That was
//     always the stated intent of the helper; only the write side was missing.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/guest/guest_auth_service.dart';
import '../screens/guest/guest_events_screen.dart' show classificationAllowsAudience;

/// Why a guest can't register, or null when they can.
enum GuestRegistrationBlock {
  /// Browsing without an account — prompt the sign-in sheet instead.
  notSignedIn,

  /// Signed in but the approved record couldn't be resolved.
  notApproved,

  /// This event's audience excludes this guest's classification.
  notEligible,

  /// The event already finished.
  past,
}

class GuestIdentity {
  final String uid;
  final String docId;
  final String email;
  final String fullName;

  /// 'BulSUan' or 'Outsider'. Defaults to the most restrictive tier so a
  /// failed read can only ever narrow what a guest is allowed to join.
  final String classification;

  const GuestIdentity({
    required this.uid,
    required this.docId,
    required this.email,
    required this.fullName,
    required this.classification,
  });
}

/// Resolves the signed-in guest, or null for a visitor.
///
/// Requires both a Firebase Auth session and an approved `external_requests`
/// doc — [GuestAuthService] alone is a SharedPreferences cache and can outlive
/// the actual auth session.
Future<GuestIdentity?> resolveGuestIdentity() async {
  final svc = GuestAuthService();
  final user = FirebaseAuth.instance.currentUser;
  final docId = svc.docId;
  if (!svc.isAuthenticated || user == null || docId == null || docId.isEmpty) {
    return null;
  }
  try {
    final doc = await FirebaseFirestore.instance
        .collection('external_requests')
        .doc(docId)
        .get();
    final data = doc.data();
    if (data == null || data['status'] != 'approved') return null;
    return GuestIdentity(
      uid: user.uid,
      docId: docId,
      email: (data['email'] ?? svc.email ?? '').toString(),
      fullName: (data['userName'] ?? svc.fullName ?? '').toString(),
      classification: data['classification'] == 'BulSUan'
          ? 'BulSUan'
          : 'Outsider',
    );
  } catch (_) {
    return null;
  }
}

/// Deterministic id so a double-tap can't create two rows.
String guestRegistrationId(String uid, String eventId) => '${uid}_$eventId';

/// Whether this guest already holds a registration for [eventId].
Future<bool> isGuestRegistered({
  required String uid,
  required String eventId,
}) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('registrations')
        .doc(guestRegistrationId(uid, eventId))
        .get();
    return doc.exists;
  } catch (_) {
    return false;
  }
}

/// Registers [identity] for [eventId].
///
/// Throws a [GuestRegistrationBlock]-carrying [GuestRegistrationException] for
/// an expected refusal, or a plain [Exception] with a user-facing message for
/// capacity/duplicate cases.
Future<void> registerGuestForEvent({
  required GuestIdentity identity,
  required String eventId,
}) async {
  final db = FirebaseFirestore.instance;
  final regRef = db
      .collection('registrations')
      .doc(guestRegistrationId(identity.uid, eventId));
  final evRef = db.collection('events').doc(eventId);

  await db.runTransaction((tx) async {
    final regDoc = await tx.get(regRef);
    if (regDoc.exists) {
      throw Exception('You are already registered for this event.');
    }

    final evDoc = await tx.get(evRef);
    if (!evDoc.exists) throw Exception('Event not found.');
    final evData = evDoc.data() as Map<String, dynamic>;

    // Re-check eligibility against the *stored* audience rather than whatever
    // the caller's screen had cached, so a stale list can't widen access.
    final audience = (evData['audience'] ?? 'Public').toString();
    if (!classificationAllowsAudience(audience, identity.classification)) {
      throw const GuestRegistrationException(GuestRegistrationBlock.notEligible);
    }

    // Capacity is read from the event doc already fetched via tx.get() — a
    // .count() aggregation can't be read transactionally, so two guests
    // taking the last slot at the same instant would both pass it. Because
    // registeredCount is incremented in this same transaction, Firestore's
    // optimistic-concurrency retry actually protects this check.
    final capacity = (evData['capacity'] as num?)?.toInt();
    final registeredCount = (evData['registeredCount'] as num?)?.toInt() ?? 0;
    if (capacity != null && registeredCount >= capacity) {
      throw Exception(
        'This event has reached its maximum capacity of $capacity and is no '
        'longer accepting registrations.',
      );
    }

    tx.set(regRef, {
      // Student-shaped keys, so org tooling that joins on userId still works.
      'userId': identity.uid,
      'eventId': eventId,
      'registeredAt': FieldValue.serverTimestamp(),
      'status': 'registered',
      // Guest-shaped keys — what every existing guest reader queries on.
      'isGuest': true,
      'email': identity.email,
      'guestEmail': identity.email,
      'guestDocId': identity.docId,
      'studentName': identity.fullName,
    });
    tx.update(evRef, {'registeredCount': FieldValue.increment(1)});
  });
}

/// Releases a guest's slot, decrementing the counter symmetrically.
Future<void> cancelGuestRegistration({
  required String uid,
  required String eventId,
}) async {
  final db = FirebaseFirestore.instance;
  final regRef = db.collection('registrations').doc(guestRegistrationId(uid, eventId));
  final evRef = db.collection('events').doc(eventId);

  await db.runTransaction((tx) async {
    final regDoc = await tx.get(regRef);
    if (!regDoc.exists) return;
    tx.delete(regRef);
    // Guard against driving the counter negative if it ever drifts.
    final evDoc = await tx.get(evRef);
    final current = evDoc.data()?['registeredCount'] as num?;
    if ((current?.toInt() ?? 0) > 0) {
      tx.update(evRef, {'registeredCount': FieldValue.increment(-1)});
    }
  });
}

class GuestRegistrationException implements Exception {
  final GuestRegistrationBlock block;
  const GuestRegistrationException(this.block);

  String get message => switch (block) {
    GuestRegistrationBlock.notSignedIn =>
      'Sign in with an approved guest account to register.',
    GuestRegistrationBlock.notApproved =>
      'Your guest account is still awaiting admin approval.',
    GuestRegistrationBlock.notEligible =>
      "This event is limited to an audience your guest account isn't part of.",
    GuestRegistrationBlock.past => 'This event has already ended.',
  };

  @override
  String toString() => message;
}
