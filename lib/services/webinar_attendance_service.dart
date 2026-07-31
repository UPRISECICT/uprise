// Rotating-code attendance for online events (webinars), as a counterpart to
// the QR-scan flow used for face-to-face events.
//
// Reuses the same `events/{eventDocId}/attendances` collection and field
// names (`studentId`, `studentName`, `status`, `timestamp`, ...) that
// org_attendance_qr.dart's QR/manual flow already writes to, so a webinar
// check-in shows up in the exact same attendance table/exports — just with
// `method: 'webinar_code'` instead of `'qr'`/`'manual'`. Subcollections used:
//
//   events/{eventDocId}/webinarSession/current     — session state (single doc)
//   events/{eventDocId}/webinarCode/{checkin|checkout} — the *current* code
//                                                         for that phase (one
//                                                         doc per phase, kept
//                                                         up to date by
//                                                         rotateCode — not a
//                                                         growing history)
//   events/{eventDocId}/codeSubmissions            — audit log of every
//                                                     submission attempt,
//                                                     successful or not
//
// The rotation timer itself runs client-side, on whichever organizer screen
// has this tab open (see org_attendance_qr.dart _WebinarCodePanelState) —
// there's no server-side scheduler. If two organizer tabs/windows are open
// on the same event, both independently notice the same code expiring and
// both call rotateCode() at nearly the same moment. rotateCode() guards
// against that with a transaction on the single per-phase doc: Firestore
// serializes concurrent transactions on the same document, so the second
// caller's retry sees the first caller's already-written code and skips —
// without this, both writes would land and the displayed code would flip
// twice within the same second.
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';

class WebinarAttendanceService {
  static final Random _rng = Random.secure();

  static String generateCode({int length = 6}) {
    // Excludes visually ambiguous characters (0/O, 1/I) since this gets read
    // off a screen and typed back in.
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    return List.generate(
      length,
      (_) => chars[_rng.nextInt(chars.length)],
    ).join();
  }

  static DocumentReference<Map<String, dynamic>> _sessionRef(
    String eventDocId,
  ) => FirebaseFirestore.instance
      .collection('events')
      .doc(eventDocId)
      .collection('webinarSession')
      .doc('current');

  static DocumentReference<Map<String, dynamic>> _codeDocRef(
    String eventDocId,
    String type,
  ) => FirebaseFirestore.instance
      .collection('events')
      .doc(eventDocId)
      .collection('webinarCode')
      .doc(type);

  static CollectionReference<Map<String, dynamic>> _submissionsRef(
    String eventDocId,
  ) => FirebaseFirestore.instance
      .collection('events')
      .doc(eventDocId)
      .collection('codeSubmissions');

  static Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(
    String eventDocId,
  ) => _sessionRef(eventDocId).snapshots();

  static Stream<DocumentSnapshot<Map<String, dynamic>>> codeStream(
    String eventDocId,
    String type,
  ) => _codeDocRef(eventDocId, type).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> submissionsStream(
    String eventDocId,
  ) => _submissionsRef(
    eventDocId,
  ).orderBy('timestamp', descending: true).limit(50).snapshots();

  // ── Organizer: session lifecycle ──────────────────────────────────────────

  static Future<void> startSession({
    required String eventDocId,
    required String startedBy,
    required int intervalMinutes,
    required bool requireCheckOut,
  }) async {
    await _sessionRef(eventDocId).set({
      'isActive': true,
      'phase': 'checkin',
      'intervalMinutes': intervalMinutes,
      'requireCheckOut': requireCheckOut,
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': null,
      'startedBy': startedBy,
    });
    await rotateCode(eventDocId, 'checkin', intervalMinutes);
  }

