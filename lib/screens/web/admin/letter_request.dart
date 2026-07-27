// lib/screens/web/admin/letter_request.dart - CORRECTED VERSION

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:uprise/widgets/admin_export_button.dart';
import 'package:intl/intl.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/firestore_collections.dart';
import '../../../services/notification_service.dart';
import '../../../utils/platform_file_utils.dart' as platform_file_utils;
import '../../../utils/file_validation.dart';
import '../../../widgets/anchored_dropdown.dart';

// Strips a near-white background from an imported signature photo/scan so it
// overlays cleanly on a document instead of showing as an opaque white box.
// Runs on a background isolate via compute() so the UI doesn't freeze.
Uint8List _removeSignatureBackground(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Unsupported image format');
  if (decoded.width > 800) {
    decoded = img.copyResize(decoded, width: 800);
  }
  const threshold = 235;
  for (final pixel in decoded) {
    final luminance = (pixel.r + pixel.g + pixel.b) / 3;
    if (luminance >= threshold) {
      pixel.a = 0;
    } else if (luminance > threshold - 40) {
      pixel.a = (255 * (threshold - luminance) / 40).clamp(0, 255).toInt();
    }
  }
  return img.encodePng(decoded);
}

// ============ COLOR SCHEME ============
class AdminColors {
  static const Color primaryDark = Color(0xFFEA580C);
  static const Color primaryLight = Color(0xFFFB923C);
  static const Color accent = Color(0xFFF97316);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF9FAFB);
  static const Color mediumGray = Color(0xFFE5E7EB);
  static const Color darkGray = Color(0xFF6B7280);
  static const Color charcoal = Color(0xFF111827);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFFB923C);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
  static const Color purple = Color(0xFF7C3AED);
}

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

// ============ MAIN WIDGET ============
class AdminLetterRequestScreen extends StatefulWidget {
  const AdminLetterRequestScreen({super.key});

  @override
  State<AdminLetterRequestScreen> createState() =>
      _AdminLetterRequestScreenState();
}

