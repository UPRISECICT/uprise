// lib/screens/web/admin/admin_message_reports.dart
// Review queue for message_reports, written by the report-message action on
// both the org side (org_broadcast.dart) and the student side
// (student_broadcast_screen.dart) of the private-messaging feature. This is
// the missing piece that was deliberately left out when reporting shipped —
// reports were being captured with nowhere for an admin to actually see or
// act on them.
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
import '../../../services/activity_logger.dart' as activity_log;

class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusPill = 100;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AdminMessageReports extends StatefulWidget {
  const AdminMessageReports({super.key});

  @override
  State<AdminMessageReports> createState() => _AdminMessageReportsState();
}

class _AdminMessageReportsState extends State<AdminMessageReports> {
  String _statusFilter = 'pending';

  Stream<QuerySnapshot> get _reportsStream {
    final base = FirebaseFirestore.instance
        .collection('message_reports')
        .orderBy('createdAt', descending: true);
    if (_statusFilter == 'all') return base.snapshots();
    return base.where('status', isEqualTo: _statusFilter).snapshots();
  }

  Future<void> _setStatus(String reportId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('message_reports')
          .doc(reportId)
          .update({
            'status': status,
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedBy': FirebaseAuth.instance.currentUser?.email ?? '',
          });
      await activity_log.ActivityLogger.log(
        action: 'Reviewed message report ($status)',
        module: 'message_reports',
        details: {'reportId': reportId, 'status': status},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'resolved'
                  ? 'Report marked resolved.'
                  : 'Report dismissed.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update report: $e')));
      }
    }
  }

  Future<void> _archiveStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Archive $name?',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This immediately signs $name out and blocks them from logging back in, same as archiving from Student Accounts. You can restore the account later from there.',
          style: GoogleFonts.beVietnamPro(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // students doc ID is the uid, same as the users doc ID — write both in
      // a batch so the login-time archived check (which reads `users`) stays
      // in sync with the admin-facing `students` record, mirroring
      // student_accounts.dart's _archiveRestoreStudent.
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('students').doc(studentId),
        {'archived': true},
      );
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(studentId),
        {'archived': true},
      );
      await batch.commit();
      await activity_log.ActivityLogger.log(
        action: 'Archived student from message report: $name',
        module: 'message_reports',
        details: {'studentId': studentId},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name has been archived.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to archive: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _resolveUser(String role, String id) async {
    if (id.isEmpty) return null;
    try {
      if (role == 'student') {
        final doc = await FirebaseFirestore.instance
            .collection('students')
            .doc(id)
            .get();
        if (!doc.exists) return null;
        return {'name': doc.data()?['name'] ?? 'Unknown student'};
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(id)
            .get();
        if (!doc.exists) return null;
        return {
          'name':
              doc.data()?['name'] ?? doc.data()?['orgName'] ?? 'Unknown org',
        };
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminColors.lightGray,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
            child: Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  color: AdminColors.primaryDark,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message Reports',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.darkText,
                        ),
                      ),
                      Text(
                        'Spam or inappropriate messages flagged by students and orgs from the private-messaging inbox.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: AdminColors.greyText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                for (final entry in const {
                  'pending': 'Pending',
                  'resolved': 'Resolved',
                  'dismissed': 'Dismissed',
                  'all': 'All',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        entry.value,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _statusFilter == entry.key
                              ? Colors.white
                              : AdminColors.darkText,
                        ),
                      ),
                      selected: _statusFilter == entry.key,
                      onSelected: (_) =>
                          setState(() => _statusFilter = entry.key),
                      selectedColor: AdminColors.primaryDark,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_DS.radiusPill),
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _reportsStream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 40,
                          color: AdminColors.greyText.withAlpha(140),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No ${_statusFilter == 'all' ? '' : _statusFilter} reports.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: AdminColors.greyText,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _ReportCard(
                      reportId: doc.id,
                      data: data,
                      resolveUser: _resolveUser,
                      onResolve: () => _setStatus(doc.id, 'resolved'),
                      onDismiss: () => _setStatus(doc.id, 'dismissed'),
                      onArchiveStudent: _archiveStudent,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final Future<Map<String, dynamic>?> Function(String role, String id)
  resolveUser;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;
  final void Function(String studentId, String name) onArchiveStudent;

  const _ReportCard({
    required this.reportId,
    required this.data,
    required this.resolveUser,
    required this.onResolve,
    required this.onDismiss,
    required this.onArchiveStudent,
  });

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending').toString();
    final reason = (data['reason'] ?? 'Other').toString();
    final details = (data['details'] ?? '').toString();
    final messageText = (data['messageText'] ?? '').toString();
    final reporterRole = (data['reporterRole'] ?? '').toString();
    final reportedUserId = (data['reportedUserId'] ?? '').toString();
    final reportedUserRole = (data['reportedUserRole'] ?? '').toString();
    final ts = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusBadge(status),
              const SizedBox(width: 8),
              _reasonChip(reason),
              const Spacer(),
              if (ts != null)
                Text(
                  DateFormat('MMM d, yyyy • h:mm a').format(ts),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: AdminColors.greyText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, dynamic>?>(
            future: resolveUser(reportedUserRole, reportedUserId),
            builder: (context, snap) {
              final name = snap.data?['name']?.toString() ?? reportedUserId;
              return Text.rich(
                TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: AdminColors.darkText,
                  ),
                  children: [
                    const TextSpan(text: 'Reported: '),
                    TextSpan(
                      text:
                          '$name (${reportedUserRole.isEmpty ? 'unknown' : reportedUserRole})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text:
                          '  —  flagged by a ${reporterRole.isEmpty ? 'user' : reporterRole}',
                      style: TextStyle(color: AdminColors.greyText),
                    ),
                  ],
                ),
              );
            },
          ),
          if (messageText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminColors.lightGray,
                borderRadius: BorderRadius.circular(_DS.radiusSm),
              ),
              child: Text(
                '"$messageText"',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AdminColors.darkText,
                ),
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Details: $details',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: AdminColors.greyText,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'pending') ...[
                ElevatedButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Mark Resolved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Dismiss'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.greyText,
                    textStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                    ),
                  ),
                ),
              ],
              if (reportedUserRole == 'student' && reportedUserId.isNotEmpty)
                FutureBuilder<Map<String, dynamic>?>(
                  future: resolveUser(reportedUserRole, reportedUserId),
                  builder: (context, snap) {
                    final name =
                        snap.data?['name']?.toString() ?? 'this student';
                    return OutlinedButton.icon(
                      onPressed: () => onArchiveStudent(reportedUserId, name),
                      icon: const Icon(Icons.block_rounded, size: 16),
                      label: const Text('Archive Student'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.error,
                        side: BorderSide(
                          color: AdminColors.error.withAlpha(140),
                        ),
                        textStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_DS.radiusSm),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final styles = {
      'pending': (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
      'resolved': (const Color(0xFFECFDF5), const Color(0xFF059669)),
      'dismissed': (const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
    };
    final (bg, fg) = styles[status] ?? styles['dismissed']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _reasonChip(String reason) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Text(
        reason,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AdminColors.error,
        ),
      ),
    );
  }
}
