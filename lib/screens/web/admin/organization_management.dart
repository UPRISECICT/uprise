// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, library_private_types_in_public_api, use_build_context_synchronously, unused_element_parameter, prefer_final_fields

import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'export_excel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/file_validation.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/stat_cards.dart';

// ============ GLOBAL CONTEXT FOR SNACKBAR ============
final GlobalKey<ScaffoldMessengerState> globalMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
BuildContext? globalContext;

// ============ ACTIVITY LOGGER ============
class ActivityLogger {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> log({
    required String action,
    required String module,
    String severity = 'info',
    Map<String, dynamic>? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email ?? 'Unknown User';
    await _firestore.collection('activity_logs').add({
      'user': userName,
      'action': action,
      'module': module,
      'severity': severity,
      'timestamp': FieldValue.serverTimestamp(),
      'ipAddress': '',
      'details': details,
    });
  }
}

// ============ DATA MODELS ============
class Officer {
  final String id;
  final String name;
  final String position;
  final String email;
  Officer({
    required this.id,
    required this.name,
    required this.position,
    required this.email,
  });
  factory Officer.fromMap(Map<String, dynamic> map) => Officer(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    position: map['position'] ?? '',
    email: map['email'] ?? '',
  );
}

class Adviser {
  final String name;
  final String title;
  final String email;
  final String phone;
  final String type;

  Adviser({
    required this.name,
    required this.title,
    required this.email,
    required this.phone,
    this.type = 'faculty',
  });

  factory Adviser.fromMap(Map<String, dynamic> map) => Adviser(
    name: map['name'] ?? '',
    title: map['title'] ?? '',
    email: map['email'] ?? '',
    phone: map['phone'] ?? '',
    type: (map['type'] ?? 'faculty').toString(),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'title': title,
    'email': email,
    'phone': phone,
    'type': type,
  };

  Adviser copyWith({
    String? name,
    String? title,
    String? email,
    String? phone,
    String? type,
  }) => Adviser(
    name: name ?? this.name,
    title: title ?? this.title,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    type: type ?? this.type,
  );

  bool get isStudentAdviser => type == 'student';
}

class Organization {
  final String id;
  final String name;
  final String shortName;
  final String type;
  final String description;
  final String adviserName;
  final String adviserTitle;
  final String adviserEmail;
  final String adviserPhone;
  final String orgEmail;
  final String logoUrl;
  final String status;
  final DateTime? createdAt;
  final List<String> categories;
  final List<Officer> officers;
  final List<Adviser> advisers;
  final String adviserPhotoUrl;
  final String facebook;
  final String instagram;
  final String twitter;
  final String gmail;

  Organization({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    required this.description,
    required this.adviserName,
    required this.adviserTitle,
    required this.adviserEmail,
    required this.adviserPhone,
    this.orgEmail = '',
    required this.logoUrl,
    required this.status,
    this.createdAt,
    required this.categories,
    required this.officers,
    this.advisers = const [],
    this.adviserPhotoUrl = '',
    this.facebook = '',
    this.instagram = '',
    this.twitter = '',
    this.gmail = '',
  });
}

// ============ SHARED DESIGN TOKENS ============
class _DS {
  static const double radiusSm = 8;
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
      color: AdminColors.darkGray,
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
                    style: labelTextStyle.copyWith(color: AdminColors.error),
                  ),
                ],
              ),
            )
          : null,
      labelText: required ? null : label,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: AdminColors.darkGray)
          : null,
      labelStyle: labelTextStyle,
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: AdminColors.mediumGray,
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.mediumGray, width: 1),
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
    );
  }
}

// ============ SHARED WIDGETS ============
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
        Expanded(child: Divider(color: AdminColors.mediumGray, thickness: 1)),
      ],
    ),
  );
}

Widget _fieldGroup(List<Widget> fields) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      border: Border.all(color: const Color(0xFFE8ECF0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields.expand((f) => [f, const SizedBox(height: 12)]).toList()
        ..removeLast(),
    ),
  );
}

Widget _statusBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'active': _BadgeStyle(
      const Color(0xFFECFDF5),
      const Color(0xFF059669),
      'ACTIVE',
    ),
    'archived': _BadgeStyle(
      const Color(0xFFF3F4F6),
      const Color(0xFF6B7280),
      'ARCHIVED',
    ),
  };
  final s = styles[status.toLowerCase()] ?? styles['archived']!;
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

// Same color-per-category convention as event_calendar.dart's
// _categoryColors — every org TYPE used to render in one flat
// AdminColors.primaryDark tint, so a Student Government row read
// identically to a Sports Organization row in the table.
const Map<String, Color> _orgTypeBadgeColors = {
  'Academic Organization': Color(0xFF6366F1),
  'Student Government': Color(0xFF2563EB),
  'Special Interest Group': Color(0xFF06B6D4),
  'Cultural Organization': Color(0xFFD946EF),
  'Sports Organization': Color(0xFF14B8A6),
};

Color _orgTypeBadgeColor(String type) =>
    _orgTypeBadgeColors[type] ?? const Color(0xFF6B7280);

// Wraps the org type in a highlighted chip instead of plain text — same
// pattern as the category chip in org_event_proposals.dart.
Widget _typeBadge(String type) {
  if (type.isEmpty) {
    return Text(
      '—',
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        color: const Color(0xFFD1D5DB),
      ),
    );
  }
  final color = _orgTypeBadgeColor(type);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      type,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

// ============ MAIN ORGANIZATION MANAGEMENT WIDGET ============
class OrganizationManagement extends StatefulWidget {
  const OrganizationManagement({super.key});

  @override
  _OrganizationManagementState createState() => _OrganizationManagementState();
}

class _OrganizationManagementState extends State<OrganizationManagement> {
  String _statusFilter = 'Active';
  String _typeFilter = 'All Types';
  int _currentPage = 1;
  static const int _pageSize = 10;
  final TextEditingController _searchController = TextEditingController();

  // Created once, not constructed inline in build() — the table/stats
  // methods that use these are called on every rebuild (search, filter
  // changes, pagination), so building a fresh .snapshots() there each time
  // was re-subscribing to Firestore from scratch on every keystroke.
  late final Stream<QuerySnapshot> _orgsStream = FirebaseFirestore.instance
      .collection('organizations')
      .snapshots();
  late final Stream<QuerySnapshot> _orgsOrderedStream = FirebaseFirestore
      .instance
      .collection('organizations')
      .orderBy('createdAt', descending: true)
      .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final List<String> _orgTypes = [
    'All Types',
    'Academic Organization',
    'Student Government',
    'Special Interest Group',
    'Cultural Organization',
    'Sports Organization',
  ];

