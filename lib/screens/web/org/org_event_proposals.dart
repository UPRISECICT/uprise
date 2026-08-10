// ignore_for_file: unused_field, duplicate_ignore, use_build_context_synchronously, deprecated_member_use
import 'dart:convert';
import 'dart:async';
import '../../../utils/platform_file_utils.dart' as platform_file_utils;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/org_attachment_preview.dart';
import '../../../widgets/org_modal_shell.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import '../../../theme/org_theme.dart';
import '../../../utils/school_year.dart';
import 'org_form_builder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper: get user full name from UID
// ─────────────────────────────────────────────────────────────────────────────
Future<String> _getUserName(String uid) async {
  if (uid.isEmpty) return '—';
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists) {
      final data = doc.data();
      // Try various possible field names
      final name = data?['fullName'] ?? data?['displayName'] ?? data?['name'];
      if (name != null && name.toString().isNotEmpty) {
        return name.toString();
      }
    }
  } catch (_) {}
  return uid; // fallback to UID
}

bool _isImageAttachment(Map<String, dynamic> data) {
  final name = data['attachmentName'] as String?;
  if (name == null) return false;
  final ext = name.split('.').last.toLowerCase();
  return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
}

Widget _buildImageFromBase64(
  String base64, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  try {
    final bytes = base64Decode(base64);
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  } catch (e) {
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge
// ─────────────────────────────────────────────────────────────────────────────
class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

Widget _statusBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'approved': _BadgeStyle(
      const Color(0xFFECFDF5),
      const Color(0xFF059669),
      'APPROVED',
    ),
    'pending': _BadgeStyle(
      const Color(0xFFFFFBEB),
      const Color(0xFFFB923C),
      'PENDING',
    ),
    'rejected': _BadgeStyle(
      const Color(0xFFFEF2F2),
      const Color(0xFFDC2626),
      'REJECTED',
    ),
    'for_review': _BadgeStyle(
      const Color(0xFFEFF6FF),
      const Color(0xFF2563EB),
      'FOR REVIEW',
    ),
  };
  final s =
      styles[status.toLowerCase()] ??
      _BadgeStyle(
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        status.toUpperCase(),
      );
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: s.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      s.label,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: s.fg,
        letterSpacing: 0.8,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Category badge — same palette as admin_dashboard.dart's
// _categoryBadgeColors / event_calendar.dart's _categoryColors, kept
// identical value-for-value so a category reads as the same color
// everywhere it shows up (admin, org dashboard, and here). Previously this
// page rendered every category in one flat brand-orange pill, which read
// as "everything is highlighted" since nothing visually distinguished a
// Workshop from a Competition from a Cultural event.
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, Color> _categoryBadgeColors = {
  'Workshop': Color(0xFF8B5CF6),
  'Seminar': Color(0xFF3B82F6),
  'Competition': Color(0xFFEF4444),
  'General Assembly': Color(0xFFF97316),
  'Social': Color(0xFFEC4899),
  'Outreach': Color(0xFF10B981),
  'Sports': Color(0xFF14B8A6),
  'Academic': Color(0xFF6366F1),
  'Technical': Color(0xFF06B6D4),
  'Cultural': Color(0xFFD946EF),
};

Color _categoryBadgeColor(String category) {
  return _categoryBadgeColors[category] ?? const Color(0xFF6B7280);
}

// Pastel bg / solid fg pair per category — same values as
// event_calendar.dart / org_events_schedule.dart's CategoryColors, so a
// category's table badge here reads as the same color as its calendar chip.
class CategoryColors {
  static const Map<String, Color> bg = {
    'Workshop': Color(0xFFEDE9FE),
    'Seminar': Color(0xFFDBEAFE),
    'Competition': Color(0xFFFEE2E2),
    'General Assembly': Color(0xFFFFEDD5),
    'Social': Color(0xFFFCE7F3),
    'Outreach': Color(0xFFD1FAE5),
    'Sports': Color(0xFFCCFBF1),
    'Academic': Color(0xFFE0E7FF),
    'Technical': Color(0xFFCFFAFE),
    'Cultural': Color(0xFFFAE8FF),
    'Other': Color(0xFFF3F4F6),
  };
  static const Map<String, Color> fg = {
    'Workshop': Color(0xFF6D28D9),
    'Seminar': Color(0xFF1D4ED8),
    'Competition': Color(0xFFB91C1C),
    'General Assembly': Color(0xFFC2410C),
    'Social': Color(0xFFBE185D),
    'Outreach': Color(0xFF047857),
    'Sports': Color(0xFF0F766E),
    'Academic': Color(0xFF4338CA),
    'Technical': Color(0xFF0E7490),
    'Cultural': Color(0xFFA21CAF),
    'Other': Color(0xFF374151),
  };
  static Color getBg(String cat) => bg[cat] ?? bg['Other']!;
  static Color getFg(String cat) => fg[cat] ?? fg['Other']!;
}

Widget _categoryBadge(String category) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: CategoryColors.getBg(category),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      category,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: CategoryColors.getFg(category),
        letterSpacing: 0.2,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label helper
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: UpriseColors.darkGray),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: UpriseColors.charcoal,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Input decoration helper
// ─────────────────────────────────────────────────────────────────────────────
InputDecoration _orgEventProposalsInputDecoration(
  String label, {
  String? hint,
  IconData? icon,
}) {
  // Required fields are labeled "Foo *" — the asterisk used to render in the
  // same muted gray as the rest of the label and was easy to miss. Splitting
  // it into its own red TextSpan (via `label:` instead of plain `labelText:`)
  // makes it actually stand out.
  final trimmed = label.trimRight();
  final isRequired = trimmed.endsWith('*');
  final baseLabel = isRequired
      ? trimmed.substring(0, trimmed.length - 1).trimRight()
      : label;

  return InputDecoration(
    labelText: isRequired ? null : label,
    label: isRequired
        ? RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: baseLabel,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
                TextSpan(
                  text: ' *',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: UpriseColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        : null,
    hintText: hint,
    prefixIcon: icon != null
        ? Icon(icon, size: 18, color: const Color(0xFF9AA5B4))
        : null,
    labelStyle: GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF64748B),
    ),
    hintStyle: GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF9AA5B4),
    ),
    filled: true,
    fillColor: const Color(0xFFF8F9FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: BorderSide(color: UpriseColors.error, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: BorderSide(color: UpriseColors.error, width: 1.5),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgEventProposalsScreen extends StatefulWidget {
  final String orgId;
  const OrgEventProposalsScreen({super.key, required this.orgId});

  @override
  State<OrgEventProposalsScreen> createState() =>
      _OrgEventProposalsScreenState();
}

class _OrgEventProposalsScreenState extends State<OrgEventProposalsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Proposals currently being published, to guard against double-tap duplicates
  final Set<String> _publishingIds = {};

  // ── Streams ──────────────────────────────────────────────────────
  // Created once, not getters — these only ever depend on widget.orgId
  // (fixed for this screen's lifetime), so re-evaluating .snapshots() on
  // every rebuild (typing in search, switching tabs, opening a modal) was
  // tearing down and re-subscribing all 5 Firestore listeners every time.
  late final Stream<QuerySnapshot> _allStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .snapshots();

  late final Stream<QuerySnapshot> _pendingStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'pending')
      .snapshots();

  late final Stream<QuerySnapshot> _approvedStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .snapshots();

  late final Stream<QuerySnapshot> _forReviewStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'for_review')
      .snapshots();

  late final Stream<QuerySnapshot> _proposalsStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .orderBy('submittedAt', descending: true)
      .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filters ───────────────────────────────────────────────────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs;
    if (_filterStatus == 'All') {
      filtered = filtered
          .where(
            (d) =>
                ((d.data())['status']?.toString().toLowerCase() ?? '') !=
                'archived',
          )
          .toList();
    } else {
      final key = _filterStatus.toLowerCase().replaceAll(' ', '_');
      filtered = filtered
          .where(
            (d) =>
                ((d.data())['status']?.toString().toLowerCase() ?? '') == key,
          )
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((d) {
        final data = d.data();
        return (data['title'] ?? '').toString().toLowerCase().contains(q) ||
            (data['category'] ?? '').toString().toLowerCase().contains(q) ||
            (data['location'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }
    return filtered;
  }

  // ── Actions ───────────────────────────────────────────────────────
  void _openSubmitModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _SubmitProposalModal(orgId: widget.orgId),
    ).then((_) => setState(() {}));
  }

  void _openEditModal(String docId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    if (status != 'pending' && status != 'for_review') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only pending or revision-requested proposals can be edited',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _SubmitProposalModal(
        orgId: widget.orgId,
        editDocId: docId,
        existing: data,
      ),
    ).then((_) => setState(() {}));
  }

  void _openFormBuilder(String docId, Map<String, dynamic> data) {
    final eventDate = data['date'];
    final isPast =
        eventDate is Timestamp && !eventDate.toDate().isAfter(DateTime.now());
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => OrgFormBuilderModal(
        proposalId: docId,
        proposalTitle: data['title'] ?? 'Event',
        orgId: widget.orgId,
        isLocked: isPast,
      ),
    );
  }

  void _openViewModal(String docId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ViewProposalModal(docId: docId, data: data),
    );
  }

  void _openLiveTrackerModal(Map<String, dynamic> data) {
    final eventDocId = (data['publishedEventId'] ?? '').toString();
    if (eventDocId.isEmpty) return;
    final eventDate = data['date'];
    final isPast =
        eventDate is Timestamp && !eventDate.toDate().isAfter(DateTime.now());
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _LiveTrackerModal(
        eventDocId: eventDocId,
        eventTitle: (data['title'] ?? 'Event').toString(),
        isPast: isPast,
      ),
    );
  }

  // ── Archive logic ────────────────────────────────────────────────
  void _confirmArchive(String docId, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // No explicit background on this Container let Flutter's default
        // (unseeded, purple-leaning) Material surface color bleed through —
        // same root cause fixed in the Announcements composer and the
        // dashboard's detail modal.
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.archive_outlined,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Archive Proposal',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to archive "$title"? You can still view it in the archived filter. This action can be reversed.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _archiveProposal(docId, title);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B7280),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Archive',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _archiveProposal(String docId, String title) async {
    try {
      await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(docId)
          .update({
            'status': 'archived',
            'archivedAt': FieldValue.serverTimestamp(),
            'archivedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          });
      await activity_log.ActivityLogger.log(
        action: 'archive_proposal',
        module: 'event_proposals',
        details: {'orgId': widget.orgId, 'proposalId': docId, 'title': title},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Proposal "$title" has been archived'),
            backgroundColor: const Color(0xFF6B7280),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive failed: $e'),
            backgroundColor: UpriseColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  // ── Publish: turn an admin-approved proposal into a live student-facing
  // event. Only the org that submitted it can do this — admin's role stops
  // at approve/reject/archive. ──────────────────────────────────────────
  void _confirmPublish(String docId, Map<String, dynamic> data) {
    final title = data['title'] ?? 'this event';
    final isPublished = (data['publishedEventId'] ?? '').toString().isNotEmpty;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.publish_rounded,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      isPublished ? 'Update Published Event' : 'Publish Event',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isPublished
                    ? 'Push the latest details of "$title" to its existing entry on the student events page. This will not create a second listing.'
                    : 'Publish "$title" to the student events page? Students will be able to view its full details and register immediately.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _publishProposal(docId);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      isPublished ? 'Update' : 'Publish',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publishProposal(String proposalId) async {
    if (_publishingIds.contains(proposalId)) return;
    _publishingIds.add(proposalId);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('You must be logged in to publish.');

      final doc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .get();
      if (!doc.exists) throw Exception('Proposal not found.');
      final data = doc.data() as Map<String, dynamic>;

      if (data['status'] != 'approved') {
        throw Exception('Proposal is not approved.');
      }

      // Validate required fields...
      final title = (data['title'] ?? '').toString().trim();
      final description = (data['description'] ?? '').toString().trim();
      final location = (data['location'] ?? '').toString().trim();
      final proposalDate = data['date'] as Timestamp?;
      if (title.isEmpty) throw Exception('Missing event title.');
      if (description.isEmpty) throw Exception('Missing description.');
      if (location.isEmpty) throw Exception('Missing location.');
      if (proposalDate == null) throw Exception('Missing event date.');
      // Backstop for the button-hiding in _buildProposalRow — a stale UI
      // (e.g. a dialog left open across midnight) could otherwise still
      // reach this call after the event date has passed.
      if (!proposalDate.toDate().isAfter(DateTime.now())) {
        throw Exception(
          'This event\'s date has already passed and can no longer be published.',
        );
      }

      // Get org details
      String orgName = (data['orgName'] ?? '').toString();
      String logoUrl = (data['orgLogoUrl'] as String?) ?? '';
      try {
        final orgDoc = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.orgId)
            .get();
        if (orgDoc.exists) {
          final orgData = orgDoc.data() ?? {};
          if (orgName.isEmpty) orgName = (orgData['name'] ?? '').toString();
          if (logoUrl.isEmpty) logoUrl = (orgData['logoUrl'] ?? '').toString();
        }
      } catch (_) {}

      // Prepare event data (without bannerUrl yet)
      final date = proposalDate.toDate();
      final startTime = (data['startTime'] ?? '').toString();
      final endTime = (data['endTime'] ?? '').toString();
      final audience = (data['audience'] ?? 'Public').toString();

      final eventData = {
        'orgId': widget.orgId,
        'orgName': orgName,
        'title': title,
        'description': description,
        'location': location,
        'category': data['category'] ?? 'Other',
        'audience': audience,
        'schoolYear': data['schoolYear'] ?? SchoolYearUtil.currentSchoolYear(),
        'semester': data['semester'] ?? SchoolYearUtil.currentSemester(),
        'date': Timestamp.fromDate(date),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'approved',
        'isPublic': true,
        'logoUrl': logoUrl,
        'createdFromProposalId': proposalId,
        // Carried over as-is — null means unlimited slots, same as on the
        // proposal.
        'capacity': (data['capacity'] as num?)?.toInt(),
        // bannerUrl will be added later
      };

      // ─── NOW SAVE EVENT IMMEDIATELY (no image yet) ───
      final existingEventId = (data['publishedEventId'] ?? '').toString();
      String eventId;

      if (existingEventId.isNotEmpty) {
        eventId = existingEventId;
        await FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .update(eventData);
      } else {
        final eventRef = FirebaseFirestore.instance.collection('events').doc();
        eventId = eventRef.id;
        await eventRef.set({
          ...eventData,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance
            .collection('event_proposals')
            .doc(proposalId)
            .update({
              'publishedEventId': eventId,
              'publishedAt': FieldValue.serverTimestamp(),
              'publishedBy': user.uid,
            });
      }

      // ─── UPLOAD IMAGE ─────────────────────────────────────────────
      // Awaited (not fire-and-forget) so a Storage failure is caught by the
      // outer try/catch below and actually shown to the org — previously
      // this ran unawaited in the background, so a failed upload looked
      // identical to success and the banner silently never appeared.
      final imgB64 = data['imageBase64'] as String?;
      String? imageUploadError;
      if (imgB64 != null && imgB64.isNotEmpty) {
        try {
          await _uploadEventImage(imgB64, data['imageName'], eventId);
        } catch (e) {
          imageUploadError = e.toString();
        }
      }

      // Show success (or a partial-success warning if the image failed)
      if (mounted) {
        final baseMsg = existingEventId.isNotEmpty
            ? 'Event updated on the student events page!'
            : 'Event published to the student events page!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              imageUploadError == null
                  ? '✅ $baseMsg'
                  : '⚠️ $baseMsg But the banner image failed to upload: $imageUploadError',
            ),
            backgroundColor: imageUploadError == null
                ? const Color(0xFF059669)
                : const Color(0xFFB45309),
            behavior: SnackBarBehavior.floating,
            duration: imageUploadError == null
                ? const Duration(seconds: 4)
                : const Duration(seconds: 7),
          ),
        );
      }

      // Log activity (optional)
      await activity_log.ActivityLogger.log(
        action: existingEventId.isNotEmpty
            ? 'update_published_event'
            : 'publish_event_from_proposal',
        module: 'event_proposals',
        details: {
          'orgId': widget.orgId,
          'proposalId': proposalId,
          'eventId': eventId,
        },
      );
    } catch (e, stack) {
      debugPrint('❌ PUBLISH ERROR: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Publish failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _publishingIds.remove(proposalId);
    }
  }

  // Separate function for image upload — lets failures propagate to the
  // caller (org_event_proposals.dart's _publishProposal) instead of being
  // silently swallowed, since a swallowed failure looks identical to a
  // successful publish from the org's point of view.
  //
  // Stored as a base64 data URL directly on the event doc (no Firebase
  // Storage — avoids Storage billing, mirrors the org profile logo/cover
  // photo pattern). The proposal already carries the image as base64, so
  // this is just a re-encode into a data: URI, no actual network upload.
  Future<void> _uploadEventImage(
    String base64Image,
    String? imageName,
    String eventId,
  ) async {
    final ext = (imageName?.contains('.') ?? false)
        ? imageName!.split('.').last.toLowerCase()
        : 'jpg';
    const contentTypes = {
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
    };
    final contentType = contentTypes[ext] ?? 'image/jpeg';
    final bannerUrl = 'data:$contentType;base64,$base64Image';

    // Firestore caps a document at 1MB; the banner shares the doc with the
    // rest of the event fields, so keep a safety margin.
    if (bannerUrl.length > 900 * 1024) {
      throw Exception(
        'Image is too large (max ~650KB). Please use a smaller image.',
      );
    }

    await FirebaseFirestore.instance.collection('events').doc(eventId).update({
      'bannerUrl': bannerUrl,
    });
  }

  // ── Export ────────────────────────────────────────────────────────
  Future<void> _exportProposals(String format) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: widget.orgId)
        .orderBy('submittedAt', descending: true)
        .get();
    final docs = _applyFilters(
      snapshot.docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
          .toList(),
    );

    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now().toString().substring(0, 10);
    final fileName = 'event_proposals_$now';

    String esc(String v) =>
        (v.contains(',') || v.contains('"') || v.contains('\n'))
        ? '"${v.replaceAll('"', '""')}"'
        : v;

    if (format == 'csv') {
      final buf = StringBuffer();
      buf.writeln(
        'Proposal ID,Title,Category,Audience,Description,Date,Start Time,End Time,Location,Status,Submitted By,Submitted At',
      );
      for (final doc in docs) {
        final d = doc.data();
        buf.writeln(
          [
            'EP-${doc.id.substring(0, 4).toUpperCase()}',
            esc(d['title'] ?? ''),
            esc(d['category'] ?? ''),
            esc(d['audience'] ?? ''),
            esc(d['description'] ?? ''),
            d['date'] != null
                ? DateFormat(
                    'yyyy-MM-dd',
                  ).format((d['date'] as Timestamp).toDate())
                : '',
            d['startTime'] ?? '',
            d['endTime'] ?? '',
            esc(d['location'] ?? ''),
            d['status'] ?? 'pending',
            d['submittedByEmail'] ?? '',
            d['submittedAt'] != null
                ? DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format((d['submittedAt'] as Timestamp).toDate())
                : '',
          ].join(','),
        );
      }
      await OrgExportUtil.saveText(
        buf.toString(),
        '$fileName.csv',
        mimeType: 'text/csv',
      );
    } else if (format == 'pdf') {
      final rows = docs.map((doc) {
        final d = doc.data();
        return <String>[
          'EP-${doc.id.substring(0, 4).toUpperCase()}',
          d['title'] ?? '',
          d['category'] ?? '',
          d['audience'] ?? '',
          d['description'] ?? '',
          d['date'] != null
              ? DateFormat(
                  'yyyy-MM-dd',
                ).format((d['date'] as Timestamp).toDate())
              : '',
          d['startTime'] ?? '',
          d['endTime'] ?? '',
          d['location'] ?? '',
          d['status'] ?? 'pending',
          d['submittedByEmail'] ?? '',
          d['submittedAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format((d['submittedAt'] as Timestamp).toDate())
              : '',
        ];
      }).toList();
      final pdfBytes = await OrgExportPdf.generateTablePdf(
        title: 'Event Proposals Report',
        headers: const [
          'Proposal ID',
          'Title',
          'Category',
          'Audience',
          'Description',
          'Date',
          'Start Time',
          'End Time',
          'Location',
          'Status',
          'Submitted By',
          'Submitted At',
        ],
        rows: rows,
      );
      await OrgExportUtil.saveBytes(
        pdfBytes,
        '$fileName.pdf',
        mimeType: 'application/pdf',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${docs.length} proposals as $format'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(isMobile, isTablet),
          _buildToolbar(isMobile, isTablet),
          SizedBox(height: isMobile ? 12 : 16),
          Expanded(child: _buildTable(isMobile, isTablet)),
          SizedBox(height: isMobile ? 16 : 24),
        ],
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final cardGap = isMobile ? 8.0 : 14.0;
    void selectStatus(String status) => setState(() {
      _filterStatus = _filterStatus == status ? 'All' : status;
      _currentPage = 1;
    });

    final statCards = [
      _StatCard(
        label: 'Total Proposals',
        stream: _allStream,
        icon: Icons.description_outlined,
        color: UpriseColors.primaryDark,
        // 'All' is the default, no-filter state — not a deliberate
        // selection — so this card never shows the "selected" glow, even
        // though _filterStatus starts equal to 'All'. Without this, the
        // very first card always rendered pre-highlighted on page load,
        // before the user had clicked anything.
        isSelected: false,
        onTap: () => setState(() {
          _filterStatus = 'All';
          _currentPage = 1;
        }),
      ),
      _StatCard(
        label: 'Pending',
        stream: _pendingStream,
        icon: Icons.hourglass_empty_rounded,
        color: const Color(0xFFFB923C),
        isSelected: _filterStatus == 'Pending',
        onTap: () => selectStatus('Pending'),
      ),
      _StatCard(
        label: 'Approved',
        stream: _approvedStream,
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF059669),
        isSelected: _filterStatus == 'Approved',
        onTap: () => selectStatus('Approved'),
      ),
      _StatCard(
        label: 'For Review',
        stream: _forReviewStream,
        icon: Icons.rate_review_outlined,
        color: const Color(0xFF2563EB),
        isSelected: _filterStatus == 'For Review',
        onTap: () => selectStatus('For Review'),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  statCards.length,
                  (index) => Padding(
                    padding: EdgeInsets.only(
                      right: index < statCards.length - 1 ? cardGap : 0,
                    ),
                    child: SizedBox(width: 220, child: statCards[index]),
                  ),
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(statCards.length * 2 - 1, (index) {
                if (index.isOdd) {
                  return SizedBox(width: cardGap);
                }
                final card = statCards[index ~/ 2];
                return Expanded(child: card);
              }),
            ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────
  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final itemGap = isMobile ? 10.0 : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isMobile ? 16 : 20,
        horizontalPadding,
        0,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search by title, category, or location…',
                      hintStyle: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF9AA5B4),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFF9AA5B4),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: UpriseColors.primaryDark,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _currentPage = 1;
                    }),
                  ),
                ),
                SizedBox(height: itemGap),
                _FilterDropdown(
                  value: _filterStatus,
                  items: const [
                    'All',
                    'Pending',
                    'Approved',
                    'For Review',
                    'Rejected',
                    'Archived',
                  ],
                  hint: 'Status',
                  icon: Icons.tune_rounded,
                  onChanged: (v) => setState(() {
                    _filterStatus = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(height: itemGap),
                AdminExportButton(
                  label: 'Export',
                  onSelected: (format) => _exportProposals(format),
                ),
                SizedBox(height: itemGap),
                _ToolbarButton(
                  label: 'Submit Proposal',
                  icon: Icons.add_rounded,
                  onPressed: _openSubmitModal,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by title, category, or location…',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF9AA5B4),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Color(0xFF9AA5B4),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E6EA),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E6EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: UpriseColors.primaryDark,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        _searchQuery = v;
                        _currentPage = 1;
                      }),
                    ),
                  ),
                ),
                SizedBox(width: itemGap),
                _FilterDropdown(
                  value: _filterStatus,
                  items: const [
                    'All',
                    'Pending',
                    'Approved',
                    'For Review',
                    'Rejected',
                    'Archived',
                  ],
                  hint: 'Status',
                  icon: Icons.tune_rounded,
                  onChanged: (v) => setState(() {
                    _filterStatus = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(width: itemGap),
                AdminExportButton(
                  label: 'Export',
                  onSelected: (format) => _exportProposals(format),
                ),
                SizedBox(width: itemGap),
                _ToolbarButton(
                  label: 'Submit Proposal',
                  icon: Icons.add_rounded,
                  outlined: false,
                  onPressed: _openSubmitModal,
                ),
              ],
            ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────
  Widget _buildTable(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);

    return StreamBuilder<QuerySnapshot>(
      stream: _proposalsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allDocs = (snapshot.data?.docs ?? [])
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        final filtered = _applyFilters(allDocs);

        final totalPages = filtered.isEmpty
            ? 1
            : (filtered.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, filtered.length);
        final pageDocs = filtered.isEmpty
            ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
            : filtered.sublist(start, end);

        final tableContent = Container(
          margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF0)),
            boxShadow: _DS.cardShadow,
          ),
          child: Column(
            children: [
              _buildTableHeader(),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageDocs.length,
                        itemBuilder: (_, i) {
                          final doc = pageDocs[i];
                          final data = doc.data();
                          return _buildProposalRow(
                            docId: doc.id,
                            data: data,
                            isLast: i == pageDocs.length - 1,
                          );
                        },
                      ),
              ),
              _buildFooter(filtered.length, totalPages, start, end),
            ],
          ),
        );

        // The table's columns use Expanded, which needs a bounded width to
        // compute flex shares against. Handing tableContent directly to a
        // horizontal SingleChildScrollView gives it unbounded width instead
        // (that's what the scroll axis means), so every Expanded column
        // inside crashed with "incoming width constraints are unbounded" on
        // narrow screens. Pinning it to a fixed, comfortably-readable width
        // gives Expanded something concrete to divide up, and that fixed
        // width is what actually scrolls horizontally.
        return isMobile
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 900, child: tableContent),
              )
            : tableContent;
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(color: UpriseColors.primaryDark.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          // Flex values here must match _buildProposalRow's Row exactly
          // (4, 2, 2, 2, 2, 2) or the header text drifts out of alignment
          // with its column's actual content.
          Expanded(flex: 4, child: _headerCell('EVENT TITLE')),
          Expanded(flex: 2, child: _headerCell('CATEGORY')),
          Expanded(flex: 2, child: _headerCell('EVENT DATE')),
          Expanded(flex: 2, child: _headerCell('STATUS')),
          Expanded(flex: 2, child: _headerCell('SUBMITTED')),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _headerCell('ACTIONS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildProposalRow({
    required String docId,
    required Map<String, dynamic> data,
    required bool isLast,
  }) {
    final status = (data['status'] ?? 'pending').toString().toLowerCase();
    final isPublished = (data['publishedEventId'] ?? '').toString().isNotEmpty;
    final date = data['date'];
    final dateStr = date is Timestamp
        ? DateFormat('MMM dd, yyyy').format(date.toDate())
        : '—';
    // Once the event date has passed there's nothing left to edit, form, or
    // publish — the only things that still make sense are viewing what
    // happened (participants/attendance, if it was published) and
    // archiving it out of the active list.
    final isPastEvent =
        date is Timestamp && !date.toDate().isAfter(DateTime.now());
    final submittedAt = data['submittedAt'];
    final submittedStr = submittedAt is Timestamp
        ? DateFormat('MMM dd, yyyy').format(submittedAt.toDate())
        : '—';

    // Use the dedicated image if present, else fallback to attachment image
    final bool hasImage =
        data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty;
    final Widget? thumbnail = hasImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildImageFromBase64(
              data['imageBase64']!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          )
        : null;

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: (isPastEvent && isPublished)
          ? () => _openLiveTrackerModal(data)
          : () => _openViewModal(docId, data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            // TITLE column – now with dedicated image thumbnail if exists
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  if (thumbnail != null) ...[
                    thumbnail,
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data['title'] ?? '—',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A202C),
                          ),
                          // No maxLines/ellipsis — a long title wraps onto a
                          // second line and grows the row instead of ever
                          // being cut off, regardless of how long it is.
                          softWrap: true,
                        ),
                        if ((data['location'] ?? '').toString().isNotEmpty)
                          Text(
                            data['location'] ?? '',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: const Color(0xFF9AA5B4),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // CATEGORY
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _categoryBadge((data['category'] ?? '—').toString()),
              ),
            ),
            // EVENT DATE
            Expanded(
              flex: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 12,
                    color: Color(0xFF9AA5B4),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      dateStr,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // STATUS
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusBadge(status),
                    if (isPublished) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Live on student events page',
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // SUBMITTED
            Expanded(
              flex: 2,
              child: Text(
                submittedStr,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            // ACTIONS
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: _ActionPopupButton(
                  // Past events: "View" absorbs the live tracker's
                  // participants/attendance view when the event was
                  // actually published; otherwise it's just the plain
                  // proposal details (nothing was ever published to view
                  // attendance for).
                  onView: (isPastEvent && isPublished)
                      ? () => _openLiveTrackerModal(data)
                      : () => _openViewModal(docId, data),
                  viewIsAttendance: isPastEvent && isPublished,
                  onEdit: (!isPastEvent && status == 'pending')
                      ? () => _openEditModal(docId, data)
                      : null,
                  onRevise: (!isPastEvent && status == 'for_review')
                      ? () => _openEditModal(docId, data)
                      : null,
                  onFormBuilder: (!isPastEvent && status == 'approved')
                      ? () => _openFormBuilder(docId, data)
                      : null,
                  onPublish:
                      (!isPastEvent && status == 'approved' && !isPublished)
                      ? () => _confirmPublish(docId, data)
                      : null,
                  // Folded into "View" above once the event is past.
                  onLiveTracker: (!isPastEvent && isPublished)
                      ? () => _openLiveTrackerModal(data)
                      : null,
                  onArchive:
                      (isPastEvent ||
                          status == 'approved' ||
                          status == 'rejected')
                      ? () =>
                            _confirmArchive(docId, data['title'] ?? 'Proposal')
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No proposals found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Submit your first event proposal to get started.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _openSubmitModal,
            icon: const Icon(Icons.add_rounded, size: 15),
            label: Text(
              'Submit Proposal',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: UpriseColors.primaryDark,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int total, int totalPages, int start, int end) {
    const int maxVisible = 5;
    int firstPage = (_currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    if (lastPage - firstPage + 1 < maxVisible && firstPage > 1) {
      firstPage = (lastPage - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total proposals',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left_rounded,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (p) => _PageNumButton(
                  page: p,
                  isActive: p == _currentPage,
                  onTap: () => setState(() => _currentPage = p),
                ),
              ),
              if (lastPage < totalPages) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '…',
                    style: GoogleFonts.beVietnamPro(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ),
                _PageNumButton(
                  page: totalPages,
                  isActive: _currentPage == totalPages,
                  onTap: () => setState(() => _currentPage = totalPages),
                ),
              ],
              const SizedBox(width: 4),
              _PageButton(
                icon: Icons.chevron_right_rounded,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Card
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final Stream<QuerySnapshot> stream;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.stream,
    required this.icon,
    required this.color,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFE8ECF0),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withAlpha(46),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : _DS.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withAlpha(26),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      Flexible(
                        child: Text(
                          '$count',
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A202C),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String hint;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnchoredMenuTrigger<String>(
      items: items,
      labelOf: (s) => s,
      selectedValue: value,
      onSelected: onChanged,
      trigger: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool outlined;
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: UpriseColors.primaryDark,
          side: BorderSide(color: UpriseColors.primaryDark),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: UpriseColors.primaryDark,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}

class _ActionPopupButton extends StatelessWidget {
  final VoidCallback onView;
  // True when "View" has been rerouted to the participants/attendance
  // tracker for a past, published event — swaps the icon/tooltip so the
  // button doesn't silently do something different than it usually does.
  final bool viewIsAttendance;
  final VoidCallback? onEdit;
  final VoidCallback? onRevise;
  final VoidCallback? onFormBuilder;
  final VoidCallback? onPublish;
  final VoidCallback? onLiveTracker;
  final VoidCallback? onArchive;
  const _ActionPopupButton({
    required this.onView,
    this.viewIsAttendance = false,
    this.onEdit,
    this.onRevise,
    this.onFormBuilder,
    this.onPublish,
    this.onLiveTracker,
    this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrgActionIconButton(
          icon: viewIsAttendance
              ? Icons.insights_outlined
              : Icons.visibility_outlined,
          color: viewIsAttendance
              ? const Color(0xFF059669)
              : const Color(0xFF3B82F6),
          tooltip: viewIsAttendance
              ? 'View Participants & Attendance'
              : 'View Details',
          onTap: onView,
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.edit_outlined,
            color: UpriseColors.primaryDark,
            tooltip: 'Edit Proposal',
            onTap: onEdit,
          ),
        ],
        if (onRevise != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.rate_review_outlined,
            color: const Color(0xFF7C3AED),
            tooltip: 'Revise & Resubmit',
            onTap: onRevise,
          ),
        ],
        if (onFormBuilder != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.dynamic_form_outlined,
            color: const Color(0xFF0D9488),
            tooltip: 'Registration Form',
            onTap: onFormBuilder,
          ),
        ],
        if (onPublish != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.publish_outlined,
            color: const Color(0xFF2563EB),
            tooltip: 'Publish to Students',
            onTap: onPublish,
          ),
        ],
        if (onLiveTracker != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.insights_outlined,
            color: const Color(0xFF059669),
            tooltip: 'Live Participants',
            onTap: onLiveTracker,
          ),
        ],
        if (onArchive != null) ...[
          const SizedBox(width: 6),
          OrgActionIconButton(
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF6B7280),
            tooltip: 'Archive',
            onTap: onArchive,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Participants Tracker — real-time registrations vs. check-ins for a
// published event. Reads the same `registrations` and
// `events/{id}/attendances` collections org_attendance_qr.dart writes to, so
// it stays in sync with whatever the QR/manual check-in flow records.
// ─────────────────────────────────────────────────────────────────────────────
class _LiveTrackerModal extends StatefulWidget {
  final String eventDocId;
  final String eventTitle;
  // Set when opened for an event whose date has already passed — swaps the
  // "LIVE" badge for a neutral "ENDED" one since nothing is actually live
  // anymore, just a record of who registered and who checked in.
  final bool isPast;
  const _LiveTrackerModal({
    required this.eventDocId,
    required this.eventTitle,
    this.isPast = false,
  });

  @override
  State<_LiveTrackerModal> createState() => _LiveTrackerModalState();
}

class _LiveTrackerModalState extends State<_LiveTrackerModal> {
  String _search = '';
  String _statusFilter = 'All';

  // Registration docs don't always carry a usable 'fullName' (e.g. rows
  // written before that field was reliably populated at registration time)
  // — students are looked up by uid alongside the raw registration doc so a
  // name still shows instead of falling straight to "Unknown", mirroring
  // the same _studentCache pattern used in org_attendance_qr.dart.
  final Map<String, Map<String, dynamic>> _studentCache = {};

  Future<void> _ensureStudentsLoaded(Iterable<String> uids) async {
    final missing = uids
        .where((u) => u.isNotEmpty && !_studentCache.containsKey(u))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    for (var i = 0; i < missing.length; i += 30) {
      final chunk = missing.sublist(i, (i + 30).clamp(0, missing.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          _studentCache[d.id] = d.data();
        }
      } catch (_) {}
      for (final id in chunk) {
        _studentCache.putIfAbsent(id, () => const {});
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _exportParticipants(
    String choice,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No participants to export')),
      );
      return;
    }
    final headers = ['Name', 'Email', 'Status', 'Registered At'];
    final tableRows = rows
        .map(
          (p) => [
            p['name'] as String,
            p['email'] as String,
            p['statusLabel'] as String,
            p['registeredAtStr'] as String,
          ],
        )
        .toList();
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    final safeTitle = widget.eventTitle.replaceAll(' ', '_');
    try {
      if (choice == 'csv') {
        final csv = [
          headers,
          ...tableRows,
        ].map((row) => row.map((c) => '"$c"').join(',')).join('\n');
        await OrgExportUtil.saveText(
          csv,
          'participants_${safeTitle}_$stamp.csv',
          mimeType: 'text/csv',
        );
      } else if (choice == 'pdf') {
        final bytes = await OrgExportPdf.generateTablePdf(
          title: 'Participants — ${widget.eventTitle}',
          headers: headers,
          rows: tableRows,
        );
        await OrgExportUtil.saveBytes(
          bytes,
          'participants_${safeTitle}_$stamp.pdf',
          mimeType: 'application/pdf',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${rows.length} participants')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      icon: Icons.insights_rounded,
      title: widget.eventTitle,
      width: 760,
      subtitleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.isPast
                  ? Colors.white.withAlpha(140)
                  : const Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isPast ? 'ENDED' : 'LIVE',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withAlpha(204),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('registrations')
            .where('eventId', isEqualTo: widget.eventDocId)
            .snapshots(),
        builder: (context, regSnap) {
          final regDocs = regSnap.data?.docs ?? [];
          if (regDocs.isNotEmpty) {
            _ensureStudentsLoaded(
              regDocs.map(
                (d) => ((d.data() as Map)['userId'] ?? '').toString(),
              ),
            );
          }
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .doc(widget.eventDocId)
                .collection('attendances')
                .snapshots(),
            builder: (context, attSnap) {
              final attDocs = attSnap.data?.docs ?? [];
              final attByStudent = <String, Map<String, dynamic>>{};
              for (final d in attDocs) {
                final m = d.data() as Map<String, dynamic>;
                final sid = (m['studentId'] ?? '').toString();
                if (sid.isNotEmpty) attByStudent[sid] = m;
              }

              final participants =
                  regDocs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final uid = (d['userId'] ?? '').toString();
                    final att = attByStudent[uid];
                    final status = att == null
                        ? 'not_checked_in'
                        : (att['status'] ?? 'present').toString();
                    final registeredAt = d['registeredAt'] as Timestamp?;
                    final regFullName = (d['fullName'] as String?)?.trim();
                    final cachedFullName =
                        (_studentCache[uid]?['fullName'] as String?)?.trim();
                    final name = regFullName?.isNotEmpty == true
                        ? regFullName!
                        : (cachedFullName?.isNotEmpty == true
                              ? cachedFullName!
                              : 'Unknown');
                    return {
                      'name': name,
                      'email': (d['email'] ?? '').toString(),
                      'status': status,
                      'statusLabel': status == 'not_checked_in'
                          ? 'Not Checked In'
                          : (status == 'late' ? 'Late' : 'Present'),
                      'registeredAtStr': registeredAt != null
                          ? DateFormat(
                              'MMM d, h:mm a',
                            ).format(registeredAt.toDate())
                          : '—',
                    };
                  }).toList()..sort(
                    (a, b) =>
                        (a['name'] as String).compareTo(b['name'] as String),
                  );

              // Same status categories as org_attendance_qr.dart's
              // stat row (Present is present-only, Late is its own
              // bucket) — this used to lump present+late together
              // under "Checked In", which never lined up with the
              // separate Present/Late counts shown on the
              // attendance page for the exact same event.
              final registered = participants.length;
              final present = participants
                  .where((p) => p['status'] == 'present')
                  .length;
              final late = participants
                  .where((p) => p['status'] == 'late')
                  .length;

              final query = _search.trim().toLowerCase();
              final filtered = participants.where((p) {
                final matchSearch =
                    query.isEmpty ||
                    (p['name'] as String).toLowerCase().contains(query) ||
                    (p['email'] as String).toLowerCase().contains(query);
                final matchFilter =
                    _statusFilter == 'All' ||
                    (_statusFilter == 'Present' && p['status'] == 'present') ||
                    (_statusFilter == 'Late' && p['status'] == 'late') ||
                    (_statusFilter == 'Not Checked In' &&
                        p['status'] == 'not_checked_in');
                return matchSearch && matchFilter;
              }).toList();

              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            'Registered',
                            '$registered',
                            Icons.how_to_reg_rounded,
                            const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            'Present',
                            '$present',
                            Icons.verified_rounded,
                            const Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            'Late',
                            '$late',
                            Icons.schedule_rounded,
                            const Color(0xFFFB923C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search by name or email…',
                              hintStyle: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: const Color(0xFF9AA5B4),
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: Color(0xFF9AA5B4),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E6EA),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E6EA),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: UpriseColors.primaryDark,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _FilterDropdown(
                          value: _statusFilter,
                          items: const [
                            'All',
                            'Present',
                            'Late',
                            'Not Checked In',
                          ],
                          hint: 'Status',
                          icon: Icons.filter_list_rounded,
                          onChanged: (v) =>
                              setState(() => _statusFilter = v ?? 'All'),
                        ),
                        const SizedBox(width: 10),
                        AdminExportButton(
                          enabled: filtered.isNotEmpty,
                          label: 'Export',
                          onSelected: (choice) =>
                              _exportParticipants(choice, filtered),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: participants.isEmpty
                          ? Center(
                              child: Text(
                                'No one has registered yet.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            )
                          : filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No participants match your search/filter.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE8ECF0),
                                ),
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusMd,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    color: const Color(0xFFFFF7ED),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            'NAME',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF64748B),
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            'EMAIL',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF64748B),
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            'STATUS',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF64748B),
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            'REGISTERED',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF64748B),
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(
                                            height: 1,
                                            color: Color(0xFFF1F5F9),
                                          ),
                                      itemBuilder: (context, i) {
                                        final p = filtered[i];
                                        final statusColor =
                                            p['status'] == 'not_checked_in'
                                            ? const Color(0xFF9AA5B4)
                                            : (p['status'] == 'late'
                                                  ? const Color(0xFFFB923C)
                                                  : const Color(0xFF059669));
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  p['name'] as String,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: const Color(
                                                          0xFF1A202C,
                                                        ),
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  p['email'] as String,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 12.5,
                                                        color: const Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withAlpha(26),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      p['statusLabel']
                                                          as String,
                                                      style:
                                                          GoogleFonts.beVietnamPro(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: statusColor,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  p['registeredAtStr']
                                                      as String,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 12,
                                                        color: const Color(
                                                          0xFF9AA5B4,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: color.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}

class _PageNumButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;
  const _PageNumButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? UpriseColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$page',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit / Edit Modal – with dedicated image upload
// ─────────────────────────────────────────────────────────────────────────────
class _SubmitProposalModal extends StatefulWidget {
  final String orgId;
  final String? editDocId;
  final Map<String, dynamic>? existing;
  const _SubmitProposalModal({
    required this.orgId,
    this.editDocId,
    this.existing,
  });

  @override
  State<_SubmitProposalModal> createState() => _SubmitProposalModalState();
}

class _SubmitProposalModalState extends State<_SubmitProposalModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _startTimeCtrl = TextEditingController();
  final _endTimeCtrl = TextEditingController();
  final _otherCategoryCtrl = TextEditingController();
  // Optional — blank means unlimited slots (current/default behavior).
  final _capacityCtrl = TextEditingController();
  // The picked DateTime is kept directly instead of only round-tripping
  // through _dateCtrl's "MM/dd/yyyy" text — parsing that text back with
  // intl's DateFormat.parse() at submit time was throwing on some devices
  // (locale-dependent parsing quirk) even though the date shown was
  // perfectly valid, surfacing as a false "Please enter a valid event
  // date." error. _dateCtrl now exists purely for display.
  DateTime? _selectedDate;

  String _category = 'Workshop';
  // Multiple audiences can apply to one event at once (e.g. "CICT Only" and
  // "Bulsuan" simultaneously) — stored back to Firestore as a single
  // comma-joined string in the same 'audience' field so every existing
  // reader across admin/org/guest screens (which all treat it as a plain
  // String) keeps working unchanged.
  final Set<String> _selectedAudiences = {'Public'};
  String _schoolYear = SchoolYearUtil.currentSchoolYear();
  String _semester = SchoolYearUtil.currentSemester();
  bool _isSubmitting = false;
  String? _errorMsg;
  bool _issuesCertificate = false;

  // DEDICATED IMAGE fields
  String? _imageBase64;
  String? _imageName;
  String? _imageSize;
  bool _isImageUploading = false;
  double _imageUploadProgress = 0.0;

  // ATTACHMENT fields (unchanged)
  String? _attachmentBase64;
  String? _attachmentName;
  String? _attachmentSize;
  bool _isAttachmentUploading = false;
  double _attachmentUploadProgress = 0.0;

  static const _categories = [
    'Workshop',
    'Seminar',
    'Competition',
    'General Assembly',
    'Social',
    'Outreach',
    'Sports',
    'Academic',
    'Technical',
    'Cultural',
    'Other',
  ];
  static const _audiences = ['Public', 'CICT Only', 'Members Only', 'BulSUan'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e['title'] ?? '';
      _descCtrl.text = e['description'] ?? '';
      _locCtrl.text = e['location'] ?? '';
      _startTimeCtrl.text = e['startTime'] ?? '';
      _endTimeCtrl.text = e['endTime'] ?? '';
      final cap = e['capacity'];
      _capacityCtrl.text = cap == null ? '' : cap.toString();
      // Dedicated image
      _imageBase64 = e['imageBase64'];
      _imageName = e['imageName'];
      _imageSize = e['imageSize'];
      // Attachment
      _attachmentBase64 = e['attachmentBase64'];
      _attachmentName = e['attachmentName'];
      _attachmentSize = e['attachmentSize'];
      if (e['date'] is Timestamp) {
        _selectedDate = (e['date'] as Timestamp).toDate();
        _dateCtrl.text = DateFormat('MM/dd/yyyy').format(_selectedDate!);
      }
      final cat = e['category'] ?? 'Workshop';
      _category = _categories.contains(cat) ? cat : 'Workshop';
      _otherCategoryCtrl.text = e['otherCategory'] ?? '';
      final rawAudience = (e['audience'] ?? 'Public').toString();
      final parsed = rawAudience
          .split(',')
          .map((s) => s.trim())
          .where((s) => _audiences.contains(s))
          .toSet();
      _selectedAudiences
        ..clear()
        ..addAll(parsed.isEmpty ? {'Public'} : parsed);
      _issuesCertificate = e['issuesCertificate'] == true;
      _schoolYear = (e['schoolYear'] ?? '').toString().isNotEmpty
          ? e['schoolYear']
          : SchoolYearUtil.currentSchoolYear();
      _semester = (e['semester'] ?? '').toString().isNotEmpty
          ? e['semester']
          : SchoolYearUtil.currentSemester();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _dateCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _otherCategoryCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  // ── Image upload ──────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showError('Cannot read image file!');
      return;
    }
    final sizeBytes = file.bytes!.length;
    if (sizeBytes > 700 * 1024) {
      _showError('Image too large. Max 700 KB allowed.');
      return;
    }
    final sizeKB = (sizeBytes / 1024).toStringAsFixed(1);
    setState(() {
      _isImageUploading = true;
      _imageUploadProgress = 0.0;
      _imageName = file.name;
      _imageSize = '$sizeKB KB';
    });
    // Simulate progress
    for (int i = 0; i <= 100; i += 20) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) setState(() => _imageUploadProgress = i / 100);
    }
    setState(() {
      _imageBase64 = base64Encode(file.bytes!);
      _imageUploadProgress = 1.0;
      _isImageUploading = false;
    });
  }

  void _removeImage() => setState(() {
    _imageBase64 = null;
    _imageName = null;
    _imageSize = null;
    _imageUploadProgress = 0.0;
  });

  // ── Attachment upload (unchanged) ──────────────────────────────
  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'png'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showError('Cannot read file!');
      return;
    }
    final sizeBytes = file.bytes!.length;
    if (sizeBytes > 700 * 1024) {
      _showError('File too large. Max 700 KB allowed.');
      return;
    }
    final sizeKB = (sizeBytes / 1024).toStringAsFixed(1);
    setState(() {
      _isAttachmentUploading = true;
      _attachmentUploadProgress = 0.0;
      _attachmentName = file.name;
      _attachmentSize = '$sizeKB KB';
    });
    for (int i = 0; i <= 100; i += 20) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) setState(() => _attachmentUploadProgress = i / 100);
    }
    setState(() {
      _attachmentBase64 = base64Encode(file.bytes!);
      _attachmentUploadProgress = 1.0;
      _isAttachmentUploading = false;
    });
  }

  void _removeAttachment() => setState(() {
    _attachmentBase64 = null;
    _attachmentName = null;
    _attachmentSize = null;
    _attachmentUploadProgress = 0.0;
  });

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: UpriseColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // Parses a "h:mm a" string (e.g. "9:00 AM", from TimeOfDay.format) into
  // minutes since midnight, for comparing two time ranges. Returns null on
  // anything unparsable so a bad/blank value never falsely blocks or falsely
  // passes a conflict check.
  int? _minutesSinceMidnight(String value) {
    if (value.trim().isEmpty) return null;
    try {
      final t = DateFormat('h:mm a').parse(value.trim());
      return t.hour * 60 + t.minute;
    } catch (_) {
      return null;
    }
  }

  // Same venue, same day, overlapping time — across every org, not just
  // this one, since two different orgs double-booking the same room is
  // exactly the case this needs to catch. Only checks against *approved*
  // proposals: a still-pending proposal from another org isn't a confirmed
  // booking yet, so it shouldn't block this one.
  Future<String?> _findVenueConflict({
    required String location,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    final loc = location.trim().toLowerCase();
    if (loc.isEmpty) return null;
    final newStart = _minutesSinceMidnight(startTime);
    final newEnd = _minutesSinceMidnight(endTime);
    if (newStart == null || newEnd == null) return null;

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Deliberately just the date range here — pairing it with a `status`
    // equality filter needs a composite index that isn't deployed for this
    // exact combination (this query spans every org, so it can't reuse the
    // orgId+status+date indexes the rest of this file relies on), and
    // without it Firestore throws FAILED_PRECONDITION on every submit.
    // `status` is filtered client-side below instead.
    final snap = await FirebaseFirestore.instance
        .collection('event_proposals')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('date', isLessThan: Timestamp.fromDate(dayEnd))
        .get();

    for (final doc in snap.docs) {
      if (doc.id == widget.editDocId) continue;
      final d = doc.data();
      if ((d['status'] as String?) != 'approved') continue;
      final otherLoc = (d['location'] as String? ?? '').trim().toLowerCase();
      if (otherLoc.isEmpty || otherLoc != loc) continue;
      final otherStart = _minutesSinceMidnight(
        (d['startTime'] as String?) ?? '',
      );
      final otherEnd = _minutesSinceMidnight((d['endTime'] as String?) ?? '');
      if (otherStart == null || otherEnd == null) continue;
      final overlaps = newStart < otherEnd && otherStart < newEnd;
      if (overlaps) {
        return '${d['title'] ?? 'Another event'} (${d['orgName'] ?? 'another org'})';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAudiences.isEmpty) {
      setState(() => _errorMsg = 'Select at least one audience.');
      return;
    }
    final capacityText = _capacityCtrl.text.trim();
    int? capacity;
    if (capacityText.isNotEmpty) {
      capacity = int.tryParse(capacityText);
      if (capacity == null || capacity <= 0) {
        setState(
          () => _errorMsg =
              'Capacity must be a whole number greater than 0, or left blank for unlimited slots.',
        );
        return;
      }
    }
    setState(() {
      _isSubmitting = true;
      _errorMsg = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      String orgName = '';
      try {
        final orgDoc = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.orgId)
            .get();
        if (orgDoc.exists) orgName = orgDoc.data()?['name'] ?? '';
      } catch (_) {}

      final payload = <String, dynamic>{
        'orgId': widget.orgId,
        'orgName': orgName,
        'title': _titleCtrl.text.trim(),
        'category': _category,
        'otherCategory': _category == 'Other'
            ? _otherCategoryCtrl.text.trim()
            : null,
        'audience': _selectedAudiences.join(', '),
        'schoolYear': _schoolYear,
        'semester': _semester,
        'description': _descCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'startTime': _startTimeCtrl.text.trim(),
        'endTime': _endTimeCtrl.text.trim(),
        // null/omitted means unlimited slots.
        'capacity': capacity,
        'submittedBy': user?.uid ?? '',
        'submittedByEmail': user?.email ?? '',
        'issuesCertificate': _issuesCertificate,
        // Dedicated image
        'imageBase64': _imageBase64,
        'imageName': _imageName,
        'imageSize': _imageSize,
        // Attachment
        'attachmentBase64': _attachmentBase64,
        'attachmentName': _attachmentName,
        'attachmentSize': _attachmentSize,
      };

      final selectedDate = _selectedDate;
      if (selectedDate == null) {
        setState(() {
          _errorMsg = 'Please select an event date.';
          _isSubmitting = false;
        });
        return;
      }
      final today = DateTime.now();
      final todayMidnight = DateTime(today.year, today.month, today.day);
      if (!selectedDate.isAfter(todayMidnight)) {
        setState(() {
          _errorMsg =
              'Event date must be a future date. Today\'s date is not allowed.';
          _isSubmitting = false;
        });
        return;
      }
      payload['date'] = Timestamp.fromDate(selectedDate);

      try {
        final conflict = await _findVenueConflict(
          location: payload['location'] as String,
          date: selectedDate,
          startTime: payload['startTime'] as String,
          endTime: payload['endTime'] as String,
        );
        if (conflict != null) {
          setState(() {
            _errorMsg =
                'That venue is already booked at this time by $conflict. '
                'Pick a different time or location.';
            _isSubmitting = false;
          });
          return;
        }
      } catch (_) {
        setState(() {
          _errorMsg = 'Could not verify venue availability. Please try again.';
          _isSubmitting = false;
        });
        return;
      }

      final col = FirebaseFirestore.instance.collection('event_proposals');
      if (widget.editDocId != null) {
        final wasForReview = (widget.existing?['status'] ?? '') == 'for_review';
        if (wasForReview) {
          payload['status'] = 'pending';
          payload['adminFeedback'] = FieldValue.delete();
        }
        await col.doc(widget.editDocId).update(payload);
        await activity_log.ActivityLogger.log(
          action: wasForReview ? 'resubmit_proposal' : 'edit_proposal',
          module: 'event_proposals',
          details: {'orgId': widget.orgId, 'proposalId': widget.editDocId},
        );
        if (wasForReview) {
          _notifyAdminsOfProposal(
            title: payload['title'] as String,
            verb: 'resubmitted',
          );
        }
      } else {
        payload['status'] = 'pending';
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['submittedAt'] = FieldValue.serverTimestamp();
        final ref = await col.add(payload);
        await activity_log.ActivityLogger.log(
          action: 'submit_proposal',
          module: 'event_proposals',
          details: {'orgId': widget.orgId, 'proposalId': ref.id},
        );
        _notifyAdminsOfProposal(
          title: payload['title'] as String,
          verb: 'submitted',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.editDocId != null
                  ? 'Proposal updated.'
                  : 'Proposal submitted successfully!',
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _isSubmitting = false;
      });
    }
  }

  // Fire-and-forget — runs after the snackbar/pop so it never blocks the
  // org's own submit flow.
  Future<void> _notifyAdminsOfProposal({
    required String title,
    required String verb,
  }) async {
    try {
      String orgName = widget.orgId;
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (orgDoc.exists) {
        orgName =
            (orgDoc.data()?['name'] ??
                    orgDoc.data()?['orgName'] ??
                    widget.orgId)
                .toString();
      }
      await NotificationService.sendToAllAdmins(
        title: 'Event proposal $verb',
        body: '$orgName $verb the proposal "$title" for review.',
        type: 'proposal_submission',
        orgId: widget.orgId,
      );
    } catch (_) {}
  }

  Widget _audienceChip(String a) {
    final selected = _selectedAudiences.contains(a);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() {
          if (selected) {
            if (_selectedAudiences.length > 1) {
              _selectedAudiences.remove(a);
            }
          } else {
            _selectedAudiences.add(a);
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? UpriseColors.primaryDark.withAlpha(20)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? UpriseColors.primaryDark
                  : const Color(0xFFE2E6EA),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: selected
                    ? UpriseColors.primaryDark
                    : const Color(0xFF9AA5B4),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  a,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? const Color(0xFF1A202C)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editDocId != null;
    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      icon: isEdit ? Icons.edit_rounded : Icons.description_outlined,
      title: isEdit ? 'Edit Event Proposal' : 'Submit Event Proposal',
      width: 560,
      maxHeightFraction: 0.88,
      closeEnabled: !_isSubmitting,
      footerActions: [
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE2E6EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          ),
          child: Text(
            'Cancel',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed:
              (_isSubmitting || _isImageUploading || _isAttachmentUploading)
              ? null
              : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isEdit ? Icons.save_rounded : Icons.send_rounded,
                  size: 16,
                ),
          label: Text(
            isEdit ? 'Save Changes' : 'Submit Proposal',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: UpriseColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrgModalSection(
                title: 'Event Image',
                icon: Icons.image_outlined,
                accentColor: UpriseColors.primaryDark,
                child: _buildImageUploadArea(),
              ),
              const SizedBox(height: 20),

              OrgModalSection(
                title: 'Event Details',
                icon: Icons.event_outlined,
                accentColor: UpriseColors.primaryDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _titleCtrl,
                            decoration: _orgEventProposalsInputDecoration(
                              'Event Title *',
                              hint: 'e.g. Flutter Workshop 2025',
                              icon: Icons.title,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            validator: (v) =>
                                v?.trim().isEmpty == true ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _category,
                            decoration: _orgEventProposalsInputDecoration(
                              'Category *',
                            ),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF1A202C),
                            ),
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _category = v!),
                          ),
                        ),
                      ],
                    ),
                    if (_category == 'Other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otherCategoryCtrl,
                        decoration: _orgEventProposalsInputDecoration(
                          'Specify Category *',
                          hint: 'e.g. Webinar',
                          icon: Icons.category_outlined,
                        ),
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        validator: (v) =>
                            _category == 'Other' && v?.trim().isEmpty == true
                            ? 'Required'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Audience *',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select every group this event applies to — more '
                      'than one can apply at once.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // A Wrap here would drop whichever chip doesn't fit onto
                    // its own row below the rest once the label list grows
                    // (e.g. adding "BulSUan" made the 4th chip wrap alone).
                    // Splitting the row's own width evenly across every chip
                    // keeps them on one line regardless of how many there
                    // are or how long their labels get.
                    Row(
                      children: [
                        for (int i = 0; i < _audiences.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: _audienceChip(_audiences[i])),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: _orgEventProposalsInputDecoration(
                        'Description *',
                        hint: 'Describe your event...',
                        icon: Icons.notes_rounded,
                      ),
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _dateCtrl,
                            readOnly: true,
                            onTap: () async {
                              final tomorrow = DateTime.now().add(
                                const Duration(days: 1),
                              );
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: tomorrow,
                                firstDate: tomorrow,
                                lastDate: DateTime(2030),
                                // Material 3's default seed skews
                                // purple/indigo unless the scheme is
                                // seeded from the brand color instead.
                                builder: (context, child) {
                                  final baseTheme = Theme.of(context);
                                  final scheme =
                                      ColorScheme.fromSeed(
                                        seedColor: UpriseColors.primaryDark,
                                        brightness: Brightness.light,
                                      ).copyWith(
                                        primary: UpriseColors.primaryDark,
                                        onPrimary: Colors.white,
                                        surface: Colors.white,
                                        surfaceTint: Colors.transparent,
                                      );
                                  return Theme(
                                    data: baseTheme.copyWith(
                                      colorScheme: scheme,
                                      textButtonTheme: TextButtonThemeData(
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              UpriseColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                  _dateCtrl.text = DateFormat(
                                    'MM/dd/yyyy',
                                  ).format(picked);
                                });
                              }
                            },
                            decoration: _orgEventProposalsInputDecoration(
                              'Date *',
                              hint: 'MM/DD/YYYY',
                              icon: Icons.calendar_today_outlined,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            validator: (v) =>
                                v?.trim().isEmpty == true ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _startTimeCtrl,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null && mounted)
                                _startTimeCtrl.text = picked.format(context);
                            },
                            decoration: _orgEventProposalsInputDecoration(
                              'Start Time *',
                              hint: '-- : --',
                              icon: Icons.access_time_rounded,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            validator: (v) =>
                                v?.trim().isEmpty == true ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _endTimeCtrl,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null && mounted)
                                _endTimeCtrl.text = picked.format(context);
                            },
                            decoration: _orgEventProposalsInputDecoration(
                              'End Time *',
                              hint: '-- : --',
                              icon: Icons.access_time_rounded,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            validator: (v) =>
                                v?.trim().isEmpty == true ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _schoolYear,
                            decoration: _orgEventProposalsInputDecoration(
                              'School Year *',
                            ),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF1A202C),
                            ),
                            items: SchoolYearUtil.schoolYears()
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _schoolYear = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _semester,
                            decoration: _orgEventProposalsInputDecoration(
                              'Semester *',
                            ),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF1A202C),
                            ),
                            items: SchoolYearUtil.semesters
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _semester = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locCtrl,
                      decoration: _orgEventProposalsInputDecoration(
                        'Location *',
                        hint: 'e.g. IT Building Room 301',
                        icon: Icons.location_on_outlined,
                      ),
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _capacityCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _orgEventProposalsInputDecoration(
                        'Capacity',
                        hint: 'Leave blank for unlimited slots',
                        icon: Icons.groups_outlined,
                      ),
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        final n = int.tryParse(t);
                        return (n == null || n <= 0)
                            ? 'Enter a whole number greater than 0'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(
                        'Issue certificates to participants/guests',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                      value: _issuesCertificate,
                      onChanged: (v) =>
                          setState(() => _issuesCertificate = v ?? false),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              OrgModalSection(
                title: 'Attachment (PDF, DOC, etc.)',
                icon: Icons.attach_file_rounded,
                accentColor: UpriseColors.primaryDark,
                child: _buildAttachmentArea(),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Image upload UI ──────────────────────────────────────────────────
  Widget _buildImageUploadArea() {
    final hasImage = _imageBase64 != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isImageUploading
              ? UpriseColors.primaryDark.withAlpha(102)
              : hasImage
              ? const Color(0xFF059669)
              : const Color(0xFFE2E6EA),
          width: (_isImageUploading || hasImage) ? 1.5 : 1,
        ),
      ),
      child: _isImageUploading
          ? _imageUploadingState()
          : hasImage
          ? _imageUploadedState()
          : _imageIdleState(),
    );
  }

  Widget _imageIdleState() => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: _pickImage,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.image_outlined,
              size: 24,
              color: UpriseColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                  children: [
                    TextSpan(
                      text: 'Click to upload event image ',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: UpriseColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: '(JPG, PNG)'),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Max 700 KB',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF9AA5B4),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _imageUploadingState() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.image_outlined, size: 16, color: UpriseColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _imageName ?? 'Uploading...',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _imageSize ?? '',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _imageUploadProgress,
          minHeight: 6,
          backgroundColor: const Color(0xFFE2E6EA),
          valueColor: AlwaysStoppedAnimation<Color>(UpriseColors.primaryDark),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Uploading ${(_imageUploadProgress * 100).toInt()}%',
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          color: const Color(0xFF64748B),
        ),
      ),
    ],
  );

  Widget _imageUploadedState() => Row(
    children: [
      // Preview thumbnail
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _buildImageFromBase64(
          _imageBase64!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _imageName ?? 'Image attached',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (_imageSize != null)
              Text(
                _imageSize!,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF059669),
                ),
              ),
          ],
        ),
      ),
      TextButton(
        onPressed: _removeImage,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Remove',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: const Color(0xFFDC2626),
          ),
        ),
      ),
      TextButton(
        onPressed: _pickImage,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Change',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: UpriseColors.primaryDark,
          ),
        ),
      ),
    ],
  );

  // ── Attachment upload UI (unchanged but renamed) ──────────────────
  Widget _buildAttachmentArea() {
    final hasFile = _attachmentBase64 != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isAttachmentUploading
              ? UpriseColors.primaryDark.withAlpha(102)
              : hasFile
              ? const Color(0xFF059669)
              : const Color(0xFFE2E6EA),
          width: (_isAttachmentUploading || hasFile) ? 1.5 : 1,
        ),
      ),
      child: _isAttachmentUploading
          ? _attachmentUploadingState()
          : hasFile
          ? _attachmentUploadedState()
          : _attachmentIdleState(),
    );
  }

  Widget _attachmentIdleState() => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: _pickAttachment,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 24,
              color: UpriseColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                  children: [
                    TextSpan(
                      text: 'Click to upload attachment ',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: UpriseColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: '(PDF, DOC, etc.)'),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'PDF, DOC, DOCX, TXT, JPG, PNG — max 700 KB',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF9AA5B4),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _attachmentUploadingState() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 16,
            color: UpriseColors.primaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _attachmentName ?? 'Uploading...',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _attachmentSize ?? '',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _attachmentUploadProgress,
          minHeight: 6,
          backgroundColor: const Color(0xFFE2E6EA),
          valueColor: AlwaysStoppedAnimation<Color>(UpriseColors.primaryDark),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Uploading ${(_attachmentUploadProgress * 100).toInt()}%',
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          color: const Color(0xFF64748B),
        ),
      ),
    ],
  );

  Widget _attachmentUploadedState() => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: Color(0xFF059669),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _attachmentName ?? 'File attached',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (_attachmentSize != null)
              Text(
                _attachmentSize!,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF059669),
                ),
              ),
          ],
        ),
      ),
      TextButton(
        onPressed: _removeAttachment,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Remove',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: const Color(0xFFDC2626),
          ),
        ),
      ),
      TextButton(
        onPressed: _pickAttachment,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Change',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: UpriseColors.primaryDark,
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// View Proposal Modal – REDESIGNED to match admin's clean layout
// ─────────────────────────────────────────────────────────────────────────────
class _ViewProposalModal extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _ViewProposalModal({required this.docId, required this.data});

  String _fmt(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) return DateFormat('MMMM dd, yyyy').format(ts.toDate());
    return ts.toString();
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) return DateFormat('h:mm a').format(ts.toDate());
    return ts.toString();
  }

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending').toString().toLowerCase();
    final propNum = 'EP-${docId.substring(0, 4).toUpperCase()}';
    final hasImage =
        data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty;
    final hasAttachment =
        data['attachmentBase64'] != null &&
        data['attachmentBase64'].toString().isNotEmpty;
    final issuesCertificate = data['issuesCertificate'] == true;

    // Time display: combine startTime and endTime if available
    final startTime = data['startTime'] ?? '';
    final endTime = data['endTime'] ?? '';
    final timeStr = (startTime.isNotEmpty && endTime.isNotEmpty)
        ? '$startTime – $endTime'
        : (startTime.isNotEmpty ? startTime : '—');

    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      icon: Icons.event_note_rounded,
      title: data['title'] ?? 'Event Proposal',
      width: 580,
      maxHeightFraction: 0.88,
      subtitleWidget: Row(
        children: [
          Text(
            propNum,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          _statusBadge(status),
        ],
      ),
      footerActions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: UpriseColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
          child: Text(
            'Close',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Event Image (if present) ──
            if (hasImage) ...[
              Container(
                width: double.infinity,
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E6EA)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  // BoxFit.cover so the image actually fills the
                  // frame — .contain on a roughly-square image
                  // inside a full-width box just centered it with a
                  // wall of empty space on both sides.
                  child: _buildImageFromBase64(
                    data['imageBase64']!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Event Details Section ──
            OrgModalSection(
              title: 'Event Details',
              icon: Icons.info_outline_rounded,
              accentColor: UpriseColors.primaryDark,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Category',
                          value:
                              data['category'] == 'Other' &&
                                  (data['otherCategory'] ?? '')
                                      .toString()
                                      .isNotEmpty
                              ? data['otherCategory']
                              : (data['category'] ?? '—'),
                          icon: Icons.category_outlined,
                          valueColor: _categoryBadgeColor(
                            (data['category'] ?? '').toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Audience',
                          value: data['audience'] ?? '—',
                          icon: Icons.people_outline_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Date',
                          value: _fmt(data['date']),
                          icon: Icons.calendar_today_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Time',
                          value: timeStr,
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'School Year',
                          value: data['schoolYear'] ?? '—',
                          icon: Icons.school_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Semester',
                          value: data['semester'] ?? '—',
                          icon: Icons.date_range_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Location',
                          value: data['location'] ?? '—',
                          icon: Icons.location_on_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Issues Certificate',
                          value: issuesCertificate ? 'Yes' : 'No',
                          icon: Icons.verified_outlined,
                          valueColor: issuesCertificate
                              ? const Color(0xFF059669)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Capacity',
                          value: data['capacity'] == null
                              ? 'Unlimited'
                              : '${data['capacity']} slots',
                          icon: Icons.groups_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Description ──
            OrgModalSection(
              title: 'Description',
              icon: Icons.description_outlined,
              accentColor: UpriseColors.primaryDark,
              child: Text(
                data['description'] ?? 'No description provided.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF374151),
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Submission Info ──
            OrgModalSection(
              title: 'Submission Info',
              icon: Icons.person_outline_rounded,
              accentColor: UpriseColors.primaryDark,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Submitted By',
                          value: data['submittedByEmail'] ?? '—',
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Submitted At',
                          value: _fmt(data['submittedAt']),
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (data['reviewedAt'] != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FutureBuilder<String>(
                            future: _getUserName(data['reviewedBy'] ?? ''),
                            builder: (context, snapshot) {
                              final name = snapshot.hasData
                                  ? snapshot.data!
                                  : 'Loading...';
                              return OrgDetailItem(
                                label: 'Reviewed By',
                                value: name,
                                icon: Icons.rate_review_outlined,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Reviewed At',
                            value: _fmt(data['reviewedAt']),
                            icon: Icons.access_time_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (data['publishedAt'] != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Published to Students',
                            value: _fmt(data['publishedAt']),
                            icon: Icons.publish_rounded,
                            valueColor: const Color(0xFF2563EB),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Admin Feedback (if present) ──
            if (data['adminFeedback'] != null &&
                data['adminFeedback'].toString().isNotEmpty) ...[
              _sectionLabel(
                status == 'rejected' ? 'Rejection Reason' : 'Feedback',
                icon: status == 'rejected'
                    ? Icons.cancel_outlined
                    : Icons.rate_review_rounded,
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: status == 'rejected'
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: status == 'rejected'
                        ? const Color(0xFFDC2626).withOpacity(0.3)
                        : const Color(0xFF7C3AED).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      status == 'rejected'
                          ? Icons.cancel_outlined
                          : Icons.rate_review_rounded,
                      size: 16,
                      color: status == 'rejected'
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data['adminFeedback'].toString(),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: status == 'rejected'
                              ? const Color(0xFF991B1B)
                              : const Color(0xFF4C1D95),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Attachment (if present) ──
            if (hasAttachment) ...[
              const SizedBox(height: 20),
              _sectionLabel('Attachment', icon: Icons.attach_file_rounded),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E6EA)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryDark.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        size: 20,
                        color: UpriseColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['attachmentName'] ?? 'Attached File',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (data['attachmentSize'] != null)
                            Text(
                              data['attachmentSize'],
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: const Color(0xFF9AA5B4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openAttachment(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: Text(
                        'Open',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UpriseColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Attachment opener ────────────────────────────────────────────
  Future<void> _openAttachment(BuildContext context) async {
    final b64 = data['attachmentBase64'];
    if (b64 == null || b64.toString().isEmpty) return;
    try {
      final bytes = base64Decode(b64.toString());
      final name = data['attachmentName'] ?? 'document';
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFromExt(ext);
      if (mime.startsWith('image/')) {
        OrgAttachmentPreview.showImage(
          context: context,
          bytes: bytes,
          fileName: name,
        );
      } else if (mime == 'text/plain') {
        final text = utf8.decode(bytes);
        OrgAttachmentPreview.showText(
          context: context,
          fileName: name,
          text: text,
        );
      } else {
        await platform_file_utils.saveBytesToTempAndOpen(
          bytes,
          name,
          mimeType: mime,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening attachment: $e')));
      }
    }
  }
}

// ─── Helper: Info Grid ─────────────────────────────────────────────
class _InfoGrid extends StatelessWidget {
  final List<Widget> children;
  const _InfoGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: children.map((child) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 24 * 2 - 16) / 2,
          child: child,
        );
      }).toList(),
    );
  }
}

// ─── Helper: Info Item ─────────────────────────────────────────────
class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: const Color(0xFF9AA5B4)),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1A202C),
          ),
        ),
      ],
    );
  }
}
