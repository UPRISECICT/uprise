// ignore_for_file: unnecessary_cast, unused_field, deprecated_member_use

import 'package:flutter/material.dart';
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
import '../../../widgets/org_modal_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RECIPIENT STATUS ROW - moved to top level
// ─────────────────────────────────────────────────────────────────────────────
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
Future<List<_RecipientStatusRow>> fetchRecipientStatus(String eventId) async {
  final attSnap = await FirebaseFirestore.instance
      .collection('events')
      .doc(eventId)
      .collection('attendances')
      .where('status', whereIn: ['present', 'late'])
      .get();

  final fbSnap = await FirebaseFirestore.instance
      .collection('feedback')
      .where('eventId', isEqualTo: eventId)
      .get();

  final evaluatedUids = fbSnap.docs
      .map((d) => d.data()['userId']?.toString())
      .whereType<String>()
      .toSet();
  final evaluatedGuestEmails = fbSnap.docs
      .where((d) => d.data()['isGuest'] == true)
      .map((d) => d.data()['guestEmail']?.toString())
      .whereType<String>()
      .toSet();

  final certSnap = await FirebaseFirestore.instance
      .collection('certificates')
      .where('eventId', isEqualTo: eventId)
      .where('status', isEqualTo: 'distributed')
      .get();

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
      'SENT',
    ),
    'partially_sent': _BadgeStyle(
      UpriseColors.warning.withOpacity(0.18),
      UpriseColors.warning,
      'PARTIALLY SENT',
    ),
    'draft': _BadgeStyle(
      UpriseColors.lightGray,
      UpriseColors.darkGray,
      'DRAFT',
    ),
    'archived': _BadgeStyle(
      const Color(0xFFF3F4F6),
      const Color(0xFF6B7280),
      'ARCHIVED',
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

Widget _sendStatusBadge(String? status) {
  final s = (status ?? 'sent').toLowerCase();
  final Map<String, _BadgeStyle> styles = {
    'sent': _BadgeStyle(
      const Color(0xFFEFF6FF),
      const Color(0xFF2563EB),
      'SENT',
    ),
    'delivered': _BadgeStyle(
      UpriseColors.success.withOpacity(0.18),
      UpriseColors.success,
      'DELIVERED',
    ),
    'failed': _BadgeStyle(
      UpriseColors.error.withOpacity(0.18),
      UpriseColors.error,
      'FAILED',
    ),
    'resent': _BadgeStyle(
      const Color(0xFFF3E8FF),
      const Color(0xFF7C3AED),
      'RESENT',
    ),
  };
  final style = styles[s] ?? styles['sent']!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: style.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      style.label,
      style: GoogleFonts.beVietnamPro(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: style.fg,
        letterSpacing: 0.6,
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
InputDecoration _fieldDecoration({
  String? label,
  String? hint,
  IconData? icon,
}) {
  return InputDecoration(
    labelText: label,
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
      placeholderKey: (d['placeholderKey'] ?? '').toString(),
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
  DateTime get date =>
      records.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b);
  String? get eventId => primary.eventId;

  int get totalRecipients => records.length;
  int get sentCount => records.where((r) => r.status == 'distributed').length;
  int get failedCount => records.where((r) => r.sendStatus == 'failed').length;
  bool get isArchived => records.every((r) => r.archived);

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  late final Stream<QuerySnapshot> _certsStream = FirebaseFirestore.instance
      .collection('certificates')
      .where('orgId', isEqualTo: widget.orgId)
      .orderBy('issuedAt', descending: true)
      .snapshots();

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _certsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final total = docs.length;
        final totalRec = docs.fold<int>(
          0,
          (s, d) =>
              s +
              ((d.data() as Map<String, dynamic>)['recipients'] as num? ?? 1)
                  .toInt(),
        );
        final distributed = docs
            .where(
              (d) =>
                  (d.data() as Map<String, dynamic>)['status'] == 'distributed',
            )
            .length;
        final pending = docs
            .where(
              (d) => (d.data() as Map<String, dynamic>)['status'] == 'pending',
            )
            .length;

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
          _StatCard(
            label: 'Total Certificates',
            value: total,
            icon: Icons.card_membership_outlined,
            color: UpriseColors.primaryDark,
            isSelected: _selectedStatCard == 0,
            onTap: () => selectCard(0, null),
          ),
          _StatCard(
            label: 'Total Recipients',
            value: totalRec,
            icon: Icons.people_outline_rounded,
            color: UpriseColors.accent,
            isSelected: _selectedStatCard == 1,
            onTap: () => selectCard(1, null),
          ),
          _StatCard(
            label: 'Distributed',
            value: distributed,
            icon: Icons.assignment_turned_in_outlined,
            color: UpriseColors.success,
            isSelected: _selectedStatCard == 2,
            onTap: () => selectCard(2, (b) => b.sentCount > 0),
          ),
          _StatCard(
            label: 'Pending',
            value: pending,
            icon: Icons.pending_outlined,
            color: UpriseColors.warning,
            isSelected: _selectedStatCard == 3,
            onTap: () => selectCard(3, (b) => b.sentCount < b.totalRecipients),
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
                      hintText: 'Search certificates...',
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
                        hintText: 'Search by ID, event name, or organization…',
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

    return StreamBuilder<QuerySnapshot>(
      stream: _certsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = (snapshot.data?.docs ?? []).cast<QueryDocumentSnapshot>();
        final allRecords = docs
            .map((d) => CertificateRecord.fromFirestore(d))
            .toList();
        var batches = CertificateBatch.groupByEvent(allRecords);

        if (_filterStatus != 'All') {
          final key = _filterStatus.toLowerCase().replaceAll(' ', '_');
          batches = batches.where((b) => b.batchStatus == key).toList();
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

        return Container(
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
              if (!isMobile) _buildTableHeader(),
              Expanded(
                child: batches.isEmpty
                    ? _buildEmptyState()
                    : isMobile
                    ? ListView.builder(
                        itemCount: pageItems.length,
                        itemBuilder: (_, i) => _buildCardRow(
                          pageItems[i],
                          i == pageItems.length - 1,
                        ),
                      )
                    : ListView.builder(
                        itemCount: pageItems.length,
                        itemBuilder: (_, i) =>
                            _buildRow(pageItems[i], i == pageItems.length - 1),
                      ),
              ),
              _buildFooter(batches.length, totalPages, start, end, isMobile),
            ],
          ),
        );
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
          Expanded(flex: 2, child: _headerCell('CERTIFICATE ID')),
          Expanded(flex: 3, child: _headerCell('EVENT NAME')),
          Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
          Expanded(flex: 2, child: _headerCell('TYPE')),
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
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _viewBatch(b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                r.certificateId,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: UpriseColors.primaryDark,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                b.eventName,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1A202C),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  b.organization,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: UpriseColors.primaryDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                r.type,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
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
            Expanded(
              flex: 2,
              child: Text(
                b.batchStatus == 'draft'
                    ? '${b.totalRecipients}'
                    : '${b.sentCount}/${b.totalRecipients}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A202C),
                ),
              ),
            ),
            Expanded(flex: 2, child: _batchBadge(b.batchStatus)),
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
                  const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: b.isEditable
                        ? 'Edit'
                        : 'Locked — certificates already sent',
                    color: UpriseColors.primaryDark,
                    onTap: b.isEditable ? () => _editCert(r) : null,
                  ),
                  const SizedBox(width: 6),
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

  void _viewBatch(CertificateBatch b) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _BatchDetailModal(
        batch: b,
        eventId: b.eventId ?? '',
        onSendAll: () => _sendCertificates(b.primary),
        onSendSingle: (key, name, isGuest) => _sendSingleCertificate(
          draftMeta: b.primary,
          eventId: b.eventId ?? '',
          recipientKey: key,
          recipientName: name,
          isGuest: isGuest,
        ),
        onResend: (record) => _resendCertificate(record),
      ),
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

    final fbSnap = await FirebaseFirestore.instance
        .collection('event_feedback')
        .where('eventId', isEqualTo: eventId)
        .get();

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

      final hasFeedback = fbSnap.docs.any((fb) {
        final fbData = fb.data();
        if (isGuest) {
          return fbData['isGuest'] == true && fbData['guestEmail'] == key;
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
    setState(() {});
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: isError ? UpriseColors.error : UpriseColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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

  Widget _buildCardRow(CertificateBatch b, bool isLast) {
    final r = b.primary;
    return InkWell(
      onTap: () => _viewBatch(b),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    r.certificateId,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                ),
                _batchBadge(b.batchStatus),
              ],
            ),
            Text(
              b.eventName,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMM d, yyyy').format(b.date),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  b.batchStatus == 'draft'
                      ? '${b.totalRecipients} recipient${b.totalRecipients != 1 ? 's' : ''}'
                      : '${b.sentCount}/${b.totalRecipients} sent',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 6,
              children: [
                OrgActionIconButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View',
                  color: const Color(0xFF3B82F6),
                  onTap: () => _viewBatch(b),
                ),
                OrgActionIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: b.isEditable ? 'Edit' : 'Locked',
                  color: UpriseColors.primaryDark,
                  onTap: b.isEditable ? () => _editCert(r) : null,
                ),
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
          ],
        ),
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
  final int value;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
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
                      '$value',
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
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
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
  Widget build(BuildContext context) => GestureDetector(
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
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BATCH DETAIL MODAL - The View button destination
// ─────────────────────────────────────────────────────────────────────────────
class _BatchDetailModal extends StatefulWidget {
  final CertificateBatch batch;
  final String eventId;
  final VoidCallback onSendAll;
  final Future<void> Function(String key, String name, bool isGuest)
  onSendSingle;
  final Future<void> Function(CertificateRecord record) onResend;

  const _BatchDetailModal({
    required this.batch,
    required this.eventId,
    required this.onSendAll,
    required this.onSendSingle,
    required this.onResend,
  });

  @override
  State<_BatchDetailModal> createState() => _BatchDetailModalState();
}

class _BatchDetailModalState extends State<_BatchDetailModal> {
  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final eventId = widget.eventId;

    if (eventId.isEmpty) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This batch is not linked to an event.',
            style: GoogleFonts.beVietnamPro(),
          ),
        ),
      );
    }

    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      icon: Icons.card_membership_outlined,
      title: b.eventName,
      width: 720,
      maxHeightFraction: 0.85,
      subtitleWidget: Row(
        children: [
          Flexible(
            child: Text(
              '${b.totalRecipients} recipient(s) · ${b.sentCount} sent',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: Colors.white.withAlpha(179),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _batchBadge(b.batchStatus),
        ],
      ),
      footerActions: [
        ElevatedButton.icon(
          onPressed: widget.onSendAll,
          icon: const Icon(Icons.send_rounded, size: 15),
          label: Text(
            'Send All Eligible',
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          ),
        ),
      ],
      body: FutureBuilder<List<_RecipientStatusRow>>(
        future: fetchRecipientStatus(eventId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
                  style: GoogleFonts.beVietnamPro(color: UpriseColors.error),
                ),
              ),
            );
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No attendees found for this event.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final row = rows[i];
              final bool canSend = row.evaluated && !row.certSent;
              final bool awaitingEval = !row.evaluated;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: canSend
                      ? UpriseColors.warning.withOpacity(0.08)
                      : (awaitingEval
                            ? Colors.grey.shade50
                            : UpriseColors.success.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    // Name
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.name,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1A202C),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Status badge
                    Expanded(flex: 1, child: _buildStatusBadge(row)),
                    const SizedBox(width: 8),
                    // Action button
                    if (awaitingEval)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Waiting',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (canSend)
                      ElevatedButton.icon(
                        onPressed: () async {
                          await widget.onSendSingle(
                            row.key,
                            row.name,
                            row.isGuest,
                          );
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UpriseColors.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                      )
                    else if (row.certSent)
                      OutlinedButton.icon(
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
                          row.resendCount > 0
                              ? 'Resend ×${row.resendCount + 1}'
                              : 'Resend',
                          style: GoogleFonts.beVietnamPro(fontSize: 11),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: BorderSide(
                            color: UpriseColors.primaryDark.withOpacity(0.4),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(_RecipientStatusRow row) {
    String label;
    Color bg, fg;

    if (!row.evaluated) {
      label = 'Awaiting Eval';
      bg = Colors.grey[200]!;
      fg = Colors.grey[600]!;
    } else if (!row.certSent) {
      label = 'Pending';
      bg = UpriseColors.warning.withOpacity(0.18);
      fg = UpriseColors.warning;
    } else {
      label = 'Sent ✓';
      bg = UpriseColors.success.withOpacity(0.15);
      fg = UpriseColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
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
        final fittedFontSize = _autoFitFontSize(
          text: recipientName,
          baseFontSize: namePlacement.fontSize,
          maxWidthPx: boxSize.width * 0.65,
        );
        final effectivePlacement = namePlacement.copyWith(
          fontSize: fittedFontSize,
        );

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
              if (signatories.containsKey(entry.key))
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
              placeholderKey: (data['placeholderKey'] ?? '').toString(),
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
            child: _CertificateComposite(
              recipientName: 'Recipient Name',
              namePlacement:
                  _selectedTemplatePlacement ?? const CertNamePlacement(),
              signatoryPlacements: validPlacements, // ← Use only valid ones!
              signatories: signatories,
              background: NetworkImage(_selectedTemplateUrl!),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Upload your certificate design first.',
              style: GoogleFonts.beVietnamPro(color: Colors.white),
            ),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
      return;
    }
    if (distribute && !_hasEligibleRecipients) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No attendees have completed their evaluation yet — certificates can only be distributed to attendees who attended and evaluated the event.',
              style: GoogleFonts.beVietnamPro(color: Colors.white),
            ),
            backgroundColor: UpriseColors.error,
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Missing signatory data for: ${missing.join(", ")}. Add them in Admin Settings → Signatories first.',
                style: GoogleFonts.beVietnamPro(color: Colors.white),
              ),
              backgroundColor: UpriseColors.error,
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              distribute
                  ? 'Distributed ${_eligibleRecipients.length} certificate(s)!'
                  : 'Saved as draft.',
              style: GoogleFonts.beVietnamPro(color: Colors.white),
            ),
            backgroundColor: distribute
                ? UpriseColors.success
                : UpriseColors.darkGray,
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
            content: Text('Error: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<int> _fetchAttendanceCount(String eventDocId) async {
    final snap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventDocId)
        .collection('attendances')
        .get();
    return snap.docs.length;
  }

  /// Attendees who showed up (present/late) AND submitted their event
  /// evaluation. This is the actual recipient list for distribution —
  /// it's recomputed every time so newly-submitted evaluations are picked up.
  ///
  /// Returns both students (keyed by uid) and guests (keyed by email) —
  /// disambiguated via the 'isGuest' flag ('true'/'false' string, since this
  /// method's `Map<String, String>` signature is relied on elsewhere).
  Future<List<Map<String, String>>> _fetchEligibleRecipients(
    String eventDocId,
  ) async {
    final attSnap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventDocId)
        .collection('attendances')
        .get();

    final feedbackSnap = await FirebaseFirestore.instance
        .collection('feedback')
        .where('eventId', isEqualTo: eventDocId)
        .get();
    final evaluatedUids = feedbackSnap.docs
        .map((d) => d.data()['userId']?.toString())
        .whereType<String>()
        .toSet();
    final evaluatedGuestEmails = feedbackSnap.docs
        .where((d) => d.data()['isGuest'] == true)
        .map((d) => d.data()['guestEmail']?.toString())
        .whereType<String>()
        .toSet();

    final eligible = <Map<String, String>>[];
    for (final doc in attSnap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      if (status != 'present' && status != 'late') continue;

      if (data['isGuest'] == true) {
        final email = (data['guestEmail'] ?? '').toString();
        if (email.isEmpty || !evaluatedGuestEmails.contains(email)) continue;
        eligible.add({
          'recipientKey': email,
          'recipientName': (data['studentName'] ?? 'Guest').toString(),
          'isGuest': 'true',
        });
      } else {
        final studentId = (data['studentId'] ?? '').toString();
        if (studentId.isEmpty || !evaluatedUids.contains(studentId)) continue;
        eligible.add({
          'recipientKey': studentId,
          'recipientName': (data['studentName'] ?? 'Unknown').toString(),
          'isGuest': 'false',
        });
      }
    }
    return eligible;
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
                              child: StreamBuilder<QuerySnapshot>(
                                stream: _eventsStream,
                                builder: (context, snapshot) {
                                  final events = snapshot.data?.docs ?? [];
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
                                    validator: (_) => _selectedEventId == null
                                        ? 'Required'
                                        : null,
                                    items: events.map((doc) {
                                      final data =
                                          doc.data() as Map<String, dynamic>;
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
                                          doc.data() as Map<String, dynamic>;
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

                                        if (mounted && evQ.docs.isNotEmpty) {
                                          final eventDoc = evQ.docs.first;
                                          final attendeeCount =
                                              await _fetchAttendanceCount(
                                                eventDoc.id,
                                              );
                                          final eligible =
                                              await _fetchEligibleRecipients(
                                                eventDoc.id,
                                              );
                                          if (mounted) {
                                            setState(() {
                                              _selectedEventDocId = eventDoc.id;
                                              _attendeeCount = attendeeCount;
                                              _eligibleRecipients = eligible;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate Preview Dialog (view mode) — now renders through the shared
// _CertificateComposite so signatories placed on the template appear here
// too, and the recipient name auto-fits regardless of its length.
// ─────────────────────────────────────────────────────────────────────────────
class _CertPreviewDialog extends StatelessWidget {
  final CertificateRecord record;
  const _CertPreviewDialog({required this.record});

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                              background: NetworkImage(record.templateFileUrl!),
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
// Import Template Modal — upload a design exported from Canva (or anywhere
// else) as the certificate background. Now also lets the org place
// signatory placeholders (requirement #2) alongside the recipient name.
// ─────────────────────────────────────────────────────────────────────────────
class _ImportTemplateModal extends StatefulWidget {
  final String orgId;
  // The event_proposals doc this template is being built for — drives which
  // signatory(ies) (if any) the admin authorized at approval time. Null
  // means no event picked yet (the signatory picker asks for one first).
  final String? proposalId;
  const _ImportTemplateModal({required this.orgId, this.proposalId});

  @override
  State<_ImportTemplateModal> createState() => _ImportTemplateModalState();
}

class _ImportTemplateModalState extends State<_ImportTemplateModal> {
  String? _name;
  PlatformFile? _file;
  bool _isUploading = false;
  CertNamePlacement _placement = const CertNamePlacement();

  // NEW: signatory placeholders placed on this template — key -> position.
  final Map<String, CertNamePlacement> _signatoryPlacements = {};
  String? _activeSignatoryKey; // which chip is currently being dragged/edited

  static const int _maxBytes = 5 * 1024 * 1024; // 5 MB

  // Which signatory IDs the admin authorized for this event at approval
  // time, resolved once from the proposal doc rather than re-fetched on
  // every rebuild.
  late final Future<Set<String>?> _authorizedSignatoryIdsFuture =
      _loadAuthorizedSignatoryIds();

  Future<Set<String>?> _loadAuthorizedSignatoryIds() async {
    final proposalId = widget.proposalId;
    if (proposalId == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .get();
      final auth = doc.data()?['signatoryAuthorization'];
      if (auth is! Map || auth['required'] != true) return const {};
      final ids = (auth['signatoryIds'] as List?) ?? [];
      return ids.map((e) => e.toString()).toSet();
    } catch (_) {
      return const {};
    }
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
    if ((picked.size) > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${picked.name} is ${(picked.size / (1024 * 1024)).toStringAsFixed(1)} MB — max size is 5 MB.',
            ),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
      return;
    }
    setState(() => _file = picked);
  }

  Future<void> _upload() async {
    if (_file == null || _name?.trim().isEmpty == true) return;
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
      final url = json['secure_url'] as String;

      final signatoryPlacementsMap = {
        for (final e in _signatoryPlacements.entries) e.key: e.value.toMap(),
      };

      await FirebaseFirestore.instance.collection('certificate_templates').add({
        'orgId': widget.orgId,
        'name': _name!.trim(),
        'url': url,
        'namePlacement': _placement.toMap(),
        if (signatoryPlacementsMap.isNotEmpty)
          'signatoryPlacements': signatoryPlacementsMap,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, {
          'name': _name!.trim(),
          'url': url,
          'namePlacement': _placement.toMap(),
          'signatoryPlacements': signatoryPlacementsMap,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // Lets the org drag the recipient's name onto the right spot on their
  // uploaded design — everything else (org/event info) is already part of
  // the image except signatories, which can now also be placed here.
  // Position is stored as 0..1 fractions of the image, not pixels, so it
  // stays correct regardless of how big the image is rendered later.
  Widget _buildPositionPicker() {
    if (_file == null) return const SizedBox.shrink();
    final ext = (_file!.extension ?? '').toLowerCase();
    if (ext == 'pdf') {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          'PDF uploads use a centered default position for the recipient\'s name. Pick PNG/JPG instead to position it yourself.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            color: const Color(0xFF94A3B8),
          ),
        ),
      );
    }
    final bytes = _file!.bytes;
    if (bytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Position the recipient\'s name',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Drag the labels onto the right spots — everything else is already in your design. Tap "Add Signatory" below to place a signatory placeholder too.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
            child: AspectRatio(
              aspectRatio: 600 / 424,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxSize = constraints.biggest;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                      Positioned(
                        left: (_placement.xPct * boxSize.width - 60).clamp(
                          0.0,
                          boxSize.width - 120,
                        ),
                        top: (_placement.yPct * boxSize.height - 14).clamp(
                          0.0,
                          boxSize.height - 28,
                        ),
                        width: 120,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              final newX =
                                  (_placement.xPct * boxSize.width +
                                          details.delta.dx)
                                      .clamp(0.0, boxSize.width);
                              final newY =
                                  (_placement.yPct * boxSize.height +
                                          details.delta.dy)
                                      .clamp(0.0, boxSize.height);
                              _placement = _placement.copyWith(
                                xPct: newX / boxSize.width,
                                yPct: newY / boxSize.height,
                              );
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_placement.light
                                          ? Colors.black
                                          : Colors.white)
                                      .withAlpha(180),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: UpriseColors.primaryDark,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              'Recipient Name',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontStyle: FontStyle.italic,
                                color: _placement.light
                                    ? Colors.white
                                    : const Color(0xFF1A202C),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // NEW: draggable chips for each placed signatory.
                      for (final entry in _signatoryPlacements.entries)
                        Positioned(
                          left: (entry.value.xPct * boxSize.width - 45).clamp(
                            0.0,
                            math.max(0.0, boxSize.width - 90),
                          ),
                          top: (entry.value.yPct * boxSize.height - 12).clamp(
                            0.0,
                            math.max(0.0, boxSize.height - 24),
                          ),
                          width: 90,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                final current =
                                    _signatoryPlacements[entry.key]!;
                                final newX =
                                    (current.xPct * boxSize.width +
                                            details.delta.dx)
                                        .clamp(0.0, boxSize.width);
                                final newY =
                                    (current.yPct * boxSize.height +
                                            details.delta.dy)
                                        .clamp(0.0, boxSize.height);
                                _signatoryPlacements[entry.key] = current
                                    .copyWith(
                                      xPct: newX / boxSize.width,
                                      yPct: newY / boxSize.height,
                                    );
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: UpriseColors.primaryDark.withAlpha(210),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white),
                              ),
                              child: Text(
                                '{{${entry.key}}}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Size',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    Slider(
                      value: _placement.fontSize,
                      min: 10,
                      max: 36,
                      activeColor: UpriseColors.primaryDark,
                      onChanged: (v) => setState(
                        () => _placement = _placement.copyWith(fontSize: v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Text Color',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _colorChoiceChip(
                        label: 'Dark',
                        selected: !_placement.light,
                        onTap: () => setState(
                          () => _placement = _placement.copyWith(light: false),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _colorChoiceChip(
                        label: 'Light',
                        selected: _placement.light,
                        onTap: () => setState(
                          () => _placement = _placement.copyWith(light: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSignatoryPicker(),
        ],
      ),
    );
  }

  // NEW: lets the org pick a signatory from the Admin Settings roster and
  // drop its placeholder onto the canvas above.
  Widget _buildSignatoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signatories',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<Set<String>?>(
          future: _authorizedSignatoryIdsFuture,
          builder: (context, authSnap) {
            if (widget.proposalId == null) {
              return Text(
                'Select an event above first — signatories are limited to '
                'whoever the admin authorized for that specific event.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: const Color(0xFF9AA5B4),
                ),
              );
            }
            if (!authSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final authorizedIds = authSnap.data ?? const {};
            if (authorizedIds.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'No signature was authorized for this event — ask your '
                  'admin to authorize one when approving it, or continue '
                  'without a signature on this certificate.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    color: const Color(0xFF92400E),
                  ),
                ),
              );
            }
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('signatories')
                  .snapshots(),
              builder: (context, snap) {
                final roster = (snap.data?.docs ?? [])
                    .map((d) => SignatoryData.fromDoc(d))
                    .where((s) => authorizedIds.contains(s.id))
                    .toList();
                if (roster.isEmpty) {
                  return Text(
                    'The signatory authorized for this event no longer '
                    'exists in Admin Settings → Signatories.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: const Color(0xFF9AA5B4),
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: roster.map((s) {
                    final placed = _signatoryPlacements.containsKey(s.id);
                    return InkWell(
                      onTap: () => setState(() {
                        if (placed) {
                          _signatoryPlacements.remove(s.id);
                        } else {
                          _signatoryPlacements[s.id] = const CertNamePlacement()
                              .copyWith(xPct: 0.5, yPct: 0.75);
                        }
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: placed
                              ? UpriseColors.primaryDark
                              : const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: placed
                                ? UpriseColors.primaryDark
                                : const Color(0xFFE4E8EF),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              placed ? Icons.check_rounded : Icons.add_rounded,
                              size: 13,
                              color: placed
                                  ? Colors.white
                                  : const Color(0xFF374151),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '{{${s.id}}} — ${s.fullName}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: placed
                                    ? Colors.white
                                    : const Color(0xFF374151),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SizedBox(
          width: 480,
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
                            'Bring in a design from outside Uprise',
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
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FieldWrapper(
                          label: 'Template Name *',
                          child: TextField(
                            decoration: _fieldDecoration(
                              hint: 'e.g. CICT Awards Design',
                              icon: Icons.badge_outlined,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            onChanged: (v) => setState(() => _name = v),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _FieldWrapper(
                          label: 'File (PNG, JPG, or PDF) *',
                          child: InkWell(
                            onTap: _pickFile,
                            borderRadius: BorderRadius.circular(_DS.radiusSm),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FA),
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusSm,
                                ),
                                border: Border.all(
                                  color: const Color(0xFFE4E8EF),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.upload_file_outlined,
                                    size: 17,
                                    color: UpriseColors.primaryDark,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _file?.name ?? 'Choose a file…',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                        color: _file == null
                                            ? const Color(0xFF9AA5B4)
                                            : const Color(0xFF1A202C),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'Browse',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: UpriseColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _buildPositionPicker(),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                  color: Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
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
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed:
                          (_file == null ||
                              _name == null ||
                              _name!.trim().isEmpty ||
                              _isUploading)
                          ? null
                          : _upload,
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
                        'Upload',
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
