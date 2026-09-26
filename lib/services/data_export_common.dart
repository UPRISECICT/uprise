// lib/services/data_export_common.dart
//
// The shared half of "Download My Data".
//
// Students and guests hold different records under different keys, so each
// role has its own collector. What they *don't* need to differ on is the
// document: same sections-and-tables layout, same empty-state wording, same
// save step. That all lives here.
//
// Kept out of app_support.dart deliberately — that file is imported by both
// roles' settings screens and shouldn't take on the pdf/printing dependency.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/download_saver.dart';

/// One exported section: a title, column headers, and the rows to print.
class ExportSection {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  const ExportSection(this.title, this.headers, this.rows);
}

String fmtExportDate(dynamic value) {
  if (value is Timestamp) {
    return DateFormat('MMM dd, yyyy').format(value.toDate());
  }
  if (value is DateTime) return DateFormat('MMM dd, yyyy').format(value);
  final s = (value ?? '').toString().trim();
  return s.isEmpty ? '—' : s;
}

String exportStr(dynamic value) {
  final s = (value ?? '').toString().trim();
  return s.isEmpty ? '—' : s;
}

/// Runs [collect] behind a modal spinner and saves the resulting PDF straight
/// to the phone's Downloads folder — it used to open the share sheet instead.
///
/// The dialog is popped exactly once: a failure while saving happens *after*
/// the dialog is dismissed, so an unguarded pop in the catch would take the
/// underlying screen down with it.
Future<void> runDataExport({
  required BuildContext context,
  required String subtitle,
  required String filenameSuffix,
  required Future<List<ExportSection>> Function() collect,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  var dialogOpen = true;
  void closeDialog() {
    if (!dialogOpen) return;
    dialogOpen = false;
    navigator.pop();
  }

  try {
    final sections = await collect();
    final bytes = await buildExportPdf(sections: sections, subtitle: subtitle);
    closeDialog();
    final saved = await saveToDownloads(
      bytes,
      'UPRISE_MyData_$filenameSuffix.pdf',
    );
    await announceDownload(messenger, saved);
  } catch (e) {
    closeDialog();
    messenger.showSnackBar(
      SnackBar(content: Text('Could not export your data: $e')),
    );
  }
}

Future<Uint8List> buildExportPdf({
  required List<ExportSection> sections,
  required String subtitle,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          'UPRISE — My Data',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          subtitle,
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.Text(
          'Exported ${DateFormat('MMM dd, yyyy · h:mm a').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 18),
        for (final section in sections) ...[
          pw.Text(
            section.title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          // An explicit "None on record" beats an empty table with only a
          // header row, which reads like something failed to load.
          if (section.rows.isEmpty)
            pw.Text(
              'None on record.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: section.headers,
              data: section.rows,
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellHeight: 18,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            ),
          pw.SizedBox(height: 18),
        ],
      ],
    ),
  );
  return doc.save();
}