  @override
  void initState() {
    super.initState();
    globalContext = context;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: _buildOrganizationList(isMobile, isTablet),
    );
  }

  Widget _buildOrganizationList(bool isMobile, bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatsRow(isMobile, isTablet),
        _buildToolbar(isMobile, isTablet),
        const SizedBox(height: 16),
        Expanded(child: _buildTable(isMobile, isTablet)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _orgsStream,
      builder: (context, snapshot) {
        int total = 0, active = 0, archived = 0;
        if (snapshot.hasData) {
          total = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final status = data['status'] ?? 'active';
            switch (status) {
              case 'active':
                active++;
                break;
              case 'archived':
                archived++;
                break;
            }
          }
        }

        final cards = [
          StatCard(
            adminLayout: true,
            label: 'Total Organizations',
            value: '$total',
            icon: Icons.business_center_rounded,
            color: AdminColors.primaryDark,
            onTap: () => setState(() {
              _statusFilter = 'All';
              _currentPage = 1;
            }),
          ),
          StatCard(
            adminLayout: true,
            label: 'Active',
            value: '$active',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF059669),
            onTap: () => setState(() {
              _statusFilter = 'Active';
              _currentPage = 1;
            }),
          ),
          StatCard(
            adminLayout: true,
            label: 'Archived',
            value: '$archived',
            icon: Icons.archive_rounded,
            color: const Color(0xFF6B7280),
            onTap: () => setState(() {
              _statusFilter = 'Archived';
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

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search organization…',
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

    final filterActions = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterDropdown(
          value: _statusFilter,
          items: ['All', 'Active', 'Archived'],
          hint: 'Status',
          icon: Icons.tune_rounded,
          onChanged: (v) => setState(() {
            _statusFilter = v!;
            _currentPage = 1;
          }),
        ),
        _FilterDropdown(
          value: _typeFilter,
          items: _orgTypes,
          hint: 'Type',
          icon: Icons.category_rounded,
          onChanged: (v) => setState(() {
            _typeFilter = v!;
            _currentPage = 1;
          }),
        ),
        _ExportButton(
          statusFilter: _statusFilter,
          typeFilter: _typeFilter,
          searchTerm: _searchController.text.trim(),
        ),
        _PrimaryButton(
          label: 'Create Organization',
          icon: Icons.add_rounded,
          onPressed: _showCreateOrganizationDialog,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 10),
                filterActions,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 10),
                filterActions,
              ],
            ),
    );
  }

  Widget _buildTable(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _orgsOrderedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var docs = snapshot.data!.docs;
        if (_statusFilter != 'All') {
          docs = docs.where((d) {
            final status =
                (d.data() as Map)['status']?.toString().toLowerCase() ?? '';
            return status == _statusFilter.toLowerCase();
          }).toList();
        }
        if (_typeFilter != 'All Types') {
          docs = docs.where((d) {
            final type =
                (d.data() as Map)['type']?.toString().toLowerCase() ?? '';
            return type == _typeFilter.toLowerCase();
          }).toList();
        }
        final searchTerm = _searchController.text.trim().toLowerCase();
        if (searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            final name = (data['name'] ?? '').toString().toLowerCase();
            final acronym = (data['shortName'] ?? '').toString().toLowerCase();
            final type = (data['type'] ?? '').toString().toLowerCase();
            return name.contains(searchTerm) ||
                acronym.contains(searchTerm) ||
                type.contains(searchTerm);
          }).toList();
        }

        final totalPages = docs.isEmpty ? 1 : (docs.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, docs.length);
        final pageDocs = docs.isEmpty ? [] : docs.sublist(start, end);

        if (isMobile || isTablet) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            child: docs.isEmpty
                ? _emptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: pageDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final data = pageDocs[i].data() as Map<String, dynamic>;
                      final org = _mapToOrg(pageDocs[i].id, data);
                      return _buildOrganizationCard(org);
                    },
                  ),
          );
        }

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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _headerCell('ORGANIZATION'),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _headerCell('ADVISERS'),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _headerCell('TYPE'),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _headerCell('STATUS'),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _headerCell('CREATED'),
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
              ),
              Expanded(
                child: docs.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        itemCount: pageDocs.length,
                        itemBuilder: (_, i) {
                          final data =
                              pageDocs[i].data() as Map<String, dynamic>;
                          final org = _mapToOrg(pageDocs[i].id, data);
                          return _buildOrganizationRow(
                            org,
                            i == pageDocs.length - 1,
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

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _emptyState() {
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
            child: Icon(
              Icons.corporate_fare_rounded,
              size: 40,
              color: AdminColors.mediumGray,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No organizations found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters or create a new organization.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AdminColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Organization _mapToOrg(String id, Map<String, dynamic> data) {
    final rawAdvisers = data['advisers'] as List?;
    List<Adviser> advisers = rawAdvisers != null
        ? rawAdvisers
              .map((e) => Adviser.fromMap(e as Map<String, dynamic>))
              .toList()
        : [];

    if (advisers.isEmpty && (data['adviserName'] ?? '').toString().isNotEmpty) {
      advisers = [
        Adviser(
          name: data['adviserName'] ?? '',
          title: data['adviserTitle'] ?? '',
          email: data['adviserEmail'] ?? '',
          phone: data['adviserPhone'] ?? '',
        ),
      ];
    }

    return Organization(
      id: id,
      name: data['name'] ?? '',
      shortName: data['shortName'] ?? '',
      type: data['type'] ?? '',
      description: data['description'] ?? '',
      adviserName: advisers.isNotEmpty
          ? advisers.first.name
          : (data['adviserName'] ?? 'No Adviser'),
      adviserTitle: advisers.isNotEmpty
          ? advisers.first.title
          : (data['adviserTitle'] ?? ''),
      adviserEmail: advisers.isNotEmpty
          ? advisers.first.email
          : (data['adviserEmail'] ?? ''),
      adviserPhone: advisers.isNotEmpty
          ? advisers.first.phone
          : (data['adviserPhone'] ?? ''),
      orgEmail: data['orgEmail'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      status: data['status'] ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      categories: List<String>.from(data['categories'] ?? []),
      officers:
          (data['officers'] as List?)
              ?.map((e) => Officer.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      adviserPhotoUrl: data['adviserPhotoUrl'] ?? '',
      facebook: data['facebook'] ?? '',
      instagram: data['instagram'] ?? '',
      twitter: data['twitter'] ?? '',
      gmail: data['gmail'] ?? '',
      advisers: advisers,
    );
  }

  Widget _buildOrganizationRow(Organization org, bool isLast) {
    final adviserSummary = org.advisers.isEmpty
        ? 'No Adviser'
        : org.advisers.map((a) => a.name).join(', ');
    final adviserEmailSummary = org.advisers.isEmpty
        ? ''
        : org.advisers.first.email +
              (org.advisers.length > 1
                  ? ' +${org.advisers.length - 1} more'
                  : '');

    return InkWell(
      onTap: () => _showViewOrganizationDialog(org),
      hoverColor: const Color(0xFFF8F9FB),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _OrgAvatar(logoUrl: org.logoUrl, name: org.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            org.name,
                            style: GoogleFonts.beVietnamPro(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: const Color(0xFF1A202C),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (org.shortName.isNotEmpty)
                            Text(
                              org.shortName,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: AdminColors.darkGray,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      adviserSummary,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF374151),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (adviserEmailSummary.isNotEmpty)
                      Text(
                        adviserEmailSummary,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: AdminColors.darkGray,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _typeBadge(org.type),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(org.status),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  org.createdAt != null ? _formatDate(org.createdAt!) : '—',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AdminColors.darkGray,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIconButton(
                      icon: Icons.visibility_outlined,
                      tooltip: 'View Details',
                      onTap: () => _showViewOrganizationDialog(org),
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 6),
                    _ActionIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: () => _showEditOrganizationDialog(org),
                      color: AdminColors.primaryDark,
                    ),
                    const SizedBox(width: 6),
                    _ActionIconButton(
                      icon: org.status == 'archived'
                          ? Icons.restore_rounded
                          : Icons.archive_outlined,
                      tooltip: org.status == 'archived' ? 'Restore' : 'Archive',
                      onTap: () => _toggleArchiveOrganization(org),
                      color: org.status == 'archived'
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationCard(Organization org) {
    final adviserSummary = org.advisers.isEmpty
        ? 'No Adviser'
        : org.advisers.map((a) => a.name).join(', ');
    final adviserEmailSummary = org.advisers.isEmpty
        ? ''
        : org.advisers.first.email +
              (org.advisers.length > 1
                  ? ' +${org.advisers.length - 1} more'
                  : '');

    return InkWell(
      onTap: () => _showViewOrganizationDialog(org),
      hoverColor: const Color(0xFFF8F9FB),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8ECF0)),
          boxShadow: _DS.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OrgAvatar(logoUrl: org.logoUrl, name: org.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                      ),
                      if (org.shortName.isNotEmpty)
                        Text(
                          org.shortName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: AdminColors.darkGray,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _statusBadge(org.status),
                          const SizedBox(width: 8),
                          _typeBadge(org.type),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Adviser',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              adviserSummary,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF334155),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (adviserEmailSummary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                adviserEmailSummary,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: AdminColors.darkGray,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    org.createdAt != null
                        ? _formatDate(org.createdAt!)
                        : 'Created date unavailable',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: AdminColors.darkGray,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _ActionIconButton(
                      icon: Icons.visibility_outlined,
                      tooltip: 'View Details',
                      onTap: () => _showViewOrganizationDialog(org),
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 6),
                    _ActionIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: () => _showEditOrganizationDialog(org),
                      color: AdminColors.primaryDark,
                    ),
                    const SizedBox(width: 6),
                    _ActionIconButton(
                      icon: org.status == 'archived'
                          ? Icons.restore_rounded
                          : Icons.archive_outlined,
                      tooltip: org.status == 'archived' ? 'Restore' : 'Archive',
                      onTap: () => _toggleArchiveOrganization(org),
                      color: org.status == 'archived'
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
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
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total organizations',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: AdminColors.darkGray,
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
                      color: AdminColors.darkGray,
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

  void _showCreateOrganizationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) =>
          _CreateOrganizationDialog(onCreated: () => setState(() {})),
    );
  }

  void _showEditOrganizationDialog(Organization org) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => _EditOrganizationDialog(
        organization: org,
        onUpdated: () => setState(() {}),
      ),
    );
  }

  void _showViewOrganizationDialog(Organization org) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => _ViewOrganizationDialog(
        organization: org,
        onEdit: () {
          Navigator.pop(ctx);
          _showEditOrganizationDialog(org);
        },
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _toggleArchiveOrganization(Organization org) async {
    final isArchived = org.status == 'archived';
    final newStatus = isArchived ? 'active' : 'archived';

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _ConfirmDialog(
        title: isArchived ? 'Restore Organization' : 'Archive Organization',
        message:
            'Are you sure you want to ${isArchived ? 'restore' : 'archive'} "${org.name}"?',
        confirmLabel: isArchived ? 'Restore' : 'Archive',
        confirmColor: isArchived
            ? const Color(0xFF059669)
            : AdminColors.primaryDark,
        icon: isArchived ? Icons.restore_rounded : Icons.archive_rounded,
        onConfirm: () async {
          await FirebaseFirestore.instance
              .collection('organizations')
              .doc(org.id)
              .update({'status': newStatus});

          // Archiving an org cascades to its adviser — an adviser's whole
          // reason for being active is the org they advise, so an archived
          // org shouldn't leave an "active" adviser role pointing at it.
          // Restoring an organization also restores the adviser roles that
          // were archived by this organization-level action.
          if (!isArchived) {
            final linkedRoles = await FirebaseFirestore.instance
                .collection('adviser_roles')
                .where('orgId', isEqualTo: org.id)
                .where('archived', isEqualTo: false)
                .get();
            if (linkedRoles.docs.isNotEmpty) {
              final batch = FirebaseFirestore.instance.batch();
              for (final doc in linkedRoles.docs) {
                batch.update(doc.reference, {
                  'archived': true,
                  'archivedByOrganization': true,
                });
              }
              await batch.commit();
            }
          } else {
            final linkedRoles = await FirebaseFirestore.instance
                .collection('adviser_roles')
                .where('orgId', isEqualTo: org.id)
                .where('archived', isEqualTo: true)
                .get();
            final rolesToRestore = linkedRoles.docs.where(
              // Null covers adviser roles archived by older versions of the
              // organization archive action, before the source flag existed.
              (doc) => doc.data()['archivedByOrganization'] != false,
            );
            if (rolesToRestore.isNotEmpty) {
              final batch = FirebaseFirestore.instance.batch();
              for (final doc in rolesToRestore) {
                batch.update(doc.reference, {
                  'archived': false,
                  'archivedByOrganization': false,
                });
              }
              await batch.commit();
            }
          }

          await ActivityLogger.log(
            action:
                '${isArchived ? 'Restored' : 'Archived'} organization: ${org.name}',
            module: 'Organizations',
            severity: isArchived ? 'info' : 'warning',
            details: {
              'orgId': org.id,
              'orgName': org.name,
              'newStatus': newStatus,
            },
          );
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${org.name} has been ${isArchived ? 'restored' : 'archived'}',
              ),
              backgroundColor: isArchived
                  ? const Color(0xFF059669)
                  : AdminColors.primaryDark,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);
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
      onSelected: (s) => onChanged(s),
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

// ============ EXPORT BUTTON WITH DOWNLOAD (CSV & PDF) ============
class _ExportButton extends StatelessWidget {
  final String statusFilter, typeFilter, searchTerm;
  const _ExportButton({
    required this.statusFilter,
    required this.typeFilter,
    required this.searchTerm,
  });

  Future<List<QueryDocumentSnapshot>> _getFilteredDocs() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('organizations')
        .orderBy('createdAt', descending: true)
        .get();
    var docs = snapshot.docs;
    final query = searchTerm.toLowerCase();

    if (statusFilter != 'All') {
      docs = docs.where((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        return data['status'] == statusFilter.toLowerCase();
      }).toList();
    }
    if (typeFilter != 'All Types') {
      docs = docs.where((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        return data['type'] == typeFilter;
      }).toList();
    }
    if (query.isNotEmpty) {
      docs = docs.where((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        return (data['name'] ?? '').toString().toLowerCase().contains(query) ||
            (data['shortName'] ?? '').toString().toLowerCase().contains(
              query,
            ) ||
            (data['adviserName'] ?? '').toString().toLowerCase().contains(
              query,
            );
      }).toList();
    }
    return docs;
  }

  Future<void> _exportCSV(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) async {
    final rows = docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final date = (d['createdAt'] as Timestamp?)?.toDate();
      final dateStr = date != null ? DateFormat('yyyy-MM-dd').format(date) : '';
      final advisers =
          (d['advisers'] as List?)
              ?.map((a) => (a['name'] ?? '').toString())
              .join('; ') ??
          (d['adviserName'] ?? '');
      return [
        (d['name'] ?? '').toString(),
        (d['shortName'] ?? '').toString(),
        (d['type'] ?? '').toString(),
        (d['status'] ?? '').toString(),
        advisers.toString(),
        (d['orgEmail'] ?? '').toString(),
        (d['description'] ?? '').toString(),
        dateStr,
      ];
    }).toList();
    final bytes = AdminExportExcel.generateStyledTable(
      title: 'Organizations',
      headers: const [
        'Organization Name',
        'Short Name',
        'Type',
        'Status',
        'Adviser(s)',
        'Org Email',
        'Description',
        'Date Created',
      ],
      rows: rows,
    );
    final fileName =
        'organizations_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';
    await AdminExportUtil.saveBytes(bytes, fileName, mimeType: xlsxMimeType);
  }

  Future<void> _exportPDF(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) async {
    try {
      final rows = docs.map<List<String>>((doc) {
        final d = doc.data() as Map<String, dynamic>? ?? {};
        final advisers = (d['advisers'] as List?)
            ?.map(
              (a) => ((a as Map<String, dynamic>?)?['name'] ?? '').toString(),
            )
            .where((name) => name.isNotEmpty)
            .join(', ');
        final adviserText = advisers != null && advisers.isNotEmpty
            ? advisers
            : (d['adviserName']?.toString() ?? 'No Adviser');
        return <String>[
          d['name']?.toString() ?? '',
          d['shortName']?.toString() ?? '',
          d['type']?.toString() ?? '',
          d['status']?.toString().toUpperCase() ?? '',
          adviserText,
        ];
      }).toList();

      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Organizations Report',
        headers: const [
          'Organization',
          'Acronym',
          'Type',
          'Status',
          'Adviser(s)',
        ],
        rows: rows,
        subtitle:
            'Bulacan State University - College of Information and Communications Technology (CICT)',
      );
      final fileName =
          'organizations_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await AdminExportUtil.saveBytes(
        pdfBytes,
        fileName,
        mimeType: 'application/pdf',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download started: $fileName'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      debugPrint('Export PDF failed: $e');
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

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) async {
        final docs = await _getFilteredDocs();
        if (docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No data to export.'),
              backgroundColor: AdminColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
          return;
        }
        if (choice == 'excel') {
          await _exportCSV(context, docs);
        } else if (choice == 'pdf') {
          await _exportPDF(context, docs);
        }
      },
    );
  }
}

// ============ PRIMARY BUTTON ============
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

// ============ ORGANIZATION AVATAR (COMPLETE FIX) ============
class _OrgAvatar extends StatelessWidget {
  final String logoUrl, name;
  const _OrgAvatar({required this.logoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: _buildImage(),
    );
  }

  Widget _buildImage() {
    if (logoUrl.isEmpty || logoUrl == 'null') {
      return _initials();
    }

    // Handle base64 data URIs
    if (logoUrl.startsWith('data:')) {
      try {
        final base64Str = logoUrl.split(',').last;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            base64Decode(base64Str),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _initials();
            },
          ),
        );
      } catch (_) {
        return _initials();
      }
    }

    String imageUrl = logoUrl;
    if (imageUrl.startsWith('http://')) {
      imageUrl = imageUrl.replaceFirst('http://', 'https://');
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _initials();
        },
      ),
    );
  }

  Widget _initials() {
    final parts = name.split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AdminColors.primaryDark,
        ),
      ),
    );
  }
}

