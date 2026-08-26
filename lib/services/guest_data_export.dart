// lib/services/guest_data_export.dart
//
// "Download My Data" for approved guests (Settings → Privacy & Security).
//
// Same document as the student export, different keys. Guest records aren't
// keyed by uid the way students' are:
//
//   profile       external_requests/{docId}
//   registrations email == guestEmail && isGuest == true
//   attendance    collectionGroup('attendances') where guestEmail
//   certificates  recipientEmail == guestEmail && isGuest == true
//   feedback      email/userId == guestEmail
//
// Every query is a single-field equality (the two-field ones mirror queries
// the guest screens already run), so none needs a new composite index.
//
// Only offered to *approved* guests. A visitor has no permanent record to
// export, which is what the settings screen's own copy says.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data_export_common.dart';
import 'guest_event_registration.dart';

Future<void> exportGuestData(BuildContext context) async {
  final identity = await resolveGuestIdentity();
  if (!context.mounted) return;

  if (identity == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You need an approved guest account to export your data.',
        ),
      ),
    );
    return;
  }

  await runDataExport(
    context: context,
    subtitle: '${identity.fullName} · ${identity.email}',
    filenameSuffix: identity.email.split('@').first,
    collect: () => _collect(identity),
  );
}

Future<List<ExportSection>> _collect(GuestIdentity identity) async {
  final db = FirebaseFirestore.instance;
  final email = identity.email;

  final results = await Future.wait([
    db.collection('external_requests').doc(identity.docId).get(),
    db.collection('registrations').where('email', isEqualTo: email).get(),
    db.collectionGroup('attendances').where('guestEmail', isEqualTo: email).get(),
    db.collection('certificates').where('recipientEmail', isEqualTo: email).get(),
    db.collection('event_feedback').where('email', isEqualTo: email).get(),
  ]);

  final profile =
      (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {};

  // isGuest is filtered client-side so each query above stays single-field.
  List<QueryDocumentSnapshot> guestOnly(dynamic snap) => (snap as QuerySnapshot)
      .docs
      .where((d) => (d.data() as Map<String, dynamic>)['isGuest'] != false)
      .toList();

  final registrations = guestOnly(results[1]);
  final attendances = (results[2] as QuerySnapshot).docs;
  final certificates = guestOnly(results[3]);
  final feedback = (results[4] as QuerySnapshot).docs;

  Map<String, dynamic> d(QueryDocumentSnapshot doc) =>
      doc.data() as Map<String, dynamic>;

  return [
    ExportSection('Profile', const ['Field', 'Value'], [
      ['Full name', exportStr(profile['userName'] ?? identity.fullName)],
      ['Email', exportStr(profile['email'] ?? email)],
      ['Classification', exportStr(profile['classification'])],
      ['Affiliation', exportStr(profile['affiliation'])],
      ['School / University', exportStr(profile['university'])],
      ['College', exportStr(profile['college'])],
      ['Year level', exportStr(profile['yearLevel'])],
      ['Section', exportStr(profile['section'])],
      ['Phone', exportStr(profile['phone'])],
      ['Purpose', exportStr(profile['purpose'])],
      ['Account status', exportStr(profile['status'])],
      ['Requested', fmtExportDate(profile['requestDate'])],
    ]),
    ExportSection(
      'Event Registrations',
      const ['Event', 'Date', 'Attended'],
      registrations.map((doc) {
        final r = d(doc);
        return [
          exportStr(r['eventName'] ?? r['eventTitle'] ?? r['eventId']),
          fmtExportDate(r['eventDate'] ?? r['registeredAt'] ?? r['createdAt']),
          (r['attended'] == true) ? 'Yes' : 'No',
        ];
      }).toList(),
    ),
    ExportSection(
      'Attendance',
      const ['Event', 'Status', 'Recorded'],
      attendances.map((doc) {
        final a = d(doc);
        return [
          exportStr(a['eventName'] ?? a['eventTitle']),
          exportStr(a['status']),
          fmtExportDate(a['timestamp'] ?? a['checkedInAt'] ?? a['createdAt']),
        ];
      }).toList(),
    ),
    ExportSection(
      'Certificates',
      const ['Event', 'Issued', 'Verification code'],
      certificates.map((doc) {
        final c = d(doc);
        return [
          exportStr(c['eventName']),
          fmtExportDate(c['issuedAt'] ?? c['createdAt']),
          exportStr(c['verificationCode']),
        ];
      }).toList(),
    ),
    ExportSection(
      'Event Feedback',
      const ['Event', 'Rating', 'Comment'],
      feedback.map((doc) {
        final f = d(doc);
        return [
          exportStr(f['eventName']),
          exportStr(f['rating']),
          exportStr(f['comment']),
        ];
      }).toList(),
    ),
  ];
}
