// ignore_for_file: unused_field, duplicate_ignore, use_build_context_synchronously, deprecated_member_use
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:csv/csv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import '../../../theme/admin_theme.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../widgets/admin_stat_cards_row.dart';
import '../../../utils/file_validation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors org_management.dart)
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

  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    bool required = false,
  }) {
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                children: const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFFDC2626)),
                  ),
                ],
              ),
            )
          : null,
      labelText: required ? null : label,
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
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.error, width: 1.5),
      ),
    );
  }
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

// Archived badge only (no status badge needed)
Widget _archivedBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      'ARCHIVED',
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF6B7280),
        letterSpacing: 0.8,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class StudentAccounts extends StatefulWidget {
  const StudentAccounts({super.key});

  @override
  _StudentAccountsState createState() => _StudentAccountsState();
}

class _StudentAccountsState extends State<StudentAccounts> {
  String _courseFilter = 'All Courses';
  String _archiveFilter =
      'Active Only'; // 'Active Only', 'Archived Only', 'All'
  int _currentPage = 1;
  final TextEditingController _searchController = TextEditingController();

  // Created once, not constructed inline in build() — the table/stats
  // methods that use these are called on every rebuild (search, filter
  // changes, pagination), so building a fresh .snapshots() there each time
  // was re-subscribing to Firestore from scratch on every keystroke.
  late final Stream<QuerySnapshot> _studentsStream = FirebaseFirestore.instance
      .collection('students')
      .snapshots();
  late final Stream<QuerySnapshot> _studentsOrderedStream = FirebaseFirestore
      .instance
      .collection('students')
      .orderBy('createdAt', descending: true)
      .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const int _pageSize = 10;

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