  static Future<void> rotateCode(
    String eventDocId,
    String type,
    int intervalMinutes,
  ) async {
    final docRef = _codeDocRef(eventDocId, type);
    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      final now = DateTime.now();
      if (snap.exists) {
        final existingExpiresAt = (snap.data()?['expiresAt'] as Timestamp?)
            ?.toDate();
        // Another caller (e.g. a second organizer tab on the same event)
        // already rotated this phase for the current window — skip so the
        // code doesn't flip twice in quick succession.
        if (existingExpiresAt != null && now.isBefore(existingExpiresAt))
          return;
      }
      txn.set(docRef, {
        'code': generateCode(),
        'type': type,
        'startsAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(
          now.add(Duration(minutes: intervalMinutes)),
        ),
      });
    });
  }

  static Future<void> startCheckOutPhase(
    String eventDocId,
    int intervalMinutes,
  ) async {
    await _sessionRef(eventDocId).update({'phase': 'checkout'});
    await rotateCode(eventDocId, 'checkout', intervalMinutes);
  }

  static Future<void> endSession(String eventDocId) async {
    await _sessionRef(
      eventDocId,
    ).update({'isActive': false, 'endedAt': FieldValue.serverTimestamp()});
  }

  // ── Student: submit a code ────────────────────────────────────────────────
  //
  // Returns one of: 'success', 'session_inactive', 'no_active_code',
  // 'expired', 'invalid_code', 'duplicate', 'not_checked_in',
  // 'not_registered', 'error'. Every attempt is recorded to codeSubmissions
  // regardless of outcome, so organizers can audit failed attempts too.
  static Future<String> submitCode({
    required String eventDocId,
    required String studentUid,
    required String submittedCode,
    required String type, // 'checkin' | 'checkout'
  }) async {
    final cleaned = submittedCode.trim().toUpperCase();
    String result;

    // Fetched once and reused for both the attendance record (checkin) and
    // the codeSubmissions audit log below — avoids reading the same
    // `students` doc twice per submission. Name/email live on `students`
    // (doc ID = uid) — `users` only has uid/email/fullName/role.
    Map<String, dynamic>? studentData;
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(studentUid)
          .get();
      studentData = studentDoc.data();
    } catch (_) {}

    try {
      final sessionSnap = await _sessionRef(eventDocId).get();
      final session = sessionSnap.data();
      if (session == null ||
          session['isActive'] != true ||
          session['phase'] != type) {
        result = 'session_inactive';
      } else {
        final codeSnap = await _codeDocRef(eventDocId, type).get();
        if (!codeSnap.exists) {
          result = 'no_active_code';
        } else {
          final codeData = codeSnap.data()!;
          final now = DateTime.now();
          final startsAt = (codeData['startsAt'] as Timestamp).toDate();
          final expiresAt = (codeData['expiresAt'] as Timestamp).toDate();
          if (now.isBefore(startsAt) || now.isAfter(expiresAt)) {
            result = 'expired';
          } else if ((codeData['code'] as String).toUpperCase() != cleaned) {
            result = 'invalid_code';
          } else {
            result = await _recordAttendance(
              eventDocId,
              studentUid,
              type,
              studentData,
            );
          }
        }
      }
    } catch (_) {
      result = 'error';
    }

    final studentName =
        (studentData?['fullName'] ?? studentData?['email'] ?? 'Unknown')
            .toString();
    final studentEmail = (studentData?['email'] ?? '').toString();

    await _submissionsRef(eventDocId).add({
      'studentId': studentUid,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'submittedCode': cleaned,
      'type': type,
      'result': result,
      // Same reasoning as rotateCode() above — submissionsStream() orders by
      // this field, so a concrete client timestamp avoids the same flicker.
      'timestamp': Timestamp.fromDate(DateTime.now()),
    });

    return result;
  }

  static Future<String> _recordAttendance(
    String eventDocId,
    String studentUid,
    String type,
    Map<String, dynamic>? studentData,
  ) async {
    // Deterministic doc ID (one attendance record per student per event, same
    // convention as org_attendance_qr.dart's QR/manual flow) instead of an
    // auto-generated one — a get-then-add on an auto ID leaves a race window
    // where two near-simultaneous submissions can both pass the "not yet
    // marked" check before either write commits, producing duplicate rows.
    final attRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventDocId)
        .collection('attendances')
        .doc(studentUid);

    if (type == 'checkin') {
      if ((await attRef.get()).exists) return 'duplicate';

      if (studentData == null) return 'not_registered';

      // Registration docs are keyed deterministically as `${uid}_${eventId}`
      // (see student_events_screen.dart's register flow) — a direct doc get
      // is enough, no query needed. Without this, anyone with the rotating
      // code could check into an event they never signed up for.
      final regDoc = await FirebaseFirestore.instance
          .collection('registrations')
          .doc('${studentUid}_$eventDocId')
          .get();
      if (!regDoc.exists) return 'not_registered';

      await attRef.set({
        'studentId': studentUid,
        'studentName':
            studentData['fullName'] ?? studentData['email'] ?? 'Unknown',
        'studentEmail': studentData['email'] ?? '',
        'program': studentData['course'] ?? 'N/A',
        'yearLevel': studentData['yearLevel'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'present',
        'method': 'webinar_code',
      });

      // Wrapped so a notification failure never undoes or blocks attendance
      // that was already recorded — mirrors org_attendance_qr.dart's QR/
      // manual check-in, which already notifies; this path silently didn't.
      try {
        final eventDoc = await FirebaseFirestore.instance
            .collection('events')
            .doc(eventDocId)
            .get();
        final eventTitle =
            (eventDoc.data()?['title'] as String?) ?? 'the event';
        final orgId = (eventDoc.data()?['orgId'] as String?) ?? '';
        await NotificationService.sendToUser(
          userId: studentUid,
          title: "You're Marked Present!",
          body: 'You\'ve been marked present for "$eventTitle".',
          type: 'event',
          orgId: orgId,
          data: {'eventId': eventDocId, 'status': 'present'},
        );
      } catch (_) {}

      return 'success';
    } else {
      final snap = await attRef.get();
      if (!snap.exists) return 'not_checked_in';
      if (snap.data()?['checkOutAt'] != null) return 'duplicate';
      await attRef.update({'checkOutAt': FieldValue.serverTimestamp()});
      return 'success';
    }
  }
}
