// lib/screens/web/admin/adviser_roles.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import '../../../services/activity_logger.dart' as activity_log;
import 'export_util.dart';
import 'export_pdf.dart';
import 'export_excel.dart';
import '../../../theme/admin_theme.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/admin_stat_cards_row.dart';

// Helper for image handling
//
// Caches the decoded MemoryImage per data URL. Without this, every rebuild
// of the table (e.g. every keystroke in the search box, since that calls
// setState on the whole page) constructed a brand-new Uint8List via
// base64Decode and wrapped it in a new MemoryImage — and since MemoryImage
// equality is based on the byte-list object identity, no two of those were
// ever `==`, so Flutter's image cache could never recognize them as the
// same image. That meant every avatar/logo was fully re-decoded from
// scratch on every rebuild instead of decoded once and reused, which is
// exactly the kind of compounding cost that made typing in the search box
// or paginating feel laggy.
final Map<String, MemoryImage> _memoryImageCache = {};

ImageProvider _imageProviderFromUrl(String url) {
  if (url.startsWith('data:image')) {
    return _memoryImageCache.putIfAbsent(url, () {
      final base64Part = url.split(',').last;
      return MemoryImage(base64Decode(base64Part));
    });
  }
  return NetworkImage(url);
}

Map<String, dynamic> buildAdviserRolePayload({
  required String orgId,
  required String orgName,
  required String orgAbbrev,
  required String orgTag,
  required String adviserName,
  required String adviserEmail,
  required String adviserPhone,
  required String adviserRank,
  required String president,
  required String vicePresident,
  required String secretary,
  required bool archived,
}) {
  return <String, dynamic>{
    'orgId': orgId,
    'orgName': orgName,
    'orgAbbrev': orgAbbrev,
    'orgTag': orgTag,
    'adviserName': adviserName,
    'adviserEmail': adviserEmail,
    'adviserPhone': adviserPhone,
    'adviserRank': adviserRank,
    'president': president,
    'vicePresident': vicePresident,
    'secretary': secretary,
    'archived': archived,
  };
}

Map<String, dynamic> buildOrganizationAdviserPayload({
  required String adviserName,
  required String adviserEmail,
  required String adviserPhone,
  required String adviserTitle,
}) {
  return <String, dynamic>{
    'adviserName': adviserName,
    'adviserEmail': adviserEmail,
    'adviserPhone': adviserPhone,
    'adviserTitle': adviserTitle,
  };
}

