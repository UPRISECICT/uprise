// ignore_for_file: unnecessary_cast, unused_field, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../widgets/stat_cards.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import '../../../theme/org_theme.dart';
import '../../../widgets/certificate_preview.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/app_toast.dart';

// ─── STATUS SUMMARY ITEM ──────────────────────────────────────
// One inline "Label 12" pair, not a card. Four stacked label-over-number
// tiles in four different accent colors turned a four-number summary into
// the loudest thing in the modal; a single quiet text row lets the
// recipient list be what you actually look at. [color] no longer tints the
// number — it only draws the underline marking the active filter, so the
// color still means "this filter is on" and nothing else.
class _StatusSummaryItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;

  const _StatusSummaryItem({
    required this.label,
    required this.count,
    required this.color,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: UpriseColors.darkGray,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientStatusRow {
  final String key;
  final String name;
  final bool isGuest;
  final bool attended;
  final bool evaluated;
  final bool certSent;
  final int resendCount;
  _RecipientStatusRow({
    required this.key,
    required this.name,
    required this.isGuest,
    required this.attended,
    required this.evaluated,
    required this.certSent,
    required this.resendCount,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FETCH RECIPIENT STATUS - top level function
// ─────────────────────────────────────────────────────────────────────────────
// Event feedback is currently split across two collections from an
// incomplete migration — three separate mobile screens submit feedback for
// an event, and only some were ever switched to the newer 'event_feedback'.
// The one most students actually complete in practice (reached via the
// "rate this event" notification, student_notifications_screen.dart) still
// writes to the older 'feedback' collection, which — live-data-checked —
// currently holds real submissions while 'event_feedback' holds none.
// Checking only one side silently undercounts who's actually evaluated, so
// every eligibility check reads both and unions the results.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
_fetchAllFeedbackForEvent(String eventId) async {
  final results = await Future.wait([
    FirebaseFirestore.instance
        .collection('feedback')
        .where('eventId', isEqualTo: eventId)
        .get(),
    FirebaseFirestore.instance
        .collection('event_feedback')
        .where('eventId', isEqualTo: eventId)
        .get(),
  ]);
  return [...results[0].docs, ...results[1].docs];
}

// Guest submissions are flagged inconsistently across write sites too —
// guest_feedback_screen.dart sets isGuest:true on its event_feedback mirror
// but type:'guest' (no isGuest field at all) on its feedback write — so
// check for either instead of trusting one specific field/value.
bool _feedbackMarkedGuest(Map<String, dynamic> data) =>
    data['isGuest'] == true || data['type'] == 'guest';

Future<List<_RecipientStatusRow>> fetchRecipientStatus(String eventId) async {
  // All four reads are independent of one another, so they run together
  // instead of one after the other (this used to be three round trips in a
  // row before the recipient list could appear).
  final attFuture = FirebaseFirestore.instance
      .collection('events')
      .doc(eventId)
      .collection('attendances')
      .where('status', whereIn: ['present', 'late'])
      .get();
  final fbFuture = _fetchAllFeedbackForEvent(eventId);
  final certFuture = FirebaseFirestore.instance
      .collection('certificates')
      .where('eventId', isEqualTo: eventId)
      .where('status', isEqualTo: 'distributed')
      .get();
  final attSnap = await attFuture;
  final fbDocs = await fbFuture;
  final certSnap = await certFuture;

  final evaluatedUids = fbDocs
      .map((d) => d.data()['userId']?.toString())
      .whereType<String>()
      .toSet();
  final evaluatedGuestEmails = fbDocs
      .where((d) => _feedbackMarkedGuest(d.data()))
      .map((d) => d.data()['guestEmail']?.toString())
      .whereType<String>()
      .toSet();

  final certByKey = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final doc in certSnap.docs) {
    final data = doc.data();
    final key = (data['recipientUid'] ?? data['recipientEmail'])?.toString();
    if (key == null || key.isEmpty) continue;
    certByKey[key] = doc;
  }

  final rows = <_RecipientStatusRow>[];
  for (final doc in attSnap.docs) {
    final data = doc.data();
    final isGuest = data['isGuest'] == true;
    final key = isGuest
        ? (data['guestEmail'] ?? '').toString()
        : (data['studentId'] ?? '').toString();
    if (key.isEmpty) continue;

    final name = (data['studentName'] ?? (isGuest ? 'Guest' : 'Unknown'))
        .toString();
    final evaluated = isGuest
        ? evaluatedGuestEmails.contains(key)
        : evaluatedUids.contains(key);
    final certDoc = certByKey[key];

    rows.add(
      _RecipientStatusRow(
        key: key,
        name: name,
        isGuest: isGuest,
        attended: true,
        evaluated: evaluated,
        certSent: certDoc != null,
        resendCount: certDoc != null
            ? ((certDoc.data()['resendCount'] as num?) ?? 0).toInt()
            : 0,
      ),
    );
  }
  return rows;
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
      color: Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// Cloudinary stores an uploaded PDF as-is — its secure_url points straight
// at the raw PDF document, which Flutter's Image widgets can't decode as
// pixels. New uploads are converted to a renderable URL at upload time (see
// _ImportTemplateModalState._upload), but any certificate saved before that
// fix still has the raw .pdf URL stored — applying the same swap here at
// render time repairs those existing records too, without a data migration.
String _renderableTemplateUrl(String url) {
  if (url.toLowerCase().endsWith('.pdf')) {
    return '${url.substring(0, url.length - 4)}.jpg';
  }
  return url;
}

// Preview-sized provider for a template image. Previews are shown at roughly
// 600 logical px wide, so decoding the full-resolution file (Canva exports are
// often 3000px+) is wasted work; the stored URL and the file itself are left
// untouched, so anything that renders the certificate at full size still gets
// full quality.
ImageProvider _previewImageProvider(String url) => ResizeImage.resizeIfNeeded(
  1400,
  null,
  NetworkImage(_renderableTemplateUrl(url)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Badge styles
// ─────────────────────────────────────────────────────────────────────────────
class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

Widget _certBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'distributed': _BadgeStyle(
      UpriseColors.success.withOpacity(0.18),
      UpriseColors.success,
      'DISTRIBUTED',
    ),
    'pending': _BadgeStyle(
      UpriseColors.warning.withOpacity(0.18),
      UpriseColors.warning,
      'PENDING',
    ),
    'draft': _BadgeStyle(
      UpriseColors.lightGray,
      UpriseColors.darkGray,
      'DRAFT',
    ),
    'undistributed': _BadgeStyle(
      UpriseColors.error.withOpacity(0.18),
      UpriseColors.error,
      'UNDISTRIBUTED',
    ),
  };
  final s =
      styles[status.toLowerCase()] ??
      _BadgeStyle(
        UpriseColors.lightGray,
        UpriseColors.darkGray,
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

Widget _batchBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'sent': _BadgeStyle(
      UpriseColors.success.withOpacity(0.18),
      UpriseColors.success,
      'All Sent', // Changed
    ),
    'partially_sent': _BadgeStyle(
      UpriseColors.warning.withOpacity(0.18),
      UpriseColors.warning,
      'Sending', // Changed - shorter and clearer
    ),
    'draft': _BadgeStyle(
      UpriseColors.lightGray,
      UpriseColors.darkGray,
      'Draft',
    ),
    'archived': _BadgeStyle(
      const Color(0xFFF3F4F6),
      const Color(0xFF6B7280),
      'Archived',
    ),
  };
  final s =
      styles[status] ??
      _BadgeStyle(
        UpriseColors.lightGray,
        UpriseColors.darkGray,
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
// Section label helper
// ─────────────────────────────────────────────────────────────────────────────
// Colored accent bar instead of a generic icon, same reasoning as
// org_merchandise.dart/org_profile.dart's identical helper — [icon] kept
// for existing call sites but intentionally unused now.
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
InputDecoration _fieldDecoration({
  String? label,
  String? hint,
  IconData? icon,
}) {
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
// Signatory model
// ─────────────────────────────────────────────────────────────────────────────
class SignatoryData {
  final String id;
  final String placeholderKey;
  final String fullName;
  final String title;
  final String? signatureBase64;

  const SignatoryData({
    required this.id,
    required this.placeholderKey,
    required this.fullName,
    required this.title,
    this.signatureBase64,
  });

  factory SignatoryData.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return SignatoryData(
      id: doc.id,
      placeholderKey:
          doc.id, // ← CHANGE THIS! Use doc.id instead of reading from document
      fullName: (d['fullName'] ?? '').toString(),
      title: (d['title'] ?? '').toString(),
      signatureBase64: d['signatureBase64'] as String?,
    );
  }
}

double _autoFitFontSize({
  required String text,
  required double baseFontSize,
  required double maxWidthPx,
  double minFontSize = 11,
  double avgCharWidthFactor = 0.56,
}) {
  if (text.isEmpty || maxWidthPx <= 0) return baseFontSize;
  double fs = baseFontSize;
  double estWidth() => text.length * fs * avgCharWidthFactor;
  while (fs > minFontSize && estWidth() > maxWidthPx) {
    fs -= 1;
  }
  return fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class CertificateRecord {
  final String id;
  final String certificateId;
  final String eventName;
  final String organization;
  final String type;
  final DateTime date;
  final int recipients;
  final String status;
  final String templateType;
  final String? templateFileUrl;
  final String? signatureImage;
  final List<Map<String, dynamic>> signatories;
  final String? verificationCode;
  final String? recipientName;
  final Map<String, dynamic>? namePlacement;
  final String? eventId;
  final String? sendStatus;
  final int resendCount;
  final bool archived;
  final Map<String, dynamic>? signatoryPlacements;

  const CertificateRecord({
    required this.id,
    required this.certificateId,
    required this.eventName,
    required this.organization,
    required this.type,
    required this.date,
    required this.recipients,
    required this.status,
    required this.templateType,
    this.templateFileUrl,
    this.signatureImage,
    this.signatories = const [],
    this.verificationCode,
    this.recipientName,
    this.namePlacement,
    this.eventId,
    this.sendStatus,
    this.resendCount = 0,
    this.archived = false,
    this.signatoryPlacements,
  });

  factory CertificateRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CertificateRecord(
      id: doc.id,
      certificateId: 'CERT-${doc.id.substring(0, 4).toUpperCase()}',
      eventName:
          d['eventName'] as String? ??
          d['certificateName'] as String? ??
          'Untitled',
      organization: d['organization'] as String? ?? 'N/A',
      type: d['type'] as String? ?? 'Participation',
      date: (d['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recipients: (d['recipients'] as num?)?.toInt() ?? 1,
      status: d['status'] as String? ?? 'draft',
      templateType: d['templateType'] as String? ?? 'Formal Academic',
      templateFileUrl: d['templateFileUrl'] as String?,
      signatureImage: d['signatureImage'] as String?,
      signatories: d['signatories'] is List
          ? (d['signatories'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [],
      verificationCode: d['verificationCode'] as String?,
      recipientName: d['recipientName'] as String?,
      namePlacement: d['namePlacement'] is Map
          ? Map<String, dynamic>.from(d['namePlacement'] as Map)
          : null,
      eventId: d['eventId'] as String?,
      sendStatus: d['sendStatus'] as String?,
      resendCount: (d['resendCount'] as num?)?.toInt() ?? 0,
      archived: d['archived'] == true,
      signatoryPlacements: d['signatoryPlacements'] is Map
          ? Map<String, dynamic>.from(d['signatoryPlacements'] as Map)
          : null,
    );
  }
}

class CertificateBatch {
  final String batchKey;
  final List<CertificateRecord> records;
  CertificateBatch({required this.batchKey, required this.records});

  CertificateRecord get primary => records.first;
  String get eventName => primary.eventName;
  String get organization => primary.organization;
  String get templateType => primary.templateType;
  // The derived values below are read many times per build (every row, the
  // stat cards, the filters), so each is computed once per batch. `records`
  // is final, which is what makes that safe.
  late final DateTime date = records
      .map((r) => r.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  String? get eventId => primary.eventId;

  // A doc in this batch is one of two unrelated things: a single draft
  // placeholder standing in for N intended recipients (N lives in its own
  // `recipients` field), or one issued certificate belonging to one person.
  // Counting docs treats those as the same unit, which is where the table's
  // numbers came apart — a draft batch for twenty people reported "1",
  // because the batch was one placeholder doc.
  late final List<CertificateRecord> _issued = records
      .where((r) => r.status != 'draft')
      .toList();

  late final int _intendedFromDraft = records
      .where((r) => r.status == 'draft')
      .fold<int>(0, (n, r) => n + r.recipients);

  late final int sentCount = _issued
      .where((r) => r.status == 'distributed')
      .length;

  // A headcount. Before anything is issued the draft's own figure is the
  // only population there is; once certificates exist they are the
  // population, and the draft's figure still counts only while it is the
  // larger of the two — which is exactly while people are still waiting.
  late final int totalRecipients = _issued.length > _intendedFromDraft
      ? _issued.length
      : _intendedFromDraft;

  int get pendingCount {
    final left = totalRecipients - sentCount;
    return left < 0 ? 0 : left;
  }

  int get failedCount => records.where((r) => r.sendStatus == 'failed').length;
  late final bool isArchived = records.every((r) => r.archived);

  // Read off the same two numbers the table prints, so the badge and the
  // count cannot disagree. They used to be derived separately — batchStatus
  // dropped the draft placeholder from its denominator while
  // totalRecipients kept it — which is how one row could read "All Sent"
  // next to "2/3".
  String get batchStatus {
    if (isArchived) return 'archived';
    if (sentCount == 0) return 'draft';
    if (sentCount < totalRecipients) return 'partially_sent';
    return 'sent';
  }

  bool get isEditable => batchStatus == 'draft';

  static List<CertificateBatch> groupByEvent(List<CertificateRecord> records) {
    final Map<String, List<CertificateRecord>> grouped = {};
    for (final r in records) {
      final key = (r.eventId != null && r.eventId!.isNotEmpty)
          ? r.eventId!
          : 'solo_${r.id}';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final batches = grouped.entries
        .map((e) => CertificateBatch(batchKey: e.key, records: e.value))
        .toList();
    batches.sort((a, b) => b.date.compareTo(a.date));
    return batches;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgCertificatesScreen extends StatefulWidget {
  final String orgId;
  const OrgCertificatesScreen({super.key, required this.orgId});

  @override
  State<OrgCertificatesScreen> createState() => _OrgCertificatesScreenState();
}

class _OrgCertificatesScreenState extends State<OrgCertificatesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Which stat card (if any) is driving an extra drill-down filter on top of
  // the status dropdown — the cards count individual recipient records
  // ('distributed'/'pending'), while the dropdown filters grouped batches, so
  // this is a separate predicate rather than reusing _filterStatus directly.
  int? _selectedStatCard;
  bool Function(CertificateBatch)? _statCardFilter;

  // Set while the batch detail page is showing. The batch *key*, not the
  // batch object: the batch is re-resolved from the live stream on every
  // build, so a certificate issued from inside the page updates the page it
  // was issued from, with no refresh.
  String? _detailBatchKey;

  // One live listener for the whole screen. The stat cards, the table and
  // the detail page all read the batches grouped from it, so a snapshot is
  // grouped once instead of once per widget on every rebuild (typing in the
  // search box used to re-group every certificate three times per keystroke)
  // and switching to the detail page can't resubscribe and sit on a spinner.
  // Null until the first snapshot arrives.
  StreamSubscription<QuerySnapshot>? _certsSub;
  List<CertificateBatch>? _allBatches;
  Object? _certsError;

  @override
  void initState() {
    super.initState();
    _certsSub = FirebaseFirestore.instance
        .collection('certificates')
        .where('orgId', isEqualTo: widget.orgId)
        .orderBy('issuedAt', descending: true)
        .snapshots()
        .listen(
          (snap) {
            final batches = CertificateBatch.groupByEvent(
              snap.docs.map((d) => CertificateRecord.fromFirestore(d)).toList(),
            );
            if (!mounted) return;
            setState(() {
              _allBatches = batches;
              _certsError = null;
            });
          },
          onError: (Object e) {
            if (mounted) setState(() => _certsError = e);
          },
        );
  }

  @override
  void dispose() {
    _certsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openGenerateFlow() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _GenerateCertificateModal(
        orgId: widget.orgId,
        selectedTemplateType: 'Formal Academic',
        selectedTemplateUrl: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      // The batch detail view takes over the body instead of opening on top
      // of it, so the sidebar and top bar org_dashboard.dart wraps this
      // screen in stay visible — the same swap as the Pending Reports page
      // in org_reports.dart and Event Overview in org_events_schedule.dart.
      body: _detailBatchKey != null
          ? _buildDetailPage(_detailBatchKey!)
          : Column(
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

  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return Builder(
      builder: (context) {
        final loading = _allBatches == null;
        final batchesForCounts = _allBatches ?? const <CertificateBatch>[];
        String fmt(int n) => loading ? '–' : '$n';
        // The table hides archived batches under every filter but
        // "Archived", so the cards summarising it work off the same set.
        final active = batchesForCounts.where((b) => !b.isArchived).toList();

        // Rows, i.e. what the table below actually lists. This card counted
        // raw Firestore docs while the table — and this card's own footer,
        // "N certificate batches" — counted grouped events, so one page
        // carried two different numbers for the same word.
        final batchCount = active.length;

        // People, for all three of the rest. They share one unit and the
        // last two add up to the first: every recipient is either holding a
        // certificate or waiting for one. Before, Distributed counted
        // batches with any send and Pending counted batches with any gap,
        // so a half-sent batch landed in both and the pair could sum past
        // the total.
        final totalRec = active.fold<int>(0, (n, b) => n + b.totalRecipients);
        final distributed = active.fold<int>(0, (n, b) => n + b.sentCount);
        final pending = active.fold<int>(0, (n, b) => n + b.pendingCount);

        final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
        final cardGap = isMobile ? 8.0 : 14.0;

        void selectCard(int index, bool Function(CertificateBatch)? filter) {
          setState(() {
            if (_selectedStatCard == index) {
              _selectedStatCard = null;
              _statCardFilter = null;
            } else {
              _selectedStatCard = index;
              _statCardFilter = filter;
            }
            _currentPage = 1;
          });
        }

        final statCards = [
          StatCard(
            label: 'Certificate Batches',
            value: fmt(batchCount),
            icon: Icons.card_membership_outlined,
            color: UpriseColors.primaryDark,
            selected: _selectedStatCard == 0,
            onTap: () => selectCard(0, null),
          ),
          StatCard(
            label: 'Total Recipients',
            value: fmt(totalRec),
            icon: Icons.people_outline_rounded,
            color: UpriseColors.accent,
            selected: _selectedStatCard == 1,
            onTap: () => selectCard(1, null),
          ),
          StatCard(
            label: 'Distributed',
            value: fmt(distributed),
            icon: Icons.assignment_turned_in_outlined,
            color: UpriseColors.success,
            selected: _selectedStatCard == 2,
            onTap: () => selectCard(2, (b) => b.sentCount > 0),
          ),
          StatCard(
            label: 'Pending',
            value: fmt(pending),
            icon: Icons.pending_outlined,
            color: UpriseColors.warning,
            selected: _selectedStatCard == 3,
            onTap: () => selectCard(
              3,
              (b) => !b.isArchived && b.sentCount < b.totalRecipients,
            ),
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isMobile ? 16 : 24,
            horizontalPadding,
            0,
          ),
          child: isMobile
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      statCards.length,
                      (i) => Padding(
                        padding: EdgeInsets.only(
                          right: i < statCards.length - 1 ? cardGap : 0,
                        ),
                        child: SizedBox(width: 200, child: statCards[i]),
                      ),
                    ),
                  ),
                )
              : Row(
                  children: List.generate(
                    statCards.length,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i < statCards.length - 1 ? cardGap : 0,
                        ),
                        child: statCards[i],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final itemGap = isMobile ? 8.0 : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isMobile ? 14 : 20,
        horizontalPadding,
        0,
      ),
      child: isMobile
          ? Column(
              spacing: itemGap,
              children: [
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.beVietnamPro(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search by event name or certificate ID…',
                      hintStyle: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: UpriseColors.greyText,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: UpriseColors.greyText,
                      ),
                      filled: true,
                      fillColor: UpriseColors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: UpriseColors.mediumGray),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: UpriseColors.mediumGray),
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
                      _searchQuery = v.toLowerCase();
                      _currentPage = 1;
                    }),
                  ),
                ),
                Row(
                  spacing: itemGap,
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterStatus,
                        items: const [
                          'All',
                          'Draft',
                          'Partially Sent',
                          'Sent',
                          'Archived',
                        ],
                        onChanged: (v) => setState(() {
                          _filterStatus = v!;
                          _selectedStatCard = null;
                          _statCardFilter = null;
                          _currentPage = 1;
                        }),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openGenerateFlow,
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: Text(
                          'Generate',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UpriseColors.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              spacing: itemGap,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by event name or certificate ID…',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: UpriseColors.greyText,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: UpriseColors.greyText,
                        ),
                        filled: true,
                        fillColor: UpriseColors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: UpriseColors.mediumGray,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: UpriseColors.mediumGray,
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
                        _searchQuery = v.toLowerCase();
                        _currentPage = 1;
                      }),
                    ),
                  ),
                ),
                _FilterDropdown(
                  value: _filterStatus,
                  items: const [
                    'All',
                    'Draft',
                    'Partially Sent',
                    'Sent',
                    'Archived',
                  ],
                  onChanged: (v) => setState(() {
                    _filterStatus = v!;
                    _selectedStatCard = null;
                    _statCardFilter = null;
                    _currentPage = 1;
                  }),
                ),
                Tooltip(
                  message:
                      'Only approved event proposals that issue certificates can be selected.',
                  child: ElevatedButton.icon(
                    onPressed: _openGenerateFlow,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: Text(
                      'Generate Certificate',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UpriseColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTable(bool isMobile, bool isTablet) {
    final horizontalMargin = isMobile ? 12.0 : (isTablet ? 16.0 : 28.0);

    return Builder(
      builder: (context) {
        if (_certsError != null && _allBatches == null) {
          return Center(child: Text('Error: $_certsError'));
        }
        // The page shell (stat cards, toolbar, table header) is already on
        // screen; only the rows wait on the first snapshot.
        final loading = _allBatches == null;
        var batches = _allBatches ?? const <CertificateBatch>[];

        // Archived batches are hidden from every other filter (including
        // "All") and only surface when "Archived" is explicitly selected —
        // same active/archived split as the reports page. Without this,
        // an archived batch never actually left the default table view.
        if (_filterStatus == 'Archived') {
          batches = batches.where((b) => b.isArchived).toList();
        } else {
          batches = batches.where((b) => !b.isArchived).toList();
          if (_filterStatus != 'All') {
            final key = _filterStatus.toLowerCase().replaceAll(' ', '_');
            batches = batches.where((b) => b.batchStatus == key).toList();
          }
        }
        if (_statCardFilter != null) {
          batches = batches.where(_statCardFilter!).toList();
        }
        if (_searchQuery.isNotEmpty) {
          batches = batches.where((b) {
            final name = b.eventName.toLowerCase();
            final org = b.organization.toLowerCase();
            final id = 'CERT-${b.primary.id.substring(0, 4).toUpperCase()}'
                .toLowerCase();
            return name.contains(_searchQuery) ||
                org.contains(_searchQuery) ||
                id.contains(_searchQuery);
          }).toList();
        }

        final totalPages = batches.isEmpty
            ? 1
            : (batches.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, batches.length);
        final pageItems = batches.isEmpty
            ? <CertificateBatch>[]
            : batches.sublist(start, end);

        final tableContent = Container(
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
          clipBehavior: Clip.antiAlias,
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
                child: loading
                    ? _buildSkeletonRows()
                    : batches.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageItems.length,
                        itemBuilder: (_, i) =>
                            _buildRow(pageItems[i], i == pageItems.length - 1),
                      ),
              ),
              if (!loading)
                _buildFooter(batches.length, totalPages, start, end, isMobile),
            ],
          ),
        );

        // Same fix as org_event_proposals.dart's table: the columns use
        // Expanded, which needs a bounded width to divide up — handing this
        // straight to a horizontal SingleChildScrollView gives it unbounded
        // width instead (that's what the scroll axis means) and crashes
        // every Expanded column on narrow screens. Pinning it to a fixed,
        // comfortably-readable width gives Expanded something concrete to
        // work with, and that fixed width is what actually scrolls
        // sideways — same clean table look on mobile as everywhere else,
        // instead of switching to a different card layout.
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
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: const Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _headerCell('EVENT NAME')),
          Expanded(flex: 2, child: _headerCell('DATE ISSUED')),
          Expanded(flex: 2, child: _headerCell('RECIPIENTS')),
          Expanded(flex: 2, child: _headerCell('STATUS')),
          Expanded(
            flex: 3,
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
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildRow(CertificateBatch b, bool isLast) {
    final r = b.primary;
    return InkWell(
      hoverColor: UpriseColors.primaryDark.withAlpha(10),
      onTap: () => _viewBatch(b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  b.eventName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('MMM d, yyyy').format(b.date),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(flex: 2, child: _recipientsCell(b)),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _batchBadge(b.batchStatus),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OrgActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View',
                    color: const Color(0xFF3B82F6),
                    onTap: () => _viewBatch(b),
                  ),
                  const SizedBox(width: 6),
                  if (b.batchStatus == 'draft' && r.eventId != null)
                    OrgActionIconButton(
                      icon: Icons.send_outlined,
                      tooltip: 'Send Certificates',
                      color: const Color(0xFF2563EB),
                      onTap: () => _sendCertificates(r),
                    ),
                  // OrgActionIconButton's own InkWell(onTap: null) doesn't
                  // block the tap from bubbling up to this row's outer
                  // InkWell (onTap: () => _viewBatch(b)) — a "disabled"
                  // edit icon on a locked batch still opened the view
                  // dialog when clicked. Not showing the icon at all for a
                  // locked batch sidesteps that entirely instead of trying
                  // to keep a truly inert disabled state.
                  if (b.isEditable) ...[
                    OrgActionIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      color: UpriseColors.primaryDark,
                      onTap: () => _editCert(r),
                    ),
                    const SizedBox(width: 6),
                  ],
                  OrgActionIconButton(
                    icon: b.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    tooltip: b.isArchived ? 'Unarchive' : 'Archive',
                    color: const Color(0xFF6B7280),
                    onTap: () => _toggleArchive(b),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonRows() {
    Widget bar(double w) => Container(
      width: w,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Align(alignment: Alignment.centerLeft, child: bar(180)),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerLeft, child: bar(80)),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerLeft, child: bar(60)),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerLeft, child: bar(70)),
            ),
            Expanded(
              flex: 3,
              child: Align(alignment: Alignment.centerRight, child: bar(90)),
            ),
          ],
        ),
      ),
    );
  }

  // One quantity on every row — how many of this event's recipients are
  // holding their certificate — instead of a bare headcount on draft rows
  // and a ratio on sent ones. The bare number was also wrong: a draft batch
  // is a single placeholder doc, so it always printed "1" however many
  // people the draft was for.
  Widget _recipientsCell(CertificateBatch b) {
    final total = b.totalRecipients;
    final sent = b.sentCount;
    final progress = total == 0 ? 0.0 : (sent / total).clamp(0.0, 1.0);
    final done = total > 0 && sent >= total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$sent / $total',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A202C),
          ),
        ),
        const SizedBox(height: 5),
        // The same fact as the fraction, read without parsing it — this is
        // what lets you spot the one half-finished batch in a column of ten
        // by looking instead of by reading.
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 72,
            height: 4,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFE8ECF0),
              valueColor: AlwaysStoppedAnimation<Color>(
                done ? UpriseColors.success : UpriseColors.primaryDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _viewBatch(CertificateBatch b) =>
      setState(() => _detailBatchKey = b.batchKey);

  void _closeDetailPage() => setState(() => _detailBatchKey = null);

  // Resolved from the live stream rather than from the CertificateBatch the
  // row handed over, so the counts and the status badge on this page move
  // the moment a certificate is issued from it.
  Widget _buildDetailPage(String batchKey) {
    return Builder(
      builder: (context) {
        final batches = _allBatches;
        if (batches == null) {
          return const Center(child: CircularProgressIndicator());
        }
        CertificateBatch? found;
        for (final candidate in batches) {
          if (candidate.batchKey == batchKey) {
            found = candidate;
            break;
          }
        }
        // The last certificate in a batch can be deleted out from under this
        // page while it is open. There is nothing left to show, so go back
        // instead of rendering an empty shell.
        if (found == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _closeDetailPage();
          });
          return const SizedBox.shrink();
        }
        final b = found;
        return _BatchDetailPage(
          key: ValueKey(batchKey),
          batch: b,
          eventId: b.eventId ?? '',
          onBack: _closeDetailPage,
          onSendAll: () => _sendCertificates(b.primary),
          onSendSingle: (key, name, isGuest) => _sendSingleCertificate(
            draftMeta: b.primary,
            eventId: b.eventId ?? '',
            recipientKey: key,
            recipientName: name,
            isGuest: isGuest,
          ),
          onResend: (record) => _resendCertificate(record),
        );
      },
    );
  }

  void _editCert(CertificateRecord r) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _GenerateCertificateModal(
        orgId: widget.orgId,
        selectedTemplateType: r.templateType,
        selectedTemplateUrl: r.templateFileUrl,
        existingRecord: r,
      ),
    );
  }

  Future<void> _sendSingleCertificate({
    required CertificateRecord draftMeta,
    required String eventId,
    required String recipientKey,
    required String recipientName,
    required bool isGuest,
  }) async {
    final docRef = FirebaseFirestore.instance
        .collection('certificates')
        .doc('${eventId}_$recipientKey');

    await docRef.set({
      'orgId': widget.orgId,
      'eventId': eventId,
      'eventName': draftMeta.eventName,
      'organization': draftMeta.organization,
      'templateType': draftMeta.templateType,
      'type': draftMeta.type,
      'issuedAt': FieldValue.serverTimestamp(),
      'status': 'distributed',
      'recipients': 1,
      'recipientName': recipientName,
      'isGuest': isGuest,
      'recipientId': recipientKey,
      'recipientUid': recipientKey,
      if (isGuest) 'recipientEmail': recipientKey,
      'verificationCode': _generateVerificationCode(),
      'templateFileUrl': draftMeta.templateFileUrl,
      'namePlacement': draftMeta.namePlacement,
      'signatoryPlacements': draftMeta.signatoryPlacements,
      'sendStatus': 'sent',
      'resendCount': 0,
    }, SetOptions(merge: true));

    // Same cleanup as _sendCertificates/_GenerateCertificateModal's distribute
    // flow — sending recipients one at a time via this button never touched
    // the draft placeholder record, so it stuck around and permanently
    // inflated this batch's totalRecipients count by 1, keeping it stuck on
    // "Partially Sent" forever even once every recipient had their
    // certificate.
    if (draftMeta.status == 'draft') {
      await FirebaseFirestore.instance
          .collection('certificates')
          .doc(draftMeta.id)
          .delete();
    }

    if (!isGuest) {
      await NotificationService.sendToUser(
        userId: recipientKey,
        title: 'Your certificate is ready 🎓',
        body: 'Your certificate for "${draftMeta.eventName}" has been issued.',
        type: 'certificate',
        orgId: widget.orgId,
        data: {'eventId': eventId},
      );
    }
    // No pop. This used to dismiss the dialog it was raised from, but the
    // batch detail view is a page now — the only route left to pop is the
    // dashboard itself. The page re-reads its recipient list when this
    // returns, and the table behind it is on a stream.
    if (mounted) setState(() {});
  }

  Future<void> _toggleArchive(CertificateBatch b) async {
    final newValue = !b.isArchived;
    final batchWrite = FirebaseFirestore.instance.batch();
    for (final r in b.records) {
      batchWrite.update(
        FirebaseFirestore.instance.collection('certificates').doc(r.id),
        {'archived': newValue},
      );
    }
    try {
      await batchWrite.commit();
      await activity_log.ActivityLogger.log(
        action: newValue
            ? 'archive_certificate_batch'
            : 'unarchive_certificate_batch',
        module: 'certificates',
        details: {'eventName': b.eventName, 'recipients': b.totalRecipients},
      );
      _showToast(newValue ? 'Batch archived.' : 'Batch restored.');
    } catch (e) {
      _showToast('Error: $e', isError: true);
    }
  }

  Future<void> _sendCertificates(CertificateRecord draft) async {
    final eventId = draft.eventId;
    if (eventId == null || eventId.isEmpty) {
      _showToast('This draft is not linked to an event.', isError: true);
      return;
    }

    final attSnap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('attendances')
        .where('status', whereIn: ['present', 'late'])
        .get();

    final fbDocs = await _fetchAllFeedbackForEvent(eventId);

    final eligibleKeys = <String>{};
    final eligibleNames = <String, String>{};

    for (final doc in attSnap.docs) {
      final data = doc.data();
      final isGuest = data['isGuest'] == true;
      String key;
      String name;
      if (isGuest) {
        key = (data['guestEmail'] ?? '').toString().trim();
        name = (data['studentName'] ?? 'Guest').toString();
      } else {
        key = (data['studentId'] ?? '').toString();
        name = (data['studentName'] ?? 'Unknown').toString();
      }
      if (key.isEmpty) continue;

      final hasFeedback = fbDocs.any((fb) {
        final fbData = fb.data();
        if (isGuest) {
          return _feedbackMarkedGuest(fbData) && fbData['guestEmail'] == key;
        } else {
          return fbData['userId'] == key;
        }
      });
      if (hasFeedback) {
        eligibleKeys.add(key);
        eligibleNames[key] = name;
      }
    }

    if (eligibleKeys.isEmpty) {
      _showToast('No eligible attendees found (attended + evaluated).');
      return;
    }

    final certSnap = await FirebaseFirestore.instance
        .collection('certificates')
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'distributed')
        .get();
    final existingKeys = <String>{};
    for (final doc in certSnap.docs) {
      final data = doc.data();
      final uid = data['recipientUid'] as String?;
      final email = data['recipientEmail'] as String?;
      if (uid != null && uid.isNotEmpty) existingKeys.add(uid);
      if (email != null && email.isNotEmpty) existingKeys.add(email);
    }

    final toIssue = eligibleKeys.difference(existingKeys);
    if (toIssue.isEmpty) {
      _showToast('All eligible attendees already have their certificates.');
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    final certsRef = FirebaseFirestore.instance.collection('certificates');

    for (final key in toIssue) {
      final name = eligibleNames[key] ?? 'Student';
      final docRef = certsRef.doc();
      batch.set(docRef, {
        'orgId': widget.orgId,
        'eventId': eventId,
        'eventName': draft.eventName,
        'organization': draft.organization,
        'templateType': draft.templateType,
        'type': draft.type,
        'issuedAt': FieldValue.serverTimestamp(),
        'status': 'distributed',
        'recipients': 1,
        'recipientName': name,
        'recipientUid': key,
        'recipientEmail': key,
        'verificationCode': _generateVerificationCode(),
        'templateFileUrl': draft.templateFileUrl,
        'namePlacement': draft.namePlacement,
        'signatoryPlacements': draft.signatoryPlacements,
        'sendStatus': 'sent',
        'resendCount': 0,
      });
    }
    await batch.commit();

    // The draft placeholder doc (one record standing in for N intended
    // recipients, via its own 'recipients' field) is now superseded by real
    // per-recipient 'distributed' docs — CertificateBatch counts raw docs
    // for totalRecipients, not that field, so leaving the draft in place
    // permanently inflated the count by 1 and kept the batch stuck showing
    // "Partially Sent" even after every eligible recipient had their
    // certificate. Safe to delete only when this really is the draft
    // record (this function also gets called with an already-distributed
    // record as the metadata source when sending more from a batch that's
    // already past draft, which shouldn't touch anything here).
    if (draft.status == 'draft') {
      await FirebaseFirestore.instance
          .collection('certificates')
          .doc(draft.id)
          .delete();
    }

    for (final key in toIssue) {
      if (!key.contains('@')) {
        await NotificationService.sendToUser(
          userId: key,
          title: 'Your certificate is ready 🎓',
          body: 'Your certificate for "${draft.eventName}" has been issued.',
          type: 'certificate',
          orgId: widget.orgId,
          data: {'eventId': eventId},
        );
      }
    }

    _showToast('Sent ${toIssue.length} certificate(s).');
    // Same as _sendSingleCertificate: no pop. This one was also reachable
    // from the table's own Send icon, where there was never a dialog open
    // to close in the first place.
    if (mounted) setState(() {});
  }

  Future<void> _resendCertificate(CertificateRecord r) async {
    try {
      await FirebaseFirestore.instance
          .collection('certificates')
          .doc(r.id)
          .update({
            'sendStatus': 'resent',
            'resendCount': FieldValue.increment(1),
            'lastResentAt': FieldValue.serverTimestamp(),
          });

      final recipientKey = r.recipientName;
      final doc = await FirebaseFirestore.instance
          .collection('certificates')
          .doc(r.id)
          .get();
      final uid = (doc.data()?['recipientUid'] as String?) ?? '';
      if (uid.isNotEmpty && !uid.contains('@')) {
        await NotificationService.sendToUser(
          userId: uid,
          title: 'Your certificate was resent 🎓',
          body: 'Your certificate for "${r.eventName}" has been resent.',
          type: 'certificate',
          orgId: widget.orgId,
          data: {'eventId': r.eventId ?? ''},
        );
      }

      await activity_log.ActivityLogger.log(
        action: 'resend_certificate',
        module: 'certificates',
        details: {
          'certId': r.id,
          'eventName': r.eventName,
          'recipient': recipientKey,
        },
      );
      _showToast('Certificate resent.');
    } catch (e) {
      _showToast('Error resending: $e', isError: true);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      isError ? AppToast.error(context, msg) : AppToast.success(context, msg);
    });
  }

  String _generateVerificationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = math.Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
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
              Icons.card_membership_outlined,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No certificates issued yet',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Click "Generate Certificate" to create your first one.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _openGenerateFlow,
            icon: const Icon(Icons.add_rounded, size: 15),
            label: Text(
              'Generate Certificate',
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

  Widget _buildFooter(
    int total,
    int totalPages,
    int start,
    int end,
    bool isMobile,
  ) {
    final int maxVisible = isMobile ? 3 : 5;
    int firstPage = (_currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    if (lastPage - firstPage + 1 < maxVisible && firstPage > 1) {
      firstPage = (lastPage - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: isMobile
          ? Column(
              spacing: 12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Showing ${total == 0 ? 0 : start + 1}–$end of $total',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          onTap: () =>
                              setState(() => _currentPage = totalPages),
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
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${total == 0 ? 0 : start + 1}–$end of $total certificate batches',
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
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────
class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
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
          color: UpriseColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: UpriseColors.mediumGray),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: UpriseColors.charcoal,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: UpriseColors.greyText,
            ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => MouseRegion(
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

// ─────────────────────────────────────────────────────────────────────────────
// BATCH DETAIL PAGE - The View button destination
// ─────────────────────────────────────────────────────────────────────────────
class _BatchDetailPage extends StatefulWidget {
  final CertificateBatch batch;
  final String eventId;
  final VoidCallback onBack;
  // Awaited, not fired and forgotten: the page stays on screen afterwards
  // and has to re-read its recipient list once the write lands.
  final Future<void> Function() onSendAll;
  final Future<void> Function(String key, String name, bool isGuest)
  onSendSingle;
  final Future<void> Function(CertificateRecord record) onResend;

  const _BatchDetailPage({
    super.key,
    required this.batch,
    required this.eventId,
    required this.onBack,
    required this.onSendAll,
    required this.onSendSingle,
    required this.onResend,
  });

  @override
  State<_BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<_BatchDetailPage> {
  // 'All' | 'evaluated' | 'waiting' | 'ready' — set by tapping a summary
  // card, filters the recipient list below to just that status.
  String _statusFilter = 'All';
  // 'All' is also the untouched default, so without this the Total card
  // would render pre-highlighted on open even though nothing was clicked.
  bool _filterTouched = false;

  // fetchRecipientStatus does 3 sequential Firestore reads (attendances,
  // feedback across two collections, certificates) — it was being called
  // fresh inline in TWO separate FutureBuilders (footer button + body),
  // so it re-ran twice on open and AGAIN on every rebuild (e.g. tapping a
  // summary card to filter), which is what made this one modal feel so
  // much slower than every other one. Caching it once here means both
  // FutureBuilders below share the same in-flight/completed future.
  late Future<List<_RecipientStatusRow>> _recipientStatusFuture =
      fetchRecipientStatus(widget.eventId);

  // The modal this replaced was closed by its own send handlers, so a
  // one-shot cache never had to outlive a send. A page stays open, so the
  // recipient list has to be re-read afterwards or it goes on listing
  // people as waiting who already have their certificate.
  Future<void> _runSend(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    setState(() {
      _recipientStatusFuture = fetchRecipientStatus(widget.eventId);
    });
  }

  // Same admin remark shown in the Import Template modal's Signatories
  // section (signatoryAuthorization.remarks on the originating proposal)
  // — this view had no way to see it at all, so events -> proposal ->
  // remarks is resolved once here too.
  late final Future<String?> _adminRemarksFuture = _loadAdminRemarks();

  Future<String?> _loadAdminRemarks() async {
    if (widget.eventId.isEmpty) return null;
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();
      final proposalId = eventDoc.data()?['createdFromProposalId'] as String?;
      if (proposalId == null || proposalId.isEmpty) return null;
      final proposalDoc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .get();
      final auth = proposalDoc.data()?['signatoryAuthorization'];
      if (auth is! Map) return null;
      final remarks = (auth['remarks'] as String?)?.trim() ?? '';
      return remarks.isEmpty ? null : remarks;
    } catch (_) {
      return null;
    }
  }

  // Held in state, not created inside build: a fresh `.snapshots()` per
  // build handed the StreamBuilder a "new" stream every time, so the preview
  // tore down and re-subscribed on every filter tap or batch update.
  late final Stream<QuerySnapshot> _signatoriesStream = FirebaseFirestore
      .instance
      .collection('signatories')
      .snapshots();

  Widget _cardShell({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: UpriseColors.darkGray,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // A compact strip, not four cards: the four numbers are also the recipient
  // list's filters, so each stays a tappable inline "Label 12".
  Widget _buildSummaryStrip(
    int total,
    int evaluated,
    int awaitingEval,
    int readyToSend,
  ) {
    void toggle(String value) => setState(() {
      _filterTouched = true;
      _statusFilter = _statusFilter == value ? 'All' : value;
    });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      // Wrap, not Row: at a narrow column four label+number pairs would
      // otherwise overflow rather than move to a second line.
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        children: [
          _StatusSummaryItem(
            label: 'Total',
            count: total,
            color: UpriseColors.charcoal,
            isSelected: _statusFilter == 'All' && _filterTouched,
            onTap: () => setState(() {
              _statusFilter = 'All';
              _filterTouched = true;
            }),
          ),
          _StatusSummaryItem(
            label: 'Evaluated',
            count: evaluated,
            color: UpriseColors.success,
            isSelected: _statusFilter == 'evaluated',
            onTap: () => toggle('evaluated'),
          ),
          _StatusSummaryItem(
            label: 'Waiting',
            count: awaitingEval,
            color: UpriseColors.warning,
            isSelected: _statusFilter == 'waiting',
            onTap: () => toggle('waiting'),
          ),
          _StatusSummaryItem(
            label: 'Ready',
            count: readyToSend,
            color: UpriseColors.primaryDark,
            isSelected: _statusFilter == 'ready',
            onTap: () => toggle('ready'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientRow(CertificateBatch b, _RecipientStatusRow row) {
    final bool canSend = row.evaluated && !row.certSent;
    final bool awaitingEval = !row.evaluated;

    Widget action;
    if (awaitingEval) {
      action = Text(
        'Waiting',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          color: const Color(0xFF9AA5B4),
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (canSend) {
      action = ElevatedButton.icon(
        onPressed: () async {
          await _runSend(
            () => widget.onSendSingle(row.key, row.name, row.isGuest),
          );
        },
        icon: const Icon(Icons.send_rounded, size: 14),
        label: const Text('Send'),
        style: ElevatedButton.styleFrom(
          backgroundColor: UpriseColors.primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
      );
    } else if (row.certSent) {
      action = OutlinedButton.icon(
        onPressed: () {
          // Find the existing record for this recipient
          final record = b.records.firstWhere(
            (r) => r.recipientName == row.name,
            orElse: () => b.records.first,
          );
          widget.onResend(record);
        },
        icon: const Icon(Icons.refresh_rounded, size: 14),
        label: Text(
          row.resendCount > 0 ? 'Resend ×${row.resendCount + 1}' : 'Resend',
          style: GoogleFonts.beVietnamPro(fontSize: 11),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: BorderSide(color: UpriseColors.primaryDark.withAlpha(100)),
        ),
      );
    } else {
      action = const SizedBox.shrink();
    }

    // Name over status, action on the right — every row reads the same way.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 3),
                _buildStatusBadge(row),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }

  Widget _buildRecipientsList(
    CertificateBatch b,
    List<_RecipientStatusRow> rows,
  ) {
    final filteredRows = switch (_statusFilter) {
      'evaluated' => rows.where((r) => r.evaluated),
      'waiting' => rows.where((r) => !r.evaluated),
      'ready' => rows.where((r) => r.evaluated && !r.certSent),
      _ => rows,
    }.toList();

    if (filteredRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No recipients match this filter.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      );
    }
    // Sized to its rows, so a batch with two recipients is a short card
    // rather than a tall one with a void under the list; a long list stops
    // growing at the cap and scrolls inside it.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: filteredRows.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (_, i) => _buildRecipientRow(b, filteredRows[i]),
      ),
    );
  }

  // A white bar with a back arrow, because this sits directly under
  // org_dashboard.dart's own top bar and a second heavy banner would just be
  // page chrome twice. "Send All Eligible" rides up here where it stays put
  // while the page scrolls.
  Widget _buildPageHeader(CertificateBatch b) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: UpriseColors.primaryDark,
              size: 20,
            ),
            tooltip: 'Back to Certificates',
            onPressed: widget.onBack,
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(20),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.card_membership_outlined,
              color: UpriseColors.primaryDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  b.eventName,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A202C),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Certificate distribution • ${b.sentCount} of '
                  '${b.totalRecipients} recipient'
                  '${b.totalRecipients == 1 ? '' : 's'} sent',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _batchBadge(b.batchStatus),
          const SizedBox(width: 12),
          FutureBuilder<List<_RecipientStatusRow>>(
            future: _recipientStatusFuture,
            builder: (context, snapshot) {
              final hasEligible =
                  snapshot.data?.any((r) => r.evaluated && !r.certSent) ??
                  false;
              return ElevatedButton.icon(
                onPressed: hasEligible
                    ? () => _runSend(widget.onSendAll)
                    : null,
                icon: const Icon(Icons.send_rounded, size: 15),
                label: Text(
                  hasEligible ? 'Send All Eligible' : 'No One to Send',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasEligible
                      ? UpriseColors.primaryDark
                      : UpriseColors.darkGray,
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
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final eventId = widget.eventId;

    if (eventId.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(b),
          Expanded(
            child: Center(
              child: Text(
                'This batch is not linked to an event.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(b),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < 900;
              // The preview does not wait on the recipient reads: only the
              // distribution card below is inside the FutureBuilder.
              final preview = _buildTemplatePreview(b);
              final distribution = FutureBuilder<List<_RecipientStatusRow>>(
                future: _recipientStatusFuture,
                builder: (context, snapshot) =>
                    _buildDistributionCard(b, snapshot),
              );
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          preview,
                          const SizedBox(height: 16),
                          distribution,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: preview),
                          const SizedBox(width: 20),
                          Expanded(flex: 5, child: distribution),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionCard(
    CertificateBatch b,
    AsyncSnapshot<List<_RecipientStatusRow>> snapshot,
  ) {
    Widget body;
    if (snapshot.connectionState == ConnectionState.waiting) {
      Widget bar(double w) => Container(
        width: w,
        height: 12,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF1F5),
          borderRadius: BorderRadius.circular(4),
        ),
      );
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(220), bar(160), bar(190)],
      );
    } else if (snapshot.hasError) {
      body = Text(
        'Error: ${snapshot.error}',
        style: GoogleFonts.beVietnamPro(color: UpriseColors.error),
      );
    } else {
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) {
        body = Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No attendees found for this event.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        );
      } else {
        final total = rows.length;
        final evaluated = rows.where((r) => r.evaluated).length;
        final sent = rows.where((r) => r.certSent).length;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryStrip(
              total,
              evaluated,
              total - evaluated,
              evaluated - sent,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Recipients become ready once they attended (present or '
                    'late) and submitted the event evaluation.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'RECIPIENTS',
              style: GoogleFonts.beVietnamPro(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: UpriseColors.darkGray,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 2),
            _buildRecipientsList(b, rows),
          ],
        );
      }
    }
    return _cardShell(label: 'DISTRIBUTION', child: body);
  }

  Widget _buildTemplatePreview(CertificateBatch b) {
    final r = b.primary;
    return _cardShell(
      label: 'CERTIFICATE PREVIEW',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE8ECF0)),
            borderRadius: BorderRadius.circular(10),
          ),
          // The certificate keeps its own 600:424 ratio at whatever width the
          // card has, instead of a fixed-height box that letterboxed it.
          child: AspectRatio(
            aspectRatio: 600 / 424,
            child: r.templateFileUrl != null
                // A custom template's recipient name and signatories are laid
                // over the image at render time (same as the Generate modal's
                // Live Preview), not baked into the file. '[Recipient Name]'
                // marks this as a preview of the design, not one recipient's
                // certificate.
                ? StreamBuilder<QuerySnapshot>(
                    stream: _signatoriesStream,
                    builder: (context, snap) {
                      final signatories = <String, SignatoryData>{};
                      for (final doc in (snap.data?.docs ?? [])) {
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        final id = doc.id;
                        signatories[id] = SignatoryData(
                          id: id,
                          placeholderKey: id,
                          fullName: (data['fullName'] ?? '').toString(),
                          title: (data['title'] ?? '').toString(),
                          signatureBase64: data['signatureBase64'] as String?,
                        );
                      }

                      final rawPlacements = r.signatoryPlacements ?? {};
                      final validPlacements = <String, CertNamePlacement>{};
                      for (final entry in rawPlacements.entries) {
                        if (!signatories.containsKey(entry.key)) continue;
                        validPlacements[entry.key] = CertNamePlacement.fromMap(
                          entry.value is Map
                              ? Map<String, dynamic>.from(entry.value as Map)
                              : null,
                        );
                      }

                      return FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 600,
                          height: 424,
                          child: _CertificateComposite(
                            recipientName: '[Recipient Name]',
                            namePlacement: CertNamePlacement.fromMap(
                              r.namePlacement,
                            ),
                            signatoryPlacements: validPlacements,
                            signatories: signatories,
                            background: _previewImageProvider(
                              r.templateFileUrl!,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                // CertificatePreview lays itself out at fixed sizing, so it is
                // rendered at its real 600x424 and uniformly scaled down.
                : FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 600,
                      height: 424,
                      child: CertificatePreview(
                        theme: CertTheme.forType(
                          r.templateType,
                          primaryDark: UpriseColors.primaryDark,
                          primaryLight: UpriseColors.primaryLight,
                          accentColor: UpriseColors.accent,
                        ),
                        orgName: r.organization,
                        eventTitle: r.eventName,
                        eventDate: DateFormat('MMMM dd, yyyy').format(r.date),
                        recipient: '[Recipient Name]',
                        signatories: r.signatories.isNotEmpty
                            ? r.signatories
                                  .map(
                                    (s) => CertSignatory(
                                      name: (s['name'] ?? '').toString(),
                                      title: (s['title'] ?? '').toString(),
                                      signatureImageBase64:
                                          s['signatureImage'] as String?,
                                    ),
                                  )
                                  .toList()
                            : (r.signatureImage != null
                                  ? [
                                      CertSignatory(
                                        name: 'Authorized Signatory',
                                        signatureImageBase64: r.signatureImage,
                                      ),
                                    ]
                                  : const []),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(_RecipientStatusRow row) {
    String label;
    Color fg;

    if (!row.evaluated) {
      label = 'Awaiting Eval';
      fg = Colors.grey[500]!;
    } else if (!row.certSent) {
      label = 'Ready to Send';
      fg = UpriseColors.warning;
    } else if (row.resendCount > 0) {
      label = 'Resent';
      fg = const Color(0xFF7C3AED);
    } else {
      label = 'Sent';
      fg = UpriseColors.success;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The rest of the file (CertificateComposite, GenerateCertificateModal,
// ImportTemplateModal, etc.) goes here unchanged
// ─────────────────────────────────────────────────────────────────────────────

// NOTE: The remaining code for _CertificateComposite, _GenerateCertificateModal,
// _CertPreviewDialog, and _ImportTemplateModal should be copied from your
// original file as they are unchanged. They are omitted here for brevity.
class _CertificateComposite extends StatelessWidget {
  final ImageProvider background;
  final String recipientName;
  final CertNamePlacement namePlacement;
  final Map<String, CertNamePlacement> signatoryPlacements; // key -> position
  final Map<String, SignatoryData> signatories; // key -> resolved signatory

  const _CertificateComposite({
    required this.background,
    required this.recipientName,
    required this.namePlacement,
    this.signatoryPlacements = const {},
    this.signatories = const {},
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = constraints.biggest;
        // Auto-resize (requirement #1): reserve ~65% of the canvas width for
        // the name so it never overflows the certificate layout, regardless
        // of how long the recipient's name is.
        // Box-model placements fit the name to their own field width inside
        // CertificateImageWithName; only older placements use this estimate.
        final fittedFontSize = namePlacement.isBox
            ? namePlacement.fontSize
            : _autoFitFontSize(
                text: recipientName,
                baseFontSize: namePlacement.fontSize,
                maxWidthPx: boxSize.width * 0.65,
              );
        final effectivePlacement = namePlacement.copyWith(
          fontSize: fittedFontSize,
        );
        final scale = boxSize.width / CertificateImageWithName.referenceWidth;

        return Stack(
          children: [
            Positioned.fill(
              child: CertificateImageWithName(
                recipientName: recipientName,
                placement: effectivePlacement,
                background: Image(image: background, fit: BoxFit.cover),
              ),
            ),
            for (final entry in signatoryPlacements.entries)
              if (signatories.containsKey(entry.key) &&
                  (signatories[entry.key]!.fullName.isNotEmpty ||
                      (signatories[entry.key]!.signatureBase64?.isNotEmpty ??
                          false)))
                if (entry.value.isBox)
                  certPlaceBoxField(
                    placement: entry.value,
                    canvas: boxSize,
                    child: CertSignatoryBlock(
                      placement: entry.value,
                      name: signatories[entry.key]!.fullName,
                      title: signatories[entry.key]!.title,
                      signatureBase64: signatories[entry.key]!.signatureBase64,
                      scale: scale,
                    ),
                  )
                else
                  _buildSignatoryOverlay(
                    boxSize: boxSize,
                    placement: entry.value,
                    signatory: signatories[entry.key]!,
                  ),
          ],
        );
      },
    );
  }

  Widget _buildSignatoryOverlay({
    required Size boxSize,
    required CertNamePlacement placement,
    required SignatoryData signatory,
  }) {
    const overlayWidth = 130.0;
    final left = (placement.xPct * boxSize.width - overlayWidth / 2)
        .clamp(0.0, math.max(0.0, boxSize.width - overlayWidth))
        .toDouble();
    final top = (placement.yPct * boxSize.height - 30)
        .clamp(0.0, math.max(0.0, boxSize.height - 60))
        .toDouble();
    final textColor = placement.light ? Colors.white : const Color(0xFF1A202C);

    return Positioned(
      left: left,
      top: top,
      width: overlayWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ⭐ SHOW THE SIGNATURE IMAGE
          if (signatory.signatureBase64 != null &&
              signatory.signatureBase64!.isNotEmpty)
            SizedBox(
              height: 40,
              child: Image.memory(
                base64Decode(signatory.signatureBase64!),
                fit: BoxFit.contain,
              ),
            ),
          // Show the name
          Text(
            signatory.fullName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.beVietnamPro(
              fontSize: (placement.fontSize * 0.7).clamp(9, 14),
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          // Show the title
          if (signatory.title.isNotEmpty)
            Text(
              signatory.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: (placement.fontSize * 0.55).clamp(8, 12),
                color: textColor.withOpacity(0.85),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generate Certificate Modal — event comes first, certificates are only
// distributed for attendees who attended and evaluated the event.
// ─────────────────────────────────────────────────────────────────────────────
class _GenerateCertificateModal extends StatefulWidget {
  final String orgId;
  final String selectedTemplateType;
  final String? selectedTemplateUrl;
  final CertificateRecord? existingRecord;
  const _GenerateCertificateModal({
    required this.orgId,
    required this.selectedTemplateType,
    this.selectedTemplateUrl,
    this.existingRecord,
  });

  @override
  State<_GenerateCertificateModal> createState() =>
      _GenerateCertificateModalState();
}

class _GenerateCertificateModalState extends State<_GenerateCertificateModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  String? _selectedEventId;
  String? _selectedEventName;
  String? _selectedEventDocId;

  // Attendees who showed up AND submitted their event evaluation —
  // these are exactly who "Generate & Distribute" issues a certificate to.
  List<Map<String, String>> _eligibleRecipients = [];
  int _attendeeCount = 0;
  bool _attendanceSynced = false;
  bool get _hasEligibleRecipients => _eligibleRecipients.isNotEmpty;

  String? _selectedTemplateUrl;
  CertNamePlacement? _selectedTemplatePlacement;
  // NEW: key -> placement for any signatories placed on this template.
  Map<String, CertNamePlacement> _signatoryPlacements = {};
  String _certType = 'Formal Academic';
  bool _isSubmitting = false;

  // Pre-filters to only approved proposals that issue certificates. Created
  // once (not a getter) — re-evaluating .snapshots() on every keystroke was
  // re-subscribing to Firestore on every rebuild and is what caused the lag.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .where('issuesCertificate', isEqualTo: true)
      .orderBy('date', descending: false)
      .snapshots();

  // "Select Event" should only offer events that issue certificates AND
  // don't already have a certificate batch — generating a second one for
  // an event that already has one would create a duplicate, orphaned
  // batch instead of the org just editing the existing one. A `certificate`
  // doc's `eventId` points at the published `events` doc, not the
  // `event_proposals` doc this dropdown lists, so this resolves the
  // proposal -> event -> certificate chain once up front. Resolved once
  // (not re-fetched every rebuild) since it only needs to reflect state as
  // of when this modal opened.
  late final Future<Set<String>> _proposalIdsWithExistingCertFuture =
      _loadProposalIdsWithExistingCert();

  Future<Set<String>> _loadProposalIdsWithExistingCert() async {
    try {
      // Both reads are independent, so they run together.
      final certsFuture = FirebaseFirestore.instance
          .collection('certificates')
          .where('orgId', isEqualTo: widget.orgId)
          .get();
      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .get();
      final eventDocIdToProposalId = <String, String>{};
      for (final doc in eventsSnap.docs) {
        final proposalId = doc.data()['createdFromProposalId'] as String?;
        if (proposalId != null && proposalId.isNotEmpty) {
          eventDocIdToProposalId[doc.id] = proposalId;
        }
      }
      if (eventDocIdToProposalId.isEmpty) {
        // Not awaited below, so swallow its outcome instead of leaving an
        // unhandled error behind.
        certsFuture.ignore();
        return {};
      }

      final certsSnap = await certsFuture;
      final result = <String>{};
      for (final doc in certsSnap.docs) {
        final eventId = doc.data()['eventId'] as String?;
        if (eventId == null) continue;
        final proposalId = eventDocIdToProposalId[eventId];
        if (proposalId != null) result.add(proposalId);
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // NEW: all signatories on file (Admin Settings roster), keyed by
  // placeholderKey, used to resolve _signatoryPlacements to actual
  // name/title/signature at preview & submit time.
  late final Stream<QuerySnapshot> _signatoriesStream = FirebaseFirestore
      .instance
      .collection('signatories')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _certType = widget.selectedTemplateType;
    _selectedTemplateUrl = widget.selectedTemplateUrl;
    _orgCtrl.text = '';
    _dateCtrl.text = DateFormat('MM/dd/yyyy').format(DateTime.now());
    if (widget.existingRecord != null) {
      _titleCtrl.text = widget.existingRecord!.eventName;
      _orgCtrl.text = widget.existingRecord!.organization;
      _dateCtrl.text = DateFormat(
        'MM/dd/yyyy',
      ).format(widget.existingRecord!.date);
      _selectedTemplatePlacement = CertNamePlacement.fromMap(
        widget.existingRecord!.namePlacement,
      );
      final rawPlacements = widget.existingRecord!.signatoryPlacements;
      if (rawPlacements != null) {
        _signatoryPlacements = rawPlacements.map(
          (k, v) => MapEntry(
            k,
            CertNamePlacement.fromMap(Map<String, dynamic>.from(v as Map)),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _orgCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  String _generateVerificationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = math.Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> _openImportTemplate() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _ImportTemplateModal(
        orgId: widget.orgId,
        proposalId: _selectedEventId,
        // Sample text for "Preview as" only; nothing here is ever written back.
        previewNames: [
          for (final r in _eligibleRecipients)
            if ((r['recipientName'] ?? '').isNotEmpty) r['recipientName']!,
        ],
      ),
    );
    if (result != null && result['name'] != null && mounted) {
      setState(() {
        _certType = result['name']!;
        _selectedTemplateUrl = result['url'];
        _selectedTemplatePlacement = CertNamePlacement.fromMap(
          result['namePlacement'] as Map<String, dynamic>?,
        );
        final rawSig = result['signatoryPlacements'] as Map<String, dynamic>?;
        _signatoryPlacements = rawSig == null
            ? {}
            : rawSig.map(
                (k, v) => MapEntry(
                  k,
                  CertNamePlacement.fromMap(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              );
      });
    }
  }

  // Single source of truth for what "the certificate" currently looks like —
  // used both inline in the modal and in the full-size preview dialog, so
  // the two can never show something different from each other.
  Widget _buildPreviewVisual() {
    if (_selectedTemplateUrl != null) {
      return StreamBuilder<QuerySnapshot>(
        stream: _signatoriesStream,
        builder: (context, snap) {
          // Build a map of signatories using their document ID as the key
          final signatories = <String, SignatoryData>{};
          for (final doc in (snap.data?.docs ?? [])) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final id = doc.id; // ← This is the key!
            signatories[id] = SignatoryData(
              id: id,
              placeholderKey: id, // ← Use the document ID as placeholderKey
              fullName: (data['fullName'] ?? '').toString(),
              title: (data['title'] ?? '').toString(),
              signatureBase64: data['signatureBase64'] as String?,
            );
          }

          // ⭐ IMPORTANT: Only use placements that have matching signatories
          final validPlacements = <String, CertNamePlacement>{};
          for (final entry in _signatoryPlacements.entries) {
            if (signatories.containsKey(entry.key)) {
              validPlacements[entry.key] = entry.value;
            }
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            // _CertificateComposite sizes itself from its parent's
            // constraints (LayoutBuilder reading constraints.biggest) —
            // the AspectRatio wrapping this whole preview already gives it
            // a real, bounded size. Wrapping it in a FittedBox additionally
            // measured it at its own "natural" size first, which it
            // doesn't have, so it collapsed to nothing and the preview
            // rendered blank.
            child: LayoutBuilder(
              builder: (context, previewConstraints) {
                final boxSize = previewConstraints.biggest;
                // Dragging used to call the modal's own setState, which
                // rebuilt the entire two-column form on every pointer-move
                // frame — that's what made it feel slow. Scoping the
                // rebuild to this StatefulBuilder means dragging only
                // repaints this small preview Stack; _selectedTemplatePlacement
                // is still updated the same way, so Save/Generate behave
                // identically.
                return StatefulBuilder(
                  builder: (context, setPreviewState) {
                    final livePlacement =
                        _selectedTemplatePlacement ?? const CertNamePlacement();
                    return Stack(
                      children: [
                        _CertificateComposite(
                          recipientName: 'Recipient Name',
                          namePlacement: livePlacement,
                          signatoryPlacements: validPlacements,
                          signatories: signatories,
                          background: _previewImageProvider(
                            _selectedTemplateUrl!,
                          ),
                        ),
                        // Invisible drag handle over the recipient name —
                        // nudges the same xPct/yPct this screen already
                        // saves on Generate & Distribute / Save as Draft.
                        // No visible box, just a grab cursor on hover.
                        Positioned(
                          left: (livePlacement.xPct * boxSize.width - 60).clamp(
                            0.0,
                            math.max(0.0, boxSize.width - 120),
                          ),
                          top: (livePlacement.yPct * boxSize.height - 14).clamp(
                            0.0,
                            math.max(0.0, boxSize.height - 28),
                          ),
                          width: 120,
                          height: 28,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanUpdate: (details) {
                                final newX =
                                    (livePlacement.xPct * boxSize.width +
                                            details.delta.dx)
                                        .clamp(0.0, boxSize.width);
                                final newY =
                                    (livePlacement.yPct * boxSize.height +
                                            details.delta.dy)
                                        .clamp(0.0, boxSize.height);
                                setPreviewState(() {
                                  _selectedTemplatePlacement = livePlacement
                                      .copyWith(
                                        xPct: newX / boxSize.width,
                                        yPct: newY / boxSize.height,
                                      );
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E6EA),
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: 36,
                color: const Color(0xFFB8C2CE),
              ),
              const SizedBox(height: 10),
              Text(
                'Upload your certificate design to see the live preview',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openImportTemplate,
                icon: const Icon(Icons.upload_file_outlined, size: 14),
                label: Text(
                  'Upload Custom Design',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UpriseColors.primaryDark,
                  side: BorderSide(
                    color: UpriseColors.primaryDark.withOpacity(0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreviewFullscreen() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: AspectRatio(
                aspectRatio: 600 / 424,
                child: _buildPreviewVisual(),
              ),
            ),
            Positioned(
              top: -16,
              right: -16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// NEW: which placed signatory keys don't have a matching roster entry
  /// yet. Requirement #2 — block generation with a clear warning instead of
  /// producing an incomplete certificate.
  List<String> _missingSignatoryKeys(List<SignatoryData> roster) {
    final available = roster.map((s) => s.id).toSet();
    return _signatoryPlacements.keys
        .where((k) => !available.contains(k))
        .toList();
  }

  Future<void> _submit({required bool distribute}) async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedTemplateUrl == null) {
      if (mounted) {
        AppToast.error(context, 'Upload your certificate design first.');
      }
      return;
    }
    if (distribute && !_hasEligibleRecipients) {
      if (mounted) {
        AppToast.error(
          context,
          'No attendees have completed their evaluation yet — certificates can only be distributed to attendees who attended and evaluated the event.',
        );
      }
      return;
    }

    // NEW: verify every placed signatory placeholder still resolves to a
    // real signatory before allowing a distribute.
    if (distribute && _signatoryPlacements.isNotEmpty) {
      final rosterSnap = await FirebaseFirestore.instance
          .collection('signatories')
          .get();
      final roster = rosterSnap.docs
          .map((d) => SignatoryData.fromDoc(d))
          .toList();
      final missing = _missingSignatoryKeys(roster);
      if (missing.isNotEmpty) {
        if (mounted) {
          AppToast.error(
            context,
            'Missing signatory data for: ${missing.join(", ")}. Add them in Admin Settings → Signatories first.',
          );
        }
        return;
      }
    }

    setState(() => _isSubmitting = true);

    final eventName = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : (_selectedEventName ?? 'Untitled');

    final signatoryPlacementsMap = {
      for (final e in _signatoryPlacements.entries) e.key: e.value.toMap(),
    };

    try {
      if (distribute) {
        // One verifiable certificate per attendee who attended AND evaluated the event.
        final batch = FirebaseFirestore.instance.batch();
        final certsRef = FirebaseFirestore.instance.collection('certificates');
        for (final r in _eligibleRecipients) {
          final isGuest = r['isGuest'] == 'true';
          final key = r['recipientKey']!;
          final docRef = certsRef.doc('${_selectedEventDocId}_$key');
          batch.set(docRef, {
            'orgId': widget.orgId,
            'eventId': _selectedEventDocId,
            'eventName': eventName,
            'organization': _orgCtrl.text.trim(),
            'templateType': _certType,
            'type': 'Participation',
            'issuedAt': FieldValue.serverTimestamp(),
            'status': 'distributed',
            'recipients': 1,
            'recipientName': r['recipientName'],
            'isGuest': isGuest,
            // recipientUid must always be set, guest or not — the student
            // viewer matches certificates by exact recipientUid equality, so
            // a guest's email here will simply never match any real
            // student's uid. Leaving it unset is what actually causes a
            // leak: this collection has no other "broadcast to everyone"
            // certificate type, so a missing recipientUid has no legitimate
            // meaning here and should never be relied on by a reader.
            'recipientId': key, 'recipientUid': key,
            if (isGuest) 'recipientEmail': key,
            'verificationCode': _generateVerificationCode(),
            'autoGenerated': false,
            if (_selectedTemplateUrl != null)
              'templateFileUrl': _selectedTemplateUrl,
            if (_selectedTemplateUrl != null)
              'namePlacement':
                  (_selectedTemplatePlacement ?? const CertNamePlacement())
                      .toMap(),
            if (signatoryPlacementsMap.isNotEmpty)
              'signatoryPlacements': signatoryPlacementsMap,
            // NEW — send-status tracking (requirement #4).
            'sendStatus': 'sent',
            'resendCount': 0,
          }, SetOptions(merge: true));
        }
        await batch.commit();

        // Same cleanup as _sendCertificates — a draft placeholder record
        // for this event (created by an earlier "Save as Draft") would
        // otherwise stick around and permanently inflate this batch's
        // totalRecipients count by 1, keeping it stuck on "Partially Sent"
        // forever even once every eligible recipient has their certificate.
        if (widget.existingRecord?.status == 'draft') {
          await FirebaseFirestore.instance
              .collection('certificates')
              .doc(widget.existingRecord!.id)
              .delete();
        } else if (_selectedEventDocId != null) {
          final existingDraft = await FirebaseFirestore.instance
              .collection('certificates')
              .where('eventId', isEqualTo: _selectedEventDocId)
              .where('status', isEqualTo: 'draft')
              .limit(1)
              .get();
          if (existingDraft.docs.isNotEmpty) {
            await existingDraft.docs.first.reference.delete();
          }
        }

        // Guests have no `users` doc to notify against — only students get
        // an in-app notification that their certificate is ready.
        await Future.wait(
          _eligibleRecipients
              .where((r) => r['isGuest'] != 'true')
              .map(
                (r) => NotificationService.sendToUser(
                  userId: r['recipientKey']!,
                  title: 'Your certificate is ready 🎓',
                  body: 'Your certificate for "$eventName" has been issued.',
                  type: 'certificate',
                  orgId: widget.orgId,
                  data: {'eventId': _selectedEventDocId ?? ''},
                ),
              ),
        );
      } else {
        // Draft: a single placeholder record, since no certificates are issued yet.
        final payload = <String, dynamic>{
          'orgId': widget.orgId,
          'eventName': eventName,
          'organization': _orgCtrl.text.trim(),
          'templateType': _certType,
          'type': 'Participation',
          'issuedAt': FieldValue.serverTimestamp(),
          'status': 'draft',
          'recipients': _eligibleRecipients.length,
          if (_selectedTemplateUrl != null)
            'templateFileUrl': _selectedTemplateUrl,
          if (_selectedTemplateUrl != null)
            'namePlacement':
                (_selectedTemplatePlacement ?? const CertNamePlacement())
                    .toMap(),
          if (signatoryPlacementsMap.isNotEmpty)
            'signatoryPlacements': signatoryPlacementsMap,
          if (_selectedEventDocId != null) 'eventId': _selectedEventDocId,
        };
        if (widget.existingRecord != null) {
          await FirebaseFirestore.instance
              .collection('certificates')
              .doc(widget.existingRecord!.id)
              .update(payload);
        } else {
          // Check if a draft already exists for this event
          final existing = await FirebaseFirestore.instance
              .collection('certificates')
              .where('eventId', isEqualTo: _selectedEventDocId)
              .where('status', isEqualTo: 'draft')
              .get();
          if (existing.docs.isNotEmpty) {
            // Update the existing draft
            await existing.docs.first.reference.update(payload);
          } else {
            // Create new draft
            await FirebaseFirestore.instance
                .collection('certificates')
                .add(payload);
          }
        }
      }

      await activity_log.ActivityLogger.log(
        action: distribute
            ? 'generate_distribute_certificate'
            : 'save_draft_certificate',
        module: 'certificates',
        details: {
          'orgId': widget.orgId,
          'templateType': _certType,
          'recipients': _eligibleRecipients.length,
        },
      );
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(
          context,
          distribute
              ? 'Distributed ${_eligibleRecipients.length} certificate(s)!'
              : 'Saved as draft.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Attendees who showed up (present/late) AND submitted their event
  /// evaluation. This is the actual recipient list for distribution —
  /// it's recomputed every time so newly-submitted evaluations are picked up.
  ///
  /// Returns both students (keyed by uid) and guests (keyed by email) —
  /// disambiguated via the 'isGuest' flag ('true'/'false' string, since this
  /// method's `Map<String, String>` signature is relied on elsewhere).
  ///
  /// Also returns the total number of attendance records (any status). That
  /// used to be a second, separate read of the same subcollection; the
  /// present/late filter is now applied here instead of in the query, which
  /// selects exactly the same records.
  Future<({int attendeeCount, List<Map<String, String>> eligible})>
  _fetchAttendanceAndEligible(String eventDocId) async {
    // The three reads don't depend on each other, so they run together.
    final attFuture = FirebaseFirestore.instance
        .collection('events')
        .doc(eventDocId)
        .collection('attendances')
        .get();
    final eventFuture = FirebaseFirestore.instance
        .collection('events')
        .doc(eventDocId)
        .get();
    final feedbackFuture = _fetchAllFeedbackForEvent(eventDocId);

    final allAtt = await attFuture;
    final attDocs = allAtt.docs.where((d) {
      final s = d.data()['status'];
      return s == 'present' || s == 'late';
    }).toList();

    // Check if webinar requires check-out
    final eventDoc = await eventFuture;
    final eventData = eventDoc.data() ?? {};
    final isWebinar =
        eventData['type'] == 'webinar' || eventData['isWebinar'] == true;
    final requireCheckOut = eventData['requireCheckOut'] == true;

    // Fetch feedback
    final feedbackDocs = await feedbackFuture;
    final evaluatedUids = feedbackDocs
        .map((d) => d.data()['userId']?.toString())
        .whereType<String>()
        .toSet();
    final evaluatedGuestEmails = feedbackDocs
        .where((d) => _feedbackMarkedGuest(d.data()))
        .map((d) => d.data()['guestEmail']?.toString())
        .whereType<String>()
        .toSet();

    // ✅ Get checked-out students if webinar requires it
    Map<String, bool> checkedOutStudents = {};
    Map<String, bool> checkedOutGuests = {};

    if (isWebinar && requireCheckOut) {
      final subSnap = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventDocId)
          .collection('webinar_submissions')
          .where('type', isEqualTo: 'checkout')
          .get();

      for (final doc in subSnap.docs) {
        final data = doc.data();
        final studentId = data['studentId'] as String?;
        if (studentId != null && studentId.isNotEmpty) {
          checkedOutStudents[studentId] = true;
        }

        final guestEmail = data['guestEmail'] as String?;
        if (guestEmail != null && guestEmail.isNotEmpty) {
          checkedOutGuests[guestEmail] = true;
        }
      }
    }

    final eligible = <Map<String, String>>[];
    for (final doc in attDocs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      if (status != 'present' && status != 'late') continue;

      if (data['isGuest'] == true) {
        final email = (data['guestEmail'] ?? '').toString();
        if (email.isEmpty) continue;

        if (isWebinar &&
            requireCheckOut &&
            !(checkedOutGuests[email] ?? false)) {
          continue;
        }

        if (!evaluatedGuestEmails.contains(email)) continue;
        eligible.add({
          'recipientKey': email,
          'recipientName': (data['studentName'] ?? 'Guest').toString(),
          'isGuest': 'true',
        });
      } else {
        final studentId = (data['studentId'] ?? '').toString();
        if (studentId.isEmpty) continue;

        if (isWebinar &&
            requireCheckOut &&
            !(checkedOutStudents[studentId] ?? false)) {
          continue;
        }

        if (!evaluatedUids.contains(studentId)) continue;
        eligible.add({
          'recipientKey': studentId,
          'recipientName': (data['studentName'] ?? 'Unknown').toString(),
          'isGuest': 'false',
        });
      }
    }
    return (attendeeCount: allAtt.docs.length, eligible: eligible);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingRecord != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        // Wide enough (with the flex split below) that the live preview
        // renders at ~600px instead of shrinking to a noticeably smaller,
        // harder to judge preview.
        width: 1080,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        // Only the header strip below had an explicit background — the rest
        // of the dialog (body/footer, and the rounded corners) had none, so
        // Flutter's default unseeded Material surface bled through there.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryDark.withAlpha(26),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_outlined,
                        color: UpriseColors.primaryDark,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit
                                ? 'Edit Certificate'
                                : 'Generate New Certificate',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Create certificates only for approved events that issue certificates',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: UpriseColors.darkGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Close',
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // ── Body ───────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left — form
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(
                              'Event & Template',
                              icon: Icons.event_outlined,
                            ),
                            _FieldWrapper(
                              label: 'Select Event *',
                              child: FutureBuilder<Set<String>>(
                                future: _proposalIdsWithExistingCertFuture,
                                builder: (context, exclusionSnap) {
                                  final excluded =
                                      exclusionSnap.data ?? const <String>{};
                                  return StreamBuilder<QuerySnapshot>(
                                    stream: _eventsStream,
                                    builder: (context, snapshot) {
                                      final events = (snapshot.data?.docs ?? [])
                                          .where(
                                            (d) =>
                                                d.id == _selectedEventId ||
                                                !excluded.contains(d.id),
                                          )
                                          .toList();
                                      return DropdownButtonFormField<String>(
                                        value: _selectedEventId,
                                        isExpanded: true,
                                        hint: Text(
                                          events.isEmpty
                                              ? 'No approved certificate events found'
                                              : 'Choose an approved event',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 13,
                                            color: const Color(0xFF9AA5B4),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        decoration: _fieldDecoration(),
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                          color: const Color(0xFF1A202C),
                                        ),
                                        validator: (_) =>
                                            _selectedEventId == null
                                            ? 'Required'
                                            : null,
                                        items: events.map((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          return DropdownMenuItem(
                                            value: doc.id,
                                            child: Text(
                                              data['title'] as String? ??
                                                  'Untitled',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (v) async {
                                          if (v == null) return;
                                          final doc = events.firstWhere(
                                            (d) => d.id == v,
                                          );
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          setState(() {
                                            _selectedEventId = v;
                                            _selectedEventName =
                                                data['title'] as String?;
                                            _titleCtrl.text =
                                                _selectedEventName ?? '';
                                            _orgCtrl.text =
                                                (data['orgName'] as String?) ??
                                                _orgCtrl.text;
                                            final eventDate =
                                                (data['date'] as Timestamp?)
                                                    ?.toDate();
                                            if (eventDate != null)
                                              _dateCtrl.text = DateFormat(
                                                'MM/dd/yyyy',
                                              ).format(eventDate);
                                            _selectedEventDocId = null;
                                            _attendeeCount = 0;
                                            _attendanceSynced = false;
                                            _eligibleRecipients = [];
                                          });

                                          try {
                                            final evQ = await FirebaseFirestore
                                                .instance
                                                .collection('events')
                                                .where(
                                                  'createdFromProposalId',
                                                  isEqualTo: v,
                                                )
                                                .limit(1)
                                                .get();

                                            if (mounted &&
                                                evQ.docs.isNotEmpty) {
                                              final eventDoc = evQ.docs.first;
                                              final result =
                                                  await _fetchAttendanceAndEligible(
                                                    eventDoc.id,
                                                  );
                                              if (mounted) {
                                                setState(() {
                                                  _selectedEventDocId =
                                                      eventDoc.id;
                                                  _attendeeCount =
                                                      result.attendeeCount;
                                                  _eligibleRecipients =
                                                      result.eligible;
                                                  _attendanceSynced = true;
                                                });
                                              }
                                            }
                                          } catch (_) {
                                            // Fall back to proposal-only detection.
                                          }
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _openImportTemplate,
                                  icon: const Icon(
                                    Icons.upload_file_outlined,
                                    size: 14,
                                  ),
                                  label: Text(
                                    'Upload Custom Design',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: UpriseColors.primaryDark,
                                    side: BorderSide(
                                      color: UpriseColors.primaryDark
                                          .withOpacity(0.4),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Designed it in Canva or elsewhere? Export as PNG/PDF and upload it here.',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _sectionLabel(
                              'Certificate Details',
                              icon: Icons.description_outlined,
                            ),
                            _FieldWrapper(
                              label: 'Certificate Title *',
                              child: TextFormField(
                                controller: _titleCtrl,
                                onChanged: (_) => setState(() {}),
                                decoration: _fieldDecoration(
                                  hint: 'e.g. Certificate of Participation',
                                ),
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                                validator: (v) => v?.trim().isEmpty == true
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Organization, event date, and signatories aren't collected
                            // here anymore — they're already part of the certificate
                            // design itself (drawn in Canva), so asking for them again
                            // would just be duplicate data entry. Organization and date
                            // are still auto-filled from the selected event above for
                            // the system's own records (search/filter/export).
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFBFD7FF),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Organization and date are auto-filled from the selected event. Signatories placed on your uploaded design (via "Upload Custom Design") are auto-inserted from Admin Settings → Signatories.',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12,
                                        color: const Color(0xFF1D4ED8),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // NEW: surfaces any placed signatory placeholders
                            // that no longer resolve to a roster entry.
                            if (_signatoryPlacements.isNotEmpty)
                              StreamBuilder<QuerySnapshot>(
                                stream: _signatoriesStream,
                                builder: (context, snap) {
                                  final roster = (snap.data?.docs ?? [])
                                      .map((d) => SignatoryData.fromDoc(d))
                                      .toList();
                                  final missing = _missingSignatoryKeys(roster);
                                  if (missing.isEmpty) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: UpriseColors.success.withOpacity(
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_signatoryPlacements.length} signatory placeholder(s) placed and matched.',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11.5,
                                          color: UpriseColors.success,
                                        ),
                                      ),
                                    );
                                  }
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: UpriseColors.warning.withOpacity(
                                        0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Missing signatory data for: ${missing.join(", ")}. Add them in Admin Settings → Signatories.',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11.5,
                                        color: UpriseColors.warning,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            // Single recipient-status banner — replaces the recipient
                            // count field entirely: recipients are always exactly the
                            // attendees who showed up and submitted their evaluation.
                            Builder(
                              builder: (_) {
                                final noEventSelected =
                                    _selectedEventId == null;
                                final checking =
                                    !noEventSelected && !_attendanceSynced;
                                final ready = _hasEligibleRecipients;
                                final bg = noEventSelected || checking
                                    ? UpriseColors.lightGray
                                    : (ready
                                          ? UpriseColors.success.withOpacity(
                                              0.18,
                                            )
                                          : UpriseColors.warning.withOpacity(
                                              0.18,
                                            ));
                                final border = noEventSelected || checking
                                    ? UpriseColors.primaryDark.withOpacity(0.12)
                                    : (ready
                                          ? UpriseColors.success.withOpacity(
                                              0.45,
                                            )
                                          : UpriseColors.warning.withOpacity(
                                              0.45,
                                            ));
                                final fg = noEventSelected || checking
                                    ? UpriseColors.charcoal
                                    : (ready
                                          ? UpriseColors.success
                                          : UpriseColors.warning);
                                final icon = noEventSelected || checking
                                    ? Icons.info_outline_rounded
                                    : (ready
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.warning_amber_rounded);
                                final message = noEventSelected
                                    ? 'Recipients are detected automatically: certificates go to attendees who attended and completed their event evaluation. Select an event to see who qualifies.'
                                    : checking
                                    ? 'Checking attendance and evaluations…'
                                    : ready
                                    ? '${_eligibleRecipients.length} of $_attendeeCount attendee(s) evaluated the event and will receive a certificate.'
                                    : '$_attendeeCount attendee(s) recorded, but none have submitted their evaluation yet. You can save a draft — "Generate & Distribute" unlocks once at least one attendee evaluates.';
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, size: 16, color: fg),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 12,
                                            color: fg,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Right — live preview
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _sectionLabel(
                                    'Live Preview',
                                    icon: Icons.preview_outlined,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.zoom_out_map_rounded,
                                    size: 16,
                                    color: UpriseColors.darkGray,
                                  ),
                                  tooltip: 'View larger',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  onPressed: () => _showPreviewFullscreen(),
                                ),
                                if (_selectedTemplateUrl != null)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _selectedTemplateUrl = null;
                                      _selectedTemplatePlacement = null;
                                      _signatoryPlacements = {};
                                    }),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      minimumSize: Size.zero,
                                    ),
                                    child: Text(
                                      'Remove design',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11.5,
                                        color: UpriseColors.primaryDark,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            AspectRatio(
                              aspectRatio: 600 / 424,
                              child: _buildPreviewVisual(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Footer ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: UpriseColors.mediumGray),
                  ),
                  color: UpriseColors.lightGray,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _submit(distribute: false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: UpriseColors.mediumGray),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                      ),
                      child: Text(
                        'Save as Draft',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: UpriseColors.charcoal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Disabled until a design is uploaded and at least one attendee has evaluated the event
                    ElevatedButton.icon(
                      onPressed:
                          (_isSubmitting ||
                              _selectedTemplateUrl == null ||
                              (_selectedEventId != null &&
                                  !_hasEligibleRecipients))
                          ? null
                          : () => _submit(distribute: true),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        'Generate & Distribute',
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
                          horizontal: 20,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Form field label wrapper — unchanged
class _FieldWrapper extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldWrapper({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    // Every call site passes its label with a literal trailing ' *' for
    // required fields — split that off and color it so it actually reads as
    // required instead of just another character in the label string.
    final isRequired = label.endsWith(' *');
    final baseLabel = isRequired ? label.substring(0, label.length - 2) : label;
    final labelStyle = GoogleFonts.beVietnamPro(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF374151),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isRequired
            ? RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: baseLabel, style: labelStyle),
                    TextSpan(
                      text: ' *',
                      style: labelStyle.copyWith(color: UpriseColors.error),
                    ),
                  ],
                ),
              )
            : Text(label, style: labelStyle),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _CertPreviewDialog extends StatelessWidget {
  final CertificateRecord record;
  const _CertPreviewDialog({required this.record});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // Was unset — Dialog falls back to Flutter's default Material
      // surface color, which skews purple/lavender on this app's
      // unseeded theme.
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.card_membership_outlined,
                      color: UpriseColors.primaryDark,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.certificateId,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          record.eventName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: UpriseColors.darkGray,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _certBadge(record.status),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: record.templateFileUrl != null
                  ? AspectRatio(
                      aspectRatio: 600 / 424,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('signatories')
                              .snapshots(),
                          builder: (context, snap) {
                            final signatories = <String, SignatoryData>{
                              for (final doc in (snap.data?.docs ?? []))
                                SignatoryData.fromDoc(doc).id:
                                    SignatoryData.fromDoc(doc),
                            };
                            final sigPlacements =
                                record.signatoryPlacements?.map(
                                  (k, v) => MapEntry(
                                    k,
                                    CertNamePlacement.fromMap(
                                      Map<String, dynamic>.from(v as Map),
                                    ),
                                  ),
                                ) ??
                                <String, CertNamePlacement>{};
                            return _CertificateComposite(
                              recipientName:
                                  record.recipientName ?? '[Recipient Name]',
                              namePlacement: CertNamePlacement.fromMap(
                                record.namePlacement,
                              ),
                              signatoryPlacements: sigPlacements,
                              signatories: signatories,
                              background: NetworkImage(
                                _renderableTemplateUrl(record.templateFileUrl!),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  : CertificatePreview(
                      theme: CertTheme.forType(
                        record.templateType,
                        primaryDark: UpriseColors.primaryDark,
                        primaryLight: UpriseColors.primaryLight,
                        accentColor: UpriseColors.accent,
                      ),
                      orgName: record.organization,
                      eventTitle: record.eventName,
                      eventDate: DateFormat(
                        'MMMM dd, yyyy',
                      ).format(record.date),
                      recipient: record.recipientName ?? '[Recipient Name]',
                      signatories: record.signatories.isNotEmpty
                          ? record.signatories
                                .map(
                                  (s) => CertSignatory(
                                    name: (s['name'] ?? '').toString(),
                                    title: (s['title'] ?? '').toString(),
                                    signatureImageBase64:
                                        s['signatureImage'] as String?,
                                  ),
                                )
                                .toList()
                          : (record.signatureImage != null
                                ? [
                                    CertSignatory(
                                      name: 'Authorized Signatory',
                                      signatureImageBase64:
                                          record.signatureImage,
                                    ),
                                  ]
                                : const []),
                      verificationCode: record.verificationCode,
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UpriseColors.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Import Template Modal — a small visual editor for a certificate design
// exported from Canva (or anywhere else). The design itself is locked; only
// the dynamic fields (recipient name, signatories) are selectable, movable
// and resizable. Everything here is presentation: the recipient name shown
// is a preview only, and signatory identity comes from the Admin roster.
// ─────────────────────────────────────────────────────────────────────────────
class _ImportTemplateModal extends StatefulWidget {
  final String orgId;
  // The event_proposals doc this template is being built for — drives which
  // signatory(ies) (if any) the admin authorized at approval time. Null
  // means no event picked yet (the signatory picker asks for one first).
  final String? proposalId;
  // Names of real eligible recipients, offered under "Preview as". Only ever
  // used as sample text on the canvas — never written anywhere.
  final List<String> previewNames;
  const _ImportTemplateModal({
    required this.orgId,
    this.proposalId,
    this.previewNames = const [],
  });

  @override
  State<_ImportTemplateModal> createState() => _ImportTemplateModalState();
}

class _ImportTemplateModalState extends State<_ImportTemplateModal> {
  static const int _maxBytes = 5 * 1024 * 1024; // 5 MB
  static const String _nameKey = 'name';
  static const List<double> _signatoryStagger = [0.25, 0.75, 0.5, 0.15, 0.85];

  final _nameCtrl = TextEditingController();
  final _customCtrl = TextEditingController(text: 'Sample Recipient Name');
  PlatformFile? _file;
  Widget? _bgImage;
  bool _isUploading = false;

  CertNamePlacement _placement = const CertNamePlacement(widthPct: 0.6);
  // signatory doc id -> its own placement. Independent per signatory.
  final Map<String, CertNamePlacement> _signatoryPlacements = {};
  // _nameKey, a signatory id, or null for nothing selected.
  String? _selected = _nameKey;

  // >= 0 index into widget.previewNames, -1 generic sample, -2 custom text.
  late int _previewIndex = widget.previewNames.isNotEmpty ? 0 : -1;

  Map<String, SignatoryData> _roster = {};
  StreamSubscription<QuerySnapshot>? _rosterSub;
  bool _authLoaded = false;
  ({Set<String> ids, String remarks})? _auth;

  @override
  void initState() {
    super.initState();
    _rosterSub = FirebaseFirestore.instance
        .collection('signatories')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _roster = {
              for (final d in snap.docs) d.id: SignatoryData.fromDoc(d),
            };
          });
        }, onError: (_) {});
    _loadAuthorizedSignatoryIds().then((v) {
      if (!mounted) return;
      setState(() {
        _auth = v;
        _authLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _rosterSub?.cancel();
    _nameCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<({Set<String> ids, String remarks})?>
  _loadAuthorizedSignatoryIds() async {
    final proposalId = widget.proposalId;
    if (proposalId == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .get();
      final auth = doc.data()?['signatoryAuthorization'];
      if (auth is! Map) return (ids: const <String>{}, remarks: '');
      final remarks = (auth['remarks'] as String?)?.trim() ?? '';
      if (auth['required'] != true) {
        return (ids: const <String>{}, remarks: remarks);
      }
      final ids = (auth['signatoryIds'] as List?) ?? [];
      return (ids: ids.map((e) => e.toString()).toSet(), remarks: remarks);
    } catch (_) {
      return (ids: const <String>{}, remarks: '');
    }
  }

  bool get _isPdf => (_file?.extension ?? '').toLowerCase() == 'pdf';
  bool get _canUse =>
      _file != null && _nameCtrl.text.trim().isNotEmpty && !_isUploading;

  String get _previewText {
    if (_previewIndex >= 0 && _previewIndex < widget.previewNames.length) {
      return widget.previewNames[_previewIndex];
    }
    if (_previewIndex == -2) {
      final t = _customCtrl.text.trim();
      return t.isEmpty ? 'Recipient Name' : t;
    }
    return 'Sample Recipient Name';
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.first;
    // Caught here, before attempting the upload — otherwise an oversized file
    // uploads fully (slow) before Storage's size rule rejects it, which looks
    // like the picker is just hanging and then mysteriously failing.
    if (picked.size > _maxBytes) {
      if (mounted) {
        AppToast.error(
          context,
          '${picked.name} is ${(picked.size / (1024 * 1024)).toStringAsFixed(1)} MB — max size is 5 MB.',
        );
      }
      return;
    }
    final ext = (picked.extension ?? '').toLowerCase();
    final bytes = picked.bytes;
    setState(() {
      _file = picked;
      // Built once per pick so dragging a field rebuilds the overlay only,
      // not the image decode.
      _bgImage = (ext != 'pdf' && bytes != null)
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 1400,
              gaplessPlayback: true,
            )
          : null;
    });
  }

  Future<void> _upload() async {
    if (!_canUse) return;
    setState(() => _isUploading = true);

    try {
      final data = _file!.bytes;
      if (data == null) throw Exception('File data is null');

      const cloudName = 'igawal9n'; // <- palitan
      const uploadPreset = 'uprise_certs'; // <- palitan

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/auto/upload',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(
          http.MultipartFile.fromBytes('file', data, filename: _file!.name),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('Upload failed: ${response.body}');
      }

      final json = jsonDecode(response.body);
      var url = json['secure_url'] as String;
      // Cloudinary stores an uploaded PDF as-is, and Image.network can't
      // decode a raw PDF. Requesting the same asset with a raster extension
      // makes Cloudinary render its first page as an image.
      if (url.toLowerCase().endsWith('.pdf')) {
        url = '${url.substring(0, url.length - 4)}.jpg';
      }

      // Only signatories that are still on the canvas and still in the roster
      // are saved.
      final signatoryPlacementsMap = {
        for (final e in _signatoryPlacements.entries)
          if (_roster.containsKey(e.key)) e.key: e.value.toMap(),
      };
      final templateName = _nameCtrl.text.trim();

      await FirebaseFirestore.instance.collection('certificate_templates').add({
        'orgId': widget.orgId,
        'name': templateName,
        'url': url,
        'namePlacement': _placement.toMap(),
        if (signatoryPlacementsMap.isNotEmpty)
          'signatoryPlacements': signatoryPlacementsMap,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, {
          'name': templateName,
          'url': url,
          'namePlacement': _placement.toMap(),
          'signatoryPlacements': signatoryPlacementsMap,
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── placement helpers ────────────────────────────────────────────────────
  CertNamePlacement _pOf(String id) => id == _nameKey
      ? _placement
      : (_signatoryPlacements[id] ?? const CertNamePlacement());

  void _setP(String id, CertNamePlacement p) {
    setState(() {
      if (id == _nameKey) {
        _placement = p;
      } else {
        _signatoryPlacements[id] = p;
      }
    });
  }

  void _select(String id) {
    if (_selected != id) setState(() => _selected = id);
  }

  // Rough half-height of a field, used only to keep a dragged field on the
  // canvas vertically; the real height is content-driven.
  double _halfHeight(String id, double scale) {
    final p = _pOf(id);
    if (id == _nameKey) return p.fontSize * scale * 0.75;
    final hasSig = (_roster[id]?.signatureBase64 ?? '').isNotEmpty;
    return p.fontSize * scale * (hasSig ? 2.8 : 1.3);
  }

  void _dragBy(String id, Offset d, Size size) {
    final p = _pOf(id);
    final bw = p.boxWidth(size.width);
    final scale = size.width / CertificateImageWithName.referenceWidth;
    final halfH = math.min(_halfHeight(id, scale), size.height / 2);
    final x =
        (p.xPct * size.width + d.dx).clamp(bw / 2, size.width - bw / 2) /
        size.width;
    final y =
        (p.yPct * size.height + d.dy).clamp(halfH, size.height - halfH) /
        size.height;
    _setP(id, p.copyWith(xPct: x.toDouble(), yPct: y.toDouble()));
  }

  void _resizeBy(String id, double dx, Size size) {
    final p = _pOf(id);
    final w = size.width;
    final minPx = (id == _nameKey ? 0.15 : 0.10) * w;
    final left = p.boxLeft(w);
    final upper = math.max(minPx, math.min(0.95 * w, w - left));
    final newBw = (p.boxWidth(w) + dx).clamp(minPx, upper).toDouble();
    _setP(id, p.copyWith(widthPct: newBw / w, xPct: (left + newBw / 2) / w));
  }

  // Slider-driven width change keeps the box on the canvas by nudging its
  // centre inward instead of letting it hang off an edge.
  void _setWidth(String id, double v) {
    final p = _pOf(id);
    final half = v / 2;
    _setP(
      id,
      p.copyWith(widthPct: v, xPct: p.xPct.clamp(half, 1 - half).toDouble()),
    );
  }

  void _togglePlaced(String id, bool place) {
    setState(() {
      if (place) {
        final n = _signatoryPlacements.length;
        _signatoryPlacements[id] = CertNamePlacement(
          xPct: _signatoryStagger[n % _signatoryStagger.length],
          yPct: 0.8,
          fontSize: 12,
          widthPct: 0.24,
        );
        _selected = id;
      } else {
        _signatoryPlacements.remove(id);
        if (_selected == id) _selected = _nameKey;
      }
    });
  }

  // ── canvas ───────────────────────────────────────────────────────────────
  Widget _buildCanvasPanel() {
    Widget canvas;
    if (_file == null) {
      canvas = _canvasPlaceholder(
        icon: Icons.upload_file_outlined,
        message: 'Choose your certificate design to start placing fields.',
        action: OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_outlined, size: 15),
          label: Text(
            'Choose file',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: UpriseColors.primaryDark,
            side: BorderSide(color: UpriseColors.primaryDark.withAlpha(110)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    } else if (_bgImage == null) {
      canvas = _canvasPlaceholder(
        icon: Icons.picture_as_pdf_outlined,
        message:
            'PDF designs can\'t be previewed here. The recipient\'s name will '
            'use a centred default position. Use a PNG or JPG if you want to '
            'position the fields yourself.',
      );
    } else {
      canvas = _buildCanvas();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        canvas,
        const SizedBox(height: 12),
        Text(
          _bgImage == null
              ? 'Max file size: 5 MB. Landscape designs work best — '
                    'certificates render at a 600:424 ratio (roughly 1200×848px).'
              : 'Click a field to select it. Drag to move it, drag the corner '
                    'handle to resize. The design itself stays locked.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _canvasPlaceholder({
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return AspectRatio(
      aspectRatio: 600 / 424,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: const Color(0xFFB8C2CE)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 600 / 424,
        child: LayoutBuilder(
          builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            final scale = size.width / CertificateImageWithName.referenceWidth;

            final ids = <String>[
              for (final id in _signatoryPlacements.keys)
                if (_roster.containsKey(id)) id,
              _nameKey,
            ];
            // The selected field is painted last so it is always the one
            // under the pointer when fields overlap.
            if (_selected != null && ids.remove(_selected)) {
              ids.add(_selected!);
            }

            Widget contentFor(String id) {
              final p = _pOf(id);
              if (id == _nameKey) {
                return CertNameText(
                  text: _previewText,
                  placement: p,
                  scale: scale,
                  boxWidthPx: p.boxWidth(size.width),
                );
              }
              final s = _roster[id]!;
              return CertSignatoryBlock(
                placement: p,
                name: s.fullName,
                title: s.title,
                signatureBase64: s.signatureBase64,
                scale: scale,
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = null),
                    child: _bgImage!,
                  ),
                ),
                for (final id in ids) _editableField(id, size, contentFor(id)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _editableField(String id, Size size, Widget content) {
    final selected = _selected == id;
    final p = _pOf(id);
    return certPlaceBoxField(
      placement: p,
      canvas: size,
      child: Stack(
        children: [
          MouseRegion(
            cursor: selected
                ? SystemMouseCursors.move
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _select(id),
              onPanStart: (_) => _select(id),
              onPanUpdate: (d) => _dragBy(id, d.delta, size),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: selected
                    ? UpriseColors.primaryDark.withAlpha(16)
                    : Colors.transparent,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? UpriseColors.primaryDark
                        : UpriseColors.primaryDark.withAlpha(70),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: content,
              ),
            ),
          ),
          if (selected)
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => _resizeBy(id, d.delta.dx, size),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── properties panel ─────────────────────────────────────────────────────
  Widget _panelTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.beVietnamPro(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: UpriseColors.darkGray,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _propLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF374151),
      ),
    ),
  );

  Widget _sliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
              Text(
                valueText,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              activeColor: UpriseColors.primaryDark,
              inactiveColor: const Color(0xFFE2E6EA),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow(String id) {
    final p = _pOf(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _propLabel('Text Color'),
          Row(
            children: [
              _colorChoiceChip(
                label: 'Dark',
                selected: !p.light,
                onTap: () => _setP(id, p.copyWith(light: false)),
              ),
              const SizedBox(width: 6),
              _colorChoiceChip(
                label: 'Light',
                selected: p.light,
                onTap: () => _setP(id, p.copyWith(light: true)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alignRow(String id) {
    final p = _pOf(id);
    Widget chip(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _colorChoiceChip(
        label: label,
        selected: p.align == value,
        onTap: () => _setP(id, p.copyWith(align: value)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _propLabel('Alignment'),
          Row(
            children: [
              chip('left', 'Left'),
              chip('center', 'Center'),
              chip('right', 'Right'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewAsControl() {
    final names = widget.previewNames;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _propLabel('Preview as'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(_DS.radiusSm),
              border: Border.all(color: const Color(0xFFE2E6EA)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _previewIndex,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF1A202C),
                ),
                items: [
                  for (var i = 0; i < names.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(names[i], overflow: TextOverflow.ellipsis),
                    ),
                  const DropdownMenuItem(value: -1, child: Text('Sample name')),
                  const DropdownMenuItem(
                    value: -2,
                    child: Text('Custom text…'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _previewIndex = v);
                },
              ),
            ),
          ),
          if (_previewIndex == -2) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customCtrl,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _fieldDecoration(hint: 'Preview text'),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            names.isEmpty
                ? 'Preview only. No evaluated attendees yet, so a sample name is used.'
                : 'Preview only. This never changes any recipient\'s real name.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldSettings() {
    final sel = _selected;
    if (sel == null || (sel != _nameKey && !_roster.containsKey(sel))) {
      return Text(
        'Select a field on the certificate to edit it.',
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          color: const Color(0xFF94A3B8),
        ),
      );
    }
    final p = _pOf(sel);
    if (sel == _nameKey) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelTitle('Recipient name'),
          _previewAsControl(),
          _sliderRow(
            label: 'Font size',
            valueText: '${p.fontSize.round()} pt',
            value: p.fontSize,
            min: 12,
            max: 48,
            onChanged: (v) => _setP(sel, p.copyWith(fontSize: v)),
          ),
          _colorRow(sel),
          _alignRow(sel),
          _sliderRow(
            label: 'Field width',
            valueText: '${((p.widthPct ?? 0.6) * 100).round()}%',
            value: p.widthPct ?? 0.6,
            min: 0.15,
            max: 0.95,
            onChanged: (v) => _setWidth(sel, v),
          ),
        ],
      );
    }
    final s = _roster[sel]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Signatory'),
        Text(
          s.fullName,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A202C),
          ),
        ),
        if (s.title.isNotEmpty)
          Text(
            s.title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
        const SizedBox(height: 14),
        _sliderRow(
          label: 'Font size',
          valueText: '${p.fontSize.round()} pt',
          value: p.fontSize,
          min: 10,
          max: 32,
          onChanged: (v) => _setP(sel, p.copyWith(fontSize: v)),
        ),
        _colorRow(sel),
        _alignRow(sel),
        _sliderRow(
          label: 'Field width',
          valueText: '${((p.widthPct ?? 0.24) * 100).round()}%',
          value: p.widthPct ?? 0.24,
          min: 0.10,
          max: 0.6,
          onChanged: (v) => _setWidth(sel, v),
        ),
        OutlinedButton.icon(
          onPressed: () => _togglePlaced(sel, false),
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 15),
          label: Text(
            'Remove from Certificate',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: UpriseColors.error,
            side: BorderSide(color: UpriseColors.error.withAlpha(110)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelTitle('Template'),
        _FieldWrapper(
          label: 'Template Name *',
          child: TextField(
            controller: _nameCtrl,
            decoration: _fieldDecoration(hint: 'e.g. CICT Awards Design'),
            style: GoogleFonts.beVietnamPro(fontSize: 13),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'An internal label, not shown on the certificate.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            color: const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 15,
              color: UpriseColors.primaryDark,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _file?.name ?? 'No file selected',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: _file == null
                      ? const Color(0xFF9AA5B4)
                      : const Color(0xFF1A202C),
                ),
              ),
            ),
            TextButton(
              onPressed: _isUploading ? null : _pickFile,
              style: TextButton.styleFrom(
                foregroundColor: UpriseColors.primaryDark,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                _file == null ? 'Choose' : 'Replace',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signatoriesSection() {
    Widget body;
    if (_isPdf || _file == null) {
      body = Text(
        _isPdf
            ? 'Signatories can only be placed on PNG or JPG designs.'
            : 'Choose a design first, then add signatories to it.',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11.5,
          color: const Color(0xFF9AA5B4),
        ),
      );
    } else if (widget.proposalId == null) {
      body = Text(
        'Select an event first — signatories are limited to whoever the '
        'admin authorized for that specific event.',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11.5,
          color: const Color(0xFF9AA5B4),
        ),
      );
    } else if (!_authLoaded) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      final authorized = _auth?.ids ?? const <String>{};
      final roster = _roster.values
          .where((s) => authorized.contains(s.id))
          .toList();
      if (authorized.isEmpty) {
        body = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Text(
            'No signature was authorized for this event — ask your admin to '
            'authorize one when approving it, or continue without a signature '
            'on this certificate.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11.5,
              color: const Color(0xFF92400E),
            ),
          ),
        );
      } else if (roster.isEmpty) {
        body = Text(
          'The signatory authorized for this event no longer exists in '
          'Admin Settings → Signatories.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            color: const Color(0xFF9AA5B4),
          ),
        );
      } else {
        body = Column(children: [for (final s in roster) _signatoryRow(s)]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_panelTitle('Signatories'), body],
    );
  }

  Widget _signatoryRow(SignatoryData s) {
    final placed = _signatoryPlacements.containsKey(s.id);
    final selected = _selected == s.id;
    return InkWell(
      onTap: () => placed ? _select(s.id) : _togglePlaced(s.id, true),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? UpriseColors.primaryDark.withAlpha(14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Checkbox(
              value: placed,
              activeColor: UpriseColors.primaryDark,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => _togglePlaced(s.id, v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  if (s.title.isNotEmpty)
                    Text(
                      s.title,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminNote() {
    final remarks = _auth?.remarks ?? '';
    if (remarks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE8ECF0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Note from admin: $remarks',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesPanel() {
    const gap = SizedBox(height: 18);
    final divider = Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Divider(height: 1, color: Colors.grey.shade200),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _templateSection(),
        divider,
        if (_bgImage != null) ...[_fieldSettings(), divider],
        _signatoriesSection(),
        _adminNote(),
        gap,
      ],
    );
  }

  Widget _colorChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? UpriseColors.primaryDark : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? UpriseColors.primaryDark
                : const Color(0xFFE4E8EF),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }

  // ── shell ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.upload_file_outlined,
              color: UpriseColors.primaryDark,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Certificate Template',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Customize dynamic fields before using this template.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    color: UpriseColors.darkGray,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Close',
            onPressed: _isUploading ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isUploading ? null : () => Navigator.pop(context),
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
            onPressed: _canUse ? _upload : null,
            icon: _isUploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              'Use Template',
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
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: const Color(0xFFF8F9FB),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildCanvasPanel(),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFFE8ECF0)),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildPropertiesPanel(),
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFF8F9FB),
                padding: const EdgeInsets.all(16),
                child: _buildCanvasPanel(),
              ),
              const Divider(height: 1, color: Color(0xFFE8ECF0)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildPropertiesPanel(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1180.0, mq.width - 48),
        height: math.min(780.0, mq.height - 48),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}
