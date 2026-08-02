import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../utils/platform_file_utils.dart' as platform_file_utils;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'export_excel.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import '../../../theme/admin_theme.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/admin_stat_cards_row.dart';

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
      // Decodes at ~2x the actual display size instead of full original
      // resolution — this helper renders logos in every table row, so
      // that was a real, compounding cost.
      cacheWidth: width != null ? (width * 2).round() : null,
      cacheHeight: height != null ? (height * 2).round() : null,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  } catch (e) {
    return const SizedBox.shrink();
  }
}

// Helper for image handling (already present for URLs)
ImageProvider _imageProviderFromUrl(String url) {
  if (url.startsWith('data:image')) {
    final base64Part = url.split(',').last;
    return MemoryImage(base64Decode(base64Part));
  }
  return NetworkImage(url);
}

Widget _buildImageWidget(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  return Image(
    image: _imageProviderFromUrl(url),
    fit: fit,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
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
// Category colors — matches the palette already used in event_calendar.dart
// / the student & org calendars, so a "Workshop" reads the same color
// everywhere. Previously every category badge here used the same flat
// AdminColors.primaryDark tint regardless of category.
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
  'Other': Color(0xFF6B7280),
};

Color _categoryBadgeColor(String category) =>
    _categoryBadgeColors[category] ?? const Color(0xFF6B7280);

// Pastel bg / solid fg pair per category — same values as
// event_calendar.dart's CategoryColors, so a category's table badge here
// reads as the same color as its calendar chip.
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
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
  const Map<String, _BadgeStyle> styles = {
    'approved': _BadgeStyle(Color(0xFFECFDF5), Color(0xFF059669), 'APPROVED'),
    'pending': _BadgeStyle(Color(0xFFFFFBEB), Color(0xFFFB923C), 'PENDING'),
    'rejected': _BadgeStyle(Color(0xFFFEF2F2), Color(0xFFDC2626), 'REJECTED'),
    'archived': _BadgeStyle(Color(0xFFF3F4F6), Color(0xFF6B7280), 'ARCHIVED'),
    'for_review': _BadgeStyle(
      const Color(0xFFEFF6FF),
      AdminColors.info,
      'NEEDS REVISION',
    ),
  };
  final s =
      styles[status.toLowerCase()] ??
      const _BadgeStyle(Color(0xFFF3F4F6), Color(0xFF6B7280), '—');
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: BoxDecoration(
      color: s.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      s.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: s.fg,
        letterSpacing: 0.6,
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
// Org Avatar with Logo (same as adviser_roles.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _OrgAvatar extends StatelessWidget {
  final String name;
  final String? logoUrl;
  const _OrgAvatar({required this.name, this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        child: _buildImageWidget(
          logoUrl!,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
        ),
      );
    }
    // Fallback to initials
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AdminColors.primaryDark.withOpacity(0.1),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class EventProposals extends StatefulWidget {
  const EventProposals({super.key});

  @override
  State<EventProposals> createState() => _EventProposalsState();
}

class _EventProposalsState extends State<EventProposals> {
  String _statusFilter = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;
  final TextEditingController _searchController = TextEditingController();

  // Created once, not constructed inline in build() — the table/stats
  // methods that use these are called on every rebuild (search, filter
  // changes, pagination), so building a fresh .snapshots() there each time
  // was re-subscribing to Firestore from scratch on every keystroke.
  late final Stream<QuerySnapshot> _proposalsStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .snapshots();
  late final Stream<QuerySnapshot> _proposalsOrderedStream = FirebaseFirestore
      .instance
      .collection('event_proposals')
      .orderBy('createdAt', descending: true)
      .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Cache for organization logos
  final Map<String, String> _orgLogoCache = {};
  // Cache for organization short names (acronyms) — table rows show this
  // instead of the full org name so long names don't crowd out the event
  // title column.
  final Map<String, String> _orgShortNameCache = {};

  // Helper to check if widget is still mounted
  bool get _isMounted => mounted;

  // Fetch org logo by orgId
  Future<String?> _fetchOrgLogo(String orgId) async {
    if (_orgLogoCache.containsKey(orgId)) {
      return _orgLogoCache[orgId];
    }

    try {
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();

      if (orgDoc.exists) {
        final data = orgDoc.data() as Map<String, dynamic>;
        final logoUrl = data['logoUrl'] as String? ?? '';
        final shortName = data['shortName'] as String? ?? '';
        _orgLogoCache[orgId] = logoUrl;
        _orgShortNameCache[orgId] = shortName;
        return logoUrl;
      }
    } catch (e) {
      debugPrint('Error fetching org logo for $orgId: $e');
    }
    return null;
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
    return StreamBuilder<QuerySnapshot>(
      stream: _proposalsStream,
      builder: (context, snapshot) {
        int total = 0, pending = 0, approved = 0, rejected = 0;
        if (snapshot.hasData) {
          total = snapshot.data!.docs.length;
          for (final doc in snapshot.data!.docs) {
            final status = (doc.data() as Map)['status'] ?? 'pending';
            if (status == 'pending') pending++;
            if (status == 'approved') approved++;
            if (status == 'rejected') rejected++;
          }
        }
        final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
        final cardGap = isMobile ? 8.0 : 14.0;
        final statCards = [
          _StatCard(
            label: 'Total Proposals',
            value: '$total',
            icon: Icons.event_note_rounded,
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

  // ── Toolbar ───────────────────────────────────────────────────────
  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);
    final itemGap = isMobile ? 10.0 : 12.0;

    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search proposal…',
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
                  value: _statusFilter,
                  items: const [
                    'All',
                    'Pending',
                    'Approved',
                    'Rejected',
                    'Archived',
                    'For Review',
                  ],
                  hint: 'Status',
                  icon: Icons.tune_rounded,
                  onChanged: (v) => setState(() {
                    _statusFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(height: itemGap),
                _ExportProposalsButton(
                  statusFilter: _statusFilter,
                  searchTerm: _searchController.text.trim(),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: searchField),
                SizedBox(width: itemGap),
                _FilterDropdown(
                  value: _statusFilter,
                  items: const [
                    'All',
                    'Pending',
                    'Approved',
                    'Rejected',
                    'Archived',
                    'For Review',
                  ],
                  hint: 'Status',
                  icon: Icons.tune_rounded,
                  onChanged: (v) => setState(() {
                    _statusFilter = v!;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(width: itemGap),
                _ExportProposalsButton(
                  statusFilter: _statusFilter,
                  searchTerm: _searchController.text.trim(),
                ),
              ],
            ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────
  Widget _buildTable(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 28.0);

    return StreamBuilder<QuerySnapshot>(
      stream: _proposalsOrderedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;

        if (_statusFilter == 'All') {
          docs = docs
              .where((d) => (d.data() as Map)['status'] != 'archived')
              .toList();
        } else {
          // 'For Review' -> 'for_review': the one status value that isn't
          // a single lowercased word, so the naive .toLowerCase() compare
          // below needs the space converted to match the stored value.
          final statusValue = _statusFilter.toLowerCase().replaceAll(' ', '_');
          docs = docs
              .where((d) => (d.data() as Map)['status'] == statusValue)
              .toList();
        }

        final _searchTerm = _searchController.text.trim().toLowerCase();
        if (_searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['title'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['orgName'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['submittedBy'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                );
          }).toList();
        }

        final totalPages = docs.isEmpty ? 1 : (docs.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, docs.length);
        final pageDocs = docs.isEmpty ? [] : docs.sublist(start, end);

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
                          return _buildProposalRow(
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

  // NEW HEADER: Organization first, then Event Title
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(flex: 1, child: _headerCell('ORGANIZATION')),
          Expanded(flex: 4, child: _headerCell('EVENT TITLE')),
          Expanded(flex: 1, child: _headerCell('CATEGORY')),
          Expanded(flex: 1, child: _headerCell('DATE')),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight, // right‑align header
              child: _headerCell('STATUS'),
            ),
          ),
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
    final status = (data['status'] ?? 'pending') as String;
    final isPublished = (data['publishedEventId'] ?? '').toString().isNotEmpty;
    final dateStr = _formatDate(data['date']);
    final orgId = data['orgId'] ?? '';
    final orgName = data['orgName'] ?? '—';
    final orgLogoUrl = data['orgLogoUrl'] as String?;

    // ── DEDICATED IMAGE thumbnail ──
    final bool hasImage =
        data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty;
    final Widget? imageThumbnail = hasImage
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

    return FutureBuilder<String?>(
      future: _fetchOrgLogo(orgId),
      builder: (context, logoSnapshot) {
        final logoUrl = orgLogoUrl ?? (logoSnapshot.data ?? '');
        final shortName = _orgShortNameCache[orgId];
        final displayName = (shortName != null && shortName.isNotEmpty)
            ? shortName
            : orgName;

        return InkWell(
          hoverColor: const Color(0xFFF8F9FB),
          onTap: () => _showProposalDetailDialog(docId, data),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                // ORGANIZATION – shows the org's short name/acronym
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      _OrgAvatar(name: orgName, logoUrl: logoUrl),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Tooltip(
                          message: orgName,
                          child: Text(
                            displayName,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A202C),
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // EVENT TITLE – widened so long titles show more
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      if (imageThumbnail != null) ...[
                        imageThumbnail,
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          data['title'] ?? '—',
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
                // CATEGORY – flex 1, matches the header
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CategoryColors.getBg(
                          data['category'] ?? 'Other',
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        data['category'] == 'Other' &&
                                (data['otherCategory'] ?? '')
                                    .toString()
                                    .isNotEmpty
                            ? data['otherCategory']
                            : (data['category'] ?? '—'),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CategoryColors.getFg(
                            data['category'] ?? 'Other',
                          ),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                // DATE – flex 1, matches the header
                Expanded(
                  flex: 1,
                  child: Text(
                    dateStr,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // STATUS – flex 1, matches the header's STATUS column
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: _statusBadge(status)),
                        if (isPublished) ...[
                          const SizedBox(width: 1),
                          const Tooltip(
                            message: 'Published to students',
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
                // ACTIONS – flex back to 2, right‑aligned (unchanged)
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ActionIconButton(
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Details',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _showProposalDetailDialog(docId, data),
                      ),
                      const SizedBox(width: 4),
                      if (status == 'pending') ...[
                        _ActionIconButton(
                          icon: Icons.check_circle_outline_rounded,
                          tooltip: 'Approve',
                          color: const Color(0xFF059669),
                          onTap: () => _confirmSetStatus(
                            docId,
                            data['title'] ?? 'this event',
                            'approved',
                          ),
                        ),
                        const SizedBox(width: 4),
                        _ActionIconButton(
                          icon: Icons.cancel_outlined,
                          tooltip: 'Reject',
                          color: const Color(0xFFDC2626),
                          onTap: () => _showRejectReasonDialog(
                            docId,
                            data['title'] ?? 'this event',
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (status != 'archived')
                        _ActionIconButton(
                          icon: Icons.archive_outlined,
                          tooltip: 'Archive',
                          color: const Color(0xFF6B7280),
                          onTap: () => _confirmSetStatus(
                            docId,
                            data['title'] ?? 'this event',
                            'archived',
                          ),
                        ),
                      if (status == 'archived')
                        _ActionIconButton(
                          icon: Icons.restore_rounded,
                          tooltip: 'Restore',
                          color: const Color(0xFFFB923C),
                          onTap: () => _confirmSetStatus(
                            docId,
                            data['title'] ?? 'this event',
                            'pending',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              Icons.event_busy_rounded,
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
            'Try adjusting your filters or wait for new submissions.',
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

  // ── Actions ───────────────────────────────────────────────────────

  void _confirmSetStatus(String docId, String title, String newStatus) async {
    // Certificate-issuing proposals get a dedicated approval flow that
    // authorizes which admin signatory(ies) the org may use on this event's
    // certificates — plain approvals (or non-certificate events) keep the
    // simple confirm dialog below unchanged.
    if (newStatus == 'approved') {
      final doc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(docId)
          .get();
      if (doc.data()?['issuesCertificate'] == true) {
        if (!_isMounted) return;
        _showCertificateApprovalDialog(docId, title);
        return;
      }
    }
    if (!_isMounted) return;
    final Map<String, _ConfirmStyle> styles = {
      'approved': _ConfirmStyle(
        icon: Icons.check_circle_outline_rounded,
        iconBg: const Color(0xFFECFDF5),
        iconColor: const Color(0xFF059669),
        btnColor: const Color(0xFF059669),
        heading: 'Approve Proposal',
        body:
            'Are you sure you want to approve "$title"? The org will then be able to publish it to their calendar.',
        btnLabel: 'Approve',
      ),
      // Removed 'rejected' from here – we handle rejection separately with reason
      'archived': _ConfirmStyle(
        icon: Icons.archive_outlined,
        iconBg: const Color(0xFFF3F4F6),
        iconColor: const Color(0xFF6B7280),
        btnColor: const Color(0xFF6B7280),
        heading: 'Archive Proposal',
        body: 'Are you sure you want to archive "$title"?',
        btnLabel: 'Archive',
      ),
      'pending': _ConfirmStyle(
        icon: Icons.restore_rounded,
        iconBg: const Color(0xFFFFFBEB),
        iconColor: const Color(0xFFFB923C),
        btnColor: const Color(0xFFFB923C),
        heading: 'Restore Proposal',
        body: 'Restore "$title" from the archive back to pending review?',
        btnLabel: 'Restore',
      ),
    };
    final s = styles[newStatus]!;

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
                      color: s.iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(s.icon, color: s.iconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    s.heading,
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
                s.body,
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
                      await _setStatus(docId, title, newStatus);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: s.btnColor,
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
                      s.btnLabel,
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

  // ── Certificate-issuing approval: authorize which signatory(ies) the org
  // may use on this event's certificates, plus a private remark that never
  // reaches the certificate itself. ──────────────────────────────────────
  void _showCertificateApprovalDialog(String docId, String title) {
    bool needsSignature = false;
    final Set<String> selectedSignatoryIds = {};
    final remarksCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 460,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
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
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF059669),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Approve Proposal',
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
                      '"$title" issues certificates. Decide whether the org needs an admin e-signature on them before it can be used.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13.5,
                        color: const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setDlg(() => needsSignature = !needsSignature),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: needsSignature,
                              activeColor: const Color(0xFF059669),
                              onChanged: (v) =>
                                  setDlg(() => needsSignature = v ?? false),
                            ),
                            Expanded(
                              child: Text(
                                'This event needs an admin e-signature on its certificates',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A202C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (needsSignature) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Select which signatory(ies) the org is authorized to use for this event only:',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('signatories')
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? [];
                          if (snap.connectionState == ConnectionState.waiting &&
                              docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (docs.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Text(
                                'No signatories on file yet — add one in Admin Settings → Signatories first.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12.5,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                            );
                          }
                          return Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE2E6EA),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < docs.length; i++)
                                  CheckboxListTile(
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: selectedSignatoryIds.contains(
                                      docs[i].id,
                                    ),
                                    activeColor: const Color(0xFF059669),
                                    onChanged: (v) => setDlg(() {
                                      if (v == true) {
                                        selectedSignatoryIds.add(docs[i].id);
                                      } else {
                                        selectedSignatoryIds.remove(docs[i].id);
                                      }
                                    }),
                                    title: Text(
                                      (docs[i].data()
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)['fullName']
                                              ?.toString() ??
                                          '',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      (docs[i].data()
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)['title']
                                              ?.toString() ??
                                          '',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11.5,
                                        color: const Color(0xFF9AA5B4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Remarks (internal — never shown on the certificate)',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksCtrl,
                      maxLines: 3,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. reason for authorizing/declining a signature, conditions, notes for other admins…',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          color: const Color(0xFFB0BAC8),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E6EA),
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: submitting
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
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  if (needsSignature &&
                                      selectedSignatoryIds.isEmpty) {
                                    AppToast.error(
                                      ctx,
                                      'Select at least one signatory, or uncheck the signature requirement.',
                                    );
                                    return;
                                  }
                                  setDlg(() => submitting = true);
                                  await _setStatus(
                                    docId,
                                    title,
                                    'approved',
                                    extraFields: {
                                      'signatoryAuthorization': {
                                        'required': needsSignature,
                                        'signatoryIds': needsSignature
                                            ? selectedSignatoryIds.toList()
                                            : <String>[],
                                        'remarks': remarksCtrl.text.trim(),
                                        'authorizedBy':
                                            FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid ??
                                            '',
                                        'authorizedAt':
                                            FieldValue.serverTimestamp(),
                                      },
                                    },
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
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
                            submitting ? 'Approving…' : 'Approve',
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
        },
      ),
    );
  }

  // ── NEW: Show rejection reason dialog ───────────────────────────
  void _showRejectReasonDialog(String docId, String title) {
    final TextEditingController reasonController = TextEditingController();

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
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Reject Proposal',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Provide a reason for rejecting "$title". This will be visible to the organization.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                maxLength: 1000,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Reason for rejection…',
                  hintStyle: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF9AA5B4),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFDC2626),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
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
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) {
                        AppToast.warning(
                          ctx,
                          'Please provide a reason for rejection.',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      await _rejectProposalWithReason(docId, title, reason);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
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
                      'Reject',
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

  // ── NEW: Reject with reason ──────────────────────────────────────
  Future<void> _rejectProposalWithReason(
    String docId,
    String title,
    String reason,
  ) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(docId);
      final orgId = (await docRef.get()).data()?['orgId']?.toString() ?? '';
      await docRef.update({
        'status': 'rejected',
        'adminFeedback': reason, // store rejection reason in adminFeedback
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });
      await activity_log.ActivityLogger.log(
        action: 'Rejected proposal: $title',
        module: 'Event Management',
        severity: 'warning',
        details: {'proposalId': docId, 'reason': reason},
      );
      if (orgId.isNotEmpty) {
        NotificationService.sendToOrgMembers(
          orgId: orgId,
          title: 'Proposal rejected',
          body: 'Your event proposal "$title" was rejected. Reason: $reason',
          type: 'proposal_status',
        );
      }
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Proposal rejected. Reason sent to organization.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _setStatus(
    String docId,
    String title,
    String newStatus, {
    Map<String, dynamic>? extraFields,
  }) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(docId);
      final orgId = (await docRef.get()).data()?['orgId']?.toString() ?? '';
      await docRef.update({
        'status': newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        if (extraFields != null) ...extraFields,
      });
      await activity_log.ActivityLogger.log(
        action: '${newStatus.toUpperCase()} proposal: $title',
        module: 'Event Management',
        severity: (newStatus == 'rejected' || newStatus == 'archived')
            ? 'warning'
            : 'info',
        details: {'proposalId': docId, 'title': title},
      );
      if (orgId.isNotEmpty &&
          (newStatus == 'approved' || newStatus == 'rejected')) {
        NotificationService.sendToOrgMembers(
          orgId: orgId,
          title: newStatus == 'approved'
              ? 'Proposal approved'
              : 'Proposal rejected',
          body: newStatus == 'approved'
              ? 'Your event proposal "$title" was approved. You can now publish it.'
              : 'Your event proposal "$title" was rejected.',
          type: 'proposal_status',
        );
      }
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proposal ${newStatus[0].toUpperCase()}${newStatus.substring(1)}',
            ),
            backgroundColor: newStatus == 'approved'
                ? const Color(0xFF059669)
                : newStatus == 'rejected'
                ? const Color(0xFFDC2626)
                : const Color(0xFF6B7280),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _requestRevision(
    String docId,
    String title,
    String feedback,
  ) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(docId);
      final orgId = (await docRef.get()).data()?['orgId']?.toString() ?? '';
      await docRef.update({
        'status': 'for_review',
        'adminFeedback': feedback,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });
      await activity_log.ActivityLogger.log(
        action: 'Requested revision for proposal: $title',
        module: 'Event Management',
        severity: 'info',
        details: {'proposalId': docId},
      );
      if (orgId.isNotEmpty) {
        NotificationService.sendToOrgMembers(
          orgId: orgId,
          title: 'Revision requested',
          body: 'Admin requested a revision for "$title": $feedback',
          type: 'proposal_revision',
        );
      }
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Revision request sent to organization'),
            backgroundColor: const Color(0xFF7C3AED),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showRevisionDialog(BuildContext parentCtx, String docId, String title) {
    final ctrl = TextEditingController();
    showDialog(
      context: parentCtx,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.rate_review_rounded,
                      color: AdminColors.primaryDark,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request Revision',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Your feedback will be visible to the organization.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 1000,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Please update the venue details and resubmit...',
                  hintStyle: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF9AA5B4),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF7C3AED),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),
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
                        horizontal: 16,
                        vertical: 10,
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
                  ElevatedButton.icon(
                    onPressed: () async {
                      final feedback = ctrl.text.trim();
                      if (feedback.isEmpty) {
                        AppToast.warning(
                          ctx,
                          'Please describe what needs to be revised.',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      Navigator.pop(parentCtx);
                      await _requestRevision(docId, title, feedback);
                    },
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: Text(
                      'Send Feedback',
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
  }

  // ── View Detail Dialog – with dedicated image preview ──
  void _showProposalDetailDialog(String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? 'pending') as String;
    final isPublished = (data['publishedEventId'] ?? '').toString().isNotEmpty;
    final hasImage =
        data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty;
    final hasAttachment =
        data['attachmentBase64'] != null &&
        data['attachmentBase64'].toString().isNotEmpty;
    final issuesCertificate = data['issuesCertificate'] == true;
    final startTime = (data['startTime'] ?? data['time'] ?? '').toString();
    final endTime = (data['endTime'] ?? '').toString();
    final timeStr = startTime.isEmpty
        ? '—'
        : (endTime.isEmpty ? startTime : '$startTime – $endTime');

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 600,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          // A soft warm cream instead of stark white — ties the body back to
          // the amber header instead of jumping straight to a flat, generic
          // white admin-form look.
          decoration: const BoxDecoration(
            color: Color(0xFFFFFAF5),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── HEADER ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 16, 20),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _statusBadge(status),
                              if ((data['orgName'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    data['orgName'],
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withAlpha(200),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            data['title'] ?? 'Event Proposal',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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

              // ── BODY ────────────────────────────────────────────────
              // Flexible (not Expanded) so the dialog shrinks to fit short
              // content instead of stretching to near-fullscreen height.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Event Image (if present) ──
                      if (hasImage) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            height: 200,
                            color: const Color(0xFFF8F9FB),
                            child: _buildImageFromBase64(
                              data['imageBase64']!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Event Details Section ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Category',
                              data['category'] == 'Other' &&
                                      (data['otherCategory'] ?? '')
                                          .toString()
                                          .isNotEmpty
                                  ? data['otherCategory']
                                  : (data['category'] ?? '—'),
                              Icons.category_outlined,
                              valueColor: _categoryBadgeColor(
                                data['category'] ?? 'Other',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _detailItem(
                              'Audience',
                              data['audience'] ?? '—',
                              Icons.people_outline_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Date',
                              _formatDate(data['date']),
                              Icons.calendar_today_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _detailItem(
                              'Time',
                              timeStr,
                              Icons.access_time_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailItem(
                              'School Year',
                              data['schoolYear'] ?? '—',
                              Icons.school_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _detailItem(
                              'Semester',
                              data['semester'] ?? '—',
                              Icons.date_range_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailItem(
                              'Location',
                              data['location'] ?? '—',
                              Icons.location_on_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _detailItem(
                              'Issues Certificate',
                              issuesCertificate ? 'Yes' : 'No',
                              Icons.verified_outlined,
                              valueColor: issuesCertificate
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Description ──
                      _sectionLabel(
                        'Description',
                        icon: Icons.description_outlined,
                      ),
                      Text(
                        data['description'] ?? 'No description provided.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13.5,
                          color: const Color(0xFF374151),
                          height: 1.65,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Submission Info ──
                      _sectionLabel(
                        'Submission Info',
                        icon: Icons.person_outline_rounded,
                      ),
                      Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _detailItem(
                                  'Submitted By',
                                  data['submittedByEmail'] ?? '—',
                                  Icons.email_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _detailItem(
                                  'Submitted At',
                                  _formatTimestamp(data['createdAt']),
                                  Icons.access_time_rounded,
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
                                      return _detailItem(
                                        'Reviewed By',
                                        name,
                                        Icons.rate_review_outlined,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _detailItem(
                                    'Reviewed At',
                                    _formatTimestamp(data['reviewedAt']),
                                    Icons.access_time_rounded,
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
                                  child: _detailItem(
                                    'Published to Students',
                                    _formatTimestamp(data['publishedAt']),
                                    Icons.publish_rounded,
                                    valueColor: const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Admin Feedback (if present) ──
                      if (data['adminFeedback'] != null &&
                          data['adminFeedback'].toString().isNotEmpty) ...[
                        _sectionLabel(
                          status == 'rejected'
                              ? 'Rejection Reason'
                              : 'Feedback',
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

                      // ── Attachment ──
                      if (hasAttachment) ...[
                        const SizedBox(height: 20),
                        _sectionLabel(
                          'Attachment',
                          icon: Icons.attach_file_rounded,
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E6EA)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AdminColors.primaryDark.withOpacity(
                                    0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.insert_drive_file_rounded,
                                  size: 20,
                                  color: AdminColors.primaryDark,
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
                                onPressed: () => _saveAndOpenFile(data),
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
                                  backgroundColor: AdminColors.primaryDark,
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

              // ── FOOTER ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Column(
                  children: [
                    if (status == 'pending') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmSetStatus(
                                  docId,
                                  data['title'] ?? 'this event',
                                  'approved',
                                );
                              },
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                size: 15,
                              ),
                              label: Text(
                                'Approve',
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showRejectReasonDialog(
                                  docId,
                                  data['title'] ?? 'this event',
                                );
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 15),
                              label: Text(
                                'Reject',
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(
                                  color: Color(0xFFDC2626),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showRevisionDialog(
                                ctx,
                                docId,
                                data['title'] ?? 'this event',
                              ),
                              icon: const Icon(
                                Icons.rate_review_rounded,
                                size: 15,
                              ),
                              label: Text(
                                'Revision',
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF7C3AED),
                                side: const BorderSide(
                                  color: Color(0xFF7C3AED),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        if (status == 'approved') ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPublished
                                      ? Icons.check_circle_rounded
                                      : Icons.hourglass_top_rounded,
                                  size: 15,
                                  color: isPublished
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF9AA5B4),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isPublished
                                        ? 'Published'
                                        : 'Awaiting publish',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isPublished
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFF9AA5B4),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (status != 'archived')
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmSetStatus(
                                docId,
                                data['title'] ?? 'this event',
                                'archived',
                              );
                            },
                            icon: const Icon(Icons.archive_outlined, size: 15),
                            label: Text(
                              'Archive',
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                            ),
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
                          ),
                        if (status == 'archived')
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmSetStatus(
                                docId,
                                data['title'] ?? 'this event',
                                'pending',
                              );
                            },
                            icon: const Icon(Icons.restore_rounded, size: 15),
                            label: Text(
                              'Restore',
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFB923C),
                              side: const BorderSide(color: Color(0xFFFDE68A)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 11,
                              ),
                            ),
                          ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFE2E6EA)),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Boxed icon-card instead of plain floating icon+label+value — the
  // "plain inline grid" this used to be read flat next to the rest of the
  // dialog's now-boxed sections (Feedback, Attachment).
  Widget _detailItem(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final accent = valueColor ?? const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF1F4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withAlpha(28),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9AA5B4),
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? const Color(0xFF1A202C),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Open attachment (unchanged) ──
  Future<void> _saveAndOpenFile(Map<String, dynamic> data) async {
    try {
      Uint8List bytes = Uint8List(0);
      final String fileName = data['attachmentName'] ?? 'document';

      final hasBase64 =
          data['attachmentBase64'] != null &&
          data['attachmentBase64'].toString().isNotEmpty;
      final hasUrl =
          data['attachmentUrl'] != null &&
          data['attachmentUrl'].toString().isNotEmpty;

      if (!hasBase64 && !hasUrl) {
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No attachment found'),
              backgroundColor: AdminColors.error,
            ),
          );
        }
        return;
      }

      if (hasBase64) {
        final String base64String = data['attachmentBase64'];
        bytes = base64Decode(base64String);
        print('✅ Loaded from Base64, size: ${bytes.length} bytes');
      } else if (hasUrl) {
        final String url = data['attachmentUrl'];
        try {
          final ref = FirebaseStorage.instance.refFromURL(url);
          bytes = await ref.getData(50 * 1024 * 1024) ?? Uint8List(0);
        } catch (_) {
          try {
            final uri = Uri.parse(url);
            final response = await http.get(uri);
            if (response.statusCode == 200) {
              bytes = response.bodyBytes;
            }
          } catch (e) {
            if (_isMounted) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(
                    'Open Attachment',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  content: Text(
                    'Cannot download attachment. Open in browser instead?',
                    style: GoogleFonts.beVietnamPro(
                      color: const Color(0xFF374151),
                    ),
                  ),
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('Cancel', style: GoogleFonts.beVietnamPro()),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        platform_file_utils.openUrl(url);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Open', style: GoogleFonts.beVietnamPro()),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      }

      if (bytes.isEmpty) {
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Empty attachment'),
              backgroundColor: AdminColors.error,
            ),
          );
        }
        return;
      }

      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final mime = _getMimeTypeFromExtension(ext);

      if (mime.startsWith('text/')) {
        final content = utf8.decode(bytes);
        if (_isMounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                fileName,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
              content: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: GoogleFonts.beVietnamPro(fontSize: 12),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFE2E6EA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text('Close', style: GoogleFonts.beVietnamPro()),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    platform_file_utils.saveBytesToTempAndOpen(
                      bytes,
                      fileName,
                      mimeType: mime,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Download', style: GoogleFonts.beVietnamPro()),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mime.startsWith('image/')) {
        if (_isMounted) {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      fileName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.memory(bytes),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFE2E6EA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Close',
                            style: GoogleFonts.beVietnamPro(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            platform_file_utils.saveBytesToTempAndOpen(
                              bytes,
                              fileName,
                              mimeType: mime,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.primaryDark,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            'Download',
                            style: GoogleFonts.beVietnamPro(),
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
        return;
      }

      await platform_file_utils.saveBytesToTempAndOpen(
        bytes,
        fileName,
        mimeType: mime,
      );
    } catch (e) {
      print('❌ Error opening attachment: $e');
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatDate(dynamic dateField) {
    if (dateField == null) return 'TBD';
    if (dateField is Timestamp) {
      final d = dateField.toDate();
      return '${d.month}/${d.day}/${d.year}';
    }
    return dateField.toString();
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.month}/${d.day}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }
    return ts.toString();
  }
}

class _ConfirmStyle {
  final IconData icon;
  final Color iconBg, iconColor, btnColor;
  final String heading, body, btnLabel;
  const _ConfirmStyle({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.btnColor,
    required this.heading,
    required this.body,
    required this.btnLabel,
  });
}

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

class _ExportProposalsButton extends StatelessWidget {
  final String statusFilter, searchTerm;
  const _ExportProposalsButton({
    required this.statusFilter,
    required this.searchTerm,
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
          .collection('event_proposals')
          .orderBy('createdAt', descending: true)
          .get();
      var docs = snap.docs;

      if (statusFilter != 'All') {
        docs = docs
            .where((d) => (d.data())['status'] == statusFilter.toLowerCase())
            .toList();
      }
      if (searchTerm.isNotEmpty) {
        docs = docs.where((d) {
          final data = d.data();
          return (data['title'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              ) ||
              (data['orgName'] ?? '').toString().toLowerCase().contains(
                searchTerm,
              );
        }).toList();
      }

      if (docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No data to export.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final now = DateTime.now().toString().substring(0, 10);

      if (format == 'excel') {
        final rows = docs.map((doc) {
          final d = doc.data();
          return [
            (d['orgName'] ?? '').toString(),
            (d['title'] ?? '').toString(),
            (d['category'] ?? '').toString(),
            _fmtDate(d['date']),
            (d['status'] ?? '').toString(),
            (d['description'] ?? '').toString(),
          ];
        }).toList();
        final bytes = AdminExportExcel.generateStyledTable(
          title: 'Event Proposals',
          headers: const [
            'Organization',
            'Event Title',
            'Category',
            'Date',
            'Status',
            'Description',
          ],
          rows: rows,
        );
        await AdminExportUtil.saveBytes(
          bytes,
          'event_proposals_$now.xlsx',
          mimeType: xlsxMimeType,
        );
      } else if (format == 'pdf') {
        final rows = docs.map((doc) {
          final d = doc.data();
          return [
            d['orgName'] ?? '',
            d['title'] ?? '',
            d['category'] ?? '',
            _fmtDate(d['date']),
            d['status'] ?? '',
            d['description'] ?? '',
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'Event Proposals Report',
          headers: const [
            'Organization',
            'Event Title',
            'Category',
            'Date',
            'Status',
            'Description',
          ],
          rows: rows,
        );
        await AdminExportUtil.saveBytes(
          pdfBytes,
          'event_proposals_$now.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        throw UnsupportedError('Unsupported export format: $format');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return 'TBD';
    if (d is Timestamp) {
      final dt = d.toDate();
      return '${dt.month}/${dt.day}/${dt.year}';
    }
    return d.toString();
  }
}

// Compact colored chip — matches the icon actions in org_event_proposals.dart
// / organization_management.dart / student_accounts.dart / adviser_roles.dart,
// instead of a bare unstyled icon.
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
