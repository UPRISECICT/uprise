// lib/services/student_data_export.dart
//
// "Download My Data" for students (Settings → Privacy & Security).
//
// Gathers everything the app holds about the signed-in student and hands it
// back as a shareable PDF. The document layout and share step are shared with
// the guest export in data_export_common.dart — only the queries differ,
// because guest records are email-keyed rather than uid-keyed.
//
// Every query below is a single-field equality already used elsewhere in the
// app, so none of them needs a composite Firestore index.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'data_export_common.dart';

/// Collects the student's records and shares them as a PDF.
Future<void> exportMyData(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You need to be signed in to export data')),
    );
    return;
  }

  final profileSnap = await FirebaseFirestore.instance
      .collection('students')
      .doc(user.uid)
      .get();
  if (!context.mounted) return;

  final profile = profileSnap.data() ?? {};
  final studentName = exportStr(
    profile['fullName'] ?? user.displayName ?? profile['firstName'],
  );
  final studentNo = exportStr(profile['studentId']);

  await runDataExport(
    context: context,
    subtitle: '$studentName · $studentNo',
    filenameSuffix: studentNo == '—' ? 'student' : studentNo,
    collect: () => _collect(user, profile),
  );
}

Future<List<ExportSection>> _collect(
  User user,
  Map<String, dynamic> profile,
) async {
  final db = FirebaseFirestore.instance;
  final uid = user.uid;

  // Four reads in parallel. Field names match the queries already used by
  // student_home_screen, student_feedback_screen and
  // student_certificates_screen.
  final results = await Future.wait([
    db.collection('registrations').where('userId', isEqualTo: uid).get(),
    db.collectionGroup('attendances').where('studentId', isEqualTo: uid).get(),
    db.collection('certificates').where('recipientUid', isEqualTo: uid).get(),
    db.collection('event_feedback').where('userId', isEqualTo: uid).get(),
  ]);

  final registrations = results[0].docs;
  final attendances = results[1].docs;
  final certificates = results[2].docs;
  final feedback = results[3].docs;

  Map<String, dynamic> d(QueryDocumentSnapshot doc) =>
      doc.data() as Map<String, dynamic>;

  return [
    ExportSection('Profile', const ['Field', 'Value'], [
      [
        'Full name',
        exportStr(
          profile['fullName'] ?? user.displayName ?? profile['firstName'],
        ),
      ],
      ['Student number', exportStr(profile['studentId'])],
      ['Email', exportStr(profile['email'] ?? user.email)],
      ['Course / Program', exportStr(profile['course'])],
      ['Year level', exportStr(profile['yearLevel'])],
      ['Major', exportStr(profile['major'])],
      ['College / Department', exportStr(profile['department'])],
      ['Campus', exportStr(profile['campus'])],
      ['Organization', exportStr(profile['orgName'] ?? profile['orgId'])],
    ]),
    ExportSection(
      'Event Registrations',
      const ['Event', 'Date', 'Attended'],
      registrations.map((doc) {
        final r = d(doc);
        return [
          exportStr(r['eventName'] ?? r['eventTitle']),
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
