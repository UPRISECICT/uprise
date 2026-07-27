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
import 'student_accounts_import_parser.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/file_validation.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../services/activity_logger.dart' as activity_log;

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
    final labelTextStyle = GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF64748B),
    );
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: labelTextStyle,
                children: [
                  TextSpan(
                    text: ' *',
                    style: labelTextStyle.copyWith(color: UpriseColors.error),
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
      labelStyle: labelTextStyle,
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
        borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1.5),
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
          Icon(icon, size: 16, color: UpriseColors.primaryDark),
          const SizedBox(width: 8),
        ],
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
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class StudentAccounts extends StatefulWidget {
  const StudentAccounts({super.key});

  @override
  StudentAccountsState createState() => StudentAccountsState();
}

class StudentAccountsState extends State<StudentAccounts> {
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
            color: UpriseColors.primaryDark,
          ),
          _StatCard(
            label: 'Active',
            value: '${total - archived}',
            icon: Icons.person_rounded,
            color: const Color(0xFF059669),
          ),
          _StatCard(
            label: 'Archived',
            value: '$archived',
            icon: Icons.archive_rounded,
            color: const Color(0xFF6B7280),
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            0,
          ),
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
                  children: List.generate(
                    statCards.length,
                    (index) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: index < statCards.length - 1 ? cardGap : 0,
                        ),
                        child: statCards[index],
                      ),
                    ),
                  ),
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
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
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
          ? SingleChildScrollView(
              child: Column(
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
              ),
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
        final searchTerm = _searchController.text.trim().toLowerCase();
        if (searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['fullName'] ?? '').toString().toLowerCase().contains(
                  searchTerm,
                ) ||
                (data['studentId'] ?? '').toString().toLowerCase().contains(
                  searchTerm,
                ) ||
                (data['email'] ?? '').toString().toLowerCase().contains(
                  searchTerm,
                ) ||
                (data['schoolYear'] ?? data['yearLevel'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(searchTerm) ||
                (data['section'] ?? '').toString().toLowerCase().contains(
                  searchTerm,
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
          Expanded(flex: 2, child: _headerCell('SCHOOL YEAR')),
          Expanded(flex: 1, child: _headerCell('SECTION')),
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
    final schoolYear = data['schoolYear'] ?? data['yearLevel'] ?? '';
    final section = data['section'] ?? '';

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
                      : UpriseColors.primaryDark,
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
                        : UpriseColors.primaryDark.withAlpha(18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    data['course'] ?? '—',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isArchived
                          ? const Color(0xFF6B7280)
                          : UpriseColors.primaryDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                schoolYear.isEmpty ? '—' : schoolYear,
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
              flex: 1,
              child: Text(
                section.isEmpty ? '—' : section,
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
                      UpriseColors.primaryDark,
                      UpriseColors.primaryDark.withAlpha(225),
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _detailItem(
                              'School Year',
                              data['schoolYear'] ?? data['yearLevel'] ?? '—',
                              Icons.calendar_today_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Section',
                              data['section'] ?? '—',
                              Icons.groups_outlined,
                            ),
                          ),
                        ],
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
            Icon(
              icon,
              size: 12,
              color: UpriseColors.primaryDark.withAlpha(150),
            ),
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
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFFEA580C),
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
                      backgroundColor: const Color(0xFFEA580C),
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
            backgroundColor: UpriseColors.error,
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
    Map<String, String>? previewHeaderMapping;
    List<Map<String, String>>? previewSampleRows;
    int importDone = 0;
    int importTotal = 0;

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
                    color: UpriseColors.primaryDark,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _sectionLabel(
                            'Select File',
                            icon: Icons.attach_file_rounded,
                          ),
                          TextButton.icon(
                            onPressed: isUploading
                                ? null
                                : _downloadImportTemplate,
                            icon: const Icon(
                              Icons.download_rounded,
                              size: 16,
                            ),
                            label: Text(
                              'Download Template',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: UpriseColors.primaryDark,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: isUploading
                            ? null
                            : () async {
                                final result = await FilePicker.platform
                                    .pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['xlsx', 'xls', 'csv'],
                                    );
                                if (result != null) {
                                  final pickedSize = result.files.single.size;
                                  if (pickedSize >
                                      FileValidation.defaultMaxDocumentBytes) {
                                    setDialogState(() {
                                      resultMessage =
                                          'File is too large. Max size is '
                                          '${(FileValidation.defaultMaxDocumentBytes / (1024 * 1024)).toStringAsFixed(0)}MB.';
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
                                    previewHeaderMapping = null;
                                    previewSampleRows = null;
                                  });

                                  if (pickedFile != null) {
                                    try {
                                      final preview = kIsWeb
                                          ? await _previewXFileImport(
                                              pickedFile!,
                                            )
                                          : await _previewFileImport(
                                              File(pickedFile!.path),
                                            );
                                      setDialogState(() {
                                        previewHeaderMapping = preview.mapping;
                                        previewSampleRows = preview.sampleRows;
                                      });
                                    } catch (e) {
                                      setDialogState(() {
                                        resultMessage =
                                            'Unable to preview file headers: $e';
                                        resultIsError = true;
                                      });
                                    }
                                  }
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
                                'Supported: .xlsx, .xls, .csv',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            ],
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
                                'Expected headers or column order:\nStudent ID · Full Name · Course · School Year · Section · Email',
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
                            value: importTotal > 0
                                ? importDone / importTotal
                                : null,
                            backgroundColor: const Color(0xFFE2E6EA),
                            color: UpriseColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          importTotal > 0
                              ? 'Importing $importDone of $importTotal…'
                              : 'Importing students…',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                      if (previewHeaderMapping != null) ...[
                        const SizedBox(height: 18),
                        _sectionLabel(
                          'Header Preview',
                          icon: Icons.view_column_outlined,
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Detected column mapping',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Column(
                                children: previewHeaderMapping!.entries.map((
                                  entry,
                                ) {
                                  final isMissing = entry.value.isEmpty;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            entry.key,
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 12,
                                              color: const Color(0xFF374151),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 6,
                                          child: Text(
                                            isMissing
                                                ? 'Missing column'
                                                : entry.value,
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 12,
                                              color: isMissing
                                                  ? const Color(0xFFB91C1C)
                                                  : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                              if (previewHeaderMapping!.values.any(
                                (header) => header.isEmpty,
                              )) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Some expected fields are missing. Please update your spreadsheet headers before importing.',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    color: const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (previewSampleRows != null &&
                          previewSampleRows!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionLabel(
                          'Sample row preview',
                          icon: Icons.visibility_outlined,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: previewSampleRows!
                              .map(
                                (row) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFFFF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: row.entries.map((entry) {
                                        return Text(
                                          '${entry.key}: ${entry.value.isEmpty ? '<empty>' : entry.value}',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11.5,
                                            color: const Color(0xFF475569),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                    color: Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: isUploading
                            ? null
                            : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: isUploading || pickedFile == null
                            ? null
                            : () async {
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
                                      'No valid data found. Check column order.',
                                    );
                                  }
                                  final validationMessage =
                                      await _validateImportedStudents(students);
                                  setDialogState(() {
                                    resultMessage = validationMessage;
                                    resultIsError = false;
                                  });

                                  int success = 0, failed = 0, failedEmails = 0;
                                  setDialogState(() {
                                    importTotal = students.length;
                                    importDone = 0;
                                  });
                                  for (final s in students) {
                                    try {
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
                                    setDialogState(() => importDone++);
                                  }
                                  setDialogState(() {
                                    isUploading = false;
                                    resultMessage =
                                        '$validationMessage\n\nImport complete: $success created, $failed skipped.${failedEmails > 0 ? ' $failedEmails credential emails failed to send.' : ''}';
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
      ),
    );
  }

  // ── Manual Add Dialog (removed status field) ─────────────────────
  void _showManualAddDialog() {
    final formKey = GlobalKey<FormState>();
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final sectionCtrl = TextEditingController();
    String course = 'BSIT';
    final schoolYearOptions = _generateSchoolYearOptions();
    String schoolYear = schoolYearOptions[schoolYearOptions.length - 2];
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
                    color: UpriseColors.primaryDark,
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
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
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
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AnchoredDropdownField<String>(
                                  value: course,
                                  decoration: _DS.inputDecoration(
                                    'Course',
                                    required: true,
                                  ),
                                  validator: (v) =>
                                      v == null ? 'Required' : null,
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnchoredDropdownField<String>(
                                  value: schoolYear,
                                  decoration: _DS.inputDecoration(
                                    'School Year',
                                    icon: Icons.calendar_today_outlined,
                                    required: true,
                                  ),
                                  validator: (v) =>
                                      v == null ? 'Required' : null,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    color: const Color(0xFF1A202C),
                                  ),
                                  items: schoolYearOptions
                                      .map(
                                        (y) => DropdownMenuItem(
                                          value: y,
                                          child: Text(y),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setDialogState(() => schoolYear = v!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: sectionCtrl,
                                  decoration: _DS.inputDecoration(
                                    'Section',
                                    hint: 'e.g., 3H-G1',
                                    icon: Icons.groups_outlined,
                                    required: true,
                                  ),
                                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailCtrl,
                            decoration: _DS.inputDecoration(
                              'Email Address',
                              hint: 'e.g., student@university.edu.ph',
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
                                    'schoolYear': schoolYear,
                                    'yearLevel': schoolYear,
                                    'section': sectionCtrl.text.trim(),
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
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<void> _downloadImportTemplate() async {
    final excel = Excel.createExcel();
    final defaultSheetName = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheetName, 'Students');
    final sheet = excel['Students'];
    sheet.appendRow([
      TextCellValue('Student ID'),
      TextCellValue('Full Name'),
      TextCellValue('Course'),
      TextCellValue('School Year'),
      TextCellValue('Section'),
      TextCellValue('Email'),
    ]);
    sheet.appendRow([
      TextCellValue('2021-00001'),
      TextCellValue('Juan Dela Cruz'),
      TextCellValue('BSIT'),
      TextCellValue(_generateSchoolYearOptions()[3]),
      TextCellValue('3H-G1'),
      TextCellValue('juan.delacruz@example.com'),
    ]);
    final bytes = excel.encode();
    if (bytes == null) return;
    await AdminExportUtil.saveBytes(
      bytes,
      'student_import_template.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // Academic year runs Aug–Jul (see reports_management.dart's semester
  // logic), so before August the "current" school year is still the one
  // that started last calendar year. Offers a few years back and one ahead
  // so admins can still add records for recently graduated/incoming batches.
  List<String> _generateSchoolYearOptions() {
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    return [
      for (var i = -3; i <= 1; i++) '${startYear + i}-${startYear + i + 1}',
    ];
  }

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return 'STU-${List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join()}';
  }

  Future<String> _validateImportedStudents(
    List<Map<String, String>> students,
  ) async {
    if (students.isEmpty) {
      return 'No data to validate.';
    }

    // Sample preview is already shown in the dialog, no need to use this variable
// Keeping it as an underscore to avoid unused warning
final _ = students.take(8).map((row) {
  return {
    'Student ID': row['studentId'] ?? '',
    'Full Name': row['fullName'] ?? '',
    'Course': row['course'] ?? '',
    'College': row['college'] ?? '',
    'Program': row['program'] ?? '',
    'School Year': row['schoolYear'] ?? '',
    'Semester': row['semester'] ?? '',
    'Section': row['section'] ?? '',
    'Email': row['email'] ?? '',
  };
}).toList();

    return _localImportValidationSummary(students);
  }

  String _localImportValidationSummary(List<Map<String, String>> students) {
    final invalidEmails = <String>[];
    final missingStudentIds = <int>[];
    final missingEmails = <int>[];
    final missingRequired = <int>[];

    for (var i = 0; i < students.length; i++) {
      final row = students[i];
      final email = row['email'] ?? '';
      final studentId = row['studentId'] ?? '';
      final fullName = row['fullName'] ?? '';
      final sem = row['semester'] ?? '';
      final course = row['course'] ?? '';

      if (studentId.isEmpty) missingStudentIds.add(i + 1);
      if (email.isEmpty) missingEmails.add(i + 1);
      if (fullName.isEmpty || course.isEmpty || sem.isEmpty) {
        missingRequired.add(i + 1);
      }
      if (email.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+\$').hasMatch(email)) {
        invalidEmails.add(email);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('Local validation summary:');
    buffer.writeln('- Rows parsed: ${students.length}.');
    if (missingStudentIds.isNotEmpty) {
      buffer.writeln(
        '- Missing Student ID in rows: ${missingStudentIds.join(', ')}.',
      );
    }
    if (missingEmails.isNotEmpty) {
      buffer.writeln('- Missing Email in rows: ${missingEmails.join(', ')}.');
    }
    if (invalidEmails.isNotEmpty) {
      buffer.writeln('- Invalid email format: ${invalidEmails.join(', ')}.');
    }
    if (missingRequired.isNotEmpty) {
      buffer.writeln(
        '- Rows missing required fields (course/full name): ${missingRequired.join(', ')}.',
      );
    }
    if (missingStudentIds.isEmpty &&
        missingEmails.isEmpty &&
        invalidEmails.isEmpty &&
        missingRequired.isEmpty) {
      buffer.writeln('- Sample data looks well-formed for import.');
    }
    buffer.writeln(
      '- Expected fields matched: Student ID, Full Name, Course, School Year, Section, Email.',
    );
    buffer.writeln(
      'If any rows look wrong, please correct the spreadsheet before importing.',
    );
    return buffer.toString();
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
      'college': student['college'] ?? '',
      'program': student['program'] ?? '',
      'schoolYear': student['schoolYear'] ?? student['yearLevel'] ?? '',
      'yearLevel': student['yearLevel'] ?? student['schoolYear'] ?? '',
      'semester': student['semester'] ?? '1st Semester',
      'section': student['section'] ?? '',
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
      'college': student['college'] ?? '',
      'program': student['program'] ?? '',
      'schoolYear': student['schoolYear'] ?? student['yearLevel'] ?? '',
      'semester': student['semester'] ?? '1st Semester',
      'section': student['section'] ?? '',
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
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt));
      }
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
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final List<List<dynamic>> rows = [];
      
      if (ext == 'csv') {
        final csvString = await file.readAsString();
        if (csvString.isEmpty) {
          throw Exception('CSV file is empty');
        }
        rows.addAll(const CsvToListConverter().convert(csvString));
      } else {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('Excel file is empty');
        }
        final excel = Excel.decodeBytes(bytes);
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet != null && sheet.rows.isNotEmpty) {
            rows.addAll(sheet.rows.map((row) => row.map((cell) => cell?.value).toList()));
          }
          break;
        }
      }

      if (rows.isEmpty) {
        throw Exception('No data found in the file');
      }

      final parsed = StudentImportParser.parseRows(rows, hasHeaderRow: true);
      final normalized = _normalizeImportedStudents(parsed);
      
      if (normalized.isEmpty) {
        throw Exception('No valid student data found. Please check the column headers.');
      }
      
      return normalized;
    } catch (e) {
      debugPrint('Parse file error: $e');
      throw Exception('Failed to parse file: $e');
    }
  }

  Future<List<Map<String, String>>> _parseXFile(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('File is empty');
      }
      
      final name = xfile.name.toLowerCase();
      final List<List<dynamic>> rows = [];
      
      if (name.endsWith('.csv')) {
        final csvString = String.fromCharCodes(bytes);
        if (csvString.isEmpty) {
          throw Exception('CSV file is empty');
        }
        rows.addAll(const CsvToListConverter().convert(csvString));
      } else {
        final excel = Excel.decodeBytes(bytes);
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet != null && sheet.rows.isNotEmpty) {
            rows.addAll(sheet.rows.map((row) => row.map((cell) => cell?.value).toList()));
          }
          break;
        }
      }

      if (rows.isEmpty) {
        throw Exception('No data found in the file');
      }

      final parsed = StudentImportParser.parseRows(rows, hasHeaderRow: true);
      final normalized = _normalizeImportedStudents(parsed);
      
      if (normalized.isEmpty) {
        throw Exception('No valid student data found. Please check the column headers.');
      }
      
      return normalized;
    } catch (e) {
      debugPrint('Parse XFile error: $e');
      throw Exception('Failed to parse file: $e');
    }
  }

  List<Map<String, String>> _normalizeImportedStudents(
    List<Map<String, String>> students,
  ) {
    final normalized = <Map<String, String>>[];
    
    for (final student in students) {
      final studentId = (student['studentId'] ?? '').trim();
      final fullName = (student['fullName'] ?? '').trim();
      final email = (student['email'] ?? '').trim().toLowerCase();
      final course = _normalizeCourse(student['course'] ?? '');
      final schoolYear = (student['schoolYear'] ?? student['yearLevel'] ?? '').trim();
      final section = (student['section'] ?? '').trim();
      
      // Skip rows missing required fields
      if (studentId.isEmpty || email.isEmpty || fullName.isEmpty) {
        continue;
      }
      
      normalized.add({
        'studentId': studentId,
        'fullName': fullName,
        'course': course,
        'college': student['college']?.trim() ?? '',
        'program': student['program']?.trim() ?? '',
        'schoolYear': schoolYear,
        'yearLevel': schoolYear,
        'semester': _normalizeSemester(student['semester'] ?? ''),
        'section': section,
        'email': email,
      });
    }
    
    return normalized;
  }

  Future<_ImportPreview> _previewFileImport(File file) async {
  try {
    final ext = file.path.split('.').last.toLowerCase();
    final List<List<dynamic>> rows = [];
    if (ext == 'csv') {
      final csvString = await file.readAsString();
      if (csvString.isEmpty) {
        throw Exception('CSV file is empty');
      }
      rows.addAll(const CsvToListConverter().convert(csvString));
    } else {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Excel file is empty');
      }
      final excel = Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet != null && sheet.rows.isNotEmpty) {
          rows.addAll(sheet.rows.map((row) => row.map((cell) => cell?.value).toList()));
        }
        break;
      }
    }
    return _buildImportPreview(rows);
  } catch (e) {
    debugPrint('Preview file error: $e');
    throw Exception('Failed to preview file: $e');
  }
}

Future<_ImportPreview> _previewXFileImport(XFile xfile) async {
  try {
    final bytes = await xfile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('File is empty');
    }
    
    final name = xfile.name.toLowerCase();
    final List<List<dynamic>> rows = [];
    
    if (name.endsWith('.csv')) {
      final csvString = String.fromCharCodes(bytes);
      if (csvString.isEmpty) {
        throw Exception('CSV file is empty');
      }
      rows.addAll(const CsvToListConverter().convert(csvString));
    } else {
      final excel = Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet != null && sheet.rows.isNotEmpty) {
          rows.addAll(sheet.rows.map((row) => row.map((cell) => cell?.value).toList()));
        }
        break;
      }
    }
    return _buildImportPreview(rows);
  } catch (e) {
    debugPrint('Preview XFile error: $e');
    throw Exception('Failed to preview file: $e');
  }
}

_ImportPreview _buildImportPreview(List<List<dynamic>> rows) {
  if (rows.isEmpty) {
    return _ImportPreview(headers: [], mapping: {}, sampleRows: []);
  }

  final headerValues = rows.first
      .map((cell) => cell?.toString().trim() ?? '')
      .toList();
  final mapping = StudentImportParser.inferHeaderMapping(headerValues);
  final sampleRows = rows
      .skip(1)
      .where(
        (row) => (row.any((cell) => (cell?.toString().trim() ?? '').isNotEmpty)),
      )
      .take(3)
      .map((row) {
        final parsed = StudentImportParser.parseRows([
          rows.first,
          row,
        ], hasHeaderRow: true);
        if (parsed.isEmpty) {
          return <String, String>{};
        }
        return {
          'Student ID': parsed.first['studentId'] ?? '',
          'Full Name': parsed.first['fullName'] ?? '',
          'Course': parsed.first['course'] ?? '',
          'College': parsed.first['college'] ?? '',
          'Program': parsed.first['program'] ?? '',
          'School Year': parsed.first['schoolYear'] ?? '',
          'Semester': parsed.first['semester'] ?? '',
          'Section': parsed.first['section'] ?? '',
          'Email': parsed.first['email'] ?? '',
        };
      })
      .toList();

  return _ImportPreview(
    headers: headerValues,
    mapping: mapping,
    sampleRows: sampleRows,
  );
}
  String _normalizeCourse(String course) {
    final upper = course.toUpperCase();
    if (upper.contains('BSIT')) return 'BSIT';
    if (upper.contains('BSIS')) return 'BSIS';
    if (upper.contains('BLIS')) return 'BLIS';
    return 'BSIT';
  }

  String _normalizeSemester(String semester) {
    final upper = semester.toUpperCase();
    if (upper.contains('SUMMER')) return 'Summer';
    if (upper.contains('2ND') || upper.contains('SECOND')) {
      return '2nd Semester';
    }
    return '1st Semester';
  }
}

class _ImportPreview {
  final List<String> headers;
  final Map<String, String> mapping;
  final List<Map<String, String>> sampleRows;

  _ImportPreview({
    required this.headers,
    required this.mapping,
    required this.sampleRows,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      constraints: const BoxConstraints(minWidth: 120),
      child: AnchoredMenuTrigger<String>(
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
          'Student ID,Full Name,Course,School Year,Section,Email,Archived',
        );
        for (final doc in docs) {
          final d = doc.data();
          String esc(String s) => '"${s.replaceAll('"', '""')}"';
          buf.writeln(
            [
              esc(d['studentId'] ?? ''),
              esc(d['fullName'] ?? ''),
              esc(d['course'] ?? ''),
              esc(d['schoolYear'] ?? d['yearLevel'] ?? ''),
              esc(d['section'] ?? ''),
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
            d['schoolYear'] ?? d['yearLevel'] ?? '',
            d['section'] ?? '',
            d['email'] ?? '',
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'Student Accounts Report',
          headers: const [
            'Student ID',
            'Full Name',
            'Course',
            'School Year',
            'Section',
            'Email',
          ],
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
          backgroundColor: UpriseColors.error,
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
            : UpriseColors.primaryDark.withOpacity(0.1),
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
                : UpriseColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

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
    return GestureDetector(
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
}

class StudentImportParser {
  static List<Map<String, String>> parseRows(
    List<List<dynamic>> rows, {
    bool hasHeaderRow = true,
  }) {
    if (rows.isEmpty) return const [];

    final List<List<String>> normalizedRows = [];
    for (final rawRow in rows) {
      normalizedRows.add(
        rawRow.map((cell) => cell?.toString().trim() ?? '').toList(),
      );
    }

    final dataRows = hasHeaderRow
        ? normalizedRows.skip(1).toList()
        : normalizedRows;
    final headers = hasHeaderRow ? normalizedRows.first : null;

    final students = <Map<String, String>>[];
    for (final row in dataRows) {
      if (row.every((cell) => cell.isEmpty)) continue;

      final record = _parseRecord(row, headers: headers);
      if (record['studentId']!.isNotEmpty || record['email']!.isNotEmpty) {
        students.add(record);
      }
    }

    students.removeWhere((s) => s['studentId']!.isEmpty || s['email']!.isEmpty);
    return students;
  }

  static Map<String, String> _parseRecord(
    List<String> row, {
    List<String>? headers,
  }) {
    // If the row is empty, return empty record
    if (row.isEmpty || row.every((cell) => cell.trim().isEmpty)) {
      return {
        'studentId': '',
        'fullName': '',
        'course': '',
        'schoolYear': '',
        'section': '',
        'email': '',
        'yearLevel': '',
      };
    }

    // Pad the row if it's shorter than expected
    final paddedRow = List<String>.from(row);
    while (paddedRow.length < 6) {
      paddedRow.add('');
    }

    final fallback = <String, String>{
      'studentId': paddedRow[0],
      'fullName': paddedRow[1],
      'course': paddedRow[2],
      'schoolYear': paddedRow[3],
      'section': paddedRow[4],
      'email': paddedRow[5],
      'yearLevel': paddedRow[3],
    };

    if (headers == null) {
      return fallback;
    }

    final normalizedHeaders = headers
        .map((header) => normalizeHeader(header))
        .toList(growable: false);

    final indexByHeader = <String, int>{};
    for (var i = 0; i < normalizedHeaders.length; i++) {
      if (normalizedHeaders[i].isEmpty) continue;
      indexByHeader.putIfAbsent(normalizedHeaders[i], () => i);
    }

    String getValue(String key) {
      final index = indexByHeader[key];
      if (index == null || index >= paddedRow.length) return '';
      return paddedRow[index];
    }

    final studentId = getValue('student id');
    final fullName = getValue('full name');
    final course = getValue('course');
    final schoolYear = getValue('school year') != ''
        ? getValue('school year')
        : (getValue('year level') != ''
            ? getValue('year level')
            : getValue('year'));
    final section = getValue('section');
    final email = getValue('email');

    return {
      'studentId': studentId,
      'fullName': fullName,
      'course': course,
      'schoolYear': schoolYear,
      'section': section,
      'email': email,
      'yearLevel': schoolYear,
    };
  }

  static String normalizeHeader(String header) {
    final normalized = header
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    const synonyms = {
      'student no': 'student id',
      'student number': 'student id',
      'studentid': 'student id',
      'id number': 'student id',
      'id': 'student id',
      'name': 'full name',
      'fullname': 'full name',
      'email address': 'email',
      'email addr': 'email',
      'e mail': 'email',
      'school year': 'school year',
      'year level': 'year level',
      'yearlevel': 'year level',
      'sem': 'semester',
      'section name': 'section',
      'programme': 'program',
      'major': 'program',
      'course code': 'course',
    };

    return synonyms[normalized] ?? normalized;
  }

  static Map<String, String> inferHeaderMapping(List<String> headers) {
    final normalizedHeaders = headers
        .map(normalizeHeader)
        .toList(growable: false);
    final expectedFields = {
      'student id': 'Student ID',
      'full name': 'Full Name',
      'course': 'Course',
      'school year': 'School Year',
      'year level': 'Year Level',
      'section': 'Section',
      'email': 'Email',
    };

    final mapping = <String, String>{};
    for (final entry in expectedFields.entries) {
      final index = normalizedHeaders.indexWhere((h) => h == entry.key);
      if (index != -1) {
        mapping[entry.value] = headers[index];
      } else {
        mapping[entry.value] = '';
      }
    }
    return mapping;
  }
}