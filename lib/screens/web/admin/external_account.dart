import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:uprise/widgets/admin_export_button.dart';
import 'package:intl/intl.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'export_excel.dart';
import '../../../theme/admin_theme.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/admin_stat_cards_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors student_accounts.dart / org_management.dart)
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
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AdminColors.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

Widget _statusBadge(String status) {
  const styles = {
    'approved': (Color(0xFFECFDF5), Color(0xFF059669), 'APPROVED'),
    'pending': (Color(0xFFFFFBEB), Color(0xFFFB923C), 'PENDING'),
    'rejected': (Color(0xFFFEF2F2), Color(0xFFDC2626), 'REJECTED'),
  };
  final s = styles[status.toLowerCase()];
  final bg = s?.$1 ?? const Color(0xFFF3F4F6);
  final fg = s?.$2 ?? const Color(0xFF6B7280);
  final label = s?.$3 ?? status.toUpperCase();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: fg,
        letterSpacing: 0.6,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────
class ExternalRequest {
  final String id;
  final String userId;
  final String userName;
  final String email;
  final String university;
  final String status;
  final DateTime requestDate;
  final String purpose;
  final String? tempPassword;
  final String? uid;
  final bool accountCreated;
  final bool isArchived;
  // 'BulSUan' | 'Outsider' — drives which fields below are meaningful, and
  // which credentials email template gets used on approval. Defaults to
  // 'Outsider' to match guest_events_screen.dart's same fallback default.
  final String classification;
  final String college;
  final String yearLevel;
  final String section;
  final String affiliation;

  const ExternalRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.email,
    required this.university,
    required this.status,
    required this.requestDate,
    required this.purpose,
    this.tempPassword,
    this.uid,
    this.accountCreated = false,
    this.isArchived = false,
    this.classification = 'Outsider',
    this.college = '',
    this.yearLevel = '',
    this.section = '',
    this.affiliation = '',
  });

  bool get isBulSUan => classification == 'BulSUan';

  factory ExternalRequest.fromFirestore(String id, Map<String, dynamic> d) {
    return ExternalRequest(
      id: id,
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? '',
      email: d['email'] ?? '',
      university: d['university'] ?? '',
      status: d['status'] ?? 'pending',
      requestDate: (d['requestDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      purpose: d['purpose'] ?? '',
      tempPassword: d['tempPassword'] as String?,
      uid: d['uid'] as String?,
      accountCreated: d['accountCreated'] == true,
      isArchived: d['isArchived'] == true,
      classification: (d['classification'] as String?) ?? 'Outsider',
      college: (d['college'] as String?) ?? '',
      yearLevel: (d['yearLevel'] as String?) ?? '',
      section: (d['section'] as String?) ?? '',
      affiliation: (d['affiliation'] as String?) ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class ExternalAccount extends StatefulWidget {
  const ExternalAccount({super.key});

  @override
  _ExternalAccountState createState() => _ExternalAccountState();
}

class _ExternalAccountState extends State<ExternalAccount> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Checked pending requests, keyed by doc id — approving is now a bulk
  // action (checkbox per row + one Approve button) instead of a per-row
  // instant-approve icon.
  final Map<String, ExternalRequest> _selectedPending = {};

  // Created once, not constructed inline in build() — the table/stats
  // methods that use these are called on every rebuild (search, filter
  // changes, pagination), so building a fresh .snapshots() there each time
  // was re-subscribing to Firestore from scratch on every keystroke.
  late final Stream<QuerySnapshot> _requestsStream = FirebaseFirestore.instance
      .collection('external_requests')
      .snapshots();
  late final Stream<QuerySnapshot> _requestsOrderedStream = FirebaseFirestore
      .instance
      .collection('external_requests')
      .orderBy('requestDate', descending: true)
      .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(isMobile, isTablet),
          _buildToolbar(isMobile, isTablet),
          const SizedBox(height: 16),
          Expanded(child: _buildTable(isMobile, isTablet)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        int total = 0, pending = 0, approved = 0, rejected = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            total++;
            final s = (doc.data() as Map)['status'] ?? 'pending';
            if (s == 'pending') pending++;
            if (s == 'approved') approved++;
            if (s == 'rejected') rejected++;
          }
        }

        final cards = [
          _StatCard(
            label: 'Total Requests',
            value: '$total',
            icon: Icons.people_rounded,
            color: AdminColors.primaryDark,
            onTap: () => setState(() {
              _statusFilter = 'All';
              _currentPage = 1;
            }),
          ),
          _StatCard(
            label: 'Approved',
            value: '$approved',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF059669),
            onTap: () => setState(() {
              _statusFilter = 'Approved';
              _currentPage = 1;
            }),
          ),
          _StatCard(
            label: 'Pending',
            value: '$pending',
            icon: Icons.pending_rounded,
            color: const Color(0xFFFB923C),
            onTap: () => setState(() {
              _statusFilter = 'Pending';
              _currentPage = 1;
            }),
          ),
          _StatCard(
            label: 'Rejected',
            value: '$rejected',
            icon: Icons.cancel_rounded,
            color: const Color(0xFFDC2626),
            onTap: () => setState(() {
              _statusFilter = 'Rejected';
              _currentPage = 1;
            }),
          ),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: StatCardsRow(cards: cards, isMobile: isMobile),
        );
      },
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────
  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by name, email, or university…',
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
            borderSide: BorderSide(color: AdminColors.primaryDark, width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() => _currentPage = 1),
      ),
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FilterDropdown(
          value: _statusFilter,
          items: const ['All', 'Pending', 'Approved', 'Rejected', 'Archived'],
          onChanged: (v) => setState(() {
            _statusFilter = v!;
            _currentPage = 1;
          }),
        ),
        SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _selectedPending.isEmpty ? null : _confirmBulkApprove,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(
              _selectedPending.isEmpty
                  ? 'Approve Selected'
                  : 'Approve Selected (${_selectedPending.length})',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              disabledForegroundColor: const Color(0xFF6B7280),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ),
        _ExportButton(
          statusFilter: _statusFilter,
          searchTerm: _searchController.text.trim(),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [searchField, const SizedBox(height: 10), actions],
            )
          : Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 10),
                actions,
              ],
            ),
    );
  }

  // ── Table ──────────────────────────────────────────────────────────
  Widget _buildTable(bool isMobile, bool isTablet) {
    final tableContent = StreamBuilder<QuerySnapshot>(
      stream: _requestsOrderedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;

        final _searchTerm = _searchController.text.trim().toLowerCase();
        if (_searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['userName'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['email'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['university'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                );
          }).toList();
        }

        if (_statusFilter == 'Archived') {
          docs = docs
              .where((d) => (d.data() as Map)['isArchived'] == true)
              .toList();
        } else {
          // Archived requests are hidden from every other view, same as
          // letter_request.dart, so they don't clutter the active queue.
          docs = docs
              .where((d) => (d.data() as Map)['isArchived'] != true)
              .toList();
          if (_statusFilter != 'All') {
            docs = docs
                .where(
                  (d) =>
                      (d.data() as Map)['status'] ==
                      _statusFilter.toLowerCase(),
                )
                .toList();
          }
        }

        final totalPages = docs.isEmpty ? 1 : (docs.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, docs.length);
        final pageDocs = docs.isEmpty
            ? <QueryDocumentSnapshot>[]
            : docs.sublist(start, end);

        final pageReqs = pageDocs
            .map(
              (d) => ExternalRequest.fromFirestore(
                d.id,
                d.data() as Map<String, dynamic>,
              ),
            )
            .toList();
        final pendingOnPage = pageReqs
            .where((r) => r.status == 'pending')
            .toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF0)),
            boxShadow: _DS.cardShadow,
          ),
          child: Column(
            children: [
              _buildTableHeader(pendingOnPage),
              Expanded(
                child: docs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageReqs.length,
                        itemBuilder: (_, i) {
                          final req = pageReqs[i];
                          return _buildRow(
                            req: req,
                            isLast: i == pageReqs.length - 1,
                          );
                        },
                      ),
              ),
              _buildFooter(docs.length, totalPages, start, end),
            ],
          ),
        );
      },
    );

    return tableContent;
  }

  Widget _buildTableHeader(List<ExternalRequest> pendingOnPage) {
    final allSelected =
        pendingOnPage.isNotEmpty &&
        pendingOnPage.every((r) => _selectedPending.containsKey(r.id));
    final someSelected =
        !allSelected &&
        pendingOnPage.any((r) => _selectedPending.containsKey(r.id));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: pendingOnPage.isEmpty
                ? null
                : Checkbox(
                    value: allSelected ? true : (someSelected ? null : false),
                    tristate: true,
                    activeColor: const Color(0xFF059669),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        for (final r in pendingOnPage) {
                          _selectedPending[r.id] = r;
                        }
                      } else {
                        for (final r in pendingOnPage) {
                          _selectedPending.remove(r.id);
                        }
                      }
                    }),
                  ),
          ),
          Expanded(flex: 3, child: _headerCell('FULL NAME')),
          Expanded(flex: 3, child: _headerCell('EMAIL')),
          Expanded(flex: 2, child: _headerCell('UNIVERSITY / ORG')),
          Expanded(flex: 2, child: _headerCell('REQUEST DATE')),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: _headerCell('STATUS'),
            ),
          ),
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
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildRow({required ExternalRequest req, required bool isLast}) {
    final formattedDate = DateFormat('MMM dd, yyyy').format(req.requestDate);
    final parts = req.userName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (req.userName.isNotEmpty ? req.userName[0].toUpperCase() : '?');

    // Not wrapped in an InkWell-with-onTap anymore — that competed with the
    // row's own Checkbox for taps (both are tap targets in the same hit-test
    // region), which made the checkbox unreliable to click. "View Details"
    // below is the one dedicated way to open the row now.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: req.status != 'pending'
                ? null
                : Checkbox(
                    value: _selectedPending.containsKey(req.id),
                    activeColor: const Color(0xFF059669),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedPending[req.id] = req;
                      } else {
                        _selectedPending.remove(req.id);
                      }
                    }),
                  ),
          ),
          // Full name with avatar
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AdminColors.primaryDark.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.primaryDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    req.userName.isNotEmpty ? req.userName : '—',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A202C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Email
          Expanded(
            flex: 3,
            child: Text(
              req.email.isNotEmpty ? req.email : '—',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF374151),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // University
          Expanded(
            flex: 2,
            child: req.university.isNotEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryDark.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        req.university,
                        maxLines: 1,
                        softWrap: false,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.primaryDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                : Text(
                    '—',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
          ),
          // Date
          Expanded(
            flex: 2,
            child: Text(
              formattedDate,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          // Status
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: _statusBadge(req.status),
            ),
          ),
          // Actions
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionIconButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View Details',
                  color: const Color(0xFF3B82F6),
                  onTap: () => _showDetails(req),
                ),
                if (req.status == 'pending') ...[
                  const SizedBox(width: 4),
                  _ActionIconButton(
                    icon: Icons.cancel_outlined,
                    tooltip: 'Reject',
                    color: const Color(0xFFDC2626),
                    onTap: () => _confirmReject(req),
                  ),
                ],
                if (req.status == 'approved') ...[
                  const SizedBox(width: 4),
                  _ActionIconButton(
                    icon: Icons.email_outlined,
                    tooltip: 'Resend Credentials',
                    color: const Color(0xFF7C3AED),
                    onTap: () => _confirmResendCredentials(req),
                  ),
                ],
                const SizedBox(width: 4),
                _ActionIconButton(
                  icon: req.isArchived
                      ? Icons.restore_rounded
                      : Icons.archive_outlined,
                  tooltip: req.isArchived ? 'Restore' : 'Archive',
                  color: req.isArchived
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280),
                  onTap: () => req.isArchived
                      ? _confirmRestore(req)
                      : _confirmArchive(req),
                ),
              ],
            ),
          ),
        ],
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
              Icons.person_off_rounded,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No external requests found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters.',
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

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _setStatus(
    String docId,
    String newStatus, {
    required String userName,
    String email = '',
  }) async {
    // Approving for the first time → create the guest account + send credentials
    if (newStatus == 'approved') {
      await _approveAndCreateAccount(docId, userName, email);
      return;
    }

    await FirebaseFirestore.instance
        .collection('external_requests')
        .doc(docId)
        .update({'status': newStatus});

    await activity_log.ActivityLogger.log(
      action: '${newStatus.toUpperCase()} external request for $userName',
      module: 'External Account',
      severity: newStatus == 'rejected' ? 'warning' : 'info',
      details: {'requestId': docId},
    );

    if (mounted) {
      final message =
          'Request ${newStatus[0].toUpperCase()}${newStatus.substring(1)}';
      if (newStatus == 'approved') {
        AppToast.success(context, message);
      } else {
        AppToast.error(context, message);
      }
    }
  }

  // ── Approve + create guest account + send credentials ──────────────
  //
  // Mirrors _createStudentAccount() in student_accounts.dart:
  //   1. Generate a temp password
  //   2. Create the Firebase Auth user via a secondary app instance
  //      (so the admin's own session isn't replaced)
  //   3. Write account fields to `external_requests` + a `users` doc
  //      so auth_service.needsPasswordChange() can read the flag
  //   4. Email the credentials (with Firestore queue fallback)
  //
  Future<void> _approveAndCreateAccount(
    String docId,
    String userName,
    String email,
  ) async {
    // Re-fetch the doc to make sure we have the freshest email/university
    final snap = await FirebaseFirestore.instance
        .collection('external_requests')
        .doc(docId)
        .get();
    final data = snap.data() ?? {};
    final resolvedEmail =
        (email.isNotEmpty ? email : (data['email'] as String? ?? ''))
            .trim()
            .toLowerCase();
    final university = (data['university'] as String?) ?? '';
    final classification = (data['classification'] as String?) ?? 'Outsider';
    final college = (data['college'] as String?) ?? '';
    final yearLevel = (data['yearLevel'] as String?) ?? '';
    final section = (data['section'] as String?) ?? '';

    if (resolvedEmail.isEmpty) {
      if (mounted) {
        AppToast.error(
          context,
          'Cannot approve: this request has no email address.',
        );
      }
      return;
    }

    // Already has an account? Just flip status, don't recreate.
    if (data['accountCreated'] == true) {
      await FirebaseFirestore.instance
          .collection('external_requests')
          .doc(docId)
          .update({'status': 'approved'});
      if (mounted) {
        AppToast.success(context, 'Request approved.');
      }
      return;
    }

    // Safety net: block creating a duplicate account if this email already
    // belongs to a real account of any role. The guest-side signup form
    // already checks this before a request can even be submitted, but this
    // covers a request that predates that check, or one where the email's
    // account situation changed between submission and approval. Checked
    // against both the lowercased and as-typed email since account
    // creation elsewhere in this app never normalizes case.
    final asTypedEmail = (data['email'] as String? ?? email).trim();
    for (final variant in {resolvedEmail, asTypedEmail}) {
      final existingUserSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: variant)
          .limit(1)
          .get();
      if (existingUserSnap.docs.isNotEmpty) {
        final role = (existingUserSnap.docs.first.data()['role'] ?? '')
            .toString();
        if (mounted) {
          AppToast.error(
            context,
            'Cannot approve: $resolvedEmail already belongs to '
            '${role.isEmpty ? 'an existing' : 'a $role'} account.',
          );
        }
        return;
      }
    }

    final password = _generateGuestPassword();

    // Secondary Firebase app so we don't sign the admin out
    FirebaseApp secondaryApp;
    try {
      secondaryApp = Firebase.app('secondaryApp');
    } catch (_) {
      secondaryApp = await Firebase.initializeApp(
        name: 'secondaryApp',
        options: Firebase.app().options,
      );
    }
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    UserCredential cred;
    try {
      cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: resolvedEmail,
        password: password,
      );
    } catch (e) {
      await secondaryAuth.signOut();
      String msg = 'Account creation failed: $e';
      if (e.toString().contains('email-already-in-use')) {
        msg = 'Email already registered: $resolvedEmail';
      }
      if (mounted) {
        AppToast.error(context, msg);
      }
      return;
    }

    await cred.user?.updateDisplayName(userName);
    final uid = cred.user!.uid;

    final batch = FirebaseFirestore.instance.batch();

    // Update the external_requests doc itself
    batch.update(
      FirebaseFirestore.instance.collection('external_requests').doc(docId),
      {
        'status': 'approved',
        'uid': uid,
        'tempPassword': password,
        'mustChangePassword': true,
        'accountCreated': true,
        'approvedAt': FieldValue.serverTimestamp(),
      },
    );

    // Mirror into a `guests` collection for easy lookups elsewhere
    batch.set(FirebaseFirestore.instance.collection('guests').doc(uid), {
      'requestId': docId,
      'fullName': userName,
      'university': university,
      'email': resolvedEmail,
      'tempPassword': password,
      'mustChangePassword': true,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'uid': uid,
    });

    // `users` doc so auth_service.needsPasswordChange() can read the flag
    batch.set(FirebaseFirestore.instance.collection('users').doc(uid), {
      'uid': uid,
      'email': resolvedEmail,
      'fullName': userName,
      'role': 'guest',
      'mustChangePassword': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    await secondaryAuth.signOut();

    // Send credentials (falls back to a queued email doc on failure) —
    // classification decides which EmailJS template/params get used, so a
    // BulSUan guest never receives the Outsider-shaped email and vice versa.
    final (sent, sendError) = await _sendGuestCredentialsEmail(
      resolvedEmail,
      userName,
      password,
      classification: classification,
      university: university,
      college: college,
      yearLevel: yearLevel,
      section: section,
    );
    if (!sent) {
      await _queueGuestCredentialEmail(
        resolvedEmail,
        userName,
        password,
        classification: classification,
        university: university,
        college: college,
        yearLevel: yearLevel,
        section: section,
        lastError: sendError,
      );
    }

    await activity_log.ActivityLogger.log(
      action:
          'APPROVED external request for $userName ($resolvedEmail) — guest account created',
      module: 'External Account',
      severity: sent ? 'info' : 'warning',
      details: {
        'requestId': docId,
        'uid': uid,
        'emailSent': sent,
        if (!sent) 'emailError': sendError ?? 'unknown',
      },
    );

    if (mounted) {
      if (sent) {
        AppToast.success(
          context,
          'Approved. Credentials sent to $resolvedEmail.',
        );
      } else {
        // Surface the actual EmailJS failure instead of a generic "queued"
        // message — the Cloud Function that drains email_queue depends on
        // its own Gmail relay credentials being configured, so a queued
        // item isn't a guaranteed eventual delivery. Admin needs to know
        // *why* it failed to know whether to check the EmailJS dashboard
        // (service/template/quota) or the Cloud Functions Gmail relay.
        AppToast.warning(
          context,
          'Approved, but the credential email failed to send to $resolvedEmail '
          '(${sendError ?? 'unknown error'}). It has been queued for retry — '
          'check the EmailJS service for this guest type if it keeps failing.',
        );
      }
    }
  }

  // ── Credential helpers (mirrors student_accounts.dart) ─────────────

  String _generateGuestPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return 'GST-${List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join()}';
  }

  // Two separate EmailJS *services* under the same account (same public/
  // private key pair) — not just two templates on one service. BulSUan
  // guests use @ms.bulsu.edu.ph addresses, and this app's earlier
  // deliverability investigation found that mail to that M365 tenant only
  // reliably lands when sent intra-tenant; the BulSUan service is connected
  // to a real bulsu.edu.ph sender for exactly that reason, while Outsider
  // guests (arbitrary external domains) keep using the original, already-
  // working service unchanged.
  static const String _guestEmailUserId = 'h6tBNFtWohoZr_B18';
  static const String _guestEmailPrivateKey = 'VTu-IcY7Q3djUcvapaFWq';

  static const String _outsiderEmailServiceId = 'service_vdfi3uo';
  static const String _outsiderCredentialsTemplateId = 'template_kqryg75';

  static const String _bulsuanEmailServiceId = 'service_oabn19f';
  static const String _bulsuanCredentialsTemplateId = 'template_okaw519';

  Future<(bool, String?)> _sendGuestCredentialsEmail(
    String email,
    String fullName,
    String password, {
    String classification = 'Outsider',
    String university = '',
    String college = '',
    String yearLevel = '',
    String section = '',
  }) async {
    final isBulSUan = classification == 'BulSUan';
    final serviceId = isBulSUan
        ? _bulsuanEmailServiceId
        : _outsiderEmailServiceId;
    final templateId = isBulSUan
        ? _bulsuanCredentialsTemplateId
        : _outsiderCredentialsTemplateId;
    final templateParams = isBulSUan
        ? {
            'to_email': email,
            'guest_name': fullName,
            'college': college,
            'year_level': yearLevel,
            'section': section,
            'password': password,
          }
        : {
            'to_email': email,
            'guest_name': fullName,
            'university': university,
            'password': password,
          };

    const int maxAttempts = 3;
    String? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
          headers: {
            'Content-Type': 'application/json',
            'origin': 'http://localhost',
          },
          body: jsonEncode({
            'service_id': serviceId,
            'template_id': templateId,
            'user_id': _guestEmailUserId,
            'accessToken': _guestEmailPrivateKey,
            'template_params': templateParams,
          }),
        );
        if (response.statusCode == 200) {
          debugPrint(
            '✅ Guest ($classification) credentials email sent to $email (attempt $attempt)',
          );
          return (true, null);
        }
        lastError = 'EmailJS ${response.statusCode}: ${response.body}';
        debugPrint('❌ $lastError (attempt $attempt)');
      } catch (e) {
        lastError = e.toString();
        debugPrint(
          '❌ Failed to send guest credentials to $email (attempt $attempt): $e',
        );
      }
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    return (false, lastError);
  }

  Future<void> _queueGuestCredentialEmail(
    String email,
    String fullName,
    String password, {
    String classification = 'Outsider',
    String university = '',
    String college = '',
    String yearLevel = '',
    String section = '',
    String? lastError,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('email_queue').add({
        'to_email': email,
        'guest_name': fullName,
        'university': university,
        'college': college,
        'year_level': yearLevel,
        'section': section,
        'password': password,
        'type': 'guest_credentials',
        'classification': classification,
        'attempts': 0,
        // The EmailJS failure that triggered this queue fallback — the
        // Cloud Function processor overwrites this with its own error if
        // the Gmail relay send also fails, but this preserves the reason
        // EmailJS itself rejected it even if the relay later succeeds.
        if (lastError != null) 'emailjsError': lastError,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Queued guest credential email for $email');
    } catch (e) {
      debugPrint('Failed to queue guest credential email for $email: $e');
    }
  }

  // ── Resend credentials (for already-approved guests) ────────────────
  //
  // We can't recover or fabricate the guest's real Firebase Auth password
  // from the client (no Admin SDK here), so a brand-new random string can't
  // be emailed as a working password when none is on file. Instead, fall
  // back to Firebase's own secure password-reset email — same mechanism
  // already used by admin/org "Forgot password?".
  Future<void> _confirmResendCredentials(ExternalRequest req) async {
    if (req.tempPassword == null || req.tempPassword!.isEmpty) {
      await _sendPasswordResetFallback(req);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      color: AdminColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Resend Credentials',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Send login credentials to:',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E6EA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.email,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    Text(
                      'Guest: ${req.userName}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send_rounded, size: 15),
                    label: Text(
                      'Send',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
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

    if (confirmed == true) {
      final (sent, sendError) = await _sendGuestCredentialsEmail(
        req.email,
        req.userName,
        req.tempPassword!,
        classification: req.classification,
        university: req.university,
        college: req.college,
        yearLevel: req.yearLevel,
        section: req.section,
      );
      if (!sent) {
        await _queueGuestCredentialEmail(
          req.email,
          req.userName,
          req.tempPassword!,
          classification: req.classification,
          university: req.university,
          college: req.college,
          yearLevel: req.yearLevel,
          section: req.section,
          lastError: sendError,
        );
      }
      await activity_log.ActivityLogger.log(
        action: 'Resent credentials for guest: ${req.userName} (${req.email})',
        module: 'External Account',
        severity: sent ? 'info' : 'warning',
        details: sent ? null : {'emailError': sendError ?? 'unknown'},
      );
      if (mounted) {
        if (sent) {
          AppToast.success(context, 'Credentials resent to ${req.email}.');
        } else {
          AppToast.warning(
            context,
            'Sending failed for ${req.email} (${sendError ?? 'unknown error'}). Queued for retry.',
          );
        }
      }
    }
  }

  Future<void> _sendPasswordResetFallback(ExternalRequest req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Send Password Reset Link',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'No temporary password is on file for ${req.userName}, so we can\'t '
          'resend the original credentials. Send a Firebase password-reset '
          'link to ${req.email} instead?',
          style: GoogleFonts.beVietnamPro(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.beVietnamPro(color: const Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.primaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Send Link',
              style: GoogleFonts.beVietnamPro(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: req.email);
      await activity_log.ActivityLogger.log(
        action:
            'Sent password reset link to guest: ${req.userName} (${req.email})',
        module: 'External Account',
        severity: 'info',
        details: {'requestId': req.id},
      );
      if (mounted) {
        AppToast.success(context, 'Password reset link sent to ${req.email}.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Failed to send reset link: $e');
      }
    }
  }

  // ── View stored credentials dialog ──────────────────────────────────
  // ── View Dialog ────────────────────────────────────────────────────
  void _showDetails(ExternalRequest req) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 500,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFAF5),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AdminColors.primaryDark,
                      AdminColors.primaryDark.withAlpha(225),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withAlpha(70)),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.userName.isNotEmpty
                                ? req.userName
                                : 'External Request',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            req.email,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status + date strip
                      Row(
                        children: [
                          _statusBadge(req.status),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: AdminColors.primaryDark.withAlpha(150),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy – hh:mm a',
                            ).format(req.requestDate),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel(
                        'Account Information',
                        icon: Icons.info_outline_rounded,
                      ),
                      _infoGrid([
                        (
                          'Full Name',
                          req.userName.isNotEmpty ? req.userName : '—',
                        ),
                        ('Email', req.email.isNotEmpty ? req.email : '—'),
                        ('Guest Type', req.classification),
                        if (req.isBulSUan) ...[
                          (
                            'College',
                            req.college.isNotEmpty ? req.college : '—',
                          ),
                          (
                            'Year Level',
                            req.yearLevel.isNotEmpty ? req.yearLevel : '—',
                          ),
                          (
                            'Section',
                            req.section.isNotEmpty ? req.section : '—',
                          ),
                        ] else
                          (
                            'Affiliation / Organization',
                            req.affiliation.isNotEmpty
                                ? req.affiliation
                                : (req.university.isNotEmpty
                                      ? req.university
                                      : '—'),
                          ),
                        ('User ID', req.userId.isNotEmpty ? req.userId : '—'),
                        (
                          'Account Status',
                          req.accountCreated
                              ? 'Credentials issued'
                              : (req.status == 'approved'
                                    ? 'Approved — pending account creation'
                                    : 'No account yet'),
                        ),
                      ]),
                      if (req.purpose.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionLabel('Purpose', icon: Icons.notes_rounded),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E6EA)),
                          ),
                          child: Text(
                            req.purpose,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF374151),
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Footer actions
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  children: [
                    if (req.status == 'pending') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _confirmReject(req);
                          },
                          icon: const Icon(Icons.cancel_rounded, size: 15),
                          label: Text(
                            'Reject',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _confirmApprove(req);
                          },
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                          ),
                          label: Text(
                            'Approve & Create Account',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFE2E6EA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: Text(
                            'Close',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoGrid(List<(String, String)> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Wrap(
        spacing: 0,
        runSpacing: 12,
        children: items
            .map(
              (item) => SizedBox(
                width: 210,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$2,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Delete confirm dialog ──────────────────────────────────────────
  // ── Simple confirm/action dialog used by approve/reject/archive/restore ──
  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A202C),
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: const Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.beVietnamPro(color: const Color(0xFF374151)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(
              confirmLabel,
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _confirmApprove(ExternalRequest req) async {
    final ok = await _confirmAction(
      title: 'Approve & Create Account',
      message:
          'Approve "${req.userName}"\'s request? This will create a guest account and email login credentials to ${req.email}.',
      confirmLabel: 'Approve',
      confirmColor: const Color(0xFF059669),
    );
    if (ok)
      await _setStatus(
        req.id,
        'approved',
        userName: req.userName,
        email: req.email,
      );
  }

  Future<void> _confirmBulkApprove() async {
    final selected = _selectedPending.values.toList();
    if (selected.isEmpty) return;

    final ok = await _confirmAction(
      title:
          'Approve ${selected.length} Request${selected.length == 1 ? '' : 's'}',
      message:
          'This creates a guest account and emails login credentials to each selected requester. Continue?',
      confirmLabel: 'Approve All',
      confirmColor: const Color(0xFF059669),
    );
    if (!ok) return;

    var success = 0, failed = 0;
    for (final req in selected) {
      try {
        await _setStatus(
          req.id,
          'approved',
          userName: req.userName,
          email: req.email,
        );
        success++;
      } catch (_) {
        failed++;
      }
    }

    setState(() => _selectedPending.clear());

    if (mounted) {
      final message = failed == 0
          ? '$success request${success == 1 ? '' : 's'} approved.'
          : '$success approved, $failed failed.';
      if (failed == 0) {
        AppToast.success(context, message);
      } else {
        AppToast.warning(context, message);
      }
    }
  }

  Future<void> _confirmReject(ExternalRequest req) async {
    final ok = await _confirmAction(
      title: 'Reject Request',
      message:
          'Reject the request from "${req.userName}"? They will not be granted guest access.',
      confirmLabel: 'Reject',
      confirmColor: const Color(0xFFDC2626),
    );
    if (ok) await _setStatus(req.id, 'rejected', userName: req.userName);
  }

  Future<void> _confirmArchive(ExternalRequest req) async {
    final ok = await _confirmAction(
      title: 'Archive Request',
      message:
          'Archive the request from "${req.userName}"? You can restore it later from the Archived filter.',
      confirmLabel: 'Archive',
      confirmColor: const Color(0xFF6B7280),
    );
    if (!ok) return;
    try {
      await FirebaseFirestore.instance
          .collection('external_requests')
          .doc(req.id)
          .update({
            'isArchived': true,
            'archivedAt': FieldValue.serverTimestamp(),
          });
      await activity_log.ActivityLogger.log(
        action: 'Archived external request for ${req.userName}',
        module: 'External Account',
        severity: 'warning',
        details: {'requestId': req.id},
      );
      if (mounted) {
        AppToast.info(context, 'Request archived.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _confirmRestore(ExternalRequest req) async {
    final ok = await _confirmAction(
      title: 'Restore Request',
      message:
          'Restore the request from "${req.userName}" back to the active list?',
      confirmLabel: 'Restore',
      confirmColor: const Color(0xFF059669),
    );
    if (!ok) return;
    try {
      await FirebaseFirestore.instance
          .collection('external_requests')
          .doc(req.id)
          .update({'isArchived': false, 'archivedAt': FieldValue.delete()});
      await activity_log.ActivityLogger.log(
        action: 'Restored external request for ${req.userName}',
        module: 'External Account',
        severity: 'info',
        details: {'requestId': req.id},
      );
      if (mounted) {
        AppToast.success(context, 'Request restored.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets (mirrors student_accounts.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A202C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final wrapped = onTap == null
        ? card
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: card),
          );
    return wrapped;
  }
}

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

class _ExportButton extends StatelessWidget {
  final String statusFilter, searchTerm;
  const _ExportButton({required this.statusFilter, this.searchTerm = ''});

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) => _doExport(context, choice),
    );
  }

  Future<void> _doExport(BuildContext context, String format) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('external_requests')
          .orderBy('requestDate', descending: true)
          .get();
      var docs = snap.docs;
      if (statusFilter != 'All') {
        docs = docs
            .where((d) => d.data()['status'] == statusFilter.toLowerCase())
            .toList();
      }
      if (searchTerm.isNotEmpty) {
        final term = searchTerm.toLowerCase();
        docs = docs.where((d) {
          final data = d.data();
          return (data['userName'] ?? '').toString().toLowerCase().contains(
                term,
              ) ||
              (data['email'] ?? '').toString().toLowerCase().contains(term) ||
              (data['university'] ?? '').toString().toLowerCase().contains(
                term,
              );
        }).toList();
      }

      if (docs.isEmpty) {
        AppToast.warning(context, 'No data to export.');
        return;
      }

      final now = DateTime.now().toString().substring(0, 10);

      if (format == 'excel') {
        final rows = docs.map((doc) {
          final d = doc.data();
          final date =
              (d['requestDate'] as Timestamp?)?.toDate().toString().substring(
                0,
                10,
              ) ??
              '';
          return [
            (d['userName'] ?? '').toString(),
            (d['email'] ?? '').toString(),
            (d['university'] ?? '').toString(),
            (d['purpose'] ?? '').toString(),
            (d['status'] ?? '').toString(),
            date,
          ];
        }).toList();
        final bytes = AdminExportExcel.generateStyledTable(
          title: 'External Requests',
          headers: const [
            'Name',
            'Email',
            'University',
            'Purpose',
            'Status',
            'Request Date',
          ],
          rows: rows,
        );
        final fileName = 'external_requests_$now.xlsx';
        await AdminExportUtil.saveBytes(
          bytes,
          fileName,
          mimeType: xlsxMimeType,
        );
      } else if (format == 'pdf') {
        final rows = docs.map((doc) {
          final d = doc.data();
          final date =
              (d['requestDate'] as Timestamp?)?.toDate().toString().substring(
                0,
                10,
              ) ??
              '';
          return [
            d['userName'] ?? '',
            d['email'] ?? '',
            d['university'] ?? '',
            d['purpose'] ?? '',
            d['status'] ?? '',
            date,
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'External Requests Report',
          headers: const [
            'Name',
            'Email',
            'University',
            'Purpose',
            'Status',
            'Request Date',
          ],
          rows: rows,
        );
        await AdminExportUtil.saveBytes(
          pdfBytes,
          'external_requests_$now.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        throw UnsupportedError('Unsupported export format: $format');
      }
    } catch (e) {
      AppToast.error(context, 'Export failed: $e');
    }
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = onTap == null
        ? const Color(0xFFD1D5DB)
        : (color ?? const Color(0xFF64748B));
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: effectiveColor.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: effectiveColor),
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
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.chevron_left_rounded
          ? 'Previous Page'
          : 'Next Page',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
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
            color: isActive ? AdminColors.primaryDark : Colors.transparent,
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