Widget _buildImageWidget(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  // Decodes at ~2x the actual display size instead of full original
  // resolution — this helper renders avatars/logos in every table row, so
  // that was a real, compounding cost. ResizeImage wraps the provider since
  // the plain Image(image: ...) constructor has no cacheWidth/cacheHeight
  // shortcut (that's only on the Image.memory/.network/.asset constructors).
  ImageProvider provider = _imageProviderFromUrl(url);
  if (width != null || height != null) {
    provider = ResizeImage(
      provider,
      width: width != null ? (width * 2).round() : null,
      height: height != null ? (height * 2).round() : null,
    );
  }
  return Image(
    image: provider,
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
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final List<BoxShadow> cardShadow = [
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
                    style: labelTextStyle.copyWith(color: AdminColors.error),
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
Widget _sectionDivider(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: AdminColors.primaryDark),
          const SizedBox(width: 7),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AdminColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

class _RankBadge extends StatelessWidget {
  final String rank;
  const _RankBadge(this.rank);

  static Color colorOf(String rank) {
    switch (rank.toLowerCase()) {
      case 'senior':
        return const Color(0xFF2563EB);
      case 'junior':
        return const Color(0xFFFB923C);
      case 'professor':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF059669);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colorOf(rank);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Text(
        rank,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: c,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final String position;
  const _PositionBadge(this.position);

  static Color colorOf(String position) {
    switch (position.toLowerCase()) {
      case 'dean':
        return const Color(0xFF7C3AED);
      case 'program chair':
        return const Color(0xFF2563EB);
      case 'department head':
        return const Color(0xFFFB923C);
      case 'coordinator':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colorOf(position);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        position,
        style: GoogleFonts.beVietnamPro(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: c,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _OrgAvatar extends StatelessWidget {
  final String abbrev;
  final String? logoUrl;
  const _OrgAvatar(this.abbrev, {this.logoUrl});

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
    final label = abbrev.length > 2
        ? abbrev.substring(0, 2).toUpperCase()
        : abbrev.toUpperCase();
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AdminColors.primaryDark.withAlpha(26),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AdminColors.primaryDark,
        ),
      ),
    );
  }
}

// Compact colored chip — matches the icon actions in org_event_proposals.dart
// / organization_management.dart / student_accounts.dart, instead of a bare
// unstyled icon.
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
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

// ─────────────────────────────────────────────────────────────────────────────
// OrgModel with logo
// ─────────────────────────────────────────────────────────────────────────────
class OrgModel {
  final String id, name, abbrev, tag, logoUrl;
  const OrgModel({
    required this.id,
    required this.name,
    required this.abbrev,
    required this.tag,
    required this.logoUrl,
  });

  factory OrgModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OrgModel(
      id: doc.id,
      name: d['name'] ?? d['orgName'] ?? d['organizationName'] ?? '',
      abbrev:
          d['shortName'] ??
          d['abbrev'] ??
          d['abbreviation'] ??
          d['acronym'] ??
          '',
      tag: d['tag'] ?? d['department'] ?? d['type'] ?? '',
      logoUrl: d['logoUrl'] ?? '',
    );
  }
}

// Officer info for view dialog
class OfficerInfo {
  final String name;
  final String position;
  final String email;
  final String phone;
  final String photoUrl;

  const OfficerInfo({
    required this.name,
    required this.position,
    required this.email,
    required this.phone,
    required this.photoUrl,
  });

  factory OfficerInfo.fromMap(Map<String, dynamic> map) {
    return OfficerInfo(
      name: map['name'] ?? '',
      position: map['position'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────────────────────────────────────
class AdviserRoles extends StatefulWidget {
  const AdviserRoles({super.key});
  @override
  State<AdviserRoles> createState() => _AdviserRolesState();
}

class _AdviserRolesState extends State<AdviserRoles> {
  String _statusFilter = 'Active';
  int _currentPage = 1;
  static const int _pageSize = 10;
  final TextEditingController _searchController = TextEditingController();

  // Created once, not constructed inline in build() — the methods that use
  // these are called on every rebuild (search, filter changes,
  // pagination), so building a fresh .snapshots() there each time was
  // re-subscribing to Firestore from scratch on every keystroke. The table
  // needs the Active/Archived split to keep working when the filter
  // toggles, so both are cached and a getter just picks between them.
  late final Stream<QuerySnapshot> _archivedCountStream = FirebaseFirestore
      .instance
      .collection('adviser_roles')
      .where('archived', isEqualTo: true)
      .snapshots();
  late final Stream<QuerySnapshot> _activeAdvisersStream = FirebaseFirestore
      .instance
      .collection('adviser_roles')
      .where('archived', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots();
  late final Stream<QuerySnapshot> _archivedAdvisersStream = FirebaseFirestore
      .instance
      .collection('adviser_roles')
      .where('archived', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots();
  Stream<QuerySnapshot> get _advisersTableStream => _statusFilter == 'Archived'
      ? _archivedAdvisersStream
      : _activeAdvisersStream;

  // Export re-fetching the whole collection with a fresh `.get()` meant
  // re-downloading every doc's embedded base64 officer photos over again —
  // that's what made PDF/CSV export noticeably slower than other pages.
  // The table's own live streams already hold this data locally, so cache
  // the latest docs from each and have export read from here instead.
  List<QueryDocumentSnapshot> _cachedActiveAdviserDocs = [];
  List<QueryDocumentSnapshot> _cachedArchivedAdviserDocs = [];
  late final StreamSubscription _activeAdvisersCacheSub;
  late final StreamSubscription _archivedAdvisersCacheSub;

  List<OrgModel> _orgs = [];
  List<String> _adviserNames = [];
  bool _loadingMeta = true;
  bool _didInitialOfficerSync = false;
  int _totalAdvisers = 0;
  int _orgsWithoutAdviser = 0;
  late StreamSubscription _metaListener;
  late StreamSubscription _officersListener;
  late StreamSubscription _orgsListener;

  @override
  void initState() {
    super.initState();
    // Pre-warms the PDF font/logo fetch so it's already cached by the time
    // the admin clicks Export — otherwise that cost is paid on click and
    // the button appears to freeze.
    AdminExportPdf.warmUp();
    _loadMeta();
    _setupMetaListener();
    _setupOfficersListener();
    _setupOrgsListener();
    _activeAdvisersCacheSub = _activeAdvisersStream.listen(
      (snap) => _cachedActiveAdviserDocs = snap.docs,
    );
    _archivedAdvisersCacheSub = _archivedAdvisersStream.listen(
      (snap) => _cachedArchivedAdviserDocs = snap.docs,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _metaListener.cancel();
    _officersListener.cancel();
    _orgsListener.cancel();
    _activeAdvisersCacheSub.cancel();
    _archivedAdvisersCacheSub.cancel();
    super.dispose();
  }

  // Every Firestore .snapshots() stream replays the current state as its
  // first event the moment you subscribe. initState already fires an
  // explicit _loadMeta() call, so without `.skip(1)` here that first replay
  // duplicated the exact same work a second (or third/fourth, across all
  // three listeners) time in the first instant the page opens — a burst of
  // redundant reads that's the real reason everything felt laggy right when
  // this page was opened, settling down once the burst finished. Skipping
  // the replay means these listeners only react to genuine subsequent
  // changes, which is all they were ever meant to do.
  void _setupMetaListener() {
    _metaListener = FirebaseFirestore.instance
        .collection('adviser_roles')
        .snapshots()
        .skip(1)
        .listen((_) => _loadMeta());
  }

  void _setupOfficersListener() {
    _officersListener = FirebaseFirestore.instance
        .collectionGroup('officers')
        .snapshots()
        .skip(1)
        .listen((snapshot) {
          _loadOfficersForAllOrgs();
        });
  }

  // Picks up adviser/logo edits made directly on the organization (e.g. via
  // Organization Management) so the Adviser Role record reflects them
  // automatically instead of staying stuck with whatever was entered when
  // the role was first created.
  void _setupOrgsListener() {
    _orgsListener = FirebaseFirestore.instance
        .collection('organizations')
        .snapshots()
        .skip(1)
        .listen((snapshot) {
          _loadOfficersForAllOrgs();
        });
  }

  Future<void> _loadOfficersForAllOrgs() async {
    // Was awaiting one org at a time — for N orgs that's N sequential
    // round trips before anything on screen updates, which is exactly the
    // "long lag then it's fine" freeze. Firing them together cuts total
    // wait time from O(N * roundtrip) down to about one roundtrip.
    await Future.wait(_orgs.map((org) => _loadOfficersForOrg(org.id)));
    if (mounted) setState(() {});
  }

  Future<void> _loadOfficersForOrg(String orgId) async {
    try {
      // These three reads don't depend on each other — firing them together
      // instead of one at a time cuts this method's latency to roughly one
      // round trip instead of three, which matters since it runs for every
      // org in parallel on first load (see _loadOfficersForAllOrgs).
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('organizations').doc(orgId).get(),
        FirebaseFirestore.instance
            .collection('adviser_roles')
            .where('orgId', isEqualTo: orgId)
            .where('archived', isEqualTo: false)
            .get(),
        FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .collection('officers')
            .get(),
      ]);
      final orgDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final roleSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final officerSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;

      final orgData = orgDoc.data();
      final adviserPhotoUrl = (orgData?['adviserPhotoUrl'] ?? '').toString();
      final adviserName = (orgData?['adviserName'] ?? '').toString();
      final adviserEmail = (orgData?['adviserEmail'] ?? '').toString();
      final adviserPhone = (orgData?['adviserPhone'] ?? '').toString();
      final adviserTitle = (orgData?['adviserTitle'] ?? '').toString();

      final officers = <String, OfficerInfo>{};
      for (final doc in officerSnap.docs) {
        final data = doc.data();
        final officer = OfficerInfo.fromMap(data);

        final position = (data['position'] ?? '').toString().toLowerCase();
        if (position == 'president') {
          officers['president'] = officer;
        } else if (position == 'vice president') {
          officers['vicePresident'] = officer;
        } else if (position == 'secretary') {
          officers['secretary'] = officer;
        }
      }

      // Keep every adviser_roles doc for this org mirrored to the org's
      // current adviser/officer info (Organization Management is the
      // source of truth) — one batch commit instead of an awaited update
      // per doc, which was also re-fetching the same org doc and role
      // query a second time via a separate sync step.
      final batch = FirebaseFirestore.instance.batch();
      var hasWrites = false;
      for (final doc in roleSnap.docs) {
        final current = doc.data();
        final updates = <String, dynamic>{};
        // Only include fields that actually changed. `_setupMetaListener`
        // listens on this same `adviser_roles` collection, so an
        // unconditional write here — even one that re-sets identical
        // values — re-fires that listener, which calls _loadMeta(), which
        // calls back into this method for every org: a self-triggering
        // read/write loop that never settles and is what made this page
        // feel like it never finished loading.
        void setIfChanged(String field, String value) {
          if (value.isNotEmpty && current[field]?.toString() != value) {
            updates[field] = value;
          }
        }

        setIfChanged('adviserPhotoUrl', adviserPhotoUrl);
        setIfChanged('adviserName', adviserName);
        setIfChanged('adviserEmail', adviserEmail);
        setIfChanged('adviserPhone', adviserPhone);
        setIfChanged('adviserRank', adviserTitle);

        if (officers.containsKey('president')) {
          setIfChanged('president', officers['president']!.name);
          setIfChanged('presidentEmail', officers['president']!.email);
          setIfChanged('presidentPhone', officers['president']!.phone);
          setIfChanged('presidentPhotoUrl', officers['president']!.photoUrl);
        }
        if (officers.containsKey('vicePresident')) {
          setIfChanged('vicePresident', officers['vicePresident']!.name);
          setIfChanged('vicePresidentEmail', officers['vicePresident']!.email);
          setIfChanged('vicePresidentPhone', officers['vicePresident']!.phone);
          setIfChanged(
            'vicePresidentPhotoUrl',
            officers['vicePresident']!.photoUrl,
          );
        }
        if (officers.containsKey('secretary')) {
          setIfChanged('secretary', officers['secretary']!.name);
          setIfChanged('secretaryEmail', officers['secretary']!.email);
          setIfChanged('secretaryPhone', officers['secretary']!.phone);
          setIfChanged('secretaryPhotoUrl', officers['secretary']!.photoUrl);
        }

        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          hasWrites = true;
        }
      }
      if (hasWrites) await batch.commit();
    } catch (e) {
      debugPrint('Error loading officers for org $orgId: $e');
    }
  }

  Future<void> _loadMeta() async {
    setState(() => _loadingMeta = true);
    try {
      // Independent reads — fire together instead of one after another.
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('organizations').get(),
        FirebaseFirestore.instance
            .collection('adviser_roles')
            .where('archived', isEqualTo: false)
            .get(),
      ]);
      final orgSnap = results[0];
      final rolesSnap = results[1];
      final orgs = orgSnap.docs.map(OrgModel.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final validRoles = rolesSnap.docs.where((doc) {
        final d = doc.data();
        final orgId = (d['orgId'] ?? '').toString().trim();
        final orgName = (d['orgName'] ?? '').toString().trim();
        return orgId.isNotEmpty && orgName.isNotEmpty;
      }).toList();

      final namesSet = <String>{};
      final orgIdsWithAdviser = <String>{};
      for (final doc in validRoles) {
        final d = doc.data();
        final n = d['adviserName']?.toString().trim();
        if (n != null && n.isNotEmpty) namesSet.add(n);
        orgIdsWithAdviser.add((d['orgId'] ?? '').toString().trim());
      }
      final orgsWithoutAdviser = orgs
          .where((o) => !orgIdsWithAdviser.contains(o.id))
          .length;

      setState(() {
        _orgs = orgs;
        _adviserNames = namesSet.toList()..sort();
        _totalAdvisers = validRoles.length;
        _orgsWithoutAdviser = orgsWithoutAdviser;
        _loadingMeta = false;
      });

      // Only sync officer/adviser data from `organizations` into every
      // `adviser_roles` doc on the very first load. `_loadMeta` itself is
      // re-run on every add/edit/archive of an adviser role (see
      // `_setupMetaListener`), so doing a full N-org resync here on every
      // call meant adding or archiving a single adviser re-fetched and
      // re-wrote data for every other org too. Actual org/officer changes
      // are already covered by `_setupOfficersListener`/`_setupOrgsListener`.
      if (!_didInitialOfficerSync) {
        _didInitialOfficerSync = true;
        await Future.wait(orgs.map((org) => _loadOfficersForOrg(org.id)));
        if (mounted) setState(() {});
      }
    } catch (e) {
      setState(() => _loadingMeta = false);
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

  Widget _buildStatsRow(bool isMobile, bool isTablet) {
    final cards = [
      _StatCard(
        label: 'Active Advisers',
        value: '$_totalAdvisers',
        icon: Icons.supervisor_account_rounded,
        color: AdminColors.primaryDark,
        onTap: () => setState(() => _statusFilter = 'Active'),
      ),
      _StatCard(
        label: 'Unique Individuals',
        value: '${_adviserNames.length}',
        icon: Icons.badge_outlined,
        color: const Color(0xFF2563EB),
      ),
      _StatCard(
        label: 'Orgs Without an Adviser',
        value: '$_orgsWithoutAdviser',
        icon: Icons.report_gmailerrorred_rounded,
        color: _orgsWithoutAdviser > 0
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
      ),
      _StatCard(
        label: 'Archived Advisers',
        value: '—',
        icon: Icons.archive_rounded,
        color: const Color(0xFF64748B),
        stream: _archivedCountStream,
        onTap: () => setState(() => _statusFilter = 'Archived'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: StatCardsRow(cards: cards, isMobile: isMobile),
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search adviser or organization…',
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
        _StatusDropdown(
          value: _statusFilter,
          onChanged: (v) => setState(() {
            if (v != null) {
              _statusFilter = v;
              _currentPage = 1;
            }
          }),
        ),
        AdminExportButton(
          onSelected: (choice) {
            if (choice == 'excel') {
              _exportCSV();
            } else if (choice == 'pdf') {
              _exportPDF();
            }
          },
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
      stream: _advisersTableStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        var docs = snap.data?.docs ?? [];

        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final orgId = (data['orgId'] ?? '').toString().trim();
          final orgName = (data['orgName'] ?? '').toString().trim();
          return orgId.isNotEmpty && orgName.isNotEmpty;
        }).toList();

        final _searchTerm = _searchController.text.trim().toLowerCase();
        if (_searchTerm.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map;
            return (data['adviserName'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchTerm) ||
                (data['orgName'] ?? '').toString().toLowerCase().contains(
                  _searchTerm,
                ) ||
                (data['position'] ?? '').toString().toLowerCase().contains(
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
              _buildTableHeader(),
              Expanded(
                child: docs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: pageDocs.length,
                        itemBuilder: (_, i) {
                          final data =
                              pageDocs[i].data() as Map<String, dynamic>;
                          return _buildRow(
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
          Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
          Expanded(flex: 2, child: _headerCell('ADVISER NAME')),
          Expanded(flex: 2, child: _headerCell('EMAIL')),
          Expanded(flex: 1, child: _headerCell('PHONE')),
          Expanded(flex: 1, child: _headerCell('POSITION')),
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
    required String docId,
    required Map<String, dynamic> data,
    required bool isLast,
  }) {
    final position =
        (data['adviserPosition'] ?? data['adviserRank'] ?? 'Faculty')
            .toString();
    final archived = data['archived'] == true;
    final orgId = data['orgId'] ?? '';

    final org = _orgs.firstWhere(
      (o) => o.id == orgId,
      orElse: () =>
          const OrgModel(id: '', name: '', abbrev: '', tag: '', logoUrl: ''),
    );
    final orgLogoUrl = org.logoUrl;

    final adviserName = data['adviserName'] ?? '—';
    final adviserEmail = data['adviserEmail'] ?? '—';
    final adviserPhone = data['adviserPhone'] ?? '—';

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _showViewDialog(data, docId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            // ORGANIZATION column
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _OrgAvatar(data['orgAbbrev'] ?? '??', logoUrl: orgLogoUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['orgName'] ?? '—',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A202C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((data['orgTag'] ?? '').toString().isNotEmpty)
                          Text(
                            data['orgTag'] ?? '',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ADVISER NAME column
            Expanded(
              flex: 2,
              child: Text(
                adviserName,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1A202C),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // EMAIL column
            Expanded(
              flex: 2,
              child: Text(
                adviserEmail,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // PHONE column
            Expanded(
              flex: 1,
              child: Text(
                adviserPhone,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // POSITION column
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PositionBadge(position),
              ),
            ),

            // ACTIONS column
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionIcon(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    color: const Color(0xFF3B82F6),
                    onTap: () => _showViewDialog(data, docId),
                  ),
                  // Only show Edit button if NOT archived
                  if (!archived) ...[
                    const SizedBox(width: 6),
                    _ActionIcon(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      color: AdminColors.primaryDark,
                      onTap: () => _showEditDialog(data, docId),
                    ),
                  ],
                  const SizedBox(width: 6),
                  _ActionIcon(
                    icon: archived
                        ? Icons.restore_rounded
                        : Icons.archive_outlined,
                    tooltip: archived ? 'Restore' : 'Archive',
                    color: archived
                        ? const Color(0xFF059669)
                        : const Color(0xFF6B7280),
                    onTap: archived
                        ? () => _confirmRestoreRecord(
                            docId,
                            data['orgName'] ?? '',
                          )
                        : () => _confirmArchive(docId, data['orgName'] ?? ''),
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.supervisor_account_rounded,
              size: 36,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusFilter == 'Archived'
                ? 'No archived records'
                : 'No adviser roles assigned yet',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusFilter == 'Archived'
                ? 'Archived roles will appear here.'
                : 'Tap "Assign Role" to get started.',
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
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total records',
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

  // ── View dialog with photos ────────────────────────────────────────────────
  void _showViewDialog(Map<String, dynamic> data, String docId) {
    final rank = data['adviserRank'] ?? 'Instructor';
    final archived = data['archived'] == true;
    final orgName = data['orgName'] ?? '—';
    final orgTag = data['orgTag'] ?? '';
    final org = _orgs.firstWhere(
      (o) => o.id == (data['orgId'] ?? ''),
      orElse: () =>
          const OrgModel(id: '', name: '', abbrev: '', tag: '', logoUrl: ''),
    );

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 540,
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
              // ---- Header ----
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
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withAlpha(70)),
                      ),
                      child: _OrgAvatar(
                        data['orgAbbrev'] ?? '??',
                        logoUrl: org.logoUrl,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            orgName,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (orgTag.isNotEmpty)
                            Text(
                              orgTag,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (archived)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'ARCHIVED',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
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
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              // ---- Adviser Card ----
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: _buildAdviserCard(
                  name: data['adviserName'] ?? '—',
                  email: data['adviserEmail'] ?? '—',
                  phone: data['adviserPhone'] ?? '—',
                  rank: rank,
                  photoUrl: data['adviserPhotoUrl'] ?? '',
                ),
              ),

              // ---- Footer ----
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  children: [
                    if (!archived)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmArchive(docId, orgName);
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
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
                      ),
                    if (archived)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmRestoreRecord(docId, orgName);
                        },
                        icon: const Icon(
                          Icons.restore_rounded,
                          size: 15,
                          color: Color(0xFF059669),
                        ),
                        label: Text(
                          'Restore',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: Color(0xFF059669),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF059669)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
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
                    if (!archived) const SizedBox(width: 10),
                    if (!archived)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditDialog(data, docId);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 15),
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
                            horizontal: 18,
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

  Widget _viewCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.primaryDark,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Divider(color: Color(0xFFE2E6EA), thickness: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildAdviserCard({
    required String name,
    required String email,
    required String phone,
    required String rank,
    required String photoUrl,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large photo
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE2E6EA),
            ),
            child: photoUrl.isNotEmpty
                ? ClipOval(
                    child: _buildImageWidget(
                      photoUrl,
                      fit: BoxFit.cover,
                      width: 60,
                      height: 60,
                    ),
                  )
                : Icon(Icons.person, size: 32, color: Colors.grey[600]),
          ),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 6),
                _infoChip(
                  Icons.work_outline,
                  rank,
                  color: AdminColors.primaryDark,
                ),
                const SizedBox(height: 8),
                _infoRow(Icons.email_outlined, email),
                _infoRow(Icons.phone_outlined, phone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
    IconData icon,
    String label, {
    Color color = const Color(0xFF64748B),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AdminColors.primaryDark.withAlpha(150)),
          const SizedBox(width: 8),
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

  // ── Form dialog (Edit) ──────────────────────────────────────
  void _showEditDialog(Map<String, dynamic> data, String docId) =>
      _showFormDialog(isEdit: true, docId: docId, existing: data);

  void _showFormDialog({
    required bool isEdit,
    required String? docId,
    required Map<String, dynamic>? existing,
  }) {
    OrgModel? selectedOrg = isEdit
        ? _orgs.cast<OrgModel?>().firstWhere(
            (o) => o?.id == existing?['orgId'],
            orElse: () => null,
          )
        : null;
    final originalOrgId = existing?['orgId']?.toString();

    final advNameCtrl = TextEditingController(
      text: existing?['adviserName'] ?? '',
    );
    final advEmailCtrl = TextEditingController(
      text: existing?['adviserEmail'] ?? '',
    );
    final advPhoneCtrl = TextEditingController(
      text: existing?['adviserPhone'] ?? '',
    );
    final advRankCtrl = TextEditingController(
      text: existing?['adviserRank'] ?? 'Instructor',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          bool isSaving = false;
          String? errorMsg;

          Future<void> onOrgChanged(OrgModel? org) async {
            if (org == null || isEdit) return;
            final orgDoc = await FirebaseFirestore.instance
                .collection('organizations')
                .doc(org.id)
                .get();
            if (orgDoc.exists) {
              final d = orgDoc.data()!;
              setDlg(() {
                advNameCtrl.text = d['adviserName'] ?? '';
                advEmailCtrl.text = d['adviserEmail'] ?? '';
                advPhoneCtrl.text = d['adviserPhone'] ?? '';
                advRankCtrl.text = d['adviserTitle'] ?? 'Instructor';
              });
            }
          }

          Future<void> save() async {
            if (!formKey.currentState!.validate()) return;
            if (selectedOrg == null) {
              setDlg(() => errorMsg = 'Please select an organization.');
              return;
            }

            // Email format is now enforced by the field's own validator
            // above (formKey.currentState!.validate() already returned
            // early if it failed), so no need to re-check it here.
            final adviserEmail = advEmailCtrl.text.trim();

            setDlg(() {
              isSaving = true;
              errorMsg = null;
            });
            try {
              final adviserName = advNameCtrl.text.trim();
              final adviserPhone = advPhoneCtrl.text.trim();
              final adviserRank = advRankCtrl.text.trim();
              // Officers aren't editable from this form anymore — they're
              // synced automatically from the org's real officers
              // subcollection (see _loadOfficersForOrg), so just carry
              // whatever is already on the record through unchanged instead
              // of overwriting it with blanks.
              final president = (existing?['president'] ?? '').toString();
              final vicePresident = (existing?['vicePresident'] ?? '')
                  .toString();
              final secretary = (existing?['secretary'] ?? '').toString();

              final payload = buildAdviserRolePayload(
                orgId: selectedOrg!.id,
                orgName: selectedOrg!.name,
                orgAbbrev: selectedOrg!.abbrev,
                orgTag: selectedOrg!.tag,
                adviserName: adviserName,
                adviserEmail: adviserEmail,
                adviserPhone: adviserPhone,
                adviserRank: adviserRank,
                president: president,
                vicePresident: vicePresident,
                secretary: secretary,
                archived: false,
              );

              if (isEdit && docId != null) {
                final orgChanged = selectedOrg!.id != originalOrgId;

                if (orgChanged) {
                  // Only one active adviser per org — reassigning here
                  // must not silently bump whoever's already there.
                  final dup = await FirebaseFirestore.instance
                      .collection('adviser_roles')
                      .where('orgId', isEqualTo: selectedOrg!.id)
                      .where('archived', isEqualTo: false)
                      .get();
                  if (dup.docs.isNotEmpty) {
                    setDlg(() {
                      isSaving = false;
                      errorMsg =
                          '${selectedOrg!.name} already has an active adviser role.';
                    });
                    return;
                  }
                }

                final batch = FirebaseFirestore.instance.batch();
                batch.update(
                  FirebaseFirestore.instance
                      .collection('adviser_roles')
                      .doc(docId),
                  payload,
                );
                batch.update(
                  FirebaseFirestore.instance
                      .collection('organizations')
                      .doc(selectedOrg!.id),
                  buildOrganizationAdviserPayload(
                    adviserName: adviserName,
                    adviserEmail: adviserEmail,
                    adviserPhone: adviserPhone,
                    adviserTitle: adviserRank,
                  ),
                );
                if (orgChanged &&
                    originalOrgId != null &&
                    originalOrgId.isNotEmpty) {
                  // Clear the adviser off their previous org so they no
                  // longer show up there once moved.
                  batch.update(
                    FirebaseFirestore.instance
                        .collection('organizations')
                        .doc(originalOrgId),
                    buildOrganizationAdviserPayload(
                      adviserName: '',
                      adviserEmail: '',
                      adviserPhone: '',
                      adviserTitle: '',
                    ),
                  );
                }
                await batch.commit();

                await activity_log.ActivityLogger.log(
                  action: orgChanged
                      ? 'Moved adviser role to ${selectedOrg!.name}'
                      : 'Updated adviser role for ${selectedOrg!.name}',
                  module: 'Adviser Roles',
                  severity: 'info',
                  details: {'orgId': selectedOrg!.id, 'adviser': adviserName},
                );
              } else {
                final dup = await FirebaseFirestore.instance
                    .collection('adviser_roles')
                    .where('orgId', isEqualTo: selectedOrg!.id)
                    .where('archived', isEqualTo: false)
                    .get();
                if (dup.docs.isNotEmpty) {
                  setDlg(() {
                    isSaving = false;
                    errorMsg =
                        '${selectedOrg!.name} already has an active adviser role.';
                  });
                  return;
                }

                final batch = FirebaseFirestore.instance.batch();
                final roleRef = FirebaseFirestore.instance
                    .collection('adviser_roles')
                    .doc();
                batch.set(roleRef, {
                  ...payload,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                batch.update(
                  FirebaseFirestore.instance
                      .collection('organizations')
                      .doc(selectedOrg!.id),
                  buildOrganizationAdviserPayload(
                    adviserName: adviserName,
                    adviserEmail: adviserEmail,
                    adviserPhone: adviserPhone,
                    adviserTitle: adviserRank,
                  ),
                );
                await batch.commit();

                await activity_log.ActivityLogger.log(
                  action: 'Assigned new adviser role for ${selectedOrg!.name}',
                  module: 'Adviser Roles',
                  severity: 'info',
                  details: {'orgId': selectedOrg!.id, 'adviser': adviserName},
                );
              }

              // Show immediate feedback and close the dialog first so the
              // user returns to the list quickly. Refresh meta data in the
              // background without awaiting so the list updates when ready.
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isEdit
                          ? 'Adviser role updated.'
                          : 'Adviser role assigned.',
                    ),
                    backgroundColor: const Color(0xFF059669),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }

              // Close the dialog first so the user returns to the list.
              Navigator.pop(ctx);

              // Trigger a local UI refresh immediately and show feedback.
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isEdit
                          ? 'Adviser role updated.'
                          : 'Adviser role assigned.',
                    ),
                    backgroundColor: const Color(0xFF059669),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }

              // Refresh metadata in background (non-blocking)
              _loadMeta();
            } catch (e) {
              setDlg(() {
                isSaving = false;
                errorMsg = e.toString();
              });
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Container(
              width: 540,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                            color: Colors.white.withAlpha(38),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isEdit
                                ? Icons.edit_outlined
                                : Icons.person_add_alt_1_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            isEdit
                                ? 'Edit Adviser Role'
                                : 'Assign Adviser Role',
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
                          onPressed: isSaving
                              ? null
                              : () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
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
                            _sectionDivider(
                              'Organization',
                              icon: Icons.business_outlined,
                            ),
                            AnchoredDropdownField<OrgModel>(
                              value: selectedOrg,
                              decoration: _DS.inputDecoration(
                                'Select Organization',
                                icon: Icons.business_outlined,
                                required: true,
                              ),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: const Color(0xFF1A202C),
                              ),
                              items: _orgs
                                  .map(
                                    (o) => DropdownMenuItem(
                                      value: o,
                                      child: Row(
                                        children: [
                                          _OrgAvatar(
                                            o.abbrev.isNotEmpty
                                                ? o.abbrev
                                                : o.name.substring(
                                                    0,
                                                    o.name.length.clamp(0, 2),
                                                  ),
                                            logoUrl: o.logoUrl,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  o.name,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                if (o.tag.isNotEmpty)
                                                  Text(
                                                    o.tag,
                                                    style:
                                                        GoogleFonts.beVietnamPro(
                                                          fontSize: 11,
                                                          color: const Color(
                                                            0xFF64748B,
                                                          ),
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setDlg(() => selectedOrg = v);
                                onOrgChanged(v);
                              },
                              validator: (_) => selectedOrg == null
                                  ? 'Select an organization'
                                  : null,
                            ),
                            if (isEdit &&
                                selectedOrg != null &&
                                selectedOrg!.id != originalOrgId)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 14,
                                      color: AdminColors.warning,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'This adviser will be moved to ${selectedOrg!.name} and removed from their current organization.',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11,
                                          color: AdminColors.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 20),

                            const SizedBox(height: 20),
                            _sectionDivider(
                              'Adviser Information',
                              icon: Icons.person_outline_rounded,
                            ),
                            TextFormField(
                              controller: advNameCtrl,
                              decoration: _DS.inputDecoration(
                                'Full Name',
                                hint: 'e.g., Dr. Juan dela Cruz',
                                icon: Icons.badge_outlined,
                                required: true,
                              ),
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return 'Required';
                                if (!RegExp(
                                  r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*(?: [A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*)+$",
                                ).hasMatch(value)) {
                                  return 'Enter a full name (first and last)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: advEmailCtrl,
                                    decoration: _DS.inputDecoration(
                                      'Email',
                                      icon: Icons.email_outlined,
                                      required: true,
                                    ),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) {
                                      final value = v?.trim() ?? '';
                                      if (value.isEmpty) return 'Required';
                                      if (!RegExp(
                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                      ).hasMatch(value)) {
                                        return 'Enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: advPhoneCtrl,
                                    decoration: _DS.inputDecoration(
                                      'Phone',
                                      icon: Icons.phone_outlined,
                                      required: true,
                                    ),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                    ),
                                    keyboardType: TextInputType.phone,
                                    validator: (v) {
                                      final value = v?.trim() ?? '';
                                      if (value.isEmpty) return 'Required';
                                      final digitCount = value
                                          .replaceAll(RegExp(r'[^0-9]'), '')
                                          .length;
                                      if (!RegExp(
                                            r'^[0-9+\-\s()]+$',
                                          ).hasMatch(value) ||
                                          digitCount < 7) {
                                        return 'Enter a valid phone number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            AnchoredDropdownField<String>(
                              value:
                                  [
                                    'Dean',
                                    'Program Chair',
                                    'Department Head',
                                    'Coordinator',
                                    'Faculty',
                                  ].contains(advRankCtrl.text)
                                  ? advRankCtrl.text
                                  : 'Faculty',
                              decoration: _DS.inputDecoration(
                                'Position',
                                required: true,
                              ),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: const Color(0xFF1A202C),
                              ),
                              items:
                                  [
                                        'Dean',
                                        'Program Chair',
                                        'Department Head',
                                        'Coordinator',
                                        'Faculty',
                                      ]
                                      .map(
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(r),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) {
                                if (v != null) advRankCtrl.text = v;
                              },
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required' : null,
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
                          onPressed: isSaving
                              ? null
                              : () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
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
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : save,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isEdit
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                  size: 16,
                                ),
                          label: Text(
                            isEdit ? 'Save Changes' : 'Assign Role',
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
        },
      ),
    );
  }

  // ── Confirm dialogs ───────────────────────────────────────────────
  void _confirmArchive(String docId, String orgName) {
    _confirmAction(
      title: 'Archive Record',
      message:
          'Archive "$orgName"? It will be moved to the Archived tab and can be restored later.',
      confirmLabel: 'Archive',
      confirmColor: const Color(0xFF64748B),
      icon: Icons.archive_outlined,
      iconBg: const Color(0xFFF1F5F9),
      onConfirm: () async {
        await FirebaseFirestore.instance
            .collection('adviser_roles')
            .doc(docId)
            .update({'archived': true});
        await activity_log.ActivityLogger.log(
          action: 'Archived adviser role for $orgName',
          module: 'Adviser Roles',
          severity: 'warning',
          details: {'docId': docId, 'orgName': orgName},
        );
        _loadMeta();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Record archived.'),
              backgroundColor: const Color(0xFF64748B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      },
    );
  }

  void _confirmRestoreRecord(String docId, String orgName) {
    _confirmAction(
      title: 'Restore Record',
      message: 'Restore "$orgName" back to the active list?',
      confirmLabel: 'Restore',
      confirmColor: const Color(0xFF059669),
      icon: Icons.unarchive_outlined,
      iconBg: const Color(0xFFECFDF5),
      onConfirm: () async {
        await FirebaseFirestore.instance
            .collection('adviser_roles')
            .doc(docId)
            .update({'archived': false});
        await activity_log.ActivityLogger.log(
          action: 'Restored adviser role for $orgName',
          module: 'Adviser Roles',
          severity: 'info',
          details: {'docId': docId, 'orgName': orgName},
        );
        _loadMeta();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Record restored.'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      },
    );
  }

  void _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required IconData icon,
    required Color iconBg,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
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
                      color: iconBg,
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
              const SizedBox(height: 14),
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      onConfirm();
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
      ),
    );
  }

  // ── Export ────────────────────────────────────────────────────────
  // Reads from the cached docs the table's own live stream already holds
  // (see _activeAdvisersCacheSub/_archivedAdvisersCacheSub) instead of
  // firing a fresh `.get()` — each doc embeds up to 3 base64 officer photos,
  // so re-querying the whole collection on every export was what made this
  // noticeably slower than other pages' exports.
  List<QueryDocumentSnapshot> get _docsForExport => _statusFilter == 'Archived'
      ? _cachedArchivedAdviserDocs
      : _cachedActiveAdviserDocs;

  Future<void> _exportCSV() async {
    try {
      final docs = _docsForExport;
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No data to export.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
        return;
      }
      String hasPhoto(dynamic v) =>
          (v is String && v.isNotEmpty) ? 'Yes' : 'No';
      final rows = docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        return [
          (d['orgName'] ?? '').toString(),
          (d['orgAbbrev'] ?? '').toString(),
          (d['orgTag'] ?? '').toString(),
          (d['adviserName'] ?? '').toString(),
          (d['adviserEmail'] ?? '').toString(),
          // Written as a text cell (TextCellValue), not a number — no
          // scientific-notation risk the way plain CSV had, so the old
          // ="..." formula workaround for that is gone.
          (d['adviserPhone'] ?? '').toString(),
          (d['adviserRank'] ?? '').toString(),
          (d['president'] ?? '').toString(),
          hasPhoto(d['presidentPhotoUrl']),
          (d['vicePresident'] ?? '').toString(),
          hasPhoto(d['vicePresidentPhotoUrl']),
          (d['secretary'] ?? '').toString(),
          hasPhoto(d['secretaryPhotoUrl']),
          (d['archived'] ?? false) ? 'Archived' : 'Active',
        ];
      }).toList();
      final bytes = AdminExportExcel.generateStyledTable(
        title: 'Adviser Roles',
        headers: const [
          'Organization',
          'Abbreviation',
          'Tag',
          'Adviser',
          'Email',
          'Phone',
          'Rank',
          'President',
          'President Photo',
          'Vice President',
          'Vice President Photo',
          'Secretary',
          'Secretary Photo',
          'Status',
        ],
        rows: rows,
      );
      final now = DateTime.now().toString().substring(0, 10);
      final name = 'adviser_roles_$now.xlsx';
      await AdminExportUtil.saveBytes(bytes, name, mimeType: xlsxMimeType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportPDF() async {
    try {
      final docs = _docsForExport;
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No data to export.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Generating PDF…'),
              ],
            ),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
      // Lets the snackbar above actually paint before the synchronous
      // PDF table build/encode work below blocks the UI thread — otherwise
      // the export looks frozen with zero feedback until it's done.
      await Future.delayed(Duration.zero);

      final rows = docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        return [
          d['orgName'] ?? '',
          d['orgAbbrev'] ?? '',
          d['orgTag'] ?? '',
          d['adviserName'] ?? '',
          d['adviserEmail'] ?? '',
          d['adviserPhone'] ?? '',
          d['adviserRank'] ?? '',
          d['president'] ?? '',
          d['vicePresident'] ?? '',
          d['secretary'] ?? '',
          ((d['archived'] ?? false) ? 'Archived' : 'Active'),
        ].map((value) => value.toString()).toList();
      }).toList();

      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Adviser Roles Report',
        headers: const [
          'Organization',
          'Abbreviation',
          'Tag',
          'Adviser',
          'Email',
          'Phone',
          'Rank',
          'President',
          'Vice President',
          'Secretary',
          'Status',
        ],
        rows: rows,
      );
      final now = DateTime.now().toString().substring(0, 10);
      await AdminExportUtil.saveBytes(
        pdfBytes,
        'adviser_roles_$now.pdf',
        mimeType: 'application/pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ──
// ───────────────────────────────────────────────────────────────────────────

class _StatusDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _StatusDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AnchoredMenuTrigger<String>(
      items: const ['Active', 'Archived'],
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

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot>? stream;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.stream,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget countWidget;
    if (stream != null) {
      countWidget = StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            );
          }
          final count = snap.hasData ? snap.data!.docs.length : 0;
          return Text(
            '$count',
            style: GoogleFonts.beVietnamPro(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A202C),
            ),
          );
        },
      );
    } else {
      countWidget = Text(
        value,
        style: GoogleFonts.beVietnamPro(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1A202C),
        ),
      );
    }

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
                countWidget,
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

class _TabToggle extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  const _TabToggle({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Row(
        children: options.map((opt) {
          final isActive = opt == selected;
          return GestureDetector(
            onTap: () => onChanged(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? AdminColors.primaryDark : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                opt,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T value;
  final String hint;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.hint,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnchoredMenuTrigger<T>(
      items: items.map((i) => i.value as T).toList(),
      itemBuilder: (item, selected) =>
          items.firstWhere((i) => i.value == item).child,
      selectedValue: value,
      onSelected: (v) => onChanged(v),
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
            DefaultTextStyle(
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
              child: items.firstWhere((i) => i.value == value).child,
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

class OrgColors {
  static const Color lightGray = Color(0xFFF5F5F5);
}