  // ── Stats row (simplified - only total and archived) ─────────────
  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _studentsStream,
      builder: (context, snapshot) {
        int total = 0, archived = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map;
            total++;
            if (data['archived'] == true) {
              archived++;
            }
          }
        }
        final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
        final cardGap = isMobile ? 8.0 : 14.0;
        final statCards = [
          _StatCard(
            label: 'Total Students',
            value: '$total',
            icon: Icons.school_rounded,
            color: AdminColors.primaryDark,
            onTap: () => setState(() => _archiveFilter = 'All Students'),
          ),
          _StatCard(
            label: 'Active',
            value: '${total - archived}',
            icon: Icons.person_rounded,
            color: const Color(0xFF059669),
            onTap: () => setState(() => _archiveFilter = 'Active Only'),
          ),
          _StatCard(
            label: 'Archived',
            value: '$archived',
            icon: Icons.archive_rounded,
            color: const Color(0xFF6B7280),
            onTap: () => setState(() => _archiveFilter = 'Archived Only'),
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            0,
          ),
          child: StatCardsRow(
            cards: statCards,
            isMobile: isMobile,
            gap: cardGap,
          ),
        );
      },
    );
  }

  // ── Toolbar (removed status filter) ──────────────────────────────
  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final itemGap = isMobile ? 10.0 : 12.0;

    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search student…',
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
                searchField,
                SizedBox(height: itemGap),
                _FilterDropdown(
                  value: _courseFilter,
                  items: const ['All Courses', 'BSIT', 'BSIS', 'BLIS'],
                  hint: 'Filter by Course',
                  icon: Icons.school_outlined,
                  onChanged: (v) => setState(() {
                    _courseFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(height: itemGap),
                _FilterDropdown(
                  value: _archiveFilter,
                  items: const ['Active Only', 'Archived Only', 'All Students'],
                  hint: 'Archive Status',
                  icon: Icons.archive_rounded,
                  onChanged: (v) => setState(() {
                    _archiveFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(height: itemGap),
                _ExportStudentsButton(
                  courseFilter: _courseFilter,
                  searchTerm: _searchController.text.trim(),
                  archiveFilter: _archiveFilter,
                ),
                SizedBox(height: itemGap),
                _ToolbarButton(
                  label: 'Batch Import',
                  icon: Icons.upload_file_rounded,
                  onPressed: _showBatchImportDialog,
                  outlined: true,
                ),
                SizedBox(height: itemGap),
                _ToolbarButton(
                  label: 'Add Student',
                  icon: Icons.person_add_rounded,
                  onPressed: _showManualAddDialog,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: searchField),
                SizedBox(width: itemGap),
                _FilterDropdown(
                  value: _courseFilter,
                  items: const ['All Courses', 'BSIT', 'BSIS', 'BLIS'],
                  hint: 'Filter by Course',
                  icon: Icons.school_outlined,
                  onChanged: (v) => setState(() {
                    _courseFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(width: itemGap),
                _FilterDropdown(
                  value: _archiveFilter,
                  items: const ['Active Only', 'Archived Only', 'All Students'],
                  hint: 'Archive Status',
                  icon: Icons.archive_rounded,
                  onChanged: (v) => setState(() {
                    _archiveFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(width: itemGap),
                _ExportStudentsButton(
                  courseFilter: _courseFilter,
                  searchTerm: _searchController.text.trim(),
                  archiveFilter: _archiveFilter,
                ),
                SizedBox(width: itemGap),
                _ToolbarButton(
                  label: 'Batch Import',
                  icon: Icons.upload_file_rounded,
                  onPressed: _showBatchImportDialog,
                  outlined: true,
                ),
                SizedBox(width: itemGap),
                _ToolbarButton(
                  label: 'Add Student',
                  icon: Icons.person_add_rounded,
                  onPressed: _showManualAddDialog,
                ),
              ],
            ),
    );
  }

  // ── Table (removed status column) ────────────────────────────────
  Widget _buildTable(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);

    return StreamBuilder<QuerySnapshot>(
      stream: _studentsOrderedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;

        // Apply archive filter
        if (_archiveFilter == 'Active Only') {
          docs = docs
              .where((d) => (d.data() as Map)['archived'] != true)
              .toList();
        } else if (_archiveFilter == 'Archived Only') {
          docs = docs
              .where((d) => (d.data() as Map)['archived'] == true)
              .toList();
        }

        // Course filter
        if (_courseFilter != 'All Courses') {
          docs = docs
              .where((d) => (d.data() as Map)['course'] == _courseFilter)
              .toList();
        }
        final _searchTerm = _searchController.text.trim().toLowerCase();
        if (_searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['fullName'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['studentId'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['email'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                );
          }).toList();
        }

        final totalPages = docs.isEmpty ? 1 : (docs.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, docs.length);
        final pageDocs = docs.isEmpty
            ? <QueryDocumentSnapshot>[]
            : docs.sublist(start, end);

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
                child: docs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageDocs.length,
                        itemBuilder: (_, i) {
                          final data =
                              pageDocs[i].data() as Map<String, dynamic>;
                          return _buildStudentRow(
                            docId: pageDocs[i].id,
                            data: data,
                            isLast: i == pageDocs.length - 1,
                          );
                        },
                      ),
              ),
              _buildFooter(docs.length, totalPages, start, end),
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
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _headerCell('STUDENT ID')),
          Expanded(flex: 3, child: _headerCell('FULL NAME')),
          Expanded(flex: 2, child: _headerCell('COURSE')),
          Expanded(flex: 1, child: _headerCell('YEAR')),
          Expanded(flex: 1, child: _headerCell('SECTION')), // NEW
          Expanded(flex: 3, child: _headerCell('EMAIL')),
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

  Widget _buildStudentRow({
    required String docId,
    required Map<String, dynamic> data,
    required bool isLast,
  }) {
    final isArchived = data['archived'] == true;

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _showStudentDetailDialog(docId, data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isArchived ? const Color(0xFFF9FAFB) : null,
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                data['studentId'] ?? '—',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isArchived
                      ? const Color(0xFF9AA5B4)
                      : AdminColors.primaryDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _StudentAvatar(
                    name: data['fullName'] ?? '',
                    isArchived: isArchived,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data['fullName'] ?? '—',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isArchived
                            ? const Color(0xFF9AA5B4)
                            : const Color(0xFF1A202C),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isArchived
                        ? const Color(0xFFF3F4F6)
                        : AdminColors.primaryDark.withAlpha(18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    data['course'] ?? '—',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isArchived
                          ? const Color(0xFF6B7280)
                          : AdminColors.primaryDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                data['yearLevel'] ?? '—',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: isArchived
                      ? const Color(0xFF9AA5B4)
                      : const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // NEW: Section column
            Expanded(
              flex: 1,
              child: Text(
                data['section'] ?? '—',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: isArchived
                      ? const Color(0xFF9AA5B4)
                      : const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                data['email'] ?? '—',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: isArchived
                      ? const Color(0xFF9AA5B4)
                      : const Color(0xFF374151),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isArchived) ...[
                    _ActionIconButton(
                      icon: Icons.email_outlined,
                      tooltip: 'Resend Credentials',
                      color: const Color(0xFF7C3AED),
                      onTap: () => _confirmResendCredentials(
                        docId,
                        data['email'] ?? '',
                        data['studentId'] ?? '',
                        data['tempPassword'],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Archive/Restore button
                  _ActionIconButton(
                    icon: isArchived
                        ? Icons.restore_rounded
                        : Icons.archive_rounded,
                    tooltip: isArchived ? 'Restore Student' : 'Archive Student',
                    color: isArchived
                        ? const Color(0xFF059669)
                        : const Color(0xFF6B7280),
                    onTap: () => _confirmArchiveStudent(
                      docId,
                      data['fullName'] ?? 'this student',
                      isArchived,
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
              Icons.school_rounded,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No students found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters or add a new student.',
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
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total students',
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

  // ── Actions ───────────────────────────────────────────────────────

  void _showStudentDetailDialog(String docId, Map<String, dynamic> data) {
    final isArchived = data['archived'] == true;
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
                            data['fullName'] ?? 'Student Details',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            data['studentId'] ?? '',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
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
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Student ID',
                              data['studentId'] ?? '—',
                              Icons.badge_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _detailItem(
                              'Status',
                              isArchived ? 'ARCHIVED' : 'ACTIVE',
                              Icons.circle_outlined,
                              valueColor: isArchived
                                  ? const Color(0xFF6B7280)
                                  : const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Course',
                              data['course'] ?? '—',
                              Icons.school_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _detailItem(
                              'Year Level',
                              data['yearLevel'] ?? '—',
                              Icons.calendar_today_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _detailItem(
                        'Section',
                        data['section'] ?? '—',
                        Icons.groups_outlined,
                      ),
                      const SizedBox(height: 16),
                      _detailItem(
                        'Email',
                        data['email'] ?? '—',
                        Icons.email_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  children: [
                    if (!isArchived) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmResendCredentials(
                              docId,
                              data['email'] ?? '',
                              data['studentId'] ?? '',
                              data['tempPassword'],
                            );
                          },
                          icon: const Icon(Icons.email_outlined, size: 15),
                          label: Text(
                            'Resend',
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF7C3AED),
                            side: const BorderSide(color: Color(0xFF7C3AED)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmArchiveStudent(
                            docId,
                            data['fullName'] ?? 'this student',
                            isArchived,
                          );
                        },
                        icon: Icon(
                          isArchived
                              ? Icons.restore_rounded
                              : Icons.archive_outlined,
                          size: 15,
                        ),
                        label: Text(
                          isArchived ? 'Restore' : 'Archive',
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isArchived
                              ? const Color(0xFF059669)
                              : const Color(0xFF6B7280),
                          side: BorderSide(
                            color: isArchived
                                ? const Color(0xFF059669)
                                : const Color(0xFF6B7280),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AdminColors.primaryDark.withAlpha(150)),
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
            color: valueColor ?? const Color(0xFF1A202C),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmResendCredentials(
    String docId,
    String email,
    String studentId,
    String? existingPassword,
  ) async {
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
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
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
                      email,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    Text(
                      'ID: $studentId',
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
      await _resendCredentials(docId, email, studentId, existingPassword);
    }
  }

  Future<void> _resendCredentials(
    String docId,
    String email,
    String studentId,
    String? existingPassword,
  ) async {
    final password = existingPassword ?? _generatePassword();
    final sent = await _sendCredentialsEmail(email, studentId, password);
    if (!sent) {
      await _queueCredentialEmail(email, studentId, password);
    }
    await activity_log.ActivityLogger.log(
      action: 'Resent credentials for student: $studentId ($email)',
      module: 'User Directory',
      severity: 'info',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Credentials resent to $email.'
                : 'Credentials queued but sending failed for $email.',
          ),
          backgroundColor: sent
              ? const Color(0xFF059669)
              : const Color(0xFFF97316),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // Archive/Restore Student
  void _confirmArchiveStudent(String docId, String name, bool isArchived) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
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
                      color: isArchived
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isArchived
                          ? Icons.restore_rounded
                          : Icons.archive_rounded,
                      color: isArchived
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    isArchived
                        ? 'Restore Student Account'
                        : 'Archive Student Account',
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
                isArchived
                    ? 'Are you sure you want to restore "$name"? The student will be able to log in again.'
                    : 'Are you sure you want to archive "$name"? The student will no longer be able to log in.',
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
                      await _archiveRestoreStudent(docId, isArchived, name);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isArchived
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
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
                      isArchived ? 'Restore' : 'Archive',
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

  Future<void> _archiveRestoreStudent(
    String docId,
    bool isArchived,
    String name,
  ) async {
    try {
      final newArchivedStatus = !isArchived;

      // students doc ID is the uid, same as the users doc ID — write both
      // in a batch so the login-time archived checks (which read `users`)
      // stay in sync with the admin-facing `students` record.
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('students').doc(docId),
        {'archived': newArchivedStatus},
      );
      batch.update(FirebaseFirestore.instance.collection('users').doc(docId), {
        'archived': newArchivedStatus,
      });
      await batch.commit();

      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(docId)
          .get();
      final email = doc.data()?['email'] ?? '';
      final studentId = doc.data()?['studentId'] ?? 'Unknown';

      await activity_log.ActivityLogger.log(
        action:
            '${isArchived ? 'Restored' : 'Archived'} student: $studentId ($email)',
        module: 'User Directory',
        severity: isArchived ? 'info' : 'warning',
        details: {
          'studentDocId': docId,
          'studentId': studentId,
          'email': email,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Student account ${isArchived ? 'restored' : 'archived'}',
            ),
            backgroundColor: isArchived
                ? const Color(0xFF059669)
                : const Color(0xFF6B7280),
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
            backgroundColor: AdminColors.error,
          ),
        );
      }
    }
  }

  // ── Batch Import Dialog ────────────────────────────────────────────
  void _showBatchImportDialog() {
    XFile? pickedFile;
    String fileName = '';
    bool isUploading = false;
    String? resultMessage;
    bool resultIsError = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            width: 540,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.upload_file_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Batch Import Students',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: isUploading
                            ? null
                            : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(
                          'Select File',
                          icon: Icons.attach_file_rounded,
                        ),
                        MouseRegion(
                          cursor: isUploading
                              ? MouseCursor.defer
                              : SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: isUploading
                                ? null
                                : () async {
                                    final result = await FilePicker.platform
                                        .pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: [
                                            'xlsx',
                                            'xls',
                                            'csv',
                                          ],
                                        );
                                    if (result != null) {
                                      final pickedSize =
                                          result.files.single.size;
                                      if (pickedSize >
                                          FileValidation
                                              .defaultMaxDocumentBytes) {
                                        setDialogState(() {
                                          resultMessage =
                                              'File is too large. Max size is '
                                              '${(FileValidation.defaultMaxDocumentBytes / (1024 * 1024)).toStringAsFixed(0)}MB.';
                                          resultIsError = true;
                                        });
                                        return;
                                      }
                                      setDialogState(() {
                                        if (kIsWeb) {
                                          pickedFile = XFile.fromData(
                                            result.files.single.bytes!,
                                            name: result.files.single.name,
                                          );
                                        } else {
                                          pickedFile = XFile(
                                            result.files.single.path!,
                                          );
                                        }
                                        fileName = result.files.single.name;
                                        resultMessage = null;
                                      });
                                    }
                                  },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: fileName.isEmpty
                                    ? const Color(0xFFF8F9FB)
                                    : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: fileName.isEmpty
                                      ? const Color(0xFFE2E6EA)
                                      : const Color(0xFF059669),
                                  width: fileName.isEmpty ? 1 : 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    fileName.isEmpty
                                        ? Icons.cloud_upload_rounded
                                        : Icons.check_circle_rounded,
                                    size: 36,
                                    color: fileName.isEmpty
                                        ? const Color(0xFF9AA5B4)
                                        : const Color(0xFF059669),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    fileName.isEmpty
                                        ? 'Click to browse or drop your file here'
                                        : fileName,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: fileName.isEmpty
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF059669),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Supported: .xlsx, .xls, .csv · Max size: '
                                    '${(FileValidation.defaultMaxDocumentBytes / (1024 * 1024)).toStringAsFixed(0)}MB',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: const Color(0xFF9AA5B4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFD7FF)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Required columns (in order):\nStudent ID · Full Name · Course · Year Level · Section · Email\n\nEmail must be an Outlook/Microsoft account (outlook.com, hotmail.com, live.com, or msn.com) — other domains will be skipped.',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    color: const Color(0xFF1D4ED8),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isUploading) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              backgroundColor: const Color(0xFFE2E6EA),
                              color: AdminColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Importing students…',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                        if (resultMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: resultIsError
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: resultIsError
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFF6EE7B7),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  resultIsError
                                      ? Icons.error_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: resultIsError
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    resultMessage!,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      color: resultIsError
                                          ? const Color(0xFF991B1B)
                                          : const Color(0xFF065F46),
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
                        onPressed: isUploading
                            ? null
                            : () => Navigator.pop(ctx),
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
                        onPressed: isUploading
                            ? null
                            : () async {
                                if (pickedFile == null) {
                                  setDialogState(() {
                                    resultMessage =
                                        'Please select a file to import.';
                                    resultIsError = true;
                                  });
                                  return;
                                }
                                setDialogState(() {
                                  isUploading = true;
                                  resultMessage = null;
                                });
                                try {
                                  List<Map<String, String>> students;
                                  if (kIsWeb) {
                                    students = await _parseXFile(pickedFile!);
                                  } else {
                                    students = await _parseFile(
                                      File(pickedFile!.path),
                                    );
                                  }
                                  if (students.isEmpty) {
                                    throw Exception(
                                      'No valid data found. Check column order '
                                      'and make sure every email is an '
                                      'Outlook/Microsoft account.',
                                    );
                                  }
                                  int success = 0, failed = 0, failedEmails = 0;
                                  for (final s in students) {
                                    try {
                                      // Credentials email is already sent
                                      // (and queued on failure) inside
                                      // _createStudentAccount — sending it
                                      // again here was emailing every
                                      // imported student twice.
                                      final cred = await _createStudentAccount(
                                        s,
                                      );
                                      if (cred['emailSent'] == 'false') {
                                        failedEmails++;
                                      }
                                      success++;
                                    } catch (_) {
                                      failed++;
                                    }
                                  }
                                  setDialogState(() {
                                    isUploading = false;
                                    resultMessage =
                                        'Import complete: $success created, $failed skipped.${failedEmails > 0 ? ' $failedEmails credential emails failed to send.' : ''}';
                                    resultIsError = failed > 0 && success == 0;
                                  });
                                  if (success > 0) {
                                    Future.delayed(
                                      const Duration(seconds: 2),
                                      () {
                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '$success students imported successfully.',
                                              ),
                                              backgroundColor: const Color(
                                                0xFF059669,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    isUploading = false;
                                    resultMessage = 'Error: $e';
                                    resultIsError = true;
                                  });
                                }
                              },
                        icon: isUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload_rounded, size: 16),
                        label: Text(
                          'Upload & Import',
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
      ),
    );
  }

  // ── Manual Add Dialog (removed status field) ─────────────────────
  void _showManualAddDialog() {
    final formKey = GlobalKey<FormState>();
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final sectionCtrl = TextEditingController(); // NEW
    String course = 'BSIT';
    String yearLevel = '1st Year';
    bool isCreating = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            width: 520,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Add Student Manually',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: isCreating ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel(
                            'Student Information',
                            icon: Icons.badge_outlined,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: idCtrl,
                                  decoration: _DS.inputDecoration(
                                    'Student ID',
                                    hint: 'e.g., 2021-00001',
                                    icon: Icons.badge_outlined,
                                    required: true,
                                  ),
                                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                                  validator: _validateStudentId,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: nameCtrl,
                                  decoration: _DS.inputDecoration(
                                    'Full Name',
                                    hint: 'e.g., Juan dela Cruz',
                                    icon: Icons.person_outline,
                                    required: true,
                                  ),
                                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                                  validator: _validateFullName,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: course,
                                  decoration: _DS.inputDecoration(
                                    'Course',
                                    required: true,
                                  ),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    color: const Color(0xFF1A202C),
                                  ),
                                  items: const ['BSIT', 'BSIS', 'BLIS']
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setDialogState(() => course = v!),
                                  validator: (v) =>
                                      v == null ? 'Required' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: yearLevel,
                                  decoration: _DS.inputDecoration(
                                    'Year Level',
                                    required: true,
                                  ),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    color: const Color(0xFF1A202C),
                                  ),
                                  items:
                                      const [
                                            '1st Year',
                                            '2nd Year',
                                            '3rd Year',
                                            '4th Year',
                                            '5th Year',
                                          ]
                                          .map(
                                            (y) => DropdownMenuItem(
                                              value: y,
                                              child: Text(y),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) =>
                                      setDialogState(() => yearLevel = v!),
                                  validator: (v) =>
                                      v == null ? 'Required' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // NEW: Section field
                          TextFormField(
                            controller: sectionCtrl,
                            decoration: _DS.inputDecoration(
                              'Section',
                              hint: 'e.g., 3H-G1',
                              icon: Icons.groups_outlined,
                              required: true,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            validator: _validateSection,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailCtrl,
                            decoration: _DS.inputDecoration(
                              'Email Address',
                              hint: 'e.g., student@outlook.com',
                              icon: Icons.email_outlined,
                              required: true,
                            ),
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (!v.contains('@') || !v.contains('.')) {
                                return 'Enter a valid email';
                              }
                              if (!_isMicrosoftEmail(v)) {
                                return 'Must be an Outlook/Microsoft email '
                                    '(outlook.com, hotmail.com, live.com, msn.com)';
                              }
                              return null;
                            },
                          ),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFCA5A5),
                                ),
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
                                      errorMsg!,
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
                        onPressed: isCreating ? null : () => Navigator.pop(ctx),
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
                        onPressed: isCreating
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setDialogState(() {
                                  isCreating = true;
                                  errorMsg = null;
                                });
                                try {
                                  await _createStudentAccount({
                                    'studentId': idCtrl.text.trim(),
                                    'fullName': nameCtrl.text.trim(),
                                    'course': course,
                                    'yearLevel': yearLevel,
                                    'section': sectionCtrl.text.trim(), // NEW
                                    'email': emailCtrl.text
                                        .trim()
                                        .toLowerCase(),
                                  });
                                  if (mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Student account created for ${nameCtrl.text.trim()}. Credentials sent.',
                                        ),
                                        backgroundColor: const Color(
                                          0xFF059669,
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    errorMsg = e.toString();
                                    isCreating = false;
                                  });
                                }
                              },
                        icon: isCreating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_rounded, size: 16),
                        label: Text(
                          'Create Account',
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
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return 'STU-${List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join()}';
  }

  Future<Map<String, String>> _createStudentAccount(
    Map<String, String> student,
  ) async {
    final email = student['email']!;
    final studentId = student['studentId']!;
    final fullName = student['fullName']!;
    final password = _generatePassword();

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
        email: email,
        password: password,
      );
    } catch (e) {
      await secondaryAuth.signOut();
      if (e.toString().contains('email-already-in-use')) {
        throw Exception('Email already registered: $email');
      }
      throw Exception('Account creation failed: ${e.toString()}');
    }
    await cred.user?.updateDisplayName(fullName);
    final uid = cred.user!.uid;
    final batch = FirebaseFirestore.instance.batch();
    batch.set(FirebaseFirestore.instance.collection('students').doc(uid), {
      'studentId': studentId,
      'fullName': fullName,
      'course': student['course'],
      'yearLevel': student['yearLevel'],
      'section': student['section'] ?? '', // NEW
      'email': email,
      'tempPassword': password,
      'mustChangePassword': true,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'uid': uid,
    });
    // Create users doc so auth_service.needsPasswordChange() can read the flag
    batch.set(FirebaseFirestore.instance.collection('users').doc(uid), {
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'role': 'student',
      'mustChangePassword': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await secondaryAuth.signOut();

    // Send credentials email
    final sent = await _sendCredentialsEmail(email, studentId, password);
    if (!sent) {
      await _queueCredentialEmail(email, studentId, password);
    }

    await activity_log.ActivityLogger.log(
      action: 'Created student account: $studentId ($email)',
      module: 'User Directory',
      severity: 'info',
    );
    return {
      'email': email,
      'studentId': studentId,
      'password': password,
      'emailSent': sent.toString(),
    };
  }

  Future<bool> _sendCredentialsEmail(
    String email,
    String studentId,
    String password,
  ) async {
    const int maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
          headers: {
            'Content-Type': 'application/json',
            'origin': 'http://localhost',
          },
          body: jsonEncode({
            'service_id': 'service_s3ke8zd',
            'template_id': 'template_76fn2md',
            'user_id': 'tmx47wQJmb1uMNUpr',
            'template_params': {
              'to_email': email,
              'student_id': studentId,
              'password': password,
            },
          }),
        );
        if (response.statusCode == 200) {
          debugPrint('✅ Email sent to $email (attempt $attempt)');
          return true;
        }
        debugPrint(
          '❌ EmailJS ${response.statusCode}: ${response.body} (attempt $attempt)',
        );
      } catch (e) {
        debugPrint('❌ Failed to send email to $email (attempt $attempt): $e');
      }
      if (attempt < maxAttempts)
        await Future.delayed(Duration(seconds: attempt));
    }
    return false;
  }

  Future<void> _queueCredentialEmail(
    String email,
    String studentId,
    String password,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('email_queue').add({
        'to_email': email,
        'student_id': studentId,
        'password': password,
        'attempts': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Queued credential email for $email');
    } catch (e) {
      debugPrint('Failed to queue credential email for $email: $e');
    }
  }

  Future<List<Map<String, String>>> _parseFile(File file) async {
    final List<Map<String, String>> students = [];
    final ext = file.path.split('.').last.toLowerCase();
    if (ext == 'csv') {
      final csvString = await file.readAsString();
      final rows = const CsvToListConverter().convert(csvString);
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length >= 5) {
          final hasSection =
              row.length >= 6; // NEW: section is column 4 when 6 cols present
          students.add({
            'studentId': row[0]?.toString().trim() ?? '',
            'fullName': row[1]?.toString().trim() ?? '',
            'course': _normalizeCourse(row[2]?.toString().trim() ?? ''),
            'yearLevel': row[3]?.toString().trim() ?? '',
            'section': hasSection
                ? (row[4]?.toString().trim() ?? '')
                : '', // NEW
            'email': hasSection
                ? (row[5]?.toString().trim() ?? '')
                : (row[4]?.toString().trim() ?? ''), // NEW
          });
        }
      }
    } else {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        for (int i = 1; i < (sheet?.rows.length ?? 0); i++) {
          final row = sheet!.rows[i];
          if (row.length >= 5) {
            final hasSection = row.length >= 6; // NEW
            students.add({
              'studentId': row[0]?.value?.toString().trim() ?? '',
              'fullName': row[1]?.value?.toString().trim() ?? '',
              'course': _normalizeCourse(
                row[2]?.value?.toString().trim() ?? '',
              ),
              'yearLevel': row[3]?.value?.toString().trim() ?? '',
              'section': hasSection
                  ? (row[4]?.value?.toString().trim() ?? '')
                  : '', // NEW
              'email': hasSection
                  ? (row[5]?.value?.toString().trim() ?? '')
                  : (row[4]?.value?.toString().trim() ?? ''), // NEW
            });
          }
        }
        break;
      }
    }
    students.removeWhere(
      (s) =>
          s['studentId']!.isEmpty ||
          (s['fullName'] ?? '').isEmpty ||
          s['email']!.isEmpty ||
          !_isMicrosoftEmail(s['email']!) ||
          !_studentIdPattern.hasMatch(s['studentId']!) ||
          !_fullNamePattern.hasMatch(s['fullName']!) ||
          ((s['section'] ?? '').isNotEmpty &&
              !_sectionPattern.hasMatch(s['section']!)),
    );
    return students;
  }

  Future<List<Map<String, String>>> _parseXFile(XFile xfile) async {
    final bytes = await xfile.readAsBytes();
    final name = xfile.name.toLowerCase();
    final List<Map<String, String>> students = [];
    if (name.endsWith('.csv')) {
      final csvString = String.fromCharCodes(bytes);
      final rows = const CsvToListConverter().convert(csvString);
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length >= 5) {
          final hasSection = row.length >= 6; // NEW
          students.add({
            'studentId': row[0]?.toString().trim() ?? '',
            'fullName': row[1]?.toString().trim() ?? '',
            'course': _normalizeCourse(row[2]?.toString().trim() ?? ''),
            'yearLevel': row[3]?.toString().trim() ?? '',
            'section': hasSection
                ? (row[4]?.toString().trim() ?? '')
                : '', // NEW
            'email': hasSection
                ? (row[5]?.toString().trim() ?? '')
                : (row[4]?.toString().trim() ?? ''), // NEW
          });
        }
      }
    } else {
      final excel = Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        for (int i = 1; i < (sheet?.rows.length ?? 0); i++) {
          final row = sheet!.rows[i];
          if (row.length >= 5) {
            final hasSection = row.length >= 6; // NEW
            students.add({
              'studentId': row[0]?.value?.toString().trim() ?? '',
              'fullName': row[1]?.value?.toString().trim() ?? '',
              'course': _normalizeCourse(
                row[2]?.value?.toString().trim() ?? '',
              ),
              'yearLevel': row[3]?.value?.toString().trim() ?? '',
              'section': hasSection
                  ? (row[4]?.value?.toString().trim() ?? '')
                  : '', // NEW
              'email': hasSection
                  ? (row[5]?.value?.toString().trim() ?? '')
                  : (row[4]?.value?.toString().trim() ?? ''), // NEW
            });
          }
        }
        break;
      }
    }
    students.removeWhere(
      (s) =>
          s['studentId']!.isEmpty ||
          (s['fullName'] ?? '').isEmpty ||
          s['email']!.isEmpty ||
          !_isMicrosoftEmail(s['email']!) ||
          !_studentIdPattern.hasMatch(s['studentId']!) ||
          !_fullNamePattern.hasMatch(s['fullName']!) ||
          ((s['section'] ?? '').isNotEmpty &&
              !_sectionPattern.hasMatch(s['section']!)),
    );
    return students;
  }

  String _normalizeCourse(String course) {
    final upper = course.toUpperCase();
    if (upper.contains('BSIT')) return 'BSIT';
    if (upper.contains('BSIS')) return 'BSIS';
    if (upper.contains('BLIS')) return 'BLIS';
    return 'BSIT';
  }

  static const _microsoftEmailDomains = {
    'outlook.com',
    'hotmail.com',
    'live.com',
    'msn.com',
  };

  bool _isMicrosoftEmail(String email) {
    final at = email.trim().toLowerCase().lastIndexOf('@');
    if (at == -1) return false;
    return _microsoftEmailDomains.contains(email.substring(at + 1));
  }

  static final RegExp _studentIdPattern = RegExp(r'^[0-9]{2,4}-[0-9]{3,8}$');
  static final RegExp _fullNamePattern = RegExp(
    r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*(?: [A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*)+$",
  );
  static final RegExp _sectionPattern = RegExp(r'^[0-9][A-Za-z0-9-]{1,9}$');

  String? _validateStudentId(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Required';
    if (!_studentIdPattern.hasMatch(value)) {
      return 'Use the format 2021-00001';
    }
    return null;
  }

  String? _validateFullName(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Required';
    if (!_fullNamePattern.hasMatch(value)) {
      return 'Enter a full name (first and last)';
    }
    return null;
  }

  String? _validateSection(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Required';
    if (!_sectionPattern.hasMatch(value)) {
      return 'Use the format 3H-G1';
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
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
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
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
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF374151),
          ),
          items: items
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, style: GoogleFonts.beVietnamPro(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: onChanged,
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
          foregroundColor: AdminColors.primaryDark,
          side: BorderSide(color: AdminColors.primaryDark),
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
        backgroundColor: AdminColors.primaryDark,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}

class _ExportStudentsButton extends StatelessWidget {
  final String courseFilter, searchTerm, archiveFilter;
  const _ExportStudentsButton({
    required this.courseFilter,
    required this.searchTerm,
    required this.archiveFilter,
  });

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) => _doExport(context, choice),
    );
  }

  Future<void> _doExport(BuildContext context, String format) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('students')
          .orderBy('createdAt', descending: true)
          .get();
      var docs = snap.docs;

      // Apply filters same as table
      if (archiveFilter == 'Active Only') {
        docs = docs.where((d) => (d.data())['archived'] != true).toList();
      } else if (archiveFilter == 'Archived Only') {
        docs = docs.where((d) => (d.data())['archived'] == true).toList();
      }

      if (courseFilter != 'All Courses') {
        docs = docs.where((d) => (d.data())['course'] == courseFilter).toList();
      }
      if (searchTerm.isNotEmpty) {
        docs = docs.where((d) {
          final data = d.data();
          return (data['fullName'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              ) ||
              (data['studentId'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              ) ||
              (data['email'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              );
        }).toList();
      }

      if (docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No data to export.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return;
      }

      final now = DateTime.now().toString().substring(0, 10);

      if (format == 'csv') {
        final buf = StringBuffer();
        buf.writeln(
          'Student ID,Full Name,Course,Year Level,Section,Email,Archived',
        ); // NEW: added Section
        for (final doc in docs) {
          final d = doc.data();
          String esc(String s) => '"${s.replaceAll('"', '""')}"';
          buf.writeln(
            [
              esc(d['studentId'] ?? ''),
              esc(d['fullName'] ?? ''),
              esc(d['course'] ?? ''),
              esc(d['yearLevel'] ?? ''),
              esc(d['section'] ?? ''), // NEW
              esc(d['email'] ?? ''),
              esc(d['archived'] == true ? 'Yes' : 'No'),
            ].join(','),
          );
        }
        await AdminExportUtil.saveText(
          buf.toString(),
          'students_$now.csv',
          mimeType: 'text/csv',
        );
      } else if (format == 'pdf') {
        final rows = docs.map((doc) {
          final d = doc.data();
          return [
            d['studentId'] ?? '',
            d['fullName'] ?? '',
            d['course'] ?? '',
            d['yearLevel'] ?? '',
            d['section'] ?? '', // NEW
            d['email'] ?? '',
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'Student Accounts Report',
          headers: const [
            'Student ID',
            'Full Name',
            'Course',
            'Year Level',
            'Section',
            'Email',
          ], // NEW
          rows: rows,
        );
        await AdminExportUtil.saveBytes(
          pdfBytes,
          'students_$now.pdf',
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}

class _StudentAvatar extends StatelessWidget {
  final String name;
  final bool isArchived;
  const _StudentAvatar({required this.name, this.isArchived = false});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isArchived
            ? const Color(0xFFF3F4F6)
            : AdminColors.primaryDark.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isArchived
                ? const Color(0xFF6B7280)
                : AdminColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

// Compact colored chip — matches the icon actions in org_event_proposals.dart
// (_IconChip) / organization_management.dart, instead of a bare unstyled icon.
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
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