class _AdminLetterRequestScreenState extends State<AdminLetterRequestScreen> {
  String _statusFilter = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _orgLogoCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _fetchOrgLogo(String orgId) async {
    if (_orgLogoCache.containsKey(orgId)) {
      return _orgLogoCache[orgId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
      final logoUrl = doc.data()?['logoUrl'] ?? '';
      _orgLogoCache[orgId] = logoUrl;
      return logoUrl;
    } catch (e) {
      return '';
    }
  }

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
            Icon(icon, size: 13, color: AdminColors.primaryDark.withAlpha(150)),
            const SizedBox(width: 6),
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

  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreCollections.letterRequests.snapshots(),
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
            final s = (doc.data() as Map)['status'] ?? 'pending';
            if (s == 'pending') pending++;
            if (s == 'approved') approved++;
            if (s == 'rejected') rejected++;
            if (s == 'revision') revision++;
            if (s == 'resubmitted') resubmitted++;
          }
        }

        final cards = [
          _StatCard(
            label: 'Total Requests',
            value: '$total',
            icon: Icons.description_rounded,
            color: AdminColors.primaryDark,
          ),
          _StatCard(
            label: 'Approved',
            value: '$approved',
            icon: Icons.check_circle_rounded,
            color: AdminColors.success,
          ),
          _StatCard(
            label: 'Pending',
            value: '$pending',
            icon: Icons.pending_rounded,
            color: AdminColors.warning,
          ),
          _StatCard(
            label: 'Resubmitted',
            value: '$resubmitted',
            icon: Icons.refresh_rounded,
            color: AdminColors.info,
          ),
          _StatCard(
            label: 'Needs Revision',
            value: '$revision',
            icon: Icons.edit_note_rounded,
            color: AdminColors.purple,
          ),
          _StatCard(
            label: 'Rejected',
            value: '$rejected',
            icon: Icons.cancel_rounded,
            color: AdminColors.error,
          ),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var card in cards) ...[
                      card,
                      const SizedBox(height: 14),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      Expanded(child: cards[i]),
                      if (i < cards.length - 1) const SizedBox(width: 14),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search letter request…',
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
            borderSide: const BorderSide(
              color: AdminColors.primaryDark,
              width: 1.5,
            ),
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
          items: const [
            'All',
            'Pending',
            'Approved',
            'Rejected',
            'Archived',
          ],
          hint: 'Status',
          icon: Icons.tune_rounded,
          onChanged: (v) => setState(() {
            _statusFilter = v!;
            _currentPage = 1;
          }),
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

  Widget _buildTable(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreCollections.letterRequests
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;

        if (_statusFilter == 'Archived') {
          docs = docs
              .where((d) => (d.data() as Map)['isArchived'] == true)
              .toList();
        } else {
          // Always hide archived items unless explicitly viewing them
          docs = docs
              .where((d) => (d.data() as Map)['isArchived'] != true)
              .toList();
          if (_statusFilter != 'All') {
            String filterValue = _statusFilter;
            if (filterValue == 'Needs Revision') filterValue = 'revision';
            if (filterValue == 'Resubmitted') filterValue = 'resubmitted';
            docs = docs.where((d) {
              final status = ((d.data() as Map)['status'] ?? 'pending')
                  .toString()
                  .toLowerCase();
              return status == filterValue.toLowerCase();
            }).toList();
          }
        }

        final _searchTerm = _searchController.text.trim().toLowerCase();
        if (_searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['purpose'] ?? data['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchTerm) ||
                (data['orgName'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['requestedBy'] ?? data['submittedBy'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchTerm);
          }).toList();
        }

        final totalPages = docs.isEmpty ? 1 : (docs.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, docs.length);
        final pageDocs = docs.isEmpty ? [] : docs.sublist(start, end);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
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
                          data['name'] = data['name'] ?? data['orgName'];
                          data['email'] = data['email'] ?? data['orgEmail'];
                          return _buildRow(
                            data: data,
                            docId: pageDocs[i].id,
                            isLast: i == pageDocs.length - 1,
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
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _headerCell('REQUESTOR')),
          Expanded(flex: 2, child: _headerCell('LETTER ID')),
          Expanded(flex: 3, child: _headerCell('SUBJECT')),
          Expanded(flex: 2, child: _headerCell('DATE SUBMITTED')),
          Expanded(flex: 2, child: _headerCell('E-SIGNED')),
          Expanded(flex: 2, child: _headerCell('STATUS')),
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

  Widget _buildRow({
    required Map<String, dynamic> data,
    required String docId,
    required bool isLast,
  }) {
    final status = (data['status'] ?? 'pending').toString();
    final isArchived = data['isArchived'] == true;
    final timestamp = data['timestamp'] as Timestamp?;
    final date = timestamp != null
        ? DateFormat('MMM dd, yyyy').format(timestamp.toDate())
        : 'Unknown';
    final orgId = data['orgId'] ?? '';
    final subject = data['subject'] ?? 'No subject';
    final letterId = data['letterId'] ?? 'N/A';
    final message = data['message'];

    // E-signature, if the letter was digitally signed on approval — lets
    // admin confirm at a glance whether a signed copy actually exists.
    final signingTs = data['signedAt'] as Timestamp?;
    final signingStr = signingTs != null
        ? DateFormat('MMM dd, yyyy').format(signingTs.toDate())
        : '—';
    final hasSigningDate = signingTs != null;

    return FutureBuilder<String>(
      future: _fetchOrgLogo(orgId),
      builder: (context, logoSnapshot) {
        final logoUrl = logoSnapshot.data ?? '';

        return InkWell(
          hoverColor: const Color(0xFFF8F9FB),
          onTap: () => _showViewDialog(data, docId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                        ),
                        child: logoUrl.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  logoUrl,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _defaultAvatar(),
                                ),
                              )
                            : _defaultAvatar(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          data['orgName'] ?? 'Unknown',
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
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryDark.withAlpha(18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        letterId,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.primaryDark,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1A202C),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (message != null && message.toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          message.length > 40
                              ? '${message.substring(0, 40)}...'
                              : message,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: const Color(0xFF9AA5B4),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    date,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: hasSigningDate
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withAlpha(20),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Icon(
                                Icons.draw_rounded,
                                size: 11,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                signingStr,
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
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildStatusBadge(status),
                  ),
                ),
                // ============ ACTIONS ============
                // "Request Revision" lives in the View dialog only (matches
                // admin/event_proposals.dart) — keeping it out of the row
                // frees up room so icons stop crowding/overlapping each other.
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // View button - always visible
                      _ActionIconButton(
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Details',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _showViewDialog(data, docId),
                      ),

                      // For PENDING or RESUBMITTED: Show Approve, Reject
                      if (status == 'pending' || status == 'resubmitted') ...[
                        const SizedBox(width: 6),
                        _ActionIconButton(
                          icon: Icons.check_circle_outline,
                          tooltip: 'Approve',
                          color: AdminColors.success,
                          onTap: () => _approveWithESignature(docId, data),
                        ),
                        const SizedBox(width: 6),
                        _ActionIconButton(
                          icon: Icons.cancel_outlined,
                          tooltip: 'Reject',
                          color: AdminColors.error,
                          onTap: () => _confirmRejectLetter(
                            docId,
                            data['orgName'] ?? 'Request',
                          ),
                        ),
                      ],

                      // Archive/Restore button - always visible for all statuses
                      const SizedBox(width: 6),
                      isArchived
                          ? _ActionIconButton(
                              icon: Icons.restore_rounded,
                              tooltip: 'Restore',
                              color: AdminColors.success,
                              onTap: () => _restoreRequest(
                                docId,
                                data['orgName'] ?? 'Request',
                                subject,
                              ),
                            )
                          : _ActionIconButton(
                              icon: Icons.archive_outlined,
                              tooltip: 'Archive',
                              color: const Color(0xFF6B7280),
                              onTap: () => _archiveRequest(
                                docId,
                                data['orgName'] ?? 'Request',
                                subject,
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

  Widget _defaultAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AdminColors.primaryDark.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        Icons.business_outlined,
        size: 18,
        color: AdminColors.primaryDark,
      ),
    );
  }

  void _requestRevision(Map<String, dynamic> data, String docId) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Revision'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                text: 'Please provide feedback/revision notes:',
                children: [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: AdminColors.error),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g., Please provide a more detailed letter...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final comment = commentController.text.trim();
              if (comment.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide revision notes'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              await _updateStatus(
                docId,
                'revision',
                data['orgName'] ?? 'Request',
                revisionNote: comment,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.info),
            child: const Text('Send Revision Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Map<String, dynamic> style;
    switch (status.toLowerCase()) {
      case 'approved':
        style = {
          'bg': const Color(0xFFECFDF5),
          'fg': const Color(0xFF059669),
          'label': 'APPROVED',
        };
        break;
      case 'rejected':
        style = {
          'bg': const Color(0xFFFEF2F2),
          'fg': const Color(0xFFDC2626),
          'label': 'REJECTED',
        };
        break;
      case 'revision':
        style = {
          'bg': const Color(0xFFEFF6FF),
          'fg': const Color(0xFF2563EB),
          'label': 'NEEDS REVISION',
        };
        break;
      case 'resubmitted':
        style = {
          'bg': const Color(0xFFF0FDF4),
          'fg': const Color(0xFF16A34A),
          'label': 'RESUBMITTED',
        };
        break;
      default:
        style = {
          'bg': const Color(0xFFFFFBEB),
          'fg': const Color(0xFFFB923C),
          'label': 'PENDING',
        };
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style['bg'] as Color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        style['label'] as String,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: style['fg'] as Color,
          letterSpacing: 0.8,
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

  Future<void> _archiveRequest(
    String docId,
    String orgName,
    String subject,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Request'),
        content: Text(
          'Archive request from "$orgName" about "$subject"? You can still view it in the archived section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.warning,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirestoreCollections.letterRequests.doc(docId).update({
        'isArchived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      });
      await activity_log.ActivityLogger.log(
        action: 'archive_letter_request',
        module: 'Letter Request',
        severity: 'warning',
        details: {'docId': docId, 'orgName': orgName},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request archived successfully'),
            backgroundColor: AdminColors.success,
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

  Future<void> _restoreRequest(
    String docId,
    String orgName,
    String subject,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Request'),
        content: Text(
          'Restore request from "$orgName" about "$subject" out of the archive?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.success,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirestoreCollections.letterRequests.doc(docId).update({
        'isArchived': false,
        'archivedAt': FieldValue.delete(),
      });
      await activity_log.ActivityLogger.log(
        action: 'restore_letter_request',
        module: 'Letter Request',
        severity: 'info',
        details: {'docId': docId, 'orgName': orgName},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request restored successfully'),
            backgroundColor: AdminColors.success,
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

  Future<void> _confirmRejectLetter(String docId, String orgName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Letter Request', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700)),
        content: Text(
          'Reject the letter request from "$orgName"? The organization will be notified.',
          style: GoogleFonts.beVietnamPro(fontSize: 14, color: const Color(0xFF64748B), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.beVietnamPro(color: const Color(0xFF374151))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.error, foregroundColor: Colors.white),
            child: Text('Reject', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateStatus(docId, 'rejected', orgName);
    }
  }

  Future<void> _updateStatus(
    String docId,
    String newStatus,
    String orgName, {
    String? revisionNote,
  }) async {
    try {
      final docRef = FirestoreCollections.letterRequests.doc(docId);
      final orgId = ((await docRef.get()).data() as Map<String, dynamic>?)?['orgId']?.toString() ?? '';
      final Map<String, dynamic> updateData = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (revisionNote != null) {
        updateData['revisionNote'] = revisionNote;
        updateData['revisionRequestedAt'] = FieldValue.serverTimestamp();
      }
      await docRef.update(updateData);
      await activity_log.ActivityLogger.log(
        action: '${newStatus.toUpperCase()} letter request from: $orgName',
        module: 'Letter Request',
        severity: newStatus == 'rejected' ? 'warning' : 'info',
      );
      if (orgId.isNotEmpty) {
        String notifTitle;
        String notifBody;
        switch (newStatus) {
          case 'approved':
            notifTitle = 'Letter request approved';
            notifBody = 'Your letter request has been approved and signed.';
            break;
          case 'rejected':
            notifTitle = 'Letter request rejected';
            notifBody = 'Your letter request was rejected.';
            break;
          case 'revision':
            notifTitle = 'Revision requested';
            notifBody = revisionNote != null && revisionNote.isNotEmpty
                ? 'Admin requested a revision on your letter request: $revisionNote'
                : 'Admin requested a revision on your letter request.';
            break;
          default:
            notifTitle = 'Letter request updated';
            notifBody = 'Your letter request status changed to $newStatus.';
        }
        NotificationService.sendToOrgMembers(
          orgId: orgId,
          title: notifTitle,
          body: notifBody,
          type: 'letter_status',
        );
      }
      if (mounted) {
        String message =
            'Status updated to ${newStatus[0].toUpperCase()}${newStatus.substring(1)}';
        if (newStatus == 'revision') message = 'Revision requested with notes';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: newStatus == 'approved'
                ? AdminColors.success
                : (newStatus == 'revision'
                      ? AdminColors.info
                      : AdminColors.error),
            behavior: SnackBarBehavior.floating,
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

  // ── Approve + e-sign. Replaces the old wet-sign appointment scheduling —
  // the admin draws a signature here and now, and a signed approval
  // certificate PDF is generated immediately instead of booking an
  // in-person office visit. ──
  Future<void> _approveWithESignature(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final orgName = (data['orgName'] ?? 'Request').toString();
    final letterId = (data['letterId'] ?? 'N/A').toString();
    final subject = (data['subject'] ?? 'No subject').toString();
    final requestorName =
        (data['requestedBy'] ?? data['submittedBy'] ?? orgName).toString();
    final signedByName = FirebaseAuth.instance.currentUser?.email ?? 'Admin';

    final savedSignatures = await _loadSavedSignatures();
    final remarkCtrl = TextEditingController();

    Uint8List? signatureBytes;
    bool isProcessing = false;
    bool isSaving = false;
    bool justImported =
        false; // true once a freshly-imported (not saved) signature is ready
    String? error;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickSignature() async {
            final res = await FilePicker.platform.pickFiles(
              withData: true,
              type: FileType.image,
            );
            if (res == null || res.files.isEmpty) return;
            final bytes = res.files.first.bytes;
            if (bytes == null) return;

            final validationError = FileValidation.validateImageBytes(bytes);
            if (validationError != null) {
              setDialogState(() => error = validationError);
              return;
            }

            setDialogState(() {
              isProcessing = true;
              error = null;
            });
            try {
              final pngBytes = await compute(_removeSignatureBackground, bytes);
              setDialogState(() {
                signatureBytes = pngBytes;
                isProcessing = false;
                justImported = true;
              });
            } catch (e) {
              setDialogState(() {
                isProcessing = false;
                error = 'Could not process that image: $e';
              });
            }
          }

          void useSavedSignature(Map<String, dynamic> sig) {
            setDialogState(() {
              signatureBytes = sig['bytes'] as Uint8List;
              justImported = false;
              error = null;
            });
          }

          Future<void> saveCurrentSignature() async {
            final nameCtrl = TextEditingController(text: signedByName);
            final formKey = GlobalKey<FormState>();
            final label = await showDialog<String>(
              context: ctx,
              builder: (dCtx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: Text(
                  'Save Signature',
                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
                ),
                content: Form(
                  key: formKey,
                  child: TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Label (e.g. your name) *',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dCtx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(dCtx, nameCtrl.text.trim());
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            if (label == null || label.isEmpty || signatureBytes == null)
              return;
            await _saveSignatureToLibrary(label, signatureBytes!);
            final fresh = await _loadSavedSignatures();
            setDialogState(() {
              savedSignatures
                ..clear()
                ..addAll(fresh);
              justImported = false;
            });
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('Saved "$label" for next time.'),
                  backgroundColor: const Color(0xFF059669),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          Future<void> deleteSavedSignature(Map<String, dynamic> sig) async {
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (dCtx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: Text(
                  'Remove "${sig['name']}"?',
                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
                ),
                content: const Text(
                  'This saved signature will be removed from your library.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dCtx, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dCtx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.error,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            await _deleteSavedSignature(sig['id'] as String);
            setDialogState(
              () => savedSignatures.removeWhere((s) => s['id'] == sig['id']),
            );
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Container(
                  width: 480,
                  padding: const EdgeInsets.all(24),
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
                              Icons.draw_rounded,
                              color: Color(0xFF059669),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'E-Sign & Approve',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A202C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Import your signature image to digitally sign and approve this letter for $orgName.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      if (signatureBytes == null &&
                          savedSignatures.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'SAVED SIGNATURES',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF9AA5B4),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: savedSignatures.map((sig) {
                            return InkWell(
                              onTap: () => useSavedSignature(sig),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAFBFC),
                                  border: Border.all(
                                    color: const Color(0xFFE2E6EA),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.memory(
                                      sig['bytes'] as Uint8List,
                                      height: 28,
                                      width: 60,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      (sig['name'] as String),
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF374151),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    InkWell(
                                      onTap: () => deleteSavedSignature(sig),
                                      borderRadius: BorderRadius.circular(12),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 13,
                                          color: Color(0xFF9AA5B4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(color: Color(0xFFE2E6EA)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                'or import new',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(color: Color(0xFFE2E6EA)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ] else
                        const SizedBox(height: 18),
                      Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFBFC),
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: isProcessing
                            ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : signatureBytes == null
                            ? InkWell(
                                onTap: pickSignature,
                                borderRadius: BorderRadius.circular(10),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.upload_file_rounded,
                                        size: 28,
                                        color: Color(0xFF9AA5B4),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Import Signature Image',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Photo or scan of your signature on plain paper',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11,
                                          color: const Color(0xFF9AA5B4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.topCenter,
                                children: [
                                  // Live preview of the signature-over-printed-name stamp.
                                  Padding(
                                    padding: const EdgeInsets.only(top: 44),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 200,
                                          child: Divider(
                                            color: const Color(
                                              0xFF059669,
                                            ).withAlpha(120),
                                            thickness: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          signedByName,
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1A202C),
                                          ),
                                        ),
                                        Text(
                                          'Admin, Uprise',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 10,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    child: Image.memory(
                                      signatureBytes!,
                                      height: 56,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Positioned(
                                    right: 6,
                                    top: 6,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: Color(0xFF9AA5B4),
                                      ),
                                      tooltip: 'Remove',
                                      onPressed: () => setDialogState(
                                        () => signatureBytes = null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (signatureBytes != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: pickSignature,
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: Text(
                                'Replace image',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                            ),
                            if (justImported) ...[
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: saveCurrentSignature,
                                icon: const Icon(
                                  Icons.bookmark_add_outlined,
                                  size: 14,
                                ),
                                label: Text(
                                  'Save for next time',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  foregroundColor: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          error!,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: AdminColors.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: remarkCtrl,
                        maxLines: 2,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Remark (optional)',
                          hintText: 'e.g. Approved with noted conditions',
                          labelStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                          hintStyle: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF9AA5B4),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: Color(0xFF9AA5B4),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Stamped directly onto the submitted PDF\'s last page, next to the signature.',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: const Color(0xFF9AA5B4),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            // Approval always requires a signature now — this
                            // just closes the dialog without approving
                            // anything, it never skips signing.
                            onPressed: isSaving ? null : () => Navigator.pop(ctx),
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
                              style: GoogleFonts.beVietnamPro(fontSize: 13, color: const Color(0xFF374151)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: (isSaving || signatureBytes == null)
                                ? null
                                : () async {
                                    setDialogState(() => isSaving = true);
                                    // Let the spinner frame actually paint before the
                                    // heavy PDF rasterize/encode work below blocks the
                                    // UI thread — otherwise the button just freezes
                                    // with no feedback instead of visibly "working".
                                    await Future.delayed(Duration.zero);
                                    try {
                                      await _saveESignature(
                                        docId: docId,
                                        data: data,
                                        orgName: orgName,
                                        letterId: letterId,
                                        subject: subject,
                                        requestorName: requestorName,
                                        signedByName: signedByName,
                                        signatureBytes: signatureBytes!,
                                        remark: remarkCtrl.text.trim(),
                                      );

                                      if (ctx.mounted) Navigator.pop(ctx);
                                    } catch (e) {
                                      setDialogState(() => isSaving = false);
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text('Signing failed: $e'),
                                            backgroundColor: AdminColors.error,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              isSaving ? 'Signing…' : 'Sign & Approve',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
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
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveESignature({
    required String docId,
    required Map<String, dynamic> data,
    required String orgName,
    required String letterId,
    required String subject,
    required String requestorName,
    required String signedByName,
    required Uint8List signatureBytes,
    String remark = '',
  }) async {
    try {
      final signedAt = DateTime.now();

      // Stamp the signature onto the org's actual submitted PDF when
      // possible — only falls back to a standalone certificate when the
      // attachment isn't a real PDF (e.g. a Word doc or image), since
      // there's no way to "stamp" those page-for-page the same way.
      final attachmentBase64 = data['attachmentBase64']?.toString() ?? '';
      final attachmentName = (data['attachmentName'] ?? '').toString();
      final ext = attachmentName.contains('.')
          ? attachmentName.split('.').last.toLowerCase()
          : '';
      final isPdfAttachment = attachmentBase64.isNotEmpty && ext == 'pdf';

      final Uint8List pdfBytes;
      if (isPdfAttachment) {
        pdfBytes = await AdminExportPdf.stampSignatureOnPdf(
          originalPdfBytes: base64Decode(attachmentBase64),
          signatureBytes: signatureBytes,
          signedByName: signedByName,
          signedAt: signedAt,
          remark: remark,
        );
      } else {
        pdfBytes = await AdminExportPdf.generateSignedLetterPdf(
          letterId: letterId,
          subject: subject,
          orgName: orgName,
          requestorName: requestorName,
          signatureBytes: signatureBytes,
          signedByName: signedByName,
          signedAt: signedAt,
          remark: remark,
        );
      }

      await FirestoreCollections.letterRequests.doc(docId).update({
        'status': 'approved',
        'signedDocumentBase64': base64Encode(pdfBytes),
        'signedAt': Timestamp.fromDate(signedAt),
        if (remark.isNotEmpty) 'signRemark': remark,
        'signedBy': signedByName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await activity_log.ActivityLogger.log(
        action: 'E-signed and approved letter request from $orgName',
        module: 'Letter Request',
        severity: 'security',
        details: {
          'docId': docId,
          'letterId': letterId,
          'signedBy': signedByName,
        },
      );

      final orgId = (data['orgId'] ?? '').toString();
      if (orgId.isNotEmpty) {
        NotificationService.sendToOrgMembers(
          orgId: orgId,
          title: 'Letter request approved',
          body: 'Your letter request "$subject" has been approved and digitally signed.',
          type: 'letter_status',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Letter approved and digitally signed!'),
            backgroundColor: AdminColors.success,
            behavior: SnackBarBehavior.floating,
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
      rethrow;
    }
  }

  // ── Saved signature library ─────────────────────────────────────────
  // Lets an admin import + background-strip a signature once, save it
  // under a label, and reuse it on every future approval instead of
  // re-importing (and re-processing) the same image each time. Scoped to
  // the signed-in admin since the printed name under the signature is
  // identity-bound.
  Future<List<Map<String, dynamic>>> _loadSavedSignatures() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return [];
    try {
      final snap = await FirestoreCollections.savedSignatures
          .where('createdBy', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {
          'id': d.id,
          'name': (data['name'] ?? 'Signature').toString(),
          'bytes': base64Decode((data['signatureBase64'] ?? '').toString()),
        };
      }).toList();
    } catch (e) {
      debugPrint('Failed to load saved signatures: $e');
      return [];
    }
  }

  Future<void> _saveSignatureToLibrary(String name, Uint8List bytes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await FirestoreCollections.savedSignatures.add({
      'name': name,
      'signatureBase64': base64Encode(bytes),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteSavedSignature(String id) async {
    await FirestoreCollections.savedSignatures.doc(id).delete();
  }

  void _showViewDialog(Map<String, dynamic> data, String docId) {
    final status = (data['status'] ?? 'pending').toString();
    final timestamp = data['timestamp'] as Timestamp?;
    final date = timestamp != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toDate())
        : 'Unknown';
    final hasAttachment =
        data['attachmentBase64'] != null &&
        data['attachmentBase64'].toString().isNotEmpty;
    final fileName = data['attachmentName'] ?? 'attachment';
    final revisionNote = data['revisionNote'];
    final message = data['message'];
    final orgId = data['orgId'] ?? '';
    final orgName = data['orgName'] ?? 'Unknown';
    final letterId = data['letterId'] ?? 'N/A';
    final subject = data['subject'] ?? 'No subject';
    // Requestor – could be a specific person's name or the org name
    final requestor = data['requestedBy'] ?? data['submittedBy'] ?? orgName;

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<String>(
        future: _fetchOrgLogo(orgId),
        builder: (context, logoSnapshot) {
          final logoUrl = logoSnapshot.data ?? '';

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Container(
              width: 600,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFAF5),
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─── HEADER ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AdminColors.primaryDark, AdminColors.primaryDark.withAlpha(225)],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withAlpha(70)),
                          ),
                          child: const Icon(
                            Icons.mail_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      letterId,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _buildStatusBadge(status),
                                ],
                              ),
                              Text(
                                subject,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
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

                  // ─── BODY ────────────────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Organization card ────────────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E6EA),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFE2E6EA),
                                    ),
                                  ),
                                  child: logoUrl.isNotEmpty
                                      ? ClipOval(
                                          child: Image.network(
                                            logoUrl,
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _defaultAvatar(),
                                          ),
                                        )
                                      : _defaultAvatar(),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        orgName,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1A202C),
                                        ),
                                      ),
                                      if (data['orgEmail'] != null &&
                                          data['orgEmail']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                          data['orgEmail'].toString(),
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 12,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Request Details ──────────────────────────
                          _sectionLabel(
                            'Request Details',
                            icon: Icons.info_outline_rounded,
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E6EA),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _detailItem(
                                        'Requestor',
                                        requestor,
                                        Icons.person_outline_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _detailItem(
                                        'Date Submitted',
                                        date,
                                        Icons.calendar_today_outlined,
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
                                        'Letter ID',
                                        letterId,
                                        Icons.numbers_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _detailItem(
                                        'Subject',
                                        subject,
                                        Icons.subject_rounded,
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
                                        (data['schoolYear'] ?? '').toString().isNotEmpty
                                            ? data['schoolYear'].toString()
                                            : '—',
                                        Icons.school_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _detailItem(
                                        'Semester',
                                        (data['semester'] ?? '').toString().isNotEmpty
                                            ? data['semester'].toString()
                                            : '—',
                                        Icons.date_range_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Message ──────────────────────────────────
                          if (message != null &&
                              message.toString().isNotEmpty) ...[
                            _sectionLabel(
                              'Message',
                              icon: Icons.message_outlined,
                            ),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE2E6EA),
                                ),
                              ),
                              child: Text(
                                message.toString(),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF374151),
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // ── Revision notes ──────────────────────────
                          if (revisionNote != null &&
                              revisionNote.toString().isNotEmpty) ...[
                            _sectionLabel(
                              'Revision Notes',
                              icon: Icons.edit_note_rounded,
                            ),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AdminColors.info.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AdminColors.info.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                revisionNote.toString(),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF1A202C),
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // ── Attachment ──────────────────────────────
                          if (hasAttachment) ...[
                            _sectionLabel(
                              'Attachment',
                              icon: Icons.attach_file_rounded,
                            ),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE2E6EA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AdminColors.primaryDark
                                          .withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _getFileIcon(fileName),
                                      color: AdminColors.primaryDark,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        if (data['attachmentSize'] != null)
                                          Text(
                                            data['attachmentSize'].toString(),
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _viewAttachment(data),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 14,
                                    ),
                                    label: Text(
                                      'View',
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
                            const SizedBox(height: 20),
                          ],

                          // ── Signed Certificate ──────────────────────
                          if (data['signedDocumentBase64'] != null &&
                              data['signedDocumentBase64']
                                  .toString()
                                  .isNotEmpty) ...[
                            _sectionLabel(
                              'Digitally Signed',
                              icon: Icons.verified_rounded,
                            ),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF059669,
                                ).withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFF059669,
                                  ).withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF059669,
                                      ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.verified_rounded,
                                      color: Color(0xFF059669),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Signed Approval Certificate',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF1A202C),
                                          ),
                                        ),
                                        if (data['signedAt'] != null)
                                          Text(
                                            'Signed on ${DateFormat('MMM dd, yyyy').format((data['signedAt'] as Timestamp).toDate())}',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                        if (data['signedBy'] != null)
                                          Text(
                                            'By ${data['signedBy']}',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _viewSignedCertificate(data),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 14,
                                    ),
                                    label: Text(
                                      'View',
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
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ─── FOOTER ──────────────────────────────────────────
                  if (status == 'pending' ||
                      status == 'revision' ||
                      status == 'resubmitted')
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFEDF0F3)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmRejectLetter(docId, orgName);
                              },
                              icon: const Icon(Icons.cancel_rounded, size: 15),
                              label: Text(
                                'Reject',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminColors.error,
                                side: const BorderSide(
                                  color: AdminColors.error,
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
                              onPressed: () {
                                Navigator.pop(ctx);
                                _requestRevision(data, docId);
                              },
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                size: 15,
                              ),
                              label: Text(
                                'Revise',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminColors.info,
                                side: const BorderSide(color: AdminColors.info),
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
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _approveWithESignature(docId, data);
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
                                backgroundColor: AdminColors.success,
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
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFEDF0F3)),
                        ),
                      ),
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
        },
      ),
    );
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

  void _viewAttachment(Map<String, dynamic> data) {
    final base64 = data['attachmentBase64'];
    if (base64 == null || base64.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attachment found'),
          backgroundColor: AdminColors.error,
        ),
      );
      return;
    }
    _openFileFromBase64(base64, data['attachmentName'] ?? 'attachment');
  }

  void _viewSignedCertificate(Map<String, dynamic> data) {
    final base64 = data['signedDocumentBase64'];
    if (base64 == null || base64.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No signed certificate found'),
          backgroundColor: AdminColors.error,
        ),
      );
      return;
    }
    final letterId = (data['letterId'] ?? 'letter').toString();
    _openFileFromBase64(base64, '$letterId-signed.pdf');
  }

  Future<void> _openFileFromBase64(String base64String, String fileName) async {
    try {
      Uint8List bytes = base64Decode(base64String);
      if (bytes.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Empty file'),
              backgroundColor: AdminColors.error,
            ),
          );
        return;
      }

      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final mime = _getMimeTypeFromExtension(ext);

      if (mime.startsWith('text/')) {
        final content = utf8.decode(bytes);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(fileName),
              content: Container(
                width: 500,
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: GoogleFonts.beVietnamPro(fontSize: 12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    platform_file_utils.saveBytesToTempAndOpen(
                      bytes,
                      fileName,
                      mimeType: mime,
                    );
                  },
                  child: const Text('Download'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mime.startsWith('image/')) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      fileName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                  OverflowBar(
                    spacing: 8,
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          platform_file_utils.saveBytesToTempAndOpen(
                            bytes,
                            fileName,
                            mimeType: mime,
                          );
                        },
                        child: const Text('Download'),
                      ),
                    ],
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
      debugPrint('Error opening file: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: AdminColors.error,
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
}

// ============ STAT CARD ============
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8ECF0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
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
      ),
    );
  }
}

// ============ FILTER DROPDOWN ============
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

// ============ EXPORT BUTTON ============
class _ExportButton extends StatelessWidget {
  final String statusFilter, searchTerm;
  const _ExportButton({required this.statusFilter, required this.searchTerm});

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) => _doExport(context, choice),
    );
  }

  Future<void> _doExport(BuildContext context, String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var snap = await FirestoreCollections.letterRequests
          .orderBy('timestamp', descending: true)
          .get();
      var docs = snap.docs;
      if (statusFilter != 'All') {
        final fv = statusFilter == 'Needs Revision'
            ? 'revision'
            : statusFilter.toLowerCase();
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>?;
          return (data?['status'] ?? '').toString().toLowerCase() == fv;
        }).toList();
      }
      if (searchTerm.isNotEmpty) {
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>?;
          final name = (data?['orgName'] ?? '').toString().toLowerCase();
          final subject = (data?['subject'] ?? '').toString().toLowerCase();
          final message = (data?['message'] ?? '').toString().toLowerCase();
          return name.contains(searchTerm) ||
              subject.contains(searchTerm) ||
              message.contains(searchTerm);
        }).toList();
      }
      if (docs.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No data to export.')),
        );
        return;
      }

      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      if (format == 'csv') {
        final buffer = StringBuffer();
        buffer.writeln(
          'Letter ID,Organization,Subject,Message,Status,Date Submitted',
        );
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>?;
          final date =
              (d?['timestamp'] as Timestamp?)?.toDate().toString().substring(
                0,
                10,
              ) ??
              '';
          final message = (d?['message'] ?? '').toString();
          String escape(String value) => '"${value.replaceAll('"', '""')}"';
          buffer.writeln(
            [
              escape(d?['letterId'] ?? ''),
              escape(d?['orgName'] ?? ''),
              escape(d?['subject'] ?? ''),
              escape(message),
              escape(d?['status'] ?? ''),
              escape(date),
            ].join(','),
          );
        }
        final fileName = 'letter_requests_$now.csv';
        await AdminExportUtil.saveText(
          buffer.toString(),
          fileName,
          mimeType: 'text/csv',
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Download started: $fileName')),
        );
      } else if (format == 'pdf') {
        final rows = docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>?;
          final date =
              (d?['timestamp'] as Timestamp?)?.toDate().toString().substring(
                0,
                10,
              ) ??
              '';
          return [
            d?['letterId'] ?? '',
            d?['orgName'] ?? '',
            d?['subject'] ?? '',
            d?['message'] ?? '',
            d?['status'] ?? '',
            date,
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'Letter Requests Report',
          headers: const [
            'Letter ID',
            'Organization',
            'Subject',
            'Message',
            'Status',
            'Date Submitted',
          ],
          rows: rows,
        );
        final fileName = 'letter_requests_$now.pdf';
        await AdminExportUtil.saveBytes(
          pdfBytes,
          fileName,
          mimeType: 'application/pdf',
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Download started: $fileName')),
        );
      } else {
        throw UnsupportedError('Unsupported export format: $format');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AdminColors.error,
        ),
      );
    }
  }
}

// ============ ACTION ICON BUTTON ============
// Compact colored chip — matches the icon actions in org_event_proposals.dart
// / organization_management.dart / student_accounts.dart / adviser_roles.dart
// / event_proposals.dart, instead of a bare unstyled icon.
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

// ============ PAGE BUTTON ============
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AdminColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive ? null : Border.all(color: const Color(0xFFE4E8EF)),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AdminColors.primaryDark.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          '$page',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
