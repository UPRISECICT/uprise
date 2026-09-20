// ignore_for_file: unused_field, duplicate_ignore, use_build_context_synchronously, deprecated_member_use
import 'dart:convert';
import '../../../widgets/stat_cards.dart';
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
import '../../../services/proposal_review_log.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/org_attachment_preview.dart';
import '../../../widgets/org_modal_shell.dart';
import '../../../widgets/app_confirmation_dialog.dart';
import '../../../widgets/app_toast.dart';
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

// The stored status is `for_review`; every surface calls it "Needs
// Revision". Admin already used that wording, the org screen said "For
// Review", and the two were the same state — so a proposal appeared to be
// in different places depending on which portal you were looking at. The
// filter label can no longer be derived by lowercasing (it would give
// `needs_revision`), hence the explicit map.
const Map<String, String> kProposalFilterStatus = {
  'Pending': 'pending',
  'Needs Revision': 'for_review',
  'Approved': 'approved',
  'Rejected': 'rejected',
  'Archived': 'archived',
};

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
      'NEEDS REVISION',
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
// Colored accent bar instead of a generic icon, same reasoning as the
// identical helper in org_merchandise.dart/org_profile.dart/
// org_certificates.dart — [icon] kept for existing call sites but
// intentionally unused now.
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: UpriseColors.primaryDark,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: UpriseColors.primaryDark,
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
  // A widget-based `label:` (RichText, to color just the "*" red) doesn't
  // report correct intrinsic sizing to OutlineInputBorder's floating-label
  // notch calculation — it left every required field's border broken or
  // overlapping around the label instead of a clean gap. Plain labelText
  // (a String) is what the notch math is actually built for, so the
  // colored asterisk isn't worth the broken border.
  return InputDecoration(
    labelText: label,
    hintText: hint,
    // [icon] intentionally unused now — a generic prefixIcon on every field
    // (label text already says what it is) was clutter, not disambiguation.
    // Kept for existing call sites.
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
  // Only true once the org has actually clicked a stat card — lets the
  // Total card show the same "selected" glow the others get on tap,
  // without it looking pre-selected on first page load (filter starts
  // equal to 'All' by default, not by choice).
  bool _filterStatusTouched = false;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Proposals currently being published, to guard against double-tap duplicates
  final Set<String> _publishingIds = {};

  // Set while the Live Tracker is showing — build() swaps to it in place of
  // the proposals table instead of opening a dialog, so org_dashboard.dart's
  // sidebar/top bar (which wrap this whole screen) stay visible, matching
  // Events & Schedules' Event Overview.
  String? _liveTrackerEventDocId;
  String _liveTrackerEventTitle = '';
  bool _liveTrackerIsPast = false;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filters ───────────────────────────────────────────────────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Sorted here instead of via a server-side orderBy('submittedAt') on
    // the stream — Firestore silently drops any document missing that
    // field from an ordered query, so a proposal without a submittedAt
    // never showed up in this list at all, even though it still fully
    // exists in Firestore. Sorting client-side keeps every document
    // visible regardless of whether that field is set.
    var filtered = docs.toList()
      ..sort((a, b) {
        final tsA = a.data()['submittedAt'] as Timestamp?;
        final tsB = b.data()['submittedAt'] as Timestamp?;
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });
    if (_filterStatus == 'All') {
      filtered = filtered
          .where(
            (d) =>
                ((d.data())['status']?.toString().toLowerCase() ?? '') !=
                'archived',
          )
          .toList();
    } else {
      final key = kProposalFilterStatus[_filterStatus] ?? '';
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
      AppToast.warning(
        context,
        'Only pending or revision-requested proposals can be edited',
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
    setState(() {
      _liveTrackerEventDocId = eventDocId;
      _liveTrackerEventTitle = (data['title'] ?? 'Event').toString();
      _liveTrackerIsPast = isPast;
    });
  }

  // ── Archive logic ────────────────────────────────────────────────
  void _confirmArchive(String docId, String title) {
    showDialog(
      context: context,
      builder: (_) => AppConfirmationDialog(
        title: 'Archive Proposal',
        message:
            'Archive "$title"? You can still view and restore it from the archived filter.',
        confirmLabel: 'Archive',
        accentColor: const Color(0xFFF59E0B),
        icon: Icons.archive_outlined,
        onConfirm: () => _archiveProposal(docId, title),
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
        AppToast.success(context, 'Proposal "$title" has been archived');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Archive failed: $e');
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
      builder: (_) => AppConfirmationDialog(
        title: isPublished ? 'Update Published Event' : 'Publish Event',
        message: isPublished
            ? 'Push the latest details of "$title" to its existing entry on the student events page. This will not create a second listing.'
            : 'Publish "$title" to the student events page? Students will be able to view its full details and register immediately.',
        confirmLabel: isPublished ? 'Update' : 'Publish',
        accentColor: const Color(0xFF2563EB),
        icon: Icons.publish_rounded,
        onConfirm: () => _publishProposal(docId),
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
        'otherCategory': data['otherCategory'] ?? '',
        'issuesCertificate': data['issuesCertificate'] ?? false,
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
        // Late-marking settings (new optional feature)
        // Default to false for backward compatibility
        'markLate': false,
        'lateAfterMinutes': 15,
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
        if (imageUploadError == null) {
          AppToast.success(context, ' $baseMsg');
        } else {
          AppToast.warning(
            context,
            ' $baseMsg But the banner image failed to upload: $imageUploadError',
          );
        }
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
        AppToast.error(context, '⚠️ Publish failed: $e');
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
        .get();
    final docs = _applyFilters(
      snapshot.docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
          .toList(),
    );

    if (docs.isEmpty) {
      AppToast.info(context, 'No data to export');
      return;
    }

    final now = DateTime.now().toString().substring(0, 10);
    final fileName = 'event_proposals_$now';

    String esc(String v) =>
        (v.contains(',') || v.contains('"') || v.contains('\n'))
        ? '"${v.replaceAll('"', '""')}"'
        : v;

    // AdminExportButton's dropdown emits 'excel'/'pdf' (see
    // admin_export_button.dart's _items), not 'csv' — this used to check
    // for 'csv', so "Export as Excel" silently did nothing.
    if (format == 'excel') {
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
      AppToast.success(context, 'Exported ${docs.length} proposals as $format');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_liveTrackerEventDocId != null) {
      return _LiveTrackerModal(
        eventDocId: _liveTrackerEventDocId!,
        eventTitle: _liveTrackerEventTitle,
        isPast: _liveTrackerIsPast,
        onBack: () => setState(() => _liveTrackerEventDocId = null),
      );
    }
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
      _filterStatusTouched = true;
      _currentPage = 1;
    });

    final statCards = [
      StatCard(
        label: 'Total Proposals',
        stream: _allStream,
        icon: Icons.description_outlined,
        color: UpriseColors.primaryDark,
        // Highlights once the org deliberately taps back to "All", same
        // as the other cards — but not on first page load, when
        // _filterStatus is already 'All' by default rather than by
        // choice (see _filterStatusTouched).
        selected: _filterStatus == 'All' && _filterStatusTouched,
        onTap: () => setState(() {
          _filterStatus = 'All';
          _filterStatusTouched = true;
          _currentPage = 1;
        }),
      ),
      StatCard(
        label: 'Pending',
        stream: _pendingStream,
        icon: Icons.hourglass_empty_rounded,
        color: const Color(0xFFFB923C),
        selected: _filterStatus == 'Pending',
        onTap: () => selectStatus('Pending'),
      ),
      StatCard(
        label: 'Approved',
        stream: _approvedStream,
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF059669),
        selected: _filterStatus == 'Approved',
        onTap: () => selectStatus('Approved'),
      ),
      StatCard(
        label: 'Needs Revision',
        stream: _forReviewStream,
        icon: Icons.rate_review_outlined,
        color: const Color(0xFF2563EB),
        selected: _filterStatus == 'Needs Revision',
        onTap: () => selectStatus('Needs Revision'),
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
                    'Needs Revision',
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
                    'Needs Revision',
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
      stream: _allStream,
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
      // Matches the row's own "View Details" action button — tapping the
      // row used to jump straight to the attendance tracker for a past,
      // published (i.e. approved) event, with no way to see the
      // proposal's own info anymore once its date had passed.
      onTap: () => _openViewModal(docId, data),
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
            // ACTIONS — icon row at full desktop width (the "old form"),
            // collapsing to the single 3-dot popup below a width threshold.
            // The popup exists specifically because a Row of up to 6
            // always-visible icons has no overflow handling and breaks
            // (icons overlapping/clipping) once squeezed narrow — so the
            // icon row is only shown when there's comfortably enough room
            // for it, and the popup remains the safe fallback everywhere
            // else instead of being the only option at every width.
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Used to always reroute to the attendance/live-tracker
                    // modal once an approved event was both past and
                    // published, entirely replacing "View Details" — an
                    // org could see attendance for a finished approved
                    // event but never its own proposal info (schedule,
                    // description, venue) again. View now always opens
                    // the real details modal; participants/attendance
                    // gets its own always-separate button below instead
                    // of stealing View's slot.
                    void onView() => _openViewModal(docId, data);
                    final onEdit = (!isPastEvent && status == 'pending')
                        ? () => _openEditModal(docId, data)
                        : null;
                    final onRevise = (!isPastEvent && status == 'for_review')
                        ? () => _openEditModal(docId, data)
                        : null;
                    final onFormBuilder = (!isPastEvent && status == 'approved')
                        ? () => _openFormBuilder(docId, data)
                        : null;
                    final onPublish =
                        (!isPastEvent && status == 'approved' && !isPublished)
                        ? () => _confirmPublish(docId, data)
                        : null;
                    // No longer gated on !isPastEvent — a published event
                    // that already happened still has real participants
                    // and attendance worth seeing, it's just no longer
                    // "live".
                    final onLiveTracker = isPublished
                        ? () => _openLiveTrackerModal(data)
                        : null;
                    final onArchive =
                        (isPastEvent ||
                            status == 'approved' ||
                            status == 'rejected')
                        ? () => _confirmArchive(
                            docId,
                            data['title'] ?? 'Proposal',
                          )
                        : null;

                    // Full desktop table (sidebar + generous content width)
                    // reliably has room for the icon row; MediaQuery is used
                    // instead of this cell's own narrow flex-based
                    // constraints, which never reflect the real window
                    // width.
                    final isWideView =
                        MediaQuery.of(context).size.width >= 1300;

                    if (!isWideView) {
                      return _ActionPopupButton(
                        onView: onView,
                        isPastEvent: isPastEvent,
                        onEdit: onEdit,
                        onRevise: onRevise,
                        onFormBuilder: onFormBuilder,
                        onPublish: onPublish,
                        onLiveTracker: onLiveTracker,
                        onArchive: onArchive,
                      );
                    }

                    return Wrap(
                      alignment: WrapAlignment.end,
                      spacing: OrgTableStyle.actionIconGap,
                      runSpacing: OrgTableStyle.actionIconGap,
                      children: [
                        OrgActionIconButton(
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Details',
                          color: const Color(0xFF3B82F6),
                          onTap: onView,
                        ),
                        if (onEdit != null)
                          OrgActionIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit Proposal',
                            color: UpriseColors.primaryDark,
                            onTap: onEdit,
                          ),
                        if (onRevise != null)
                          OrgActionIconButton(
                            icon: Icons.rate_review_outlined,
                            tooltip: 'Revise & Resubmit',
                            color: const Color(0xFF7C3AED),
                            onTap: onRevise,
                          ),
                        if (onFormBuilder != null)
                          OrgActionIconButton(
                            icon: Icons.dynamic_form_outlined,
                            tooltip: 'Registration Form',
                            color: const Color(0xFF0D9488),
                            onTap: onFormBuilder,
                          ),
                        if (onPublish != null)
                          OrgActionIconButton(
                            icon: Icons.publish_outlined,
                            tooltip: 'Publish to Students',
                            color: const Color(0xFF2563EB),
                            onTap: onPublish,
                          ),
                        if (onLiveTracker != null)
                          OrgActionIconButton(
                            icon: Icons.insights_outlined,
                            tooltip: isPastEvent
                                ? 'Participants & Attendance'
                                : 'Live Participants',
                            color: const Color(0xFF059669),
                            onTap: onLiveTracker,
                          ),
                        if (onArchive != null)
                          OrgActionIconButton(
                            icon: Icons.inventory_2_outlined,
                            tooltip: 'Archive',
                            color: const Color(0xFF6B7280),
                            onTap: onArchive,
                          ),
                      ],
                    );
                  },
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
                tooltip: 'Previous Page',
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
                tooltip: 'Next Page',
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
  final bool isPastEvent;
  final VoidCallback? onEdit;
  final VoidCallback? onRevise;
  final VoidCallback? onFormBuilder;
  final VoidCallback? onPublish;
  final VoidCallback? onLiveTracker;
  final VoidCallback? onArchive;
  const _ActionPopupButton({
    required this.onView,
    this.isPastEvent = false,
    this.onEdit,
    this.onRevise,
    this.onFormBuilder,
    this.onPublish,
    this.onLiveTracker,
    this.onArchive,
  });

  Widget _menuRow(IconData icon, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          color: const Color(0xFF1A202C),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // A single trigger button opening a dropdown menu instead of a Row of
    // up to 6 always-visible icon buttons — that Row had no overflow
    // handling, so it broke (icons overlapping/clipping) once the table's
    // Actions column got squeezed narrower than the window. A fixed-size
    // trigger can't overflow that way regardless of window width.
    final items = <PopupMenuEntry<VoidCallback>>[
      PopupMenuItem<VoidCallback>(
        value: onView,
        child: _menuRow(
          Icons.visibility_outlined,
          const Color(0xFF3B82F6),
          'View Details',
        ),
      ),
      if (onEdit != null)
        PopupMenuItem<VoidCallback>(
          value: onEdit,
          child: _menuRow(
            Icons.edit_outlined,
            UpriseColors.primaryDark,
            'Edit Proposal',
          ),
        ),
      if (onRevise != null)
        PopupMenuItem<VoidCallback>(
          value: onRevise,
          child: _menuRow(
            Icons.rate_review_outlined,
            const Color(0xFF7C3AED),
            'Revise & Resubmit',
          ),
        ),
      if (onFormBuilder != null)
        PopupMenuItem<VoidCallback>(
          value: onFormBuilder,
          child: _menuRow(
            Icons.dynamic_form_outlined,
            const Color(0xFF0D9488),
            'Registration Form',
          ),
        ),
      if (onPublish != null)
        PopupMenuItem<VoidCallback>(
          value: onPublish,
          child: _menuRow(
            Icons.publish_outlined,
            const Color(0xFF2563EB),
            'Publish to Students',
          ),
        ),
      if (onLiveTracker != null)
        PopupMenuItem<VoidCallback>(
          value: onLiveTracker,
          child: _menuRow(
            Icons.insights_outlined,
            const Color(0xFF059669),
            isPastEvent ? 'Participants & Attendance' : 'Live Participants',
          ),
        ),
      if (onArchive != null)
        PopupMenuItem<VoidCallback>(
          value: onArchive,
          child: _menuRow(
            Icons.inventory_2_outlined,
            const Color(0xFF6B7280),
            'Archive',
          ),
        ),
    ];

    return PopupMenuButton<VoidCallback>(
      tooltip: 'Actions',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: Color(0xFF64748B),
        ),
      ),
      itemBuilder: (context) => items,
      onSelected: (action) => action(),
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
  // Returns to the proposals table — the parent screen owns the "which
  // tracker is open" state, this widget just reports back when done.
  final VoidCallback onBack;
  const _LiveTrackerModal({
    required this.eventDocId,
    required this.eventTitle,
    this.isPast = false,
    required this.onBack,
  });

  @override
  State<_LiveTrackerModal> createState() => _LiveTrackerModalState();
}

class _LiveTrackerModalState extends State<_LiveTrackerModal> {
  String _search = '';
  String _statusFilter = 'All';
  // 'All' is the default, no-filter state — not a deliberate selection —
  // so the "Registered" card shouldn't show the selected glow until the
  // user actually taps something. Same bug/fix as this file's other stat
  // cards and org_letter_request.dart's.
  bool _filterTouched = false;

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
      AppToast.info(context, 'No participants to export');
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
      // AdminExportButton's dropdown emits 'excel'/'pdf' (see
      // admin_export_button.dart's _items), not 'csv' — this used to
      // check for 'csv', so "Export as Excel" silently did nothing.
      if (choice == 'excel') {
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
        AppToast.success(context, 'Exported ${rows.length} participants');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rendered in place of the proposals table (see
    // _OrgEventProposalsScreenState.build()) instead of as a dialog —
    // org_dashboard.dart's sidebar/top bar wrap this whole screen already,
    // matching how Events & Schedules' Event Overview behaves.
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Column(
        children: [
          // Light, compact header instead of a full-bleed colored banner —
          // this sits right below org_dashboard.dart's own top bar, so a
          // second heavy colored block just doubled up on banner chrome.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: UpriseColors.primaryDark,
                    size: 20,
                  ),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: UpriseColors.primaryDark.withAlpha(28),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: UpriseColors.primaryDark,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.eventTitle,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: widget.isPast
                                  ? const Color(0xFF9AA5B4)
                                  : const Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isPast ? 'ENDED' : 'LIVE',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: widget.isPast
                                  ? const Color(0xFF9AA5B4)
                                  : const Color(0xFF16A34A),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ─── CONTENT CARD ──────────────────────────────────────────
          // A white card with a margin around it instead of the stats/
          // search/table sitting directly on the page's flat gray canvas.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: StreamBuilder<QuerySnapshot>(
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
                              final registeredAt =
                                  d['registeredAt'] as Timestamp?;
                              final regFullName = (d['fullName'] as String?)
                                  ?.trim();
                              final cachedFullName =
                                  (_studentCache[uid]?['fullName'] as String?)
                                      ?.trim();
                              final name = regFullName?.isNotEmpty == true
                                  ? regFullName!
                                  : (cachedFullName?.isNotEmpty == true
                                        ? cachedFullName!
                                        : 'Unknown');
                              // Registration docs don't always carry their
                              // own 'email' field — same reason 'name' falls
                              // back to the students collection above, this
                              // was reading only d['email'] with no
                              // fallback, so the column rendered blank
                              // whenever a registration doc predated (or
                              // never had) that field.
                              final regEmail = (d['email'] as String?)?.trim();
                              final cachedEmail =
                                  (_studentCache[uid]?['email'] as String?)
                                      ?.trim();
                              final email = regEmail?.isNotEmpty == true
                                  ? regEmail!
                                  : (cachedEmail ?? '');
                              return {
                                'name': name,
                                'email': email,
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
                              (a, b) => (a['name'] as String).compareTo(
                                b['name'] as String,
                              ),
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
                              (p['name'] as String).toLowerCase().contains(
                                query,
                              ) ||
                              (p['email'] as String).toLowerCase().contains(
                                query,
                              );
                          final matchFilter =
                              _statusFilter == 'All' ||
                              (_statusFilter == 'Present' &&
                                  p['status'] == 'present') ||
                              (_statusFilter == 'Late' &&
                                  p['status'] == 'late') ||
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
                                      isSelected:
                                          _statusFilter == 'All' &&
                                          _filterTouched,
                                      onTap: () => setState(() {
                                        _filterTouched = true;
                                        _statusFilter = 'All';
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _statTile(
                                      'Present',
                                      '$present',
                                      Icons.verified_rounded,
                                      const Color(0xFF059669),
                                      isSelected: _statusFilter == 'Present',
                                      onTap: () => setState(() {
                                        _filterTouched = true;
                                        _statusFilter =
                                            _statusFilter == 'Present'
                                            ? 'All'
                                            : 'Present';
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _statTile(
                                      'Late',
                                      '$late',
                                      Icons.schedule_rounded,
                                      const Color(0xFFFB923C),
                                      isSelected: _statusFilter == 'Late',
                                      onTap: () => setState(() {
                                        _filterTouched = true;
                                        _statusFilter = _statusFilter == 'Late'
                                            ? 'All'
                                            : 'Late';
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      onChanged: (v) =>
                                          setState(() => _search = v),
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                      ),
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
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E6EA),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E6EA),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                    onChanged: (v) => setState(
                                      () => _statusFilter = v ?? 'All',
                                    ),
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
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.how_to_reg_outlined,
                                              size: 40,
                                              color: const Color(0xFFCBD5E1),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'No one has registered yet.',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 13,
                                                color: const Color(0xFF9AA5B4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : filtered.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.search_off_rounded,
                                              size: 40,
                                              color: const Color(0xFFCBD5E1),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'No participants match your search/filter.',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 13,
                                                color: const Color(0xFF9AA5B4),
                                              ),
                                            ),
                                          ],
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                      style:
                                                          GoogleFonts.beVietnamPro(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: const Color(
                                                              0xFF64748B,
                                                            ),
                                                            letterSpacing: 0.7,
                                                          ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      'EMAIL',
                                                      style:
                                                          GoogleFonts.beVietnamPro(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: const Color(
                                                              0xFF64748B,
                                                            ),
                                                            letterSpacing: 0.7,
                                                          ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      'STATUS',
                                                      style:
                                                          GoogleFonts.beVietnamPro(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: const Color(
                                                              0xFF64748B,
                                                            ),
                                                            letterSpacing: 0.7,
                                                          ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      'REGISTERED',
                                                      style:
                                                          GoogleFonts.beVietnamPro(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: const Color(
                                                              0xFF64748B,
                                                            ),
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
                                                      p['status'] ==
                                                          'not_checked_in'
                                                      ? const Color(0xFF9AA5B4)
                                                      : (p['status'] == 'late'
                                                            ? const Color(
                                                                0xFFFB923C,
                                                              )
                                                            : const Color(
                                                                0xFF059669,
                                                              ));
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          flex: 3,
                                                          child: Text(
                                                            p['name'] as String,
                                                            style: GoogleFonts.beVietnamPro(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  const Color(
                                                                    0xFF1A202C,
                                                                  ),
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        Expanded(
                                                          flex: 3,
                                                          child: Text(
                                                            p['email']
                                                                as String,
                                                            style: GoogleFonts.beVietnamPro(
                                                              fontSize: 12.5,
                                                              color:
                                                                  const Color(
                                                                    0xFF64748B,
                                                                  ),
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        Expanded(
                                                          flex: 2,
                                                          child: Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical: 3,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: statusColor
                                                                    .withAlpha(
                                                                      26,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      6,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                p['statusLabel']
                                                                    as String,
                                                                style: GoogleFonts.beVietnamPro(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      statusColor,
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
                                                            style: GoogleFonts.beVietnamPro(
                                                              fontSize: 12,
                                                              color:
                                                                  const Color(
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Matches org_dashboard.dart's own _StatCardWidget exactly (icon badge
  // top-left, big number top-right, label below) — the dashboard's stat
  // cards are the reference "this looks good" style for the whole portal.
  // Tappable — filters the table below to that status, reusing the same
  // _statusFilter the Status dropdown already drives, instead of sitting
  // there as a static number with no relation to the list underneath it.
  Widget _statTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return StatCard(
      label: label,
      value: value,
      icon: icon,
      color: color,
      selected: isSelected,
      onTap: onTap,
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
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
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
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
  // Current step in the proposal workflow.
  int _step = 0;
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
  // New proposals must explicitly choose their intended audience.
  final Set<String> _selectedAudiences = {};
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
      final rawAudience = (e['audience'] ?? '').toString();
      final parsed = rawAudience
          .split(',')
          .map((s) => s.trim())
          .where((s) => _audiences.contains(s))
          .toSet();
      // Legacy/manually-created proposals could have 'Public' saved
      // alongside other audiences (no longer possible from this form going
      // forward) — normalize back to Public-only when editing one, so the
      // exclusive-Public UI rule below isn't loaded into a contradictory
      // state.
      _selectedAudiences
        ..clear()
        ..addAll(
          parsed.isEmpty
              ? {'Public'}
              : (parsed.contains('Public') ? {'Public'} : parsed),
        );
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
    AppToast.error(context, msg);
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

  // Nothing validated that the end time came after the start time, so a
  // proposal could be saved as 5:00 PM to 9:00 AM. That also quietly broke
  // the venue-overlap maths below, which assumes start < end.
  String? _timeOrderError() {
    final start = _minutesSinceMidnight(_startTimeCtrl.text);
    final end = _minutesSinceMidnight(_endTimeCtrl.text);
    if (start == null || end == null) return null;
    if (end == start) return 'The start and end time are the same.';
    if (end < start) return 'The end time must be after the start time.';
    return null;
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
    // Re-run both step gates: the user can reach the last step and then go
    // back and clear something, and these checks (audience chips, date in
    // the future, end-after-start) live outside the Form's validators.
    for (var i = 0; i < _stepTitles.length - 1; i++) {
      final err = _validateStep(i);
      if (err != null) {
        setState(() {
          _errorMsg = err;
          _step = i;
        });
        return;
      }
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
        // Snapshot, not a live reference: whoever the adviser was when the
        // endorsement was given is who the record must keep naming.
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
          await ProposalReviewLog.add(
            proposalId: widget.editDocId!,
            action: ProposalReviewAction.resubmitted,
          );
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
        await ProposalReviewLog.add(
          proposalId: ref.id,
          action: ProposalReviewAction.submitted,
        );
        _notifyAdminsOfProposal(
          title: payload['title'] as String,
          verb: 'submitted',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        AppToast.success(
          context,
          widget.editDocId != null
              ? 'Proposal updated.'
              : 'Proposal submitted successfully!',
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
    // Public is exclusive — it can't be combined with the other three, so
    // while it's selected they're locked out entirely rather than just
    // being togglable alongside it.
    final publicSelected = _selectedAudiences.contains('Public');
    final disabled = publicSelected && a != 'Public';

    void handleTap() {
      if (disabled) return;
      setState(() {
        if (a == 'Public') {
          if (selected) {
            _selectedAudiences.remove('Public');
          } else {
            // Selecting Public always clears whatever else was picked —
            // "CICT Only + Members Only" then tapping Public must become
            // just "Public", never "Public + CICT Only + Members Only".
            _selectedAudiences
              ..clear()
              ..add('Public');
          }
          return;
        }
        if (selected) {
          _selectedAudiences.remove(a);
        } else {
          _selectedAudiences.add(a);
        }
      });
    }

    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFF3F4F6)
                : (selected
                      ? UpriseColors.primaryDark.withAlpha(20)
                      : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (selected && !disabled)
                  ? UpriseColors.primaryDark
                  : const Color(0xFFE2E6EA),
              width: (selected && !disabled) ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: (selected && !disabled)
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
                      fontWeight: (selected && !disabled)
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: disabled
                          ? const Color(0xFFB0B7C3)
                          : (selected
                                ? const Color(0xFF1A202C)
                                : const Color(0xFF64748B)),
                    ),
                  ),
                ),
              ],
            ),
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
      headerColor: UpriseColors.primaryDark,
      compactHeader: true,
      icon: isEdit ? Icons.edit_rounded : Icons.description_outlined,
      title: isEdit ? 'Edit Event Proposal' : 'Submit Event Proposal',
      width: 640,
      maxHeightFraction: 0.88,
      closeEnabled: !_isSubmitting,
      footerActions: [
        // Step 0 offers Cancel; later steps offer Back, so there is always
        // a way out to the left and a way forward to the right.
        OutlinedButton(
          onPressed: _isSubmitting
              ? null
              : (_step == 0 ? () => Navigator.pop(context) : _goBack),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE2E6EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          ),
          child: Text(
            _step == 0 ? 'Cancel' : 'Back',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_step < _stepTitles.length - 1)
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _goNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              'Next',
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
          )
        else
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
      body: _buildWizardBody(),
    );
  }

  // -- Wizard ----------------------------------------------------------
  // Three steps instead of one 1,400-line scroll. The old form put fifteen
  // required fields in a single column, so the only way to discover you had
  // missed one was to press Submit and hunt for the red text.
  //
  // The step bodies live in an IndexedStack, not a swap: Form.validate()
  // only visits *mounted* fields, so tearing down step 1 to show step 2
  // would quietly exempt every field behind you from the final submit
  // check. IndexedStack keeps all three mounted, which also means every
  // controller and scroll offset survives moving back and forth for free.
  static const List<String> _stepTitles = [
    'Details',
    'Schedule & Venue',
    'Attachments & Review',
  ];

  Widget _buildWizardBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepHeader(),
        Flexible(
          child: _step == 2
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: _buildProposalForm(),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: _buildProposalForm(),
                ),
        ),
      ],
    );
  }

  Widget _buildProposalForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrentStep(),
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
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 1:
        return _buildStepSchedule();
      case 2:
        return _buildStepAttachments();
      default:
        return _buildStepDetails();
    }
  }

  Widget _buildStepHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: i <= _step
                      ? UpriseColors.primaryDark
                      : const Color(0xFFE8ECF0),
                ),
              ),
            _StepDot(
              index: i,
              label: _stepTitles[i],
              current: _step,
              // Only steps already completed are clickable - jumping ahead
              // past an unfilled required field is what this prevents.
              onTap: i < _step ? () => setState(() => _step = i) : null,
            ),
          ],
        ],
      ),
    );
  }

  /// Validates only the fields belonging to [step], by reading the
  /// controllers directly. _formKey.currentState!.validate() cannot be used
  /// per step: every step is mounted, so it would validate all three and
  /// light up errors on pages the user has not reached yet.
  String? _validateStep(int step) {
    if (step == 0) {
      if (_titleCtrl.text.trim().isEmpty) return 'Enter an event title.';
      if (_category == 'Other' && _otherCategoryCtrl.text.trim().isEmpty) {
        return 'Specify the category.';
      }
      if (_selectedAudiences.isEmpty) return 'Select at least one audience.';
      if (_descCtrl.text.trim().isEmpty) return 'Enter a description.';
      return null;
    }
    if (step == 1) {
      final date = _selectedDate;
      if (date == null) return 'Pick an event date.';
      final today = DateTime.now();
      if (!date.isAfter(DateTime(today.year, today.month, today.day))) {
        return 'The event date must be in the future.';
      }
      if (_startTimeCtrl.text.trim().isEmpty) return 'Pick a start time.';
      if (_endTimeCtrl.text.trim().isEmpty) return 'Pick an end time.';
      final order = _timeOrderError();
      if (order != null) return order;
      if (_locCtrl.text.trim().isEmpty) return 'Enter a location.';
      final cap = _capacityCtrl.text.trim();
      if (cap.isNotEmpty && (int.tryParse(cap) ?? 0) <= 0) {
        return 'Capacity must be a number greater than zero.';
      }
      return null;
    }
    return null;
  }

  void _goNext() {
    final err = _validateStep(_step);
    if (err != null) {
      setState(() => _errorMsg = err);
      return;
    }
    setState(() {
      _errorMsg = null;
      _step = (_step + 1).clamp(0, _stepTitles.length - 1);
    });
  }

  void _goBack() => setState(() {
    _errorMsg = null;
    _step = (_step - 1).clamp(0, _stepTitles.length - 1);
  });

  Widget _buildStepDetails() {
    return Column(
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
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _category,
                decoration: _orgEventProposalsInputDecoration('Category *'),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF1A202C),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
            validator: (v) => _category == 'Other' && v?.trim().isEmpty == true
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
          validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 12),
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
          onChanged: (v) => setState(() => _issuesCertificate = v ?? false),
        ),
      ],
    );
  }

  Widget _buildStepSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _dateCtrl,
                readOnly: true,
                onTap: () async {
                  final tomorrow = DateTime.now().add(const Duration(days: 1));
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
                              foregroundColor: UpriseColors.primaryDark,
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
                      _dateCtrl.text = DateFormat('MM/dd/yyyy').format(picked);
                    });
                  }
                },
                decoration: _orgEventProposalsInputDecoration(
                  'Date *',
                  hint: 'MM/DD/YYYY',
                  icon: Icons.calendar_today_outlined,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
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
                  if (picked != null && mounted) {
                    // setState so the review summary and the
                    // end-after-start check repaint, matching
                    // what the Date field above already does.
                    setState(
                      () => _startTimeCtrl.text = picked.format(context),
                    );
                  }
                },
                decoration: _orgEventProposalsInputDecoration(
                  'Start Time *',
                  hint: '-- : --',
                  icon: Icons.access_time_rounded,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
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
                  if (picked != null && mounted) {
                    // setState so the review summary and the
                    // end-after-start check repaint, matching
                    // what the Date field above already does.
                    setState(() => _endTimeCtrl.text = picked.format(context));
                  }
                },
                decoration: _orgEventProposalsInputDecoration(
                  'End Time *',
                  hint: '-- : --',
                  icon: Icons.access_time_rounded,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
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
                decoration: _orgEventProposalsInputDecoration('School Year *'),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF1A202C),
                ),
                items: SchoolYearUtil.schoolYears()
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) => setState(() => _schoolYear = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _semester,
                decoration: _orgEventProposalsInputDecoration('Semester *'),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF1A202C),
                ),
                items: SchoolYearUtil.semesters
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
          validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
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
      ],
    );
  }

  Widget _buildStepAttachments() {
    return Column(
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
          title: 'Attachment (PDF, DOC, etc.)',
          icon: Icons.attach_file_rounded,
          accentColor: UpriseColors.primaryDark,
          child: _buildAttachmentArea(),
        ),
        _buildReviewSummary(),
      ],
    );
  }

  /// Read-only recap of steps 1-2, so the last thing before Submit is a
  /// look at what is actually being sent rather than a file picker.
  Widget _buildReviewSummary() {
    final rows = <MapEntry<String, String>>[
      MapEntry('Title', _titleCtrl.text.trim()),
      MapEntry(
        'Category',
        _category == 'Other' ? _otherCategoryCtrl.text.trim() : _category,
      ),
      MapEntry('Audience', _selectedAudiences.join(', ')),
      MapEntry('Date', _dateCtrl.text.trim()),
      MapEntry(
        'Time',
        '${_startTimeCtrl.text.trim()} - ${_endTimeCtrl.text.trim()}',
      ),
      MapEntry('Location', _locCtrl.text.trim()),
      MapEntry('School year', '$_schoolYear - $_semester'),
      MapEntry(
        'Capacity',
        _capacityCtrl.text.trim().isEmpty
            ? 'Unlimited'
            : _capacityCtrl.text.trim(),
      ),
      MapEntry('Certificates', _issuesCertificate ? 'Yes' : 'No'),
    ];

    return OrgModalSection(
      title: 'Review',
      icon: Icons.fact_check_outlined,
      accentColor: UpriseColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      r.key,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value.isEmpty ? '-' : r.value,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

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
                // The only place this image actually displays today is
                // Home's event preview card, cropped to 200×100 — a 2:1
                // ratio — so an image shot at a very different ratio gets
                // an off-center BoxFit.cover crop there. Naming the ratio
                // here lets the org avoid that instead of finding out after
                // publishing.
                'Max 700 KB · recommended ratio 2:1 (e.g. 1200×600)',
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
/// One numbered node in the proposal wizard's step header. Filled when the
/// step is done, outlined-in-brand when it is the current one, and plain
/// grey when it is still ahead.
class _StepDot extends StatelessWidget {
  final int index;
  final int current;
  final String label;
  final VoidCallback? onTap;

  const _StepDot({
    required this.index,
    required this.current,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final accent = UpriseColors.primaryDark;
    final color = done || active ? accent : const Color(0xFF9AA5B4);

    final node = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? accent : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: active ? 2 : 1),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFF1A202C) : color,
          ),
        ),
      ],
    );

    if (onTap == null) return node;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: node),
    );
  }
}