// ============ ACTION ICON BUTTON ============
// Compact colored chip — same size/shape as the icon actions in
// org_event_proposals.dart (_IconChip), instead of the old 36×36
// mostly-neutral button that barely fit 3-in-a-row in the actions column.
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

// ============ PAGE BUTTONS ============
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

// ============ CONFIRM DIALOG ============
class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;
  final IconData icon;
  final Future<void> Function() onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.icon,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                    color: confirmColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: confirmColor, size: 20),
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
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await onConfirm();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
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
    );
  }
}

class _ViewOrganizationDialog extends StatelessWidget {
  final Organization organization;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  const _ViewOrganizationDialog({
    required this.organization,
    required this.onEdit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 640,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        // A soft warm cream instead of stark white — ties the body back
        // to the amber header instead of a flat, generic admin-form look.
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
                      Icons.open_in_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Organization Details',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          organization.name,
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
                    tooltip: 'Close',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Large Logo
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E6EA)),
                          ),
                          child: _buildLargeLogo(
                            organization.logoUrl,
                            organization.name,
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Right side: Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                organization.name,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A202C),
                                ),
                              ),
                              if (organization.shortName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  organization.shortName,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AdminColors.primaryDark,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _statusBadge(organization.status),
                                  _typeBadge(organization.type),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (organization.orgEmail.isNotEmpty)
                                _infoRow(
                                  Icons.email_outlined,
                                  organization.orgEmail,
                                ),
                              if (organization.createdAt != null)
                                _infoRow(
                                  Icons.calendar_today_rounded,
                                  DateFormat(
                                    'MMMM d, yyyy',
                                  ).format(organization.createdAt!),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionLabel(
                      'Description',
                      icon: Icons.description_rounded,
                    ),
                    Text(
                      organization.description.isNotEmpty
                          ? organization.description
                          : 'No description added yet.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: AdminColors.darkGray,
                        height: 1.6,
                      ),
                    ),
                    if (organization.categories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _sectionLabel('Categories', icon: Icons.label_rounded),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: organization.categories
                            .map((category) => _infoPill('', category))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _sectionLabel(
                      'Faculty Adviser(s)',
                      icon: Icons.school_rounded,
                    ),
                    if (organization.advisers.isEmpty)
                      Text(
                        'No adviser information available.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: AdminColors.darkGray,
                        ),
                      )
                    else
                      Column(
                        children: organization.advisers.map((adviser) {
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E6EA),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (organization.adviserPhotoUrl.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ClipOval(
                                      child: _buildOrgImageWidget(
                                        organization.adviserPhotoUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        adviser.name,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1A202C),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        adviser.title,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          color: AdminColors.darkGray,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _readOnlyDetail('Email', adviser.email),
                                      const SizedBox(height: 4),
                                      _readOnlyDetail('Phone', adviser.phone),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    if ([
                      organization.facebook,
                      organization.instagram,
                      organization.twitter,
                      organization.gmail,
                    ].any((v) => v.trim().isNotEmpty)) ...[
                      const SizedBox(height: 24),
                      _sectionLabel('Social Links', icon: Icons.link_rounded),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (organization.facebook.isNotEmpty)
                            _infoPill('Facebook', organization.facebook),
                          if (organization.instagram.isNotEmpty)
                            _infoPill('Instagram', organization.instagram),
                          if (organization.twitter.isNotEmpty)
                            _infoPill('Twitter/X', organization.twitter),
                          if (organization.gmail.isNotEmpty)
                            _infoPill('Gmail', organization.gmail),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onClose,
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
                      'Close',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(
                      'Edit',
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
    );
  }

  Widget _buildLargeLogo(String url, String name) {
    if (url.isEmpty || url == 'null') return _logoPlaceholder(name);
    if (url.startsWith('data:')) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.memory(
            base64Decode(url.split(',').last),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _logoPlaceholder(name),
          ),
        );
      } catch (_) {
        return _logoPlaceholder(name);
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _logoPlaceholder(name),
      ),
    );
  }

  Widget _logoPlaceholder(String name) {
    final parts = name.split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.beVietnamPro(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AdminColors.primaryDark,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AdminColors.primaryDark.withAlpha(150)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildOrgImageWidget(
  String url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (url.startsWith('data:')) {
    try {
      // Decodes at ~2x the actual display size instead of whatever
      // resolution the logo was uploaded at — this helper renders logos
      // in every org row of the table, so a full-resolution decode per
      // row was a real, compounding cost.
      return Image.memory(
        base64Decode(url.split(',').last),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: width != null ? (width * 2).round() : null,
        cacheHeight: height != null ? (height * 2).round() : null,
        errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
      );
    } catch (_) {
      return SizedBox(width: width, height: height);
    }
  }
  return Image.network(
    url,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
  );
}

Widget _infoPill(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E6EA)),
    ),
    child: Text(
      label.isNotEmpty ? '$label: $value' : value,
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        color: AdminColors.darkGray,
      ),
    ),
  );
}

