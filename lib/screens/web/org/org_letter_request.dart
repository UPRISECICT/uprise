// lib/screens/web/org/org_letter_request.dart
// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:convert';
import '../../../widgets/stat_cards.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../models/letter_type.dart';
import '../../../services/firestore_collections.dart';
import '../../../services/notification_service.dart';
import '../../../utils/platform_file_utils.dart' as platform_file_utils;
import '../../../utils/school_year.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/org_attachment_preview.dart';
import '../../../widgets/org_modal_shell.dart';
import '../../../theme/org_theme.dart';
import 'export_util.dart';
import 'export_pdf.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusPill = 100;

  // Same brand color org_event_proposals.dart uses, so both screens are on-themed.
  static const Color primary = UpriseColors.primaryDark;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
  }) {
    // Every call site already writes labels like 'Subject *' — the
    // asterisk was just plain text in the same gray as the rest of the
    // label, so nothing actually read as "required" at a glance. Splitting
    // it into its own red TextSpan is a purely cosmetic fix; no call site
    // needs to change.
    final labelTextStyle = GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF64748B),
    );
    final isRequired = label.endsWith(' *');
    final baseLabel = isRequired ? label.substring(0, label.length - 2) : label;
    return InputDecoration(
      label: isRequired
          ? Text.rich(
              TextSpan(
                text: baseLabel,
                style: labelTextStyle,
                children: [
                  TextSpan(
                    text: ' *',
                    style: labelTextStyle.copyWith(
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            )
          : null,
      labelText: isRequired ? null : label,
      hintText: hint,
      // [icon] intentionally unused now — a generic prefixIcon on every
      // field (label text already says what it is) was clutter, not
      // disambiguation. Kept for existing call sites.
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
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _DS.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
Widget _statusBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'pending': _BadgeStyle(
      const Color(0xFFFFFBEB),
      const Color(0xFFFB923C),
      'PENDING',
    ),
    'approved': _BadgeStyle(
      const Color(0xFFECFDF5),
      const Color(0xFF059669),
      'APPROVED',
    ),
    'rejected': _BadgeStyle(
      const Color(0xFFFEF2F2),
      const Color(0xFFDC2626),
      'REJECTED',
    ),
    'revision': _BadgeStyle(
      const Color(0xFFEFF6FF),
      const Color(0xFF2563EB),
      'NEEDS REVISION',
    ),
    'resubmitted': _BadgeStyle(
      const Color(0xFFF3E8FF),
      const Color(0xFF7C3AED),
      'RESUBMITTED',
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
      softWrap: false,
      overflow: TextOverflow.visible,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: s.fg,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class OrgLetterRequestScreen extends StatefulWidget {
  final String orgId;
  const OrgLetterRequestScreen({super.key, required this.orgId});

  @override
  State<OrgLetterRequestScreen> createState() => _OrgLetterRequestScreenState();
}

class _OrgLetterRequestScreenState extends State<OrgLetterRequestScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;

  Map<String, dynamic>? _orgProfile;
  String _orgName = '';
  String _orgEmail = '';
  String _orgLogoUrl = '';

  @override
  void initState() {
    super.initState();
    _loadOrgProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrgProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (doc.exists) {
        setState(() {
          _orgProfile = doc.data();
          _orgName = doc.data()?['name'] ?? 'Organization';
          _orgEmail = doc.data()?['email'] ?? '';
          _orgLogoUrl = doc.data()?['logoUrl'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading org profile: $e');
    }
  }

  // Created once, not a getter — widget.orgId never changes for this
  // screen's lifetime, so a getter here was re-subscribing (twice, since
  // it's used in two places) on every rebuild.
  late final Stream<QuerySnapshot> _requestsStream = FirestoreCollections
      .letterRequests
      .where('orgId', isEqualTo: widget.orgId)
      .where('isArchived', isEqualTo: false)
      .orderBy('timestamp', descending: true)
      .snapshots();

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

  // ── Stats Row ─────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    return StreamBuilder<QuerySnapshot>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        int total = 0,
            pending = 0,
            approved = 0,
            rejected = 0,
            revision = 0,
            resubmitted = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            total++;
            final status = (doc.data() as Map)['status'] ?? 'pending';
            if (status == 'pending') pending++;
            if (status == 'approved') approved++;
            if (status == 'rejected') rejected++;
            if (status == 'revision') revision++;
            if (status == 'resubmitted') resubmitted++;
          }
        }
        void selectStatus(String status) => setState(() {
          _statusFilter = _statusFilter == status ? 'All' : status;
          _currentPage = 1;
        });

        // Four cards, not six. These used to sit in a bare Row with no
        // Expanded and no wrapping, so at six cards the row simply ran off
        // the edge of a narrow window. StatCardsRow divides the width and
        // wraps; the two least-used states moved to the strip below.
        final cards = [
          StatCard(
            label: 'Total Requests',
            value: '$total',
            icon: Icons.description_outlined,
            color: _DS.primary,
            // 'All' is the default, no-filter state — not a deliberate
            // selection — so this card never shows the "selected" glow,
            // even though _statusFilter starts equal to 'All'. Without
            // this, the very first card always rendered pre-highlighted
            // on page load, before the user had clicked anything (same
            // bug as event proposals' stat cards).
            selected: false,
            onTap: () => setState(() {
              _statusFilter = 'All';
              _currentPage = 1;
            }),
          ),
          StatCard(
            label: 'Pending',
            value: '$pending',
            icon: Icons.pending_outlined,
            color: const Color(0xFFFB923C),
            selected: _statusFilter == 'Pending',
            onTap: () => selectStatus('Pending'),
          ),
          StatCard(
            label: 'Approved',
            value: '$approved',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF059669),
            selected: _statusFilter == 'Approved',
            onTap: () => selectStatus('Approved'),
          ),
          StatCard(
            label: 'Rejected',
            value: '$rejected',
            icon: Icons.cancel_outlined,
            color: const Color(0xFFDC2626),
            selected: _statusFilter == 'Rejected',
            onTap: () => selectStatus('Rejected'),
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatCardsRow(cards: cards, isMobile: isMobile, gap: 12),
              const SizedBox(height: 14),
              StatStrip(
                items: [
                  StatStripItem.count(
                    label: 'Needs revision',
                    count: revision,
                    color: const Color(0xFF2563EB),
                    selected: _statusFilter == 'Needs Revision',
                    onTap: () => selectStatus('Needs Revision'),
                  ),
                  StatStripItem.count(
                    label: 'Resubmitted',
                    count: resubmitted,
                    color: const Color(0xFF7C3AED),
                    selected: _statusFilter == 'Resubmitted',
                    onTap: () => selectStatus('Resubmitted'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final fieldWidth = isMobile ? double.infinity : (isTablet ? 260.0 : 340.0);
    final searchField = SizedBox(
      width: fieldWidth,
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by ID, subject, or message…',
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
            borderSide: const BorderSide(color: _DS.primary, width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() => _currentPage = 1),
      ),
    );

    final controls = [
      _FilterDropdown(
        value: _statusFilter,
        items: const [
          'All',
          'Pending',
          'Approved',
          'Rejected',
          'Needs Revision',
          'Resubmitted',
        ],
        hint: 'Status',
        icon: Icons.tune_rounded,
        onChanged: (v) => setState(() {
          _statusFilter = v!;
          _currentPage = 1;
        }),
      ),
      AdminExportButton(
        label: 'Export',
        onSelected: (format) => _exportRequests(format),
      ),
      _ToolbarButton(
        label: 'New Request',
        icon: Icons.add_rounded,
        onPressed: _openNewRequestModal,
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 980) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      controls
                          .expand(
                            (widget) => [widget, const SizedBox(width: 10)],
                          )
                          .toList()
                        ..removeLast(),
                ),
              ],
            );
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [searchField, ...controls],
          );
        },
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────
  Widget _buildTable(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    return StreamBuilder<QuerySnapshot>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;

        if (_statusFilter != 'All') {
          final filterValue = _statusFilter == 'Needs Revision'
              ? 'revision'
              : _statusFilter.toLowerCase();
          docs = docs
              .where((d) => (d.data() as Map)['status'] == filterValue)
              .toList();
        }

        final term = _searchController.text.trim().toLowerCase();
        if (term.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['letterId'] ?? '').toString().toLowerCase().contains(
                  term,
                ) ||
                (data['subject'] ?? '').toString().toLowerCase().contains(
                  term,
                ) ||
                (data['message'] ?? '').toString().toLowerCase().contains(term);
          }).toList();
        }

        final requests = docs
            .map((d) => LetterRequestModel.fromFirestore(d))
            .toList();

        final totalPages = requests.isEmpty
            ? 1
            : (requests.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, requests.length);
        final pageItems = requests.isEmpty
            ? <LetterRequestModel>[]
            : requests.sublist(start, end);

        final tableContent = Container(
          margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                child: requests.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageItems.length,
                        itemBuilder: (_, i) => _buildRequestRow(
                          pageItems[i],
                          isLast: i == pageItems.length - 1,
                        ),
                      ),
              ),
              _buildFooter(requests.length, totalPages, start, end),
            ],
          ),
        );

        return isMobile
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: tableContent,
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
        border: Border(bottom: BorderSide(color: _DS.primary.withAlpha(60))),
      ),
      child: Row(
        // Every column below is a fixed width now (not Expanded) — with
        // spaceBetween, any extra room on a wide screen becomes equal gaps
        // between columns instead of one column (SUBJECT) swallowing all of
        // it while the rest cluster together on the right.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(width: 340, child: _headerCell('SUBJECT')),
          SizedBox(width: 130, child: _headerCell('DATE SUBMITTED')),
          SizedBox(width: 150, child: _headerCell('E-SIGNED')),
          SizedBox(width: 130, child: _headerCell('STATUS')),
          SizedBox(
            width: 110,
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

  Widget _buildRequestRow(LetterRequestModel request, {required bool isLast}) {
    final submittedAt = request.timestamp.toDate();
    final messagePreview =
        request.message != null && request.message!.isNotEmpty
        ? (request.message!.length > 40
              ? '${request.message!.substring(0, 40)}...'
              : request.message!)
        : '—';

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _viewRequestDetails(request),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 340,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    request.subject,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A202C),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (messagePreview != '—') ...[
                    const SizedBox(height: 2),
                    Text(
                      messagePreview,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF9AA5B4),
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                DateFormat('MMM dd, yyyy').format(submittedAt),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 150,
              child: request.signedAt != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.draw_rounded,
                          size: 12,
                          color: Color(0xFF059669),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat(
                              'MMM dd, yyyy',
                            ).format(request.signedAt!.toDate()),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF059669),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '—',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFFD1D5DB),
                      ),
                    ),
            ),
            SizedBox(
              width: 130,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(request.status),
              ),
            ),
            SizedBox(
              width: 110,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OrgActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    onTap: () => _viewRequestDetails(request),
                  ),
                  const SizedBox(width: 6),
                  if (request.status == 'pending' ||
                      request.status == 'revision' ||
                      request.status == 'resubmitted')
                    OrgActionIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit Request',
                      color: _DS.primary,
                      onTap: () => _openEditRequestModal(request),
                    ),
                  if (request.status == 'pending' ||
                      request.status == 'revision' ||
                      request.status == 'resubmitted')
                    const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: Icons.archive_outlined,
                    tooltip: 'Archive',
                    color: const Color(0xFF6B7280),
                    onTap: () => _archiveRequest(request),
                  ),
                ],
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
              Icons.mail_outline_rounded,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No letter requests found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters or create a new request.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
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
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total requests',
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

  // ── Dialogs ───────────────────────────────────────────────────────
  Future<void> _openNewRequestModal() async {
    if (_orgProfile == null) {
      _showSnack('Loading organization info…');
      return;
    }
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _LetterRequestModal(
        orgId: widget.orgId,
        orgName: _orgName,
        orgEmail: _orgEmail,
        orgLogoUrl: _orgLogoUrl,
      ),
    );
  }

  Future<void> _openEditRequestModal(LetterRequestModel request) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _LetterRequestModal(
        orgId: widget.orgId,
        orgName: _orgName,
        orgEmail: _orgEmail,
        orgLogoUrl: _orgLogoUrl,
        existingRequest: request,
      ),
    );
  }

  Future<void> _viewRequestDetails(LetterRequestModel request) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _RequestDetailsDialog(request: request),
    );
  }

  Future<void> _archiveRequest(LetterRequestModel request) async {
    final confirm = await _showConfirmDialog(
      title: 'Archive Request',
      message:
          'Archive "${request.subject}"? You can still view it in the archived section.',
      confirmLabel: 'Archive',
      isDestructive: false,
    );
    if (confirm != true) return;

    try {
      await FirestoreCollections.letterRequests.doc(request.id).update({
        'isArchived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      });
      await activity_log.ActivityLogger.log(
        action: 'archive_letter_request',
        module: 'letter_request',
        details: {'orgId': widget.orgId, 'requestId': request.id},
      );
      _showSnack('Request archived successfully');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _exportRequests(String format) async {
    final searchTerm = _searchController.text.trim().toLowerCase();
    try {
      var snap = await FirestoreCollections.letterRequests
          .where('orgId', isEqualTo: widget.orgId)
          .where('isArchived', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .get();
      var docs = snap.docs;

      if (_statusFilter != 'All') {
        final fv = _statusFilter == 'Needs Revision'
            ? 'revision'
            : _statusFilter.toLowerCase();
        docs = docs.where((d) => (d.data() as Map)['status'] == fv).toList();
      }
      if (searchTerm.isNotEmpty) {
        docs = docs.where((d) {
          final data = d.data() as Map;
          return (data['letterId'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              ) ||
              (data['subject'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              ) ||
              (data['message'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              );
        }).toList();
      }

      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data to export'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final requests = docs
          .map((d) => LetterRequestModel.fromFirestore(d))
          .toList();
      final headers = [
        'Letter ID',
        'Type',
        'Subject',
        'Message',
        'Date Submitted',
        'Status',
        'Revision Notes',
      ];
      final rows = requests
          .map(
            (r) => [
              r.letterId,
              r.letterType,
              r.subject,
              r.message ?? '',
              DateFormat('yyyy-MM-dd').format(r.timestamp.toDate()),
              r.status,
              r.revisionNote ?? '',
            ],
          )
          .toList();

      final now = DateTime.now().toString().substring(0, 10);

      // AdminExportButton's dropdown emits 'excel'/'pdf' (see
      // admin_export_button.dart's _items), not 'csv' — this used to
      // check for 'csv', so "Export as Excel" silently did nothing.
      if (format == 'excel') {
        final csv = [headers, ...rows]
            .map(
              (row) => row.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
            )
            .join('\n');
        await OrgExportUtil.saveText(
          csv,
          'letter_requests_$now.csv',
          mimeType: 'text/csv',
        );
      } else if (format == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Letter Requests',
          headers: headers,
          rows: rows,
          orgLogoUrl: _orgLogoUrl,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'letter_requests_$now.pdf',
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.beVietnamPro(color: Colors.white),
        ),
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
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
                      color: isDestructive
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDestructive
                          ? Icons.delete_outline_rounded
                          : Icons.archive_outlined,
                      color: isDestructive
                          ? const Color(0xFFDC2626)
                          : _DS.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    title,
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
                message,
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
                    onPressed: () => Navigator.pop(ctx, false),
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
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDestructive
                          ? const Color(0xFFDC2626)
                          : _DS.primary,
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
                      confirmLabel,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Request Details Dialog (with attachment viewer)
// ─────────────────────────────────────────────────────────────────────────────
class _RequestDetailsDialog extends StatelessWidget {
  final LetterRequestModel request;
  const _RequestDetailsDialog({required this.request});

  void _openAttachment(BuildContext context) async {
    final base64 = request.attachmentBase64;
    if (base64 == null || base64.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attachment found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final bytes = base64Decode(base64);
      final fileName = request.attachmentName ?? 'attachment';
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final mime = _getMimeTypeFromExtension(ext);

      if (mime.startsWith('text/')) {
        final content = utf8.decode(bytes);
        OrgAttachmentPreview.showText(
          context: context,
          fileName: fileName,
          text: content,
          onDownload: () => platform_file_utils.saveBytesToTempAndOpen(
            bytes,
            fileName,
            mimeType: mime,
          ),
        );
        return;
      }

      if (mime.startsWith('image/')) {
        OrgAttachmentPreview.showImage(
          context: context,
          bytes: bytes,
          fileName: fileName,
          onDownload: () => platform_file_utils.saveBytesToTempAndOpen(
            bytes,
            fileName,
            mimeType: mime,
          ),
        );
        return;
      }

      // PDFs render natively in the browser's own viewer when opened with
      // the correct MIME type in a new tab — passing the real mime here
      // (instead of the default octet-stream) is what makes this "view"
      // instead of forcing a download.
      await platform_file_utils.saveBytesToTempAndOpen(
        bytes,
        fileName,
        mimeType: mime,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openSignedDocument(BuildContext context) async {
    final base64 = request.signedDocumentBase64;
    if (base64 == null || base64.isEmpty) return;
    try {
      final bytes = base64Decode(base64);
      await platform_file_utils.saveBytesToTempAndOpen(
        bytes,
        '${request.letterId}-signed.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening signed copy: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getMimeTypeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'json':
        return 'application/json';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrgModalShell(
      accentColor: _DS.primary,
      icon: Icons.description_outlined,
      title: 'Request Details',
      subtitle: request.letterId,
      footerActions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DS.primary,
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrgModalSection(
                title: 'Request Details',
                icon: Icons.info_outline_rounded,
                accentColor: _DS.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Letter ID',
                            value: request.letterId,
                            icon: Icons.badge_outlined,
                            iconColor: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Status',
                            value: request.status.toUpperCase(),
                            icon: Icons.circle_outlined,
                            valueColor: _statusColor(request.status),
                            iconColor: _statusColor(request.status),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: const Color(0xFFE8ECF0)),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Type',
                            value: request.letterType,
                            icon: Icons.label_outlined,
                            iconColor: const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Date Submitted',
                            value: DateFormat(
                              'MMM dd, yyyy',
                            ).format(request.timestamp.toDate()),
                            icon: Icons.calendar_today_outlined,
                            iconColor: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: const Color(0xFFE8ECF0)),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OrgDetailItem(
                            label: 'School Year',
                            value: request.schoolYear.isNotEmpty
                                ? request.schoolYear
                                : '—',
                            icon: Icons.school_outlined,
                            iconColor: const Color(0xFF0D9488),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OrgDetailItem(
                            label: 'Semester',
                            value: request.semester.isNotEmpty
                                ? request.semester
                                : '—',
                            icon: Icons.date_range_outlined,
                            iconColor: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: const Color(0xFFE8ECF0)),
                    const SizedBox(height: 12),
                    OrgDetailItem(
                      label: 'Subject',
                      value: request.subject,
                      icon: Icons.subject_rounded,
                      iconColor: _DS.primary,
                    ),
                    if (request.message != null &&
                        request.message!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: const Color(0xFFE8ECF0)),
                      const SizedBox(height: 12),
                      OrgDetailItem(
                        label: 'Message',
                        value: request.message!,
                        icon: Icons.message_outlined,
                        iconColor: const Color(0xFF7C3AED),
                      ),
                    ],
                  ],
                ),
              ),
              if (request.attachmentName != null &&
                  request.attachmentBase64 != null) ...[
                const SizedBox(height: 14),
                _buildAttachmentViewer(context),
              ] else if (request.attachmentName != null) ...[
                const SizedBox(height: 14),
                OrgDetailItem(
                  label: 'Attachment',
                  value:
                      '${request.attachmentName}${request.attachmentSize != null ? ' (${request.attachmentSize})' : ''}',
                  icon: Icons.attach_file_rounded,
                  iconColor: const Color(0xFFDB2777),
                ),
              ],
              if (request.signedDocumentBase64 != null &&
                  request.signedDocumentBase64!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF059669).withAlpha(38),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Digitally Signed Copy',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A202C),
                              ),
                            ),
                            if (request.signedBy != null)
                              Text(
                                'Signed by ${request.signedBy}',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _openSignedDocument(context),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('View'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (request.status.toLowerCase() == 'rejected') ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.cancel_outlined,
                            size: 14,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'REJECTION REASON',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFDC2626),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (request.rejectionReason != null &&
                                request.rejectionReason!.isNotEmpty)
                            ? request.rejectionReason!
                            : 'No reason was recorded for this rejection.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontStyle:
                              (request.rejectionReason != null &&
                                  request.rejectionReason!.isNotEmpty)
                              ? FontStyle.normal
                              : FontStyle.italic,
                          color:
                              (request.rejectionReason != null &&
                                  request.rejectionReason!.isNotEmpty)
                              ? const Color(0xFF1A202C)
                              : const Color(0xFF9AA5B4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (request.revisionNote != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'REVISION NOTE FROM ADMIN',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2563EB),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        request.revisionNote!,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF1A202C),
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

  Widget _buildAttachmentViewer(BuildContext context) {
    final fileName = request.attachmentName ?? 'attachment';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.attach_file_rounded,
              size: 13,
              color: const Color(0xFF9AA5B4),
            ),
            const SizedBox(width: 5),
            Text(
              'Attachment',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _DS.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _DS.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _DS.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getFileIcon(fileName),
                  color: _DS.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (request.attachmentSize != null)
                      Text(
                        request.attachmentSize!,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openAttachment(context),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _DS.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'revision':
        return const Color(0xFF2563EB);
      case 'resubmitted':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFFFB923C);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Letter Request Modal (New / Edit)
// ─────────────────────────────────────────────────────────────────────────────
class _LetterRequestModal extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgEmail;
  final String orgLogoUrl;
  final LetterRequestModel? existingRequest;

  const _LetterRequestModal({
    required this.orgId,
    required this.orgName,
    required this.orgEmail,
    this.orgLogoUrl = '',
    this.existingRequest,
  });

  @override
  State<_LetterRequestModal> createState() => _LetterRequestModalState();
}

class _LetterRequestModalState extends State<_LetterRequestModal> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _addressedToCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  String _letterType = LetterType.all.first.id;
  DateTime? _neededBy;

  String? _attachmentBase64;
  String? _attachmentName;
  String? _attachmentSize;
  bool _isSubmitting = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _errorMsg;
  bool _attachmentError = false;
  String _schoolYear = SchoolYearUtil.currentSchoolYear();
  String _semester = SchoolYearUtil.currentSemester();

  @override
  void initState() {
    super.initState();
    final r = widget.existingRequest;
    if (r != null) {
      _subjectCtrl.text = r.subject;
      _messageCtrl.text = r.message ?? '';
      _addressedToCtrl.text = r.addressedTo;
      _purposeCtrl.text = r.purpose;
      // Legacy documents carry the old hardcoded 'General', which
      // LetterType.byId resolves to 'Other' — the type that still requires
      // the attachment those requests already have.
      _letterType = LetterType.byId(r.letterType).id;
      _neededBy = r.neededBy?.toDate();
      _attachmentBase64 = r.attachmentBase64;
      _attachmentName = r.attachmentName;
      _attachmentSize = r.attachmentSize;
      if (r.schoolYear.isNotEmpty) _schoolYear = r.schoolYear;
      if (r.semester.isNotEmpty) _semester = r.semester;
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    _addressedToCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'png'],
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showMsg('Cannot read file!', isError: true);
      return;
    }

    final sizeBytes = file.bytes!.length;
    if (sizeBytes > 700 * 1024) {
      _showMsg(
        'File is ${(sizeBytes / 1024).toStringAsFixed(1)} KB. Maximum is 700 KB.',
        isError: true,
      );
      return;
    }

    final sizeKB = (sizeBytes / 1024).toStringAsFixed(1);
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _attachmentName = file.name;
      _attachmentSize = '$sizeKB KB';
      _errorMsg = null;
      _attachmentError = false;
    });

    for (int i = 0; i <= 100; i += 20) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) setState(() => _uploadProgress = i / 100);
    }

    try {
      setState(() {
        _attachmentBase64 = base64Encode(file.bytes!);
        _uploadProgress = 1.0;
        _isUploading = false;
      });
    } catch (e) {
      setState(() => _isUploading = false);
      _showMsg('Error converting file: $e', isError: true);
    }
  }

  void _removeFile() => setState(() {
    _attachmentBase64 = null;
    _attachmentName = null;
    _attachmentSize = null;
    _uploadProgress = 0;
  });

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.beVietnamPro(color: Colors.white),
        ),
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pickNeededBy() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        // Material 3's default seed skews purple/indigo unless the scheme
        // is seeded from the brand color instead — same fix as the other
        // date pickers in the portal.
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: _DS.primary,
                  brightness: Brightness.light,
                ).copyWith(
                  primary: _DS.primary,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  surfaceTint: Colors.transparent,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _neededBy = picked;
        _errorMsg = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _errorMsg = null;
      _attachmentError = false;
    });
    if (!_formKey.currentState!.validate()) return;

    if (_neededBy == null) {
      setState(() => _errorMsg = 'Pick the date you need this letter by.');
      return;
    }
    if (widget.existingRequest == null &&
        _attachmentBase64 == null &&
        LetterType.needsAttachment(_letterType)) {
      setState(() {
        _errorMsg =
            'A ${LetterType.byId(_letterType).label} request needs your \n'
            'draft attached.';
        _attachmentError = true;
      });
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final data = <String, dynamic>{
        'orgId': widget.orgId,
        'orgName': widget.orgName,
        'orgEmail': widget.orgEmail,
        'orgLogoUrl': widget.orgLogoUrl,
        'name': widget.orgName,
        'email': widget.orgEmail,
        'letterType': _letterType,
        'addressedTo': _addressedToCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim(),
        'neededBy': _neededBy == null ? null : Timestamp.fromDate(_neededBy!),
        'schoolYear': _schoolYear,
        'semester': _semester,
        'subject': _subjectCtrl.text.trim(),
        'message': _messageCtrl.text.trim().isEmpty
            ? null
            : _messageCtrl.text.trim(),
        'attachmentBase64': _attachmentBase64,
        'attachmentName': _attachmentName,
        'attachmentSize': _attachmentSize,
        'updatedAt': FieldValue.serverTimestamp(),
        'isArchived': false,
      };

      final col = FirestoreCollections.letterRequests;

      if (widget.existingRequest != null) {
        if (widget.existingRequest!.status == 'revision') {
          data['status'] = 'resubmitted';
          data['resubmittedAt'] = FieldValue.serverTimestamp();
          data['revisionNote'] = null;
          data['revisionCount'] = FieldValue.increment(1);
        }
        await col.doc(widget.existingRequest!.id).update(data);
        await activity_log.ActivityLogger.log(
          action: 'edit_letter_request',
          module: 'letter_request',
          details: {
            'orgId': widget.orgId,
            'requestId': widget.existingRequest!.id,
          },
        );
        if (widget.existingRequest!.status == 'revision') {
          NotificationService.sendToAllAdmins(
            title: 'Letter request resubmitted',
            body:
                '${widget.orgName} resubmitted "${data['subject']}" after revision.',
            type: 'letter_resubmission',
            orgId: widget.orgId,
          );
        }
        _showMsg('Letter request updated successfully!');
      } else {
        final letterId =
            'RLR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        data['status'] = 'pending';
        data['letterId'] = letterId;
        data['timestamp'] = FieldValue.serverTimestamp();
        data['revisionCount'] = 0;
        await col.add(data);
        await activity_log.ActivityLogger.log(
          action: 'create_letter_request',
          module: 'letter_request',
          details: {'orgId': widget.orgId, 'subject': data['subject']},
        );
        NotificationService.sendToAllAdmins(
          title: 'New letter request submitted',
          body:
              '${widget.orgName} submitted a letter request: "${data['subject']}".',
          type: 'letter_submission',
          orgId: widget.orgId,
        );
        _showMsg('Letter request submitted successfully!');
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingRequest != null;

    return OrgModalShell(
      accentColor: _DS.primary,
      icon: isEdit ? Icons.edit_outlined : Icons.mail_outline_rounded,
      title: isEdit ? 'Edit Letter Request' : 'New Letter Request',
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
          onPressed: _isSubmitting || _isUploading ? null : _submit,
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
            isEdit ? 'Save Changes' : 'Submit Request',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DS.primary,
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
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrgModalSection(
                title: 'Request Details',
                icon: Icons.description_outlined,
                accentColor: _DS.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type first: it decides whether an attachment is
                    // required further down, so asking for it last would
                    // move the goalposts after the org had already filled
                    // the form in.
                    DropdownButtonFormField<String>(
                      value: _letterType,
                      isExpanded: true,
                      decoration: _DS.inputDecoration(
                        'Type of letter *',
                        icon: Icons.category_outlined,
                      ),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF1A202C),
                      ),
                      items: [
                        for (final t in LetterType.all)
                          DropdownMenuItem(value: t.id, child: Text(t.label)),
                      ],
                      onChanged: (v) => setState(() {
                        _letterType = v!;
                        _errorMsg = null;
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      LetterType.byId(_letterType).description,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _subjectCtrl,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: _DS.inputDecoration(
                        'Subject *',
                        hint: 'What is this letter regarding?',
                        icon: Icons.subject_rounded,
                      ),
                      validator: (v) => v?.trim().isEmpty == true
                          ? 'Subject is required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _addressedToCtrl,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: _DS.inputDecoration(
                        'Addressed to *',
                        hint: 'e.g. Dean, College of ICT',
                        icon: Icons.person_outline_rounded,
                      ),
                      validator: (v) => v?.trim().isEmpty == true
                          ? 'Say who the letter is addressed to'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _purposeCtrl,
                      maxLines: 2,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: _DS.inputDecoration(
                        'Purpose *',
                        hint: 'Why the letter is needed',
                        icon: Icons.flag_outlined,
                      ),
                      validator: (v) => v?.trim().isEmpty == true
                          ? 'Describe the purpose'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    // Needed-by gives the admin something to triage by;
                    // before this every request looked equally urgent.
                    InkWell(
                      onTap: _pickNeededBy,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: _DS.inputDecoration(
                          'Needed by *',
                          icon: Icons.event_outlined,
                        ),
                        child: Text(
                          _neededBy == null
                              ? 'Select a date'
                              : DateFormat('MMM d, yyyy').format(_neededBy!),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: _neededBy == null
                                ? const Color(0xFF9AA5B4)
                                : const Color(0xFF1A202C),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _schoolYear,
                            decoration: _DS.inputDecoration('School Year *'),
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
                            decoration: _DS.inputDecoration('Semester *'),
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
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _messageCtrl,
                      maxLines: 3,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: _DS.inputDecoration(
                        'Message (optional)',
                        hint:
                            'Additional instructions or notes for the admin...',
                        icon: Icons.message_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              OrgModalSection(
                title: 'File Attachment',
                icon: Icons.attach_file_rounded,
                accentColor: _DS.primary,
                required:
                    widget.existingRequest == null &&
                    LetterType.needsAttachment(_letterType),
                child: _buildFileZone(),
              ),

              if (widget.existingRequest?.revisionNote != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'REVISION NOTE FROM ADMIN',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2563EB),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.existingRequest!.revisionNote!,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF1A202C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

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

  Widget _buildFileZone() {
    final hasFile = _attachmentBase64 != null;

    if (_isUploading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _DS.primary.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: _DS.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _attachmentName ?? 'Uploading…',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E6EA),
                valueColor: const AlwaysStoppedAnimation(_DS.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Uploading ${(_uploadProgress * 100).toInt()}%',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    if (hasFile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF059669), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.1),
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
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF065F46),
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
              onPressed: _removeFile,
              child: Text(
                'Remove',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
            TextButton(
              onPressed: _pickFile,
              child: Text(
                'Change',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: _DS.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickFile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _attachmentError
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _attachmentError
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFE2E6EA),
              width: _attachmentError ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _DS.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  size: 24,
                  color: _DS.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                  children: [
                    TextSpan(
                      text: 'Click to browse ',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w600,
                        color: _DS.primary,
                      ),
                    ),
                    const TextSpan(text: 'or drop your file here'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Supported: PDF, DOC, DOCX, TXT, JPG, PNG — max 700 KB',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF9AA5B4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final resolvedValue = items.contains(value) ? value : null;
    return AnchoredMenuTrigger<String>(
      items: items,
      labelOf: (s) => s,
      selectedValue: resolvedValue,
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
              resolvedValue ?? hint,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: resolvedValue == null
                    ? const Color(0xFF9AA5B4)
                    : const Color(0xFF374151),
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

  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: _DS.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
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
            color: isActive ? _DS.primary : Colors.transparent,
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
// Letter Request Model
// ─────────────────────────────────────────────────────────────────────────────
class LetterRequestModel {
  final String id;
  final String letterId;
  final String orgId;
  final String orgName;
  final String orgEmail;
  final String orgLogoUrl;
  final String letterType;
  // Added when letterType became a real taxonomy. All four default so that
  // documents written before this change keep parsing untouched.
  final String addressedTo;
  final String purpose;
  final Timestamp? neededBy;
  final String schoolYear;
  final String semester;
  final String subject;
  final String? message;
  final String? attachmentBase64;
  final String? attachmentName;
  final String? attachmentSize;
  final String status;
  final String? revisionNote;
  final String? rejectionReason;
  final int? revisionCount;
  final Timestamp? resubmittedAt;
  final bool isArchived;
  final Timestamp timestamp;
  final String? signedDocumentBase64;
  final Timestamp? signedAt;
  final String? signedBy;

  LetterRequestModel({
    required this.id,
    required this.letterId,
    required this.orgId,
    required this.orgName,
    required this.orgEmail,
    this.orgLogoUrl = '',
    required this.letterType,
    this.addressedTo = '',
    this.purpose = '',
    this.neededBy,
    this.schoolYear = '',
    this.semester = '',
    required this.subject,
    this.message,
    this.attachmentBase64,
    this.attachmentName,
    this.attachmentSize,
    required this.status,
    this.revisionNote,
    this.rejectionReason,
    this.revisionCount,
    this.resubmittedAt,
    required this.isArchived,
    required this.timestamp,
    this.signedDocumentBase64,
    this.signedAt,
    this.signedBy,
  });

  factory LetterRequestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return LetterRequestModel(
      id: doc.id,
      letterId: d['letterId'] ?? 'RLR-${doc.id.substring(0, 6)}',
      orgId: d['orgId'] ?? '',
      orgName: d['orgName'] ?? 'Unknown Organization',
      orgEmail: d['orgEmail'] ?? '',
      orgLogoUrl: d['orgLogoUrl'] ?? '',
      letterType: d['letterType'] ?? 'General',
      addressedTo: (d['addressedTo'] ?? '').toString(),
      purpose: (d['purpose'] ?? '').toString(),
      neededBy: d['neededBy'] as Timestamp?,
      schoolYear: (d['schoolYear'] ?? '').toString(),
      semester: (d['semester'] ?? '').toString(),
      subject: d['subject'] ?? '',
      message: d['message'],
      attachmentBase64: d['attachmentBase64'],
      attachmentName: d['attachmentName'],
      attachmentSize: d['attachmentSize'],
      status: d['status'] ?? 'pending',
      revisionNote: d['revisionNote'],
      rejectionReason: d['rejectionReason'],
      revisionCount: d['revisionCount'] ?? 0,
      resubmittedAt: d['resubmittedAt'] as Timestamp?,
      isArchived: d['isArchived'] ?? false,
      timestamp: d['timestamp'] as Timestamp? ?? Timestamp.now(),
      signedDocumentBase64: d['signedDocumentBase64'],
      signedAt: d['signedAt'] as Timestamp?,
      signedBy: d['signedBy'],
    );
  }
}