class _ViewProposalModal extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _ViewProposalModal({required this.docId, required this.data});

  String _fmt(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) return DateFormat('MMMM dd, yyyy').format(ts.toDate());
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

  /// Full review history from the `reviews` subcollection. Renders
  /// nothing until there are at least two entries — for a proposal that
  /// has only just been submitted, a one-item "timeline" is noise, and
  /// the status badge already says the same thing.
  Widget _buildReviewTimeline() {
    return StreamBuilder<List<ProposalReviewEntry>>(
      stream: ProposalReviewLog.watch(docId),
      builder: (context, snap) {
        final entries = snap.data ?? const <ProposalReviewEntry>[];
        if (entries.length < 2) return const SizedBox.shrink();

        Color colorFor(String action) => switch (action) {
          ProposalReviewAction.approved => const Color(0xFF059669),
          ProposalReviewAction.rejected => const Color(0xFFDC2626),
          ProposalReviewAction.revisionRequested => const Color(0xFF2563EB),
          _ => const Color(0xFF64748B),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _sectionLabel('Review History', icon: Icons.history_rounded),
            for (var i = 0; i < entries.length; i++)
              Builder(
                builder: (context) {
                  final e = entries[i];
                  final isLast = i == entries.length - 1;
                  final c = colorFor(e.action);
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dot + connector rail
                        Column(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 1,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  color: const Color(0xFFE2E6EA),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      e.label,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: c,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        e.at == null
                                            ? ''
                                            : DateFormat(
                                                'MMM d, y · h:mm a',
                                              ).format(e.at!.toDate()),
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11,
                                          color: const Color(0xFF9AA5B4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (e.message.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    e.message,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      color: const Color(0xFF374151),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
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
      headerColor: UpriseColors.primaryDark,
      compactHeader: true,
      icon: Icons.event_note_rounded,
      title: data['title'] ?? 'Event Proposal',
      // Widened from 580 for the banner-left/details-right layout below —
      // a photo shown BoxFit.contain (whole, not cropped) needs real width
      // to not look tiny squeezed into a single-column modal.
      width: 960,
      maxHeightFraction: 0.85,
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
      // Fixed-height Row instead of one scrolling Column — banner on the
      // left (BoxFit.contain so the whole photo shows instead of being
      // cropped to a 220px-tall strip), details scrolling independently on
      // the right, so a tall image and long details don't fight over the
      // same vertical space.
      body: SizedBox(
        height: 560,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasImage) ...[
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  // Fills the whole column edge-to-edge regardless of the
                  // source photo's own proportions — BoxFit.cover crops as
                  // needed instead of shrinking the box to match the
                  // image's ratio, which used to leave large dead-space
                  // gaps above/below or beside an image whose ratio didn't
                  // match this column's own tall, narrow shape.
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E6EA)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImageFromBase64(
                      data['imageBase64']!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
            Expanded(
              flex: hasImage ? 6 : 10,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hasImage ? 4 : 24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  iconColor: UpriseColors.primaryDark,
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
                                  iconColor: const Color(0xFF06B6D4),
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
                                  iconColor: const Color(0xFF3B82F6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrgDetailItem(
                                  label: 'Time',
                                  value: timeStr,
                                  icon: Icons.access_time_rounded,
                                  iconColor: const Color(0xFFF59E0B),
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
                                  iconColor: const Color(0xFF8B5CF6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrgDetailItem(
                                  label: 'Semester',
                                  value: data['semester'] ?? '—',
                                  icon: Icons.date_range_outlined,
                                  iconColor: const Color(0xFF6366F1),
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
                                  iconColor: const Color(0xFF14B8A6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrgDetailItem(
                                  label: 'Issues Certificate',
                                  value: issuesCertificate ? 'Yes' : 'No',
                                  icon: Icons.verified_outlined,
                                  iconColor: const Color(0xFF10B981),
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
                                  iconColor: const Color(0xFFEC4899),
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
                                  iconColor: const Color(0xFF0EA5E9),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OrgDetailItem(
                                  label: 'Submitted At',
                                  value: _fmt(data['submittedAt']),
                                  icon: Icons.access_time_rounded,
                                  iconColor: const Color(0xFF64748B),
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
                                    future: _getUserName(
                                      data['reviewedBy'] ?? '',
                                    ),
                                    builder: (context, snapshot) {
                                      final name = snapshot.hasData
                                          ? snapshot.data!
                                          : 'Loading...';
                                      return OrgDetailItem(
                                        label: 'Reviewed By',
                                        value: name,
                                        icon: Icons.rate_review_outlined,
                                        iconColor: const Color(0xFF0EA5E9),
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
                                    iconColor: const Color(0xFF64748B),
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
                                    iconColor: const Color(0xFF10B981),
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

                    // ── Review history ──
                    // The box above shows only the *latest* note, because
                    // adminFeedback is one field. This is every round of
                    // it, so an org that has been sent back twice can
                    // still read what was asked the first time.
                    _buildReviewTimeline(),

                    // ── Attachment (if present) ──
                    if (hasAttachment) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(
                        'Attachment',
                        icon: Icons.attach_file_rounded,
                      ),
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
                                color: UpriseColors.primaryDark.withOpacity(
                                  0.10,
                                ),
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
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                              ),
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
            ),
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
        AppToast.error(context, 'Error opening attachment: $e');
      }
    }
  }
}