Widget _readOnlyDetail(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label: ',
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF334155),
        ),
      ),
      Expanded(
        child: Text(
          value.isNotEmpty ? value : '—',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: AdminColors.darkGray,
            height: 1.5,
          ),
        ),
      ),
    ],
  );
}

// ============ SHARED FORM VALIDATORS ============
// Previously these fields only checked for non-empty, so garbage input like
// "asdasd" saved straight to Firestore as an org/adviser name or email.
final RegExp _emailFormatPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final RegExp _personNamePattern = RegExp(
  r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*(?: [A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*)+$",
);
final RegExp _orgShortNamePattern = RegExp(r'^[A-Za-z0-9]{2,12}$');

String? _validateEmailFormat(String? v, {required bool required}) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return required ? 'Required' : null;
  if (!_emailFormatPattern.hasMatch(value)) return 'Enter a valid email';
  return null;
}

String? _validatePersonName(String? v, {required bool required}) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return required ? 'Required' : null;
  if (!_personNamePattern.hasMatch(value)) {
    return 'Enter a full name (first and last)';
  }
  return null;
}

String? _validateOrgName(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Required';
  if (value.length < 3 || !RegExp(r'[A-Za-z]').hasMatch(value)) {
    return 'Enter a valid organization name';
  }
  return null;
}

String? _validateOrgShortName(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Required';
  if (!_orgShortNamePattern.hasMatch(value)) {
    return '2-12 letters/numbers, no spaces';
  }
  return null;
}

String? _validateOrgDescription(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Required';
  if (value.length < 10) return 'Please provide a bit more detail';
  return null;
}

// ============ ADVISER FORM WIDGET ============
class _AdviserForm extends StatefulWidget {
  final Adviser adviser;
  final int index;
  final bool canRemove;
  final ValueChanged<Adviser> onChanged;
  final VoidCallback onRemove;

  const _AdviserForm({
    required this.adviser,
    required this.index,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_AdviserForm> createState() => _AdviserFormState();
}

class _AdviserFormState extends State<_AdviserForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.adviser.name);
    _emailCtrl = TextEditingController(text: widget.adviser.email);
    _phoneCtrl = TextEditingController(text: widget.adviser.phone);
  }

  @override
  void didUpdateWidget(covariant _AdviserForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adviser != widget.adviser) {
      if (_nameCtrl.text != widget.adviser.name) {
        _nameCtrl.text = widget.adviser.name;
      }
      if (_emailCtrl.text != widget.adviser.email) {
        _emailCtrl.text = widget.adviser.email;
      }
      if (_phoneCtrl.text != widget.adviser.phone) {
        _phoneCtrl.text = widget.adviser.phone;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // Previously this field had no validator at all — any string, including
  // letters or an empty value for the required primary adviser, saved
  // straight to Firestore. Accepts digits, spaces, +, -, and parentheses,
  // with a minimum of 7 digits so a real phone number gets through but
  // "abcdefg" or "12" doesn't.
  String? _validateAdviserPhone(String? v, {required bool required}) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return required ? 'Required' : null;
    final digitCount = value.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(value) || digitCount < 7) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final validPositions = [
      'Dean',
      'Program Chair',
      'Department Head',
      'Coordinator',
      'Faculty',
    ];
    // Only warn when the title is a real, non-empty value that no longer
    // matches the known positions (e.g. old data saved before a position
    // was removed from the list) — a brand-new, untouched adviser has an
    // empty title, which isn't "invalid", just not chosen yet.
    final bool isKnownPosition = validPositions.contains(widget.adviser.title);
    final bool isStaleInvalid =
        widget.adviser.title.isNotEmpty && !isKnownPosition;
    final String? selectedValue = isKnownPosition ? widget.adviser.title : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Adviser ${widget.index + 1}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.primaryDark,
                ),
              ),
              if (widget.canRemove)
                Tooltip(
                  message: 'Remove Adviser',
                  waitDuration: const Duration(milliseconds: 400),
                  child: InkWell(
                    onTap: widget.onRemove,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 18,
                        color: AdminColors.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameCtrl,
            decoration: _DS.inputDecoration(
              'Full Name',
              hint: 'e.g., Dr. Juan dela Cruz',
              icon: Icons.badge_outlined,
              required: widget.index == 0,
            ),
            style: GoogleFonts.beVietnamPro(fontSize: 13),
            onChanged: (v) =>
                widget.onChanged(widget.adviser.copyWith(name: v)),
            validator: (v) =>
                _validatePersonName(v, required: widget.index == 0),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AnchoredDropdownField<String>(
                  value: selectedValue,
                  validator: (v) =>
                      widget.index == 0 && v == null ? 'Required' : null,
                  decoration: InputDecoration(
                    labelText: widget.index == 0 ? 'Position *' : 'Position',
                    hintText: 'Select position',
                    prefixIcon: Icon(
                      Icons.work_outline,
                      size: 18,
                      color: AdminColors.darkGray,
                    ),
                    labelStyle: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AdminColors.darkGray,
                    ),
                    hintStyle: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AdminColors.mediumGray,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FB),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      borderSide: BorderSide(
                        color: AdminColors.mediumGray,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      borderSide: const BorderSide(
                        color: Color(0xFFE2E6EA),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      borderSide: BorderSide(
                        color: AdminColors.primaryDark,
                        width: 1.5,
                      ),
                    ),
                  ),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF1A202C),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        isStaleInvalid
                            ? '⚠️ Invalid position, select a new one'
                            : 'Select position',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: isStaleInvalid
                              ? AdminColors.error
                              : AdminColors.darkGray,
                          fontStyle: isStaleInvalid
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                    ...validPositions.map((pos) {
                      return DropdownMenuItem<String>(
                        value: pos,
                        child: Text(pos),
                      );
                    }),
                  ],
                  onChanged: (newValue) {
                    widget.onChanged(
                      widget.adviser.copyWith(title: newValue ?? ''),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 480;
              if (useTwoColumns) {
                return Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emailCtrl,
                        decoration: _DS.inputDecoration(
                          'Email',
                          hint: 'e.g., jdelacruz@university.edu.ph',
                          icon: Icons.email_outlined,
                          required: widget.index == 0,
                        ),
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (v) =>
                            widget.onChanged(widget.adviser.copyWith(email: v)),
                        validator: (v) => _validateEmailFormat(
                          v,
                          required: widget.index == 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: _DS.inputDecoration(
                          'Phone Number',
                          hint: 'e.g., +63 912 345 6789',
                          icon: Icons.phone_outlined,
                        ),
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        keyboardType: TextInputType.phone,
                        onChanged: (v) =>
                            widget.onChanged(widget.adviser.copyWith(phone: v)),
                        validator: (v) => _validateAdviserPhone(
                          v,
                          required: widget.index == 0,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: _DS.inputDecoration(
                      'Email',
                      hint: 'e.g., jdelacruz@university.edu.ph',
                      icon: Icons.email_outlined,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (v) =>
                        widget.onChanged(widget.adviser.copyWith(email: v)),
                    validator: (v) =>
                        _validateEmailFormat(v, required: widget.index == 0),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: _DS.inputDecoration(
                      'Phone Number',
                      hint: 'e.g., +63 912 345 6789',
                      icon: Icons.phone_outlined,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    keyboardType: TextInputType.phone,
                    onChanged: (v) =>
                        widget.onChanged(widget.adviser.copyWith(phone: v)),
                    validator: (v) =>
                        _validateAdviserPhone(v, required: widget.index == 0),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============ CREATE ORGANIZATION DIALOG ============
class _CreateOrganizationDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateOrganizationDialog({super.key, required this.onCreated});

  @override
  _CreateOrganizationDialogState createState() =>
      _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<_CreateOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  final _orgEmailCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'Academic Organization';
  XFile? _logoXFile;
  Uint8List? _logoBytes;

  List<Adviser> _advisers = [
    Adviser(name: '', title: '', email: '', phone: ''),
  ];

  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _shortNameCtrl, _orgEmailCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          children: [
            _buildModalHeader(
              'Create New Organization',
              Icons.add_business_rounded,
            ),
            _buildStepIndicator(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: _step == 0 ? _buildStep1() : _buildStep2(),
                ),
              ),
            ),
            _buildModalFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHeader(String title, IconData icon) {
    return Container(
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 18,
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
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['Basic Information', 'Faculty Advisers'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final label = entry.value;
          final isActive = idx == _step;
          final isDone = idx < _step;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? AdminColors.primaryDark
                        : const Color(0xFFE2E6EA),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 14,
                          )
                        : Text(
                            '${idx + 1}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF9AA5B4),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? AdminColors.primaryDark
                        : const Color(0xFF9AA5B4),
                  ),
                ),
                if (idx < steps.length - 1) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Divider(
                      color: isDone
                          ? AdminColors.primaryDark
                          : const Color(0xFFE2E6EA),
                      thickness: 1.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Organization Logo', icon: Icons.image_rounded),
        Center(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E6EA),
                    width: 1.5,
                  ),
                ),
                child: _logoBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.memory(_logoBytes!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 32,
                            color: AdminColors.darkGray,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Upload Logo',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: AdminColors.darkGray,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Supported: PNG, JPEG, GIF, WEBP · Max size: '
            '${(FileValidation.defaultMaxImageBytes / (1024 * 1024)).toStringAsFixed(0)}MB',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              color: const Color(0xFF9AA5B4),
            ),
          ),
        ),
        const SizedBox(height: 24),

        _sectionLabel('Organization Details', icon: Icons.business_rounded),
        _fieldGroup([
          TextFormField(
            controller: _nameCtrl,
            decoration: _DS.inputDecoration(
              'Organization Name',
              hint: 'e.g., Society of Web Innovators and Tech Specialists',
              required: true,
            ),
            style: GoogleFonts.beVietnamPro(fontSize: 13),
            validator: _validateOrgName,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _shortNameCtrl,
                  decoration: _DS.inputDecoration(
                    'Acronym / Short Name',
                    hint: 'e.g., SWITS',
                    required: true,
                  ),
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  validator: _validateOrgShortName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnchoredDropdownField<String>(
                  value: _type,
                  decoration: _DS.inputDecoration(
                    'Organization Type',
                    required: true,
                  ),
                  validator: (v) => v == null ? 'Required' : null,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF1A202C),
                  ),
                  items:
                      [
                            'Academic Organization',
                            'Student Government',
                            'Special Interest Group',
                            'Cultural Organization',
                            'Sports Organization',
                          ]
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _orgEmailCtrl,
            decoration: _DS.inputDecoration(
              'Organization Email',
              hint: 'e.g., swits@university.edu.ph',
              icon: Icons.email_outlined,
              required: true,
            ),
            style: GoogleFonts.beVietnamPro(fontSize: 13),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => _validateEmailFormat(v, required: true),
          ),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: _DS.inputDecoration(
              'Organization Description',
              hint:
                  'Brief description of the organization\'s goals and activities...',
              required: true,
            ),
            style: GoogleFonts.beVietnamPro(fontSize: 13),
            validator: _validateOrgDescription,
          ),
        ]),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Advisers', icon: Icons.people_rounded),
        const SizedBox(height: 8),
        Text(
          'You may add up to 3 faculty advisers for this organization.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: AdminColors.darkGray,
          ),
        ),
        const SizedBox(height: 16),

        ..._advisers.asMap().entries.map((entry) {
          final idx = entry.key;
          final adviser = entry.value;
          return _AdviserForm(
            adviser: adviser,
            index: idx,
            canRemove: _advisers.length > 1,
            onChanged: (updated) => setState(() => _advisers[idx] = updated),
            onRemove: () => setState(() => _advisers.removeAt(idx)),
          );
        }),

        if (_advisers.length < 3)
          TextButton.icon(
            onPressed: () => setState(
              () => _advisers.add(
                Adviser(
                  name: '',
                  title: '',
                  email: '',
                  phone: '',
                  type: 'faculty',
                ),
              ),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
            label: Text(
              'Add Another Adviser',
              style: GoogleFonts.beVietnamPro(fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AdminColors.primaryDark,
            ),
          ),
      ],
    );
  }

  Widget _buildModalFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_step > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _step--),
              icon: const Icon(Icons.arrow_back_rounded, size: 15),
              label: Text(
                'Back',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF374151),
                ),
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
            )
          else
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
            onPressed: _isLoading ? null : _onNextOrCreate,
            icon: _isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _step == 0
                        ? Icons.arrow_forward_rounded
                        : Icons.check_rounded,
                    size: 16,
                  ),
            label: Text(
              _step == 0 ? 'Continue' : 'Create Organization',
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _onNextOrCreate() {
    if (!_formKey.currentState!.validate()) return;
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      _createOrganization();
    }
  }

  void _showFileError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AdminColors.error),
    );
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        final bytes = file.bytes;
        if (bytes != null) {
          final error = FileValidation.validateImageBytes(bytes);
          if (error != null) {
            _showFileError(error);
            return;
          }
          setState(() {
            _logoXFile = XFile.fromData(bytes, name: file.name);
            _logoBytes = bytes;
          });
        }
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 500,
      maxHeight: 500,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final error = FileValidation.validateImageBytes(bytes);
      if (error != null) {
        _showFileError(error);
        return;
      }
      setState(() {
        _logoXFile = picked;
        _logoBytes = bytes;
      });
    }
  }

  String _createLogoDataUri(Uint8List bytes, String fileName) {
    final lowerName = fileName.toLowerCase();
    String mimeType;

    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      mimeType = 'image/png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      mimeType = 'image/jpeg';
    } else if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      mimeType = 'image/gif';
    } else if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      mimeType = 'image/webp';
    } else if (lowerName.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (lowerName.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else if (lowerName.endsWith('.webp')) {
      mimeType = 'image/webp';
    } else {
      mimeType = 'image/jpeg';
    }

    final base64Data = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Data';
  }

  Future<String?> _checkDuplicateOrg(String name, String shortName) async {
    final byNameFuture = FirebaseFirestore.instance
        .collection('organizations')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    final byShortFuture = FirebaseFirestore.instance
        .collection('organizations')
        .where('shortName', isEqualTo: shortName)
        .limit(1)
        .get();

    final results = await Future.wait([byNameFuture, byShortFuture]);
    final byName = results[0];
    final byShort = results[1];

    if (byName.docs.isNotEmpty)
      return 'An organization named "$name" already exists.';
    if (byShort.docs.isNotEmpty)
      return 'An organization with acronym "$shortName" already exists.';
    return null;
  }

  Future<bool> _isEmailRegistered(String email) async {
    try {
      final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(
        email,
      );
      return methods.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return 'UPR-${List.generate(6, (_) => chars[random.nextInt(chars.length)]).join()}';
  }

  Future<bool> _sendCredentialsEmail({
    required String toEmail,
    required String orgName,
    required String recipientName,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost',
        },
        body: jsonEncode({
          'service_id': 'service_s3ke8zd',
          'template_id': 'template_t92k1um',
          'user_id': 'tmx47wQJmb1uMNUpr',
          'template_params': {
            'to_email': toEmail,
            'to_name': recipientName,
            'password': password,
            'org_name': orgName,
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Organization credentials email sent to $toEmail');
        return true;
      }

      debugPrint('❌ EmailJS error ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Failed to send organization credentials email: $e');
      return false;
    }
  }

  Future<void> _createOrganization() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final orgName = _nameCtrl.text.trim();
    final orgShortName = _shortNameCtrl.text.trim();
    final orgDesc = _descCtrl.text.trim();
    final orgEmail = _orgEmailCtrl.text.trim().toLowerCase();

    final validAdvisers = _advisers
        .where((a) => a.name.trim().isNotEmpty)
        .toList();

    try {
      final dupError = await _checkDuplicateOrg(orgName, orgShortName);
      if (dupError != null) {
        _showError(dupError);
        return;
      }

      if (orgEmail.isEmpty) {
        _showError('Organization email is required for portal login.');
        return;
      }
      if (await _isEmailRegistered(orgEmail)) {
        _showError('Email "$orgEmail" already has an account in the system.');
        return;
      }

      final String? logoUrl = _logoBytes != null
          ? _createLogoDataUri(_logoBytes!, _logoXFile?.name ?? 'logo')
          : null;
      final orgRef = FirebaseFirestore.instance
          .collection('organizations')
          .doc();
      final orgId = orgRef.id;
      final batch = FirebaseFirestore.instance.batch();

      final List<Map<String, dynamic>> adviserMaps = validAdvisers
          .map(
            (a) => {
              'name': a.name,
              'title': a.title,
              'email': a.email.trim().toLowerCase(),
              'phone': a.phone,
              'type': a.type.isNotEmpty ? a.type : 'faculty',
            },
          )
          .toList();

      final tempPassword = _generateTemporaryPassword();
      final List<Map<String, String>> createdAccounts = [
        {'email': orgEmail, 'name': orgName, 'password': tempPassword},
      ];

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
          email: orgEmail,
          password: tempPassword,
        );
      } on FirebaseAuthException catch (e) {
        await secondaryAuth.signOut();
        _showError('Failed to create organization login account: ${e.message}');
        return;
      }

      final uid = cred.user!.uid;
      await cred.user!.updateDisplayName(orgName);

      batch.set(FirebaseFirestore.instance.collection('users').doc(uid), {
        'uid': uid,
        'fullName': orgName,
        'name': orgName,
        'email': orgEmail,
        'role': 'org',
        'orgId': orgId,
        'organizationId': orgId,
        'organizationName': orgName,
        'mustChangePassword': true,
        'isFirstLogin': true,
        'needsPasswordChange': true,
        'firstLogin': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      });

      await secondaryAuth.signOut();

      final primaryAdviser = validAdvisers.isNotEmpty
          ? validAdvisers.first
          : Adviser(name: '', title: '', email: '', phone: '');

      batch.set(orgRef, {
        'id': orgId,
        'name': orgName,
        'shortName': orgShortName,
        'acronym': orgShortName,
        'type': _type,
        'description': orgDesc,
        'orgEmail': orgEmail,
        'logoUrl': logoUrl ?? '',
        'adviserId': '',
        'adviserName': primaryAdviser.name,
        'adviserEmail': primaryAdviser.email.trim().toLowerCase(),
        'adviserTitle': primaryAdviser.title,
        'adviserPhone': primaryAdviser.phone,
        'advisers': adviserMaps,
        'categories': [],
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'createdByEmail': FirebaseAuth.instance.currentUser?.email,
      });

      await batch.commit();

      // ✅ AUTO-CREATE ADVISER ROLE
      if (primaryAdviser.name.trim().isNotEmpty) {
        final existingRole = await FirebaseFirestore.instance
            .collection('adviser_roles')
            .where('orgId', isEqualTo: orgId)
            .where('archived', isEqualTo: false)
            .get();

        if (existingRole.docs.isEmpty) {
          await FirebaseFirestore.instance.collection('adviser_roles').add({
            'orgId': orgId,
            'orgName': orgName,
            'orgAbbrev': orgShortName,
            'orgTag': _type,
            'adviserName': primaryAdviser.name,
            'adviserEmail': primaryAdviser.email.trim().toLowerCase(),
            'adviserPhone': primaryAdviser.phone,
            'adviserRank': primaryAdviser.title.isNotEmpty
                ? primaryAdviser.title
                : 'Instructor',
            'president': '',
            'vicePresident': '',
            'secretary': '',
            'archived': false,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': FirebaseAuth.instance.currentUser?.uid,
          });

          debugPrint('✅ Auto-created adviser_role for organization: $orgName');
        }
      }

      final account = createdAccounts.first;
      _sendCredentialsEmail(
        toEmail: account['email']!,
        orgName: orgName,
        recipientName: orgName,
        password: account['password']!,
      ).then((sent) {
        if (!sent) {
          debugPrint('⚠️ Failed to send credentials email to $orgEmail');
        }
      });

      await ActivityLogger.log(
        action: 'Created new organization: $orgName',
        module: 'Organizations',
      );

      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Organization "$orgName" created! Credentials are being sent to $orgEmail.',
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      setState(() => _isLoading = false);
    }
  }
}

// ============ EDIT ORGANIZATION DIALOG ============
class _EditOrganizationDialog extends StatefulWidget {
  final Organization organization;
  final VoidCallback onUpdated;
  const _EditOrganizationDialog({
    super.key,
    required this.organization,
    required this.onUpdated,
  });

  @override
  _EditOrganizationDialogState createState() => _EditOrganizationDialogState();
}

class _EditOrganizationDialogState extends State<_EditOrganizationDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _shortCtrl, _orgEmailCtrl, _descCtrl;
  late String _type, _status;
  late List<Adviser> _advisers;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final org = widget.organization;
    _nameCtrl = TextEditingController(text: org.name);
    _shortCtrl = TextEditingController(text: org.shortName);
    _orgEmailCtrl = TextEditingController(text: org.orgEmail);
    _descCtrl = TextEditingController(text: org.description);
    _type = org.type;
    // Older records remain editable, but the form only exposes supported
    // organization states.
    _status = org.status.toLowerCase() == 'archived' ? 'archived' : 'active';
    _advisers = org.advisers.isNotEmpty
        ? List<Adviser>.from(org.advisers)
        : [
            Adviser(
              name: org.adviserName,
              title: org.adviserTitle,
              email: org.adviserEmail,
              phone: org.adviserPhone,
            ),
          ];
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _shortCtrl, _orgEmailCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 640,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
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
                      Icons.edit_outlined,
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
                          'Edit Organization',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.organization.name,
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
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                        'Organization Information',
                        icon: Icons.business_rounded,
                      ),
                      _fieldGroup([
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: _DS.inputDecoration(
                            'Organization Name',
                            required: true,
                          ),
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                          validator: _validateOrgName,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _shortCtrl,
                                decoration: _DS.inputDecoration(
                                  'Acronym / Short Name',
                                  required: true,
                                ),
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                                validator: _validateOrgShortName,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AnchoredDropdownField<String>(
                                value: _type,
                                decoration: _DS.inputDecoration(
                                  'Organization Type',
                                  required: true,
                                ),
                                validator: (v) => v == null ? 'Required' : null,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF1A202C),
                                ),
                                items:
                                    [
                                          'Academic Organization',
                                          'Student Government',
                                          'Special Interest Group',
                                          'Cultural Organization',
                                          'Sports Organization',
                                        ]
                                        .map(
                                          (t) => DropdownMenuItem(
                                            value: t,
                                            child: Text(t),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) => setState(() => _type = v!),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _orgEmailCtrl,
                                decoration: _DS.inputDecoration(
                                  'Organization Email',
                                  icon: Icons.email_outlined,
                                  required: true,
                                ),
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) =>
                                    _validateEmailFormat(v, required: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AnchoredDropdownField<String>(
                                value: _status,
                                decoration: _DS.inputDecoration(
                                  'Status',
                                  required: true,
                                ),
                                validator: (v) => v == null ? 'Required' : null,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF1A202C),
                                ),
                                items: ['active', 'archived']
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          s[0].toUpperCase() + s.substring(1),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() => _status = v!),
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          controller: _descCtrl,
                          maxLines: 3,
                          decoration: _DS.inputDecoration(
                            'Description',
                            required: true,
                          ),
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                          validator: _validateOrgDescription,
                        ),
                      ]),
                      const SizedBox(height: 24),

                      _sectionLabel('Advisers', icon: Icons.people_rounded),
                      const SizedBox(height: 8),
                      Text(
                        'You may add up to 3 faculty advisers for this organization.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: AdminColors.darkGray,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._advisers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final adviser = entry.value;
                        return _AdviserForm(
                          adviser: adviser,
                          index: idx,
                          canRemove: _advisers.length > 1,
                          onChanged: (updated) =>
                              setState(() => _advisers[idx] = updated),
                          onRemove: () =>
                              setState(() => _advisers.removeAt(idx)),
                        );
                      }),
                      if (_advisers.length < 3)
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _advisers.add(
                              Adviser(
                                name: '',
                                title: '',
                                email: '',
                                phone: '',
                                type: 'faculty',
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 16,
                          ),
                          label: Text(
                            'Add Another Adviser',
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AdminColors.primaryDark,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
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
                    onPressed: _isLoading ? null : _update,
                    icon: _isLoading
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
                      'Save Changes',
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
    );
  }

  Future<void> _update() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final validAdvisers = _advisers
          .where((a) => a.name.trim().isNotEmpty)
          .toList();
      final primaryAdviser = validAdvisers.isNotEmpty
          ? validAdvisers.first
          : Adviser(name: '', title: '', email: '', phone: '');

      final adviserMaps = validAdvisers.map((a) => a.toMap()).toList();

      final batch = FirebaseFirestore.instance.batch();

      batch.update(
        FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.organization.id),
        {
          'name': _nameCtrl.text.trim(),
          'shortName': _shortCtrl.text.trim(),
          'type': _type,
          'description': _descCtrl.text.trim(),
          'orgEmail': _orgEmailCtrl.text.trim().toLowerCase(),
          'status': _status,
          'adviserName': primaryAdviser.name,
          'adviserTitle': primaryAdviser.title,
          'adviserEmail': primaryAdviser.email,
          'adviserPhone': primaryAdviser.phone,
          'advisers': adviserMaps,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      final existingRoles = await FirebaseFirestore.instance
          .collection('adviser_roles')
          .where('orgId', isEqualTo: widget.organization.id)
          .get();
      if (existingRoles.docs.isNotEmpty) {
        batch.update(existingRoles.docs.first.reference, {
          'orgName': _nameCtrl.text.trim(),
          'orgAbbrev': _shortCtrl.text.trim(),
          'orgTag': _type,
          'adviserName': primaryAdviser.name,
          'adviserEmail': primaryAdviser.email,
          'adviserPhone': primaryAdviser.phone,
          'adviserRank': primaryAdviser.title,
        });
      }

      await batch.commit();
      await ActivityLogger.log(
        action:
            'Updated organization: ${widget.organization.name} → ${_nameCtrl.text.trim()}',
        module: 'Organizations',
      );

      widget.onUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Organization updated successfully.'),
            backgroundColor: const Color(0xFF059669),
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ============ ORGANIZATION DETAIL PAGE (FIXED FOR MOBILE) ============
class _OrganizationDetailPage extends StatefulWidget {
  final Organization organization;
  final VoidCallback onBack;
  const _OrganizationDetailPage({
    super.key,
    required this.organization,
    required this.onBack,
  });

  @override
  _OrganizationDetailPageState createState() => _OrganizationDetailPageState();
}

class _OrganizationDetailPageState extends State<_OrganizationDetailPage> {
  @override
  Widget build(BuildContext context) {
    final org = widget.organization;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: AdminColors.darkGray,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Organizations',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: AdminColors.darkGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AdminColors.mediumGray,
                ),
              ),
              Text(
                org.shortName.isNotEmpty ? org.shortName : org.name,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8ECF0)),
              boxShadow: _DS.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E6EA)),
                  ),
                  child: _buildDetailLogo(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              org.name,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A202C),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _statusBadge(org.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (org.shortName.isNotEmpty)
                        Text(
                          org.shortName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.primaryDark,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        org.type,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: AdminColors.darkGray,
                        ),
                      ),
                      if (org.orgEmail.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 14,
                              color: AdminColors.darkGray,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              org.orgEmail,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: AdminColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (org.createdAt != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: AdminColors.darkGray,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Created ${DateFormat('MMMM d, yyyy').format(org.createdAt!)}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: AdminColors.darkGray,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _detailCard(
                  icon: Icons.info_outline_rounded,
                  title: 'About the Organization',
                  child: Text(
                    org.description.isNotEmpty
                        ? org.description
                        : 'No description provided.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AdminColors.darkGray,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _detailCard(
                  icon: Icons.people_rounded,
                  title: 'Faculty Advisers',
                  child: org.advisers.isEmpty
                      ? Text(
                          'No adviser assigned.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: AdminColors.darkGray,
                          ),
                        )
                      : Column(
                          children:
                              org.advisers
                                  .map((a) => _adviserTile(a))
                                  .expand(
                                    (w) => [w, const SizedBox(height: 12)],
                                  )
                                  .toList()
                                ..removeLast(),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailLogo() {
    final logoUrl = widget.organization.logoUrl;

    if (logoUrl.isEmpty) {
      return _logoPlaceholder(widget.organization.name);
    }

    // Handle base64 data URIs
    if (logoUrl.startsWith('data:')) {
      try {
        final base64Str = logoUrl.split(',').last;
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.memory(
            base64Decode(base64Str),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _logoPlaceholder(widget.organization.name),
          ),
        );
      } catch (_) {
        return _logoPlaceholder(widget.organization.name);
      }
    }

    // Handle network URLs - ensure HTTPS
    String secureUrl = logoUrl;
    if (secureUrl.startsWith('http://')) {
      secureUrl = secureUrl.replaceFirst('http://', 'https://');
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        secureUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (_, __, ___) =>
            _logoPlaceholder(widget.organization.name),
      ),
    );
  }

  Widget _adviserTile(Adviser a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AdminColors.primaryDark.withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(
                  a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.primaryDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  if (a.title.isNotEmpty)
                    Text(
                      a.title,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: AdminColors.darkGray,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (a.email.isNotEmpty) ...[
          const SizedBox(height: 6),
          _adviserDetailRow(Icons.email_outlined, a.email),
        ],
        if (a.phone.isNotEmpty)
          _adviserDetailRow(Icons.phone_outlined, a.phone),
      ],
    );
  }

  Widget _logoPlaceholder(String name) {
    final parts = name.split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.beVietnamPro(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AdminColors.primaryDark,
        ),
      ),
    );
  }

  Widget _detailCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AdminColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _adviserDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AdminColors.darkGray),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
