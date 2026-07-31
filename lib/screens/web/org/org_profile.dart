// lib/screens/web/org/org_profile.dart
// Redesigned: Professional, matches StudentAccounts / OrgAnnouncements design language
// All Firestore parameters and logic fully preserved
// UPDATED: Added Members section (batch import, manual add, list, archive/resend)
//          mirroring the StudentAccounts import pattern. Members are written to
//          `users` with role: 'org' + orgId/orgName so the mobile app can tag
//          them to this org and Members-Only events can filter on it.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:csv/csv.dart';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import '../../../services/activity_logger.dart' as activity_log;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// Drives which tier of the org chart (_HierarchyTree) an officer lands in.
const Map<String, int> _standardPositionRanks = {
  'President': 0,
  'Vice President': 1,
  'Secretary': 2,
  'Treasurer': 2,
  'Business Manager': 3,
  'Board Member': 3,
};

// ─────────────────────────────────────────────────────────────────────────────
// Image helpers (preserved exactly)
// ─────────────────────────────────────────────────────────────────────────────
String _mimeTypeFromBytes(List<int> bytes) {
  if (bytes.length < 4) return 'image/png';
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47)
    return 'image/png';
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46)
    return 'image/gif';
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'image/bmp';
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46)
    return 'image/webp';
  return 'image/png';
}

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
  Widget? errorWidget,
}) {
  return Image(
    image: _imageProviderFromUrl(url),
    fit: fit,
    errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Officer ↔ student account tagging
//
// Officers are students first — they already have (or will have) a regular
// student account created via Student Accounts. Rather than creating a
// second login for them (like Members get), we best-effort match their
// officer email to an existing `users` doc and tag *that* doc with
// orgId/orgName/officerPosition. The mobile app can then read a signed-in
// student's own `users` doc and show "Officer · {position} at {org}" instead
// of (or alongside) their normal student view, with no separate login.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> _tagMatchingStudentAccount({
  required String email,
  required Map<String, dynamic> updates,
}) async {
  final trimmed = email.trim().toLowerCase();
  if (trimmed.isEmpty) return false;

  try {
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();

    final studentSnap = await FirebaseFirestore.instance
        .collection('students')
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();

    if (userSnap.docs.isEmpty && studentSnap.docs.isEmpty) {
      return false;
    }

    if (userSnap.docs.isNotEmpty) {
      await userSnap.docs.first.reference.set(updates, SetOptions(merge: true));
    }
    if (studentSnap.docs.isNotEmpty) {
      await studentSnap.docs.first.reference.set(
        updates,
        SetOptions(merge: true),
      );
    }

    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _clearMatchingStudentAccountTag({
  required String email,
  required Map<String, dynamic> updates,
}) async {
  final trimmed = email.trim().toLowerCase();
  if (trimmed.isEmpty) return;

  try {
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: trimmed)
        .limit(5)
        .get();

    final studentSnap = await FirebaseFirestore.instance
        .collection('students')
        .where('email', isEqualTo: trimmed)
        .limit(5)
        .get();

    for (final doc in [...userSnap.docs, ...studentSnap.docs]) {
      await doc.reference.update(updates);
    }
  } catch (_) {}
}

Future<void> _clearStudentAccountTagByUid({
  required String uid,
  required Map<String, dynamic> updates,
}) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update(updates);
    await FirebaseFirestore.instance
        .collection('students')
        .doc(uid)
        .update(updates);
  } catch (_) {}
}

Future<bool> _syncOfficerUserTag({
  required String orgId,
  required String orgName,
  required String email,
  required String position,
  required bool isCaptain,
}) async {
  return _tagMatchingStudentAccount(
    email: email,
    updates: {
      'orgId': orgId,
      'orgName': orgName,
      'orgRole': 'officer',
      'officerPosition': position,
      'isOrgOfficer': true,
      'isOfficerCaptain': isCaptain,
    },
  );
}

Future<void> _clearOfficerUserTag({
  required String orgId,
  required String email,
}) async {
  await _clearMatchingStudentAccountTag(
    email: email,
    updates: {
      'orgId': FieldValue.delete(),
      'orgName': FieldValue.delete(),
      'orgRole': FieldValue.delete(),
      'officerPosition': FieldValue.delete(),
      'isOrgOfficer': FieldValue.delete(),
      'isOfficerCaptain': FieldValue.delete(),
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Adviser model — mirrors the `Adviser` shape admin's organization_management
// screen already writes/reads (name/title/email/phone), capped at 3 per org.
// `type` distinguishes a regular Faculty Adviser from a Student Adviser.
// ─────────────────────────────────────────────────────────────────────────────
class AdviserInfo {
  final String name;
  final String title;
  final String email;
  final String phone;
  final String type; // 'faculty' (default) or 'student'
  const AdviserInfo({
    this.name = '',
    this.title = '',
    this.email = '',
    this.phone = '',
    this.type = 'faculty',
  });

  factory AdviserInfo.fromMap(Map<String, dynamic> map) => AdviserInfo(
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

  bool get isEmpty => name.trim().isEmpty;
  bool get isStudentAdviser => type == 'student';
}

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens — identical to StudentAccounts / OrgAnnouncements
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const Color primaryDark = Color(0xFFEA580C);
  static const Color accent = Color(0xFFF97316);

  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FB);
  static const Color pageBg = Color(0xFFFBFCFE);

  static const Color border = Color(0xFFE8ECF0);
  static const Color borderSoft = Color(0xFFE2E6EA);

  static const Color charcoal = Color(0xFF1A202C);
  static const Color textMid = Color(0xFF374151);
  static const Color darkGray = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF9AA5B4);

  static const Color success = Color(0xFF059669);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFFB923C);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF2563EB);
}

class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.06),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _card({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(22),
}) {
  return Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: _C.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
      boxShadow: _DS.cardShadow,
    ),
    child: child,
  );
}

Widget _sectionLabel(String title, {IconData? icon}) {
  return Row(
    children: [
      if (icon != null) ...[
        Icon(icon, size: 16, color: _C.primaryDark),
        const SizedBox(width: 8),
      ],
      Text(
        title,
        style: GoogleFonts.beVietnamPro(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _C.primaryDark,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Divider(color: _C.borderSoft, thickness: 1)),
    ],
  );
}

InputDecoration _inputDecoration(String label, {String? hint, IconData? icon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon != null ? Icon(icon, size: 18, color: _C.textFaint) : null,
    labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.darkGray),
    hintStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.textFaint),
    filled: true,
    fillColor: _C.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _C.borderSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _C.borderSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _C.primaryDark, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _C.error),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgProfileScreen extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgShortName;
  final String orgEmail;

  const OrgProfileScreen({
    super.key,
    required this.orgId,
    required this.orgName,
    required this.orgShortName,
    required this.orgEmail,
  });

  @override
  State<OrgProfileScreen> createState() => _OrgProfileScreenState();
}

class _OrgProfileScreenState extends State<OrgProfileScreen> {
  String _orgName = '';
  String _orgShortName = '';
  String _orgEmail = '';
  String _orgDescription = '';
  String _orgLogoUrl = '';
  String _coverPhotoUrl = '';
  String _facebook = '';
  String _instagram = '';
  String _twitter = '';
  String _gmail = '';
  // Orgs can have up to 2 advisers (same cap admin enforces on its side).
  // The photo is only kept for the primary (first) adviser, matching the
  // existing org-doc schema admin already writes to.
  List<AdviserInfo> _advisers = [];
  String _adviserPhotoUrl = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _orgName = widget.orgName;
    _orgShortName = widget.orgShortName;
    _orgEmail = widget.orgEmail;
    _loadOrgData();
    _backfillOfficerRanks();
  }

  // One-time self-heal for officers saved before positionRank was derived
  // from the selected position — those all landed on rank 0, collapsing the
  // org chart into a single tier instead of a real hierarchy. Only touches
  // officers whose position is one of the standard ones we have a rank for;
  // custom titles are left alone since there's nothing to correct them to.
  Future<void> _backfillOfficerRanks() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .collection('officers')
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final position = data['position'] as String? ?? '';
        final expectedRank = _standardPositionRanks[position];
        if (expectedRank != null && data['positionRank'] != expectedRank) {
          await doc.reference.update({'positionRank': expectedRank});
        }
      }
    } catch (_) {}
  }

  Future<void> _loadOrgData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        _syncOrganizationOfficersIfNeeded(data);

        // `advisers` is the array admin's organization_management screen
        // already reads/writes (max 2). Fall back to the legacy singular
        // fields for orgs that only ever had one adviser set.
        final rawAdvisers = (data['advisers'] as List?) ?? [];
        List<AdviserInfo> advisers = rawAdvisers
            .whereType<Map>()
            .map((a) => AdviserInfo.fromMap(Map<String, dynamic>.from(a)))
            .where((a) => !a.isEmpty)
            .toList();
        if (advisers.isEmpty &&
            (data['adviserName'] ?? '').toString().isNotEmpty) {
          advisers = [
            AdviserInfo(
              name: data['adviserName'] ?? '',
              title: data['adviserTitle'] ?? '',
              email: data['adviserEmail'] ?? '',
              phone: data['adviserPhone'] ?? '',
            ),
          ];
        }
        if (advisers.length > 3) advisers = advisers.sublist(0, 3);

        setState(() {
          _orgName = data['name'] ?? widget.orgName;
          _orgShortName = data['shortName'] ?? widget.orgShortName;
          _orgEmail = data['email'] ?? widget.orgEmail;
          _orgDescription = data['description'] ?? '';
          _orgLogoUrl = data['logoUrl'] ?? '';
          _coverPhotoUrl = data['coverPhotoUrl'] ?? '';
          _facebook = data['facebook'] ?? '';
          _instagram = data['instagram'] ?? '';
          _twitter = data['twitter'] ?? '';
          _gmail = data['gmail'] ?? '';
          _advisers = advisers;
          _adviserPhotoUrl = data['adviserPhotoUrl'] ?? '';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _snack('Organization not found', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Failed to load: $e', isError: true);
      }
    }
  }

  Future<void> _syncOrganizationOfficersIfNeeded(
    Map<String, dynamic> data,
  ) async {
    try {
      final storedOfficers = data['officers'] as List<dynamic>?;
      final officerSnap = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .collection('officers')
          .orderBy('positionRank', descending: false)
          .get();
      final officers = officerSnap.docs.map((d) {
        final dd = d.data();
        return {
          'name': dd['name'] ?? '',
          'role': dd['position'] ?? '',
          'email': dd['email'] ?? '',
          'phone': dd['phone'] ?? '',
          'photoUrl': dd['photoUrl'] ?? '',
        };
      }).toList();
      if (!_officersMatch(storedOfficers, officers)) {
        await FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.orgId)
            .update({'officers': officers});
      }
    } catch (_) {}
  }

  bool _officersMatch(
    List<dynamic>? stored,
    List<Map<String, dynamic>> expected,
  ) {
    if (stored == null || stored.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      final s = stored[i];
      if (s is! Map) return false;
      for (final key in expected[i].keys) {
        if ((s[key] ?? '') != expected[i][key]) return false;
      }
    }
    return true;
  }

  Future<void> _syncOrganizationOfficers() async {
    final orgDoc = FirebaseFirestore.instance
        .collection('organizations')
        .doc(widget.orgId);
    final snap = await orgDoc.collection('officers').get();
    final officers = snap.docs.map((d) {
      final dd = d.data();
      return {
        'name': dd['name'] ?? '',
        'role': dd['position'] ?? '',
        'email': dd['email'] ?? '',
        'phone': dd['phone'] ?? '',
        'photoUrl': dd['photoUrl'] ?? '',
      };
    }).toList();
    await orgDoc.update({'officers': officers});
  }

  // Created once, not a getter — used in three separate StreamBuilders, so
  // a getter here was tearing down and re-subscribing all three on every
  // rebuild.
  late final Stream<QuerySnapshot> _officersStream = FirebaseFirestore.instance
      .collection('organizations')
      .doc(widget.orgId)
      .collection('officers')
      .orderBy('positionRank', descending: false)
      .snapshots();

  // Members of this org — same tagging model as officers: rather than a
  // separate login, a member is an existing student `users` doc tagged with
  // orgId/orgName/orgRole:'member' (see _tagMemberAccount below). Two
  // equality `where` clauses don't need a composite index (only combining
  // `where` with `orderBy` on a different field does), so this is safe as-is
  // as long as no `.orderBy()` is added here — sort client-side instead.
  late final Stream<QuerySnapshot> _membersStream = FirebaseFirestore.instance
      .collection('users')
      .where('orgId', isEqualTo: widget.orgId)
      .where('orgRole', isEqualTo: 'member')
      .snapshots();

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _C.error : _C.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  void _openEditProfile() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: _EditOrgProfileSheet(
          orgId: widget.orgId,
          orgName: _orgName,
          shortName: _orgShortName,
          email: _orgEmail,
          description: _orgDescription,
          logoUrl: _orgLogoUrl,
          coverPhotoUrl: _coverPhotoUrl,
          advisers: _advisers,
          adviserPhotoUrl: _adviserPhotoUrl,
          facebook: _facebook,
          instagram: _instagram,
          twitter: _twitter,
          gmail: _gmail,
          onSaved: _loadOrgData,
        ),
      ),
    );
  }

  void _openOfficerModal({OfficerModel? officer}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _OfficerModal(
        orgId: widget.orgId,
        orgName: _orgName,
        existingOfficer: officer,
        onSuccess: () => setState(() {}),
      ),
    );
  }

  Future<void> _deleteOfficer(OfficerModel officer) async {
    final confirm = await showDialog<bool>(
      context: context,
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
                      color: _C.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: _C.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Remove Officer',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _C.charcoal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Remove "${officer.name}" from the officers list? This cannot be undone.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: _C.darkGray,
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
                      side: const BorderSide(color: _C.borderSoft),
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
                        color: _C.textMid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.error,
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
                      'Remove',
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
    if (confirm != true) return;
    await FirebaseFirestore.instance
        .collection('organizations')
        .doc(widget.orgId)
        .collection('officers')
        .doc(officer.id)
        .delete();
    await _syncOrganizationOfficers();
    // Best-effort: if this officer was linked to a student account (matched
    // by email when they were added), clear the officer tag from it so the
    // mobile app stops showing them as an officer of this org.
    await _clearOfficerUserTag(orgId: widget.orgId, email: officer.email);
    await activity_log.ActivityLogger.log(
      action: 'delete_officer',
      module: 'org_profile',
      details: {'orgId': widget.orgId, 'name': officer.name},
    );
    if (mounted) setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _C.primaryDark),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final horizontalPadding = isMobile ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: _C.pageBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHero(isMobile),
            const SizedBox(height: 20),

            // ── Two-column layout ──────────────────────────────────────────
            if (isMobile) ...[
              _buildAdviserCard(),
              const SizedBox(height: 20),
              _buildOfficersCard(),
              const SizedBox(height: 20),
              _buildMembersCard(),
              const SizedBox(height: 20),
              _buildHierarchyCard(),
              const SizedBox(height: 20),
              _buildSocialCard(),
              const SizedBox(height: 16),
              _buildQuickStatsCard(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column (main content)
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAdviserCard(),
                        const SizedBox(height: 20),
                        _buildOfficersCard(),
                        const SizedBox(height: 20),
                        _buildMembersCard(),
                        const SizedBox(height: 20),
                        _buildHierarchyCard(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right column (sidebar)
                  SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        _buildSocialCard(),
                        const SizedBox(height: 16),
                        _buildQuickStatsCard(),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Profile Hero — cover banner + overlapping logo + quick stats ──────────
  Widget _buildProfileHero(bool isMobile) {
    final logoSize = isMobile ? 76.0 : 92.0;
    final coverHeight = isMobile ? 130.0 : 150.0;
    final sidePad = isMobile ? 16.0 : 26.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.border),
        boxShadow: _DS.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: coverHeight,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_C.primaryDark, _C.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_coverPhotoUrl.isNotEmpty)
                      _buildImageWidget(_coverPhotoUrl, fit: BoxFit.cover)
                    else
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.10,
                          child: Icon(
                            Icons.business_rounded,
                            size: coverHeight * 1.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    // Scrim so the edit button stays legible over a photo.
                    if (_coverPhotoUrl.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.25),
                              Colors.transparent,
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 14,
                child: Material(
                  color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _openEditProfile,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Edit Profile',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: sidePad,
                top: coverHeight - logoSize / 2,
                child: Container(
                  width: logoSize,
                  height: logoSize,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _C.white,
                    shape: BoxShape.circle,
                    boxShadow: _DS.cardShadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ClipOval(
                    child: Container(
                      color: _C.surface,
                      child: _orgLogoUrl.isNotEmpty
                          ? _buildImageWidget(
                              _orgLogoUrl,
                              fit: BoxFit.cover,
                              errorWidget: const Icon(
                                Icons.business,
                                color: _C.textFaint,
                                size: 30,
                              ),
                            )
                          : const Icon(
                              Icons.business,
                              color: _C.textFaint,
                              size: 30,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              sidePad,
              logoSize / 2 + 12,
              sidePad,
              22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      _orgName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _C.charcoal,
                      ),
                    ),
                    if (_orgShortName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _C.primaryDark.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _orgShortName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _C.primaryDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 13,
                      color: _C.textFaint,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _orgEmail,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          color: _C.darkGray,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_orgDescription.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _orgDescription,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.textMid,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: _officersStream,
                      builder: (ctx, snap) => _heroStatChip(
                        Icons.badge_outlined,
                        '${snap.data?.docs.length ?? 0} Officers',
                        _C.primaryDark,
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _membersStream,
                      builder: (ctx, snap) => _heroStatChip(
                        Icons.people_outline_rounded,
                        '${snap.data?.docs.length ?? 0} Members',
                        _C.success,
                      ),
                    ),
                    if (_advisers.isNotEmpty)
                      _heroStatChip(
                        Icons.person_outline_rounded,
                        _advisers.length > 1
                            ? 'Advised by ${_advisers.first.name} +${_advisers.length - 1}'
                            : 'Advised by ${_advisers.first.name}',
                        _C.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
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

  // ── Adviser Card ──────────────────────────────────────────────────────────
  // Orgs can list up to 3 advisers (one of which may be tagged as a Student
  // Adviser rather than a faculty adviser).
  Widget _buildAdviserCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionLabel(
                  'Advisers',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              if (_advisers.length < 3)
                TextButton.icon(
                  onPressed: _openEditProfile,
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: _C.primaryDark,
                  ),
                  label: Text(
                    'Add Adviser',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_advisers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.borderSoft),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_off_outlined,
                    size: 18,
                    color: _C.textFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No adviser assigned',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.darkGray,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _openEditProfile,
                    icon: const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Add Adviser',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < _advisers.length; i++) ...[
                  _adviserTile(_advisers[i], isPrimary: i == 0),
                  if (i != _advisers.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _adviserTile(AdviserInfo a, {required bool isPrimary}) {
    final photo = isPrimary ? _adviserPhotoUrl : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo (only the primary adviser has one, matching admin's schema)
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _C.primaryDark.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(color: _C.border, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo.isNotEmpty
              ? Image(
                  image: _imageProviderFromUrl(photo),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _C.primaryDark,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryDark,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    a.name,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _C.charcoal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _C.successBg,
                      borderRadius: BorderRadius.circular(_DS.radiusPill),
                    ),
                    child: Text(
                      isPrimary ? 'Primary Adviser' : 'Co-Adviser',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _C.success,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (a.isStudentAdviser) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _C.info.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(_DS.radiusPill),
                      ),
                      child: Text(
                        'Student Adviser',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _C.info,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (a.title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  a.title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: _C.textMid,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              if (a.email.isNotEmpty)
                Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 12,
                      color: _C.textFaint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      a.email,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: _C.darkGray,
                      ),
                    ),
                  ],
                ),
              if (a.phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_outlined,
                      size: 12,
                      color: _C.textFaint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      a.phone,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: _C.darkGray,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Officers Card ─────────────────────────────────────────────────────────
  Widget _buildOfficersCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionLabel(
                  'Officers',
                  icon: Icons.people_outline_rounded,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openOfficerModal(),
                icon: const Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: Colors.white,
                ),
                label: Text(
                  'Add Officer',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your organization\'s officers and positions',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.darkGray),
          ),
          const SizedBox(height: 16),

          // Member count pill
          StreamBuilder<QuerySnapshot>(
            stream: _membersStream,
            builder: (ctx, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.borderSoft),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_outline_rounded,
                      size: 16,
                      color: _C.darkGray,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Total Members',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.darkGray,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _C.primaryDark.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(_DS.radiusPill),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Officers list
          StreamBuilder<QuerySnapshot>(
            stream: _officersStream,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: _C.primaryDark),
                );
              }
              final officers = snap.data!.docs
                  .map((d) => OfficerModel.fromFirestore(d))
                  .toList();
              if (officers.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.borderSoft),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.people_outline_rounded,
                          size: 32,
                          color: _C.textFaint,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No officers added yet',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: _C.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: officers
                    .map(
                      (o) => _OfficerTile(
                        officer: o,
                        onEdit: () => _openOfficerModal(officer: o),
                        onDelete: () => _deleteOfficer(o),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Members Card ──────────────────────────────────────────────────────────
  // Displays every user with role: 'org' and orgId == this org — the same
  // record shape the mobile app should read at sign-in to tag a user as a
  // member of this org, and that Members-Only event filtering can key off.
  Widget _buildMembersCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionLabel('Members', icon: Icons.groups_outlined),
              ),
              ElevatedButton.icon(
                onPressed: _showAddMemberDialog,
                icon: const Icon(
                  Icons.person_add_rounded,
                  size: 15,
                  color: Colors.white,
                ),
                label: Text(
                  'Add Member',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Search the admin-managed student list to add or remove members for this org.',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.darkGray),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _membersStream,
            builder: (ctx, snap) {
              // Surface real query errors (e.g. a missing Firestore index or a
              // rules/permission issue) instead of spinning forever — a
              // StreamBuilder in error state never sets hasData, so without
              // this check the loading indicator below would run indefinitely.
              if (snap.hasError) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _C.errorBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: _C.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Couldn\'t load members',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF991B1B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${snap.error}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11.5,
                                color: const Color(0xFF991B1B),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: _C.primaryDark,
                            strokeWidth: 2.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Loading members…',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: _C.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  final an = ((a.data() as Map)['fullName'] ?? '')
                      .toString()
                      .toLowerCase();
                  final bn = ((b.data() as Map)['fullName'] ?? '')
                      .toString()
                      .toLowerCase();
                  return an.compareTo(bn);
                });

              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.borderSoft),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.groups_outlined,
                          size: 32,
                          color: _C.textFaint,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No members yet — add one from the student roster',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: _C.darkGray,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: docs.map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return _MemberTile(
                    docId: d.id,
                    data: m,
                    onRemove: () => _confirmUntagMember(
                      d.id,
                      (m['fullName'] ?? '').toString().isNotEmpty
                          ? (m['fullName'] ?? '').toString()
                          : (m['email'] ?? '').toString(),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Hierarchy Card ────────────────────────────────────────────────────────
  Widget _buildHierarchyCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            'Organization Hierarchy',
            icon: Icons.account_tree_outlined,
          ),
          const SizedBox(height: 4),
          Text(
            'Visual structure of the organization',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.darkGray),
          ),
          const SizedBox(height: 20),
          _HierarchyTree(orgId: widget.orgId, orgName: _orgName),
        ],
      ),
    );
  }

  // ── Social Card ───────────────────────────────────────────────────────────
  Widget _buildSocialCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Social Media', icon: Icons.share_outlined),
          const SizedBox(height: 14),
          _socialRow(Icons.facebook_rounded, 'Facebook', _facebook, _C.info),
          _socialRow(
            Icons.camera_alt_outlined,
            'Instagram',
            _instagram,
            const Color(0xFFE1306C),
          ),
          _socialRow(
            Icons.alternate_email_rounded,
            'Twitter / X',
            _twitter,
            _C.charcoal,
          ),
          _socialRow(Icons.mail_outline_rounded, 'Gmail', _gmail, _C.error),
        ],
      ),
    );
  }

  Widget _socialRow(IconData icon, String label, String value, Color color) {
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hasValue ? color.withOpacity(0.10) : _C.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: hasValue ? color : _C.textFaint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10,
                    color: _C.textFaint,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  hasValue ? value : 'Not set',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: hasValue ? _C.textMid : _C.textFaint,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Stats Card ──────────────────────────────────────────────────────
  Widget _buildQuickStatsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Quick Stats', icon: Icons.bar_chart_rounded),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: _officersStream,
            builder: (ctx, snap) {
              final officerCount = snap.data?.docs.length ?? 0;
              return Column(
                children: [
                  _statRow(
                    Icons.badge_outlined,
                    'Total Officers',
                    officerCount.toString(),
                    _C.primaryDark,
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: _membersStream,
                    builder: (ctx2, snap2) => _statRow(
                      Icons.people_outline_rounded,
                      'Total Members',
                      (snap2.data?.docs.length ?? 0).toString(),
                      _C.success,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.borderSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.darkGray),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(_DS.radiusPill),
            ),
            child: Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Members — account creation, batch import, resend/archive
  // ═════════════════════════════════════════════════════════════════════════

  // Members are students too — same approach as Officers. Instead of
  // creating a second login, tag the member's existing student account
  // (matched by email) with this org, so the mobile app can read the
  // signed-in student's own `users` doc and show "Member of {org}" / filter
  // this org's Members-Only events, with no separate credentials involved.
  Future<void> _toggleMemberArchived(
    String uid,
    bool archived,
    String name,
  ) async {
    try {
      final updates = {'archived': !archived};
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updates, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .set(updates, SetOptions(merge: true));
      _snack(archived ? '$name restored.' : '$name archived.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _confirmResendMemberCredentials(
    String uid,
    Map<String, dynamic> member,
  ) async {
    final email = (member['email'] ?? '').toString();
    if (email.isEmpty) {
      _snack('No email on file for this member.', isError: true);
      return;
    }
    _snack(
      'This member already uses their existing student account. No new credentials are created.',
    );
  }

  Future<Map<String, dynamic>> _createMemberAccount(
    Map<String, String> row,
  ) async {
    final email = row['email']?.trim() ?? '';
    final memberId = row['memberId']?.trim() ?? '';
    final fullName = row['fullName']?.trim() ?? '';

    if (email.isEmpty) {
      return {'email': null, 'fullName': fullName, 'memberId': memberId};
    }

    final tagged = await _tagMemberAccount(email: email, memberId: memberId);
    return {
      'email': email,
      'fullName': fullName,
      'memberId': memberId,
      'tagged': tagged,
    };
  }

  Future<bool> _tagMemberAccount({
    required String email,
    required String memberId,
  }) async {
    final tagged = await _tagMatchingStudentAccount(
      email: email,
      updates: {
        'orgId': widget.orgId,
        'orgName': _orgName,
        'orgRole': 'member',
        'memberId': memberId,
        'isOrgMember': true,
      },
    );

    if (tagged) {
      await activity_log.ActivityLogger.log(
        action: 'tag_member',
        module: 'org_profile',
        details: {'orgId': widget.orgId, 'email': email.trim().toLowerCase()},
      );
    }
    return tagged;
  }

  // Removes this org's tag from a member's student account (their account
  // itself is untouched — they simply stop being tagged to this org).
  Future<void> _untagMember(String uid, String name) async {
    try {
      await _clearStudentAccountTagByUid(
        uid: uid,
        updates: {
          'orgId': FieldValue.delete(),
          'orgName': FieldValue.delete(),
          'orgRole': FieldValue.delete(),
          'memberId': FieldValue.delete(),
          'isOrgMember': FieldValue.delete(),
        },
      );
      await activity_log.ActivityLogger.log(
        action: 'untag_member',
        module: 'org_profile',
        details: {'orgId': widget.orgId, 'uid': uid},
      );
      _snack('$name removed from members');
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _confirmUntagMember(String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _C.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_remove_outlined,
                      color: _C.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Remove Member',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _C.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Remove "$name" from this org\'s members? Their student account itself is not affected — this only removes the org tag.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.darkGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.borderSoft),
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
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.error,
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
                    child: Text(
                      'Remove',
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
    if (confirm == true) await _untagMember(uid, name);
  }

  void _showAddMemberDialog() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool isLoading = false;

    Future<void> loadStudents(String query) async {
      if (!mounted) return;
      setState(() => isLoading = true);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .orderBy('fullName')
            .get();
        final filtered = snap.docs
            .map((doc) {
              final data = doc.data();
              final firstName = (data['firstName'] ?? '').toString();
              final lastName = (data['lastName'] ?? '').toString();
              final fullName = (data['fullName'] ?? '').toString();
              final email = (data['email'] ?? '').toString();
              final studentId = (data['studentId'] ?? '').toString();
              final displayName = fullName.isNotEmpty
                  ? fullName
                  : [
                      firstName,
                      lastName,
                    ].where((s) => s.isNotEmpty).join(' ').trim();
              final isMember =
                  (data['orgId'] ?? '') == widget.orgId &&
                  (data['orgRole'] ?? '') == 'member';

              return {
                'uid': doc.id,
                'name': displayName,
                'email': email,
                'studentId': studentId,
                'isMember': isMember,
              };
            })
            .where((item) {
              final q = query.trim().toLowerCase();
              if (q.isEmpty) return true;
              final name = (item['name'] as String).toLowerCase();
              final email = (item['email'] as String).toLowerCase();
              final studentId = (item['studentId'] as String).toLowerCase();
              return name.contains(q) ||
                  email.contains(q) ||
                  studentId.contains(q);
            })
            .toList();

        if (mounted) {
          setState(() {
            results = filtered;
            isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> localLoad(String query) async {
            setDialogState(() => isLoading = true);
            try {
              final snap = await FirebaseFirestore.instance
                  .collection('students')
                  .orderBy('fullName')
                  .get();
              final filtered = snap.docs
                  .map((doc) {
                    final data = doc.data();
                    final firstName = (data['firstName'] ?? '').toString();
                    final lastName = (data['lastName'] ?? '').toString();
                    final fullName = (data['fullName'] ?? '').toString();
                    final email = (data['email'] ?? '').toString();
                    final studentId = (data['studentId'] ?? '').toString();
                    final displayName = fullName.isNotEmpty
                        ? fullName
                        : [
                            firstName,
                            lastName,
                          ].where((s) => s.isNotEmpty).join(' ').trim();
                    final isMember =
                        (data['orgId'] ?? '') == widget.orgId &&
                        (data['orgRole'] ?? '') == 'member';
                    return {
                      'uid': doc.id,
                      'name': displayName,
                      'email': email,
                      'studentId': studentId,
                      'isMember': isMember,
                    };
                  })
                  .where((item) {
                    final q = query.trim().toLowerCase();
                    if (q.isEmpty) return true;
                    final name = (item['name'] as String).toLowerCase();
                    final email = (item['email'] as String).toLowerCase();
                    final studentId = (item['studentId'] as String)
                        .toLowerCase();
                    return name.contains(q) ||
                        email.contains(q) ||
                        studentId.contains(q);
                  })
                  .toList();
              setDialogState(() {
                results = filtered;
                isLoading = false;
              });
            } catch (_) {
              setDialogState(() => isLoading = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Container(
              width: 560,
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
                          color: _C.primaryDark.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: _C.primaryDark,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add or Remove Members',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _C.charcoal,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search the admin-managed student list and add or remove members for this org.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: _C.darkGray,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: searchCtrl,
                    decoration: _inputDecoration(
                      'Search student',
                      hint: 'Name, email, or student ID',
                      icon: Icons.search_rounded,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    onChanged: (value) => localLoad(value),
                  ),
                  const SizedBox(height: 14),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: _C.primaryDark),
                      ),
                    )
                  else if (results.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _C.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _C.borderSoft),
                      ),
                      child: Text(
                        'No students found for this search.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: _C.darkGray,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          final name = (item['name'] ?? '').toString();
                          final email = (item['email'] ?? '').toString();
                          final studentId = (item['studentId'] ?? '')
                              .toString();
                          final isMember = item['isMember'] == true;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _C.borderSoft),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isNotEmpty
                                            ? name
                                            : 'Unnamed student',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _C.charcoal,
                                        ),
                                      ),
                                      if (email.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 12,
                                            color: _C.darkGray,
                                          ),
                                        ),
                                      ],
                                      if (studentId.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: $studentId',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            color: _C.textFaint,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    final uid = item['uid'].toString();
                                    final memberName = name.isNotEmpty
                                        ? name
                                        : email;
                                    if (isMember) {
                                      await _untagMember(uid, memberName);
                                    } else {
                                      final tagged = await _tagMemberAccount(
                                        email: email,
                                        memberId: studentId,
                                      );
                                      _snack(
                                        tagged
                                            ? '$memberName added as a member.'
                                            : 'No student account found for that email yet.',
                                        isError: !tagged,
                                      );
                                    }
                                    await localLoad(searchCtrl.text);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isMember
                                        ? _C.error
                                        : _C.primaryDark,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    isMember ? 'Remove' : 'Add',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  void _showMemberBatchImportDialog() {
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
          child: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                  decoration: BoxDecoration(
                    color: _C.primaryDark,
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
                          'Batch Import Members',
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
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                        'Select File',
                        icon: Icons.attach_file_rounded,
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
                                ? _C.surface
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: fileName.isEmpty
                                  ? _C.borderSoft
                                  : _C.success,
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
                                    ? _C.textFaint
                                    : _C.success,
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
                                      ? _C.darkGray
                                      : _C.success,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Supported: .xlsx, .xls, .csv',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: _C.textFaint,
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
                                'Columns (in order): Member ID (optional) · Full Name · Email',
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
                            backgroundColor: _C.borderSoft,
                            color: _C.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Importing members…',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: _C.darkGray,
                          ),
                        ),
                      ],
                      if (resultMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: resultIsError
                                ? _C.errorBg
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
                                color: resultIsError ? _C.error : _C.success,
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
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  decoration: BoxDecoration(
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE8ECF0)),
                    ),
                    color: _C.surface,
                    borderRadius: const BorderRadius.vertical(
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
                            color: _C.darkGray,
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
                                  final rows = await _parseMemberFile(
                                    pickedFile!,
                                  );
                                  if (rows.isEmpty) {
                                    throw Exception(
                                      'No valid data found. Check column order.',
                                    );
                                  }
                                  int success = 0, failed = 0, failedEmails = 0;
                                  for (final r in rows) {
                                    try {
                                      final createdCred =
                                          await _createMemberAccount(r);
                                      // _createMemberAccount already tries to
                                      // send + queue on failure; track it here
                                      // only to report an accurate summary.
                                      if (createdCred['email'] == null) {
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
                                        'Import complete: $success created, $failed skipped.';
                                    resultIsError = failed > 0 && success == 0;
                                  });
                                  if (success > 0) {
                                    Future.delayed(
                                      const Duration(seconds: 2),
                                      () {
                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          _snack(
                                            '$success members imported successfully.',
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
                          backgroundColor: _C.primaryDark,
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

  Future<List<Map<String, String>>> _parseMemberFile(XFile xfile) async {
    final bytes = await xfile.readAsBytes();
    final name = xfile.name.toLowerCase();
    final List<Map<String, String>> rows = [];
    if (name.endsWith('.csv')) {
      final csvString = String.fromCharCodes(bytes);
      final parsed = const CsvToListConverter().convert(csvString);
      for (int i = 1; i < parsed.length; i++) {
        final row = parsed[i];
        if (row.length >= 2) {
          final hasId = row.length >= 3;
          rows.add({
            'memberId': hasId ? row[0].toString().trim() : '',
            'fullName': hasId
                ? row[1].toString().trim()
                : row[0].toString().trim(),
            'email': hasId
                ? row[2].toString().trim()
                : row[1].toString().trim(),
          });
        }
      }
    } else {
      final excel = Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        for (int i = 1; i < (sheet?.rows.length ?? 0); i++) {
          final row = sheet!.rows[i];
          if (row.length >= 2) {
            final hasId = row.length >= 3;
            rows.add({
              'memberId': hasId ? (row[0]?.value?.toString().trim() ?? '') : '',
              'fullName': hasId
                  ? (row[1]?.value?.toString().trim() ?? '')
                  : (row[0]?.value?.toString().trim() ?? ''),
              'email': hasId
                  ? (row[2]?.value?.toString().trim() ?? '')
                  : (row[1]?.value?.toString().trim() ?? ''),
            });
          }
        }
        break;
      }
    }
    rows.removeWhere((r) => r['fullName']!.isEmpty || r['email']!.isEmpty);
    return rows;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member Tile — row in the Members card
// ─────────────────────────────────────────────────────────────────────────────
class _MemberTile extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onRemove;
  const _MemberTile({
    required this.docId,
    required this.data,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['fullName'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final memberId = (data['memberId'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _C.primaryDark.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _C.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _C.charcoal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (memberId.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· $memberId',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: _C.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: _C.darkGray,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onRemove,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _C.error),
              foregroundColor: _C.error,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Remove',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Officer Tile
// ─────────────────────────────────────────────────────────────────────────────
class _OfficerTile extends StatefulWidget {
  final OfficerModel officer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _OfficerTile({
    required this.officer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_OfficerTile> createState() => _OfficerTileState();
}

class _OfficerTileState extends State<_OfficerTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.officer;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hovered ? _C.primaryDark.withOpacity(0.03) : _C.surface,
          borderRadius: BorderRadius.circular(_DS.radiusMd),
          border: Border.all(
            color: _hovered ? _C.primaryDark.withOpacity(0.2) : _C.borderSoft,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _C.primaryDark.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: o.photoUrl.isNotEmpty
                  ? _buildImageWidget(
                      o.photoUrl,
                      fit: BoxFit.cover,
                      errorWidget: _initials(o.name),
                    )
                  : _initials(o.name),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        o.name,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _C.charcoal,
                        ),
                      ),
                      if (o.isCaptain) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _C.warningBg,
                            borderRadius: BorderRadius.circular(_DS.radiusPill),
                          ),
                          child: Text(
                            'Captain',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _C.warning,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.position,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _C.primaryDark,
                    ),
                  ),
                  if (o.email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          size: 11,
                          color: _C.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          o.email,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: _C.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (o.phone.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 11,
                          color: _C.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          o.phone,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: _C.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Action buttons
            AnimatedOpacity(
              opacity: _hovered ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 150),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconBtn(Icons.edit_outlined, _C.info, widget.onEdit, 'Edit'),
                  const SizedBox(width: 4),
                  _iconBtn(
                    Icons.delete_outline_rounded,
                    _C.error,
                    widget.onDelete,
                    'Remove',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials(String name) => Center(
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: GoogleFonts.beVietnamPro(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _C.primaryDark,
      ),
    ),
  );

  Widget _iconBtn(
    IconData icon,
    Color color,
    VoidCallback onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hierarchy Tree
// ─────────────────────────────────────────────────────────────────────────────
String _currentAcademicYearLabel() {
  final now = DateTime.now();
  final startYear = now.month >= 8 ? now.year : now.year - 1;
  return '$startYear - ${startYear + 1}';
}

class _HierarchyTree extends StatelessWidget {
  final String orgId;
  final String orgName;
  const _HierarchyTree({required this.orgId, required this.orgName});

  static const double _boxWidth = 112;
  static const double _spacing = 18;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .collection('officers')
          .orderBy('positionRank', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _C.primaryDark),
          );
        }
        final officers = snap.data!.docs
            .map((d) => OfficerModel.fromFirestore(d))
            .toList();
        if (officers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.borderSoft),
            ),
            child: Center(
              child: Text(
                'No officers to display',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.darkGray,
                ),
              ),
            ),
          );
        }

        final tier1 = officers.where((o) => o.positionRank <= 1).toList();
        final tier2 = officers.where((o) => o.positionRank == 2).toList();
        final tier3 = officers.where((o) => o.positionRank >= 3).toList();
        final tiers = [tier1, tier2, tier3].where((t) => t.isNotEmpty).toList();

        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .where('orgId', isEqualTo: orgId)
              .where('orgRole', isEqualTo: 'member')
              .limit(6)
              .get(),
          builder: (context, memberSnap) {
            final members = memberSnap.data?.docs ?? [];
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_DS.radiusLg),
                gradient: LinearGradient(
                  colors: [
                    _C.primaryDark.withAlpha(15),
                    _C.accent.withAlpha(10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '${orgName.toUpperCase()} OFFICERS',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _C.charcoal,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A.Y. ${_currentAcademicYearLabel()}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.darkGray,
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (var i = 0; i < tiers.length; i++) ...[
                    _tierRow(tiers[i], isTop: i == 0),
                    if (i < tiers.length - 1)
                      _TierConnector(childCount: tiers[i + 1].length),
                  ],
                  if (members.isNotEmpty) ...[
                    _TierConnector(childCount: 1),
                    _MembersRow(members: members),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _tierRow(List<OfficerModel> officers, {bool isTop = false}) {
    // A bus-style connector (drawn in _TierConnector) assumes a single,
    // non-wrapping row laid out with _boxWidth/_spacing — fall back to a
    // plain Wrap for unusually large tiers where that assumption breaks.
    if (officers.length <= 6) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < officers.length; i++) ...[
            if (i > 0) const SizedBox(width: _spacing),
            _HierarchyBox(officer: officers[i], isTop: isTop, width: _boxWidth),
          ],
        ],
      );
    }
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: officers
            .map(
              (o) => _HierarchyBox(officer: o, isTop: isTop, width: _boxWidth),
            )
            .toList(),
      ),
    );
  }
}

// Draws a trunk-and-bus connector between two tiers: a single vertical line
// down from the parent row's center, a horizontal bus, and a vertical stub
// down into each box of the next tier — closer to a real org chart than a
// single straight line, without needing per-officer parent/child data.
class _TierConnector extends StatelessWidget {
  final int childCount;
  const _TierConnector({required this.childCount});

  static const double _boxWidth = _HierarchyTree._boxWidth;
  static const double _spacing = _HierarchyTree._spacing;
  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    if (childCount <= 1) {
      return SizedBox(
        height: _height,
        child: Center(
          child: Container(width: 2, color: _C.primaryDark.withAlpha(76)),
        ),
      );
    }
    final count = childCount.clamp(1, 6);
    final totalWidth = count * _boxWidth + (count - 1) * _spacing;
    return SizedBox(
      height: _height,
      width: totalWidth,
      child: CustomPaint(
        painter: _BusConnectorPainter(
          childCount: count,
          boxWidth: _boxWidth,
          spacing: _spacing,
          color: _C.primaryDark.withAlpha(76),
        ),
      ),
    );
  }
}

class _BusConnectorPainter extends CustomPainter {
  final int childCount;
  final double boxWidth;
  final double spacing;
  final Color color;
  _BusConnectorPainter({
    required this.childCount,
    required this.boxWidth,
    required this.spacing,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final busY = size.height * 0.45;
    final centerX = size.width / 2;

    canvas.drawLine(Offset(centerX, 0), Offset(centerX, busY), paint);

    final firstCenter = boxWidth / 2;
    final lastCenter = size.width - boxWidth / 2;
    canvas.drawLine(Offset(firstCenter, busY), Offset(lastCenter, busY), paint);

    for (var i = 0; i < childCount; i++) {
      final cx = i * (boxWidth + spacing) + boxWidth / 2;
      canvas.drawLine(Offset(cx, busY), Offset(cx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BusConnectorPainter oldDelegate) =>
      oldDelegate.childCount != childCount || oldDelegate.color != color;
}

class _HierarchyBox extends StatelessWidget {
  final OfficerModel officer;
  final bool isTop;
  final double width;
  const _HierarchyBox({
    required this.officer,
    this.isTop = false,
    this.width = 112,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Portrait-style photo frame, matching a printed org-chart card
          // rather than a small circular avatar.
          Container(
            width: width,
            height: width * 1.15,
            decoration: BoxDecoration(
              color: _C.primaryDark.withAlpha(18),
              borderRadius: BorderRadius.circular(_DS.radiusSm),
              border: Border.all(
                color: isTop ? _C.primaryDark : _C.borderSoft,
                width: isTop ? 1.6 : 1.2,
              ),
              boxShadow: _DS.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: officer.photoUrl.isNotEmpty
                ? _buildImageWidget(
                    officer.photoUrl,
                    fit: BoxFit.cover,
                    errorWidget: _initials(),
                  )
                : _initials(),
          ),
          const SizedBox(height: 6),
          Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _C.white,
              borderRadius: BorderRadius.circular(_DS.radiusSm),
              border: Border.all(color: _C.borderSoft),
            ),
            child: Column(
              children: [
                Text(
                  officer.name,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _C.primaryDark,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  officer.position,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10,
                    color: _C.darkGray,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      officer.name.isNotEmpty ? officer.name[0].toUpperCase() : '?',
      style: GoogleFonts.beVietnamPro(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _C.primaryDark,
      ),
    ),
  );
}

class _MembersRow extends StatelessWidget {
  final List<QueryDocumentSnapshot> members;
  const _MembersRow({required this.members});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.borderSoft),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 14,
                color: _C.darkGray,
              ),
              const SizedBox(width: 6),
              Text(
                'Members (${members.length}+)',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.darkGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: members.map((m) {
              final data = m.data() as Map<String, dynamic>;
              final name = data['fullName'] ?? data['name'] ?? 'Member';
              final photo = data['photoUrl'] ?? '';
              return Tooltip(
                message: name,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _C.primaryDark.withOpacity(0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: _C.white, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photo.isNotEmpty
                      ? Image(
                          image: _imageProviderFromUrl(photo),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              name[0].toUpperCase(),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _C.primaryDark,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            name[0].toUpperCase(),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _C.primaryDark,
                            ),
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Org Profile Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _EditOrgProfileSheet extends StatefulWidget {
  final String orgId;
  final String orgName, shortName, email, description, logoUrl, coverPhotoUrl;
  final List<AdviserInfo> advisers;
  final String adviserPhotoUrl;
  final String facebook, instagram, twitter, gmail;
  final VoidCallback onSaved;

  const _EditOrgProfileSheet({
    required this.orgId,
    required this.orgName,
    required this.shortName,
    required this.email,
    required this.description,
    required this.logoUrl,
    required this.coverPhotoUrl,
    required this.advisers,
    required this.adviserPhotoUrl,
    required this.facebook,
    required this.instagram,
    required this.twitter,
    required this.gmail,
    required this.onSaved,
  });

  @override
  State<_EditOrgProfileSheet> createState() => _EditOrgProfileSheetState();
}

class _EditOrgProfileSheetState extends State<_EditOrgProfileSheet> {
  final _descCtrl = TextEditingController();
  // Primary adviser (slot 1 — the only one with a photo, matching the
  // existing org-doc schema admin already writes to).
  final _a1NameCtrl = TextEditingController();
  final _a1TitleCtrl = TextEditingController();
  final _a1EmailCtrl = TextEditingController();
  final _a1PhoneCtrl = TextEditingController();
  String _a1Type = 'faculty';
  // Co-adviser (slot 2 — optional).
  final _a2NameCtrl = TextEditingController();
  final _a2TitleCtrl = TextEditingController();
  final _a2EmailCtrl = TextEditingController();
  final _a2PhoneCtrl = TextEditingController();
  String _a2Type = 'faculty';
  // Third adviser (slot 3 — optional, capped at 3 total advisers per org).
  // Commonly used for a Student Adviser, but any slot can be marked as one.
  final _a3NameCtrl = TextEditingController();
  final _a3TitleCtrl = TextEditingController();
  final _a3EmailCtrl = TextEditingController();
  final _a3PhoneCtrl = TextEditingController();
  String _a3Type = 'student';
  final _fbCtrl = TextEditingController();
  final _igCtrl = TextEditingController();
  final _twCtrl = TextEditingController();
  final _gmCtrl = TextEditingController();

  String? _logoUrl;
  String? _coverPhotoUrl;
  String? _adviserPhotoUrl;
  bool _hasSecondAdviser = false;
  bool _hasThirdAdviser = false;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _descCtrl.text = widget.description;
    if (widget.advisers.isNotEmpty) {
      _a1NameCtrl.text = widget.advisers[0].name;
      _a1TitleCtrl.text = widget.advisers[0].title;
      _a1EmailCtrl.text = widget.advisers[0].email;
      _a1PhoneCtrl.text = widget.advisers[0].phone;
      _a1Type = widget.advisers[0].type;
    }
    if (widget.advisers.length > 1) {
      _hasSecondAdviser = true;
      _a2NameCtrl.text = widget.advisers[1].name;
      _a2TitleCtrl.text = widget.advisers[1].title;
      _a2EmailCtrl.text = widget.advisers[1].email;
      _a2PhoneCtrl.text = widget.advisers[1].phone;
      _a2Type = widget.advisers[1].type;
    }
    if (widget.advisers.length > 2) {
      _hasThirdAdviser = true;
      _a3NameCtrl.text = widget.advisers[2].name;
      _a3TitleCtrl.text = widget.advisers[2].title;
      _a3EmailCtrl.text = widget.advisers[2].email;
      _a3PhoneCtrl.text = widget.advisers[2].phone;
      _a3Type = widget.advisers[2].type;
    }
    _fbCtrl.text = widget.facebook;
    _igCtrl.text = widget.instagram;
    _twCtrl.text = widget.twitter;
    _gmCtrl.text = widget.gmail;
    _logoUrl = widget.logoUrl.isNotEmpty ? widget.logoUrl : null;
    _coverPhotoUrl = widget.coverPhotoUrl.isNotEmpty
        ? widget.coverPhotoUrl
        : null;
    _adviserPhotoUrl = widget.adviserPhotoUrl.isNotEmpty
        ? widget.adviserPhotoUrl
        : null;
  }

  @override
  void dispose() {
    for (final c in [
      _descCtrl,
      _a1NameCtrl,
      _a1TitleCtrl,
      _a1EmailCtrl,
      _a1PhoneCtrl,
      _a2NameCtrl,
      _a2TitleCtrl,
      _a2EmailCtrl,
      _a2PhoneCtrl,
      _a3NameCtrl,
      _a3TitleCtrl,
      _a3EmailCtrl,
      _a3PhoneCtrl,
      _fbCtrl,
      _igCtrl,
      _twCtrl,
      _gmCtrl,
    ])
      c.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    setState(() => _isUploadingLogo = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final mime = _mimeTypeFromBytes(file.bytes!);
      setState(
        () => _logoUrl = 'data:$mime;base64,${base64Encode(file.bytes!)}',
      );
    } catch (e) {
      if (mounted) _snack('Failed to load image: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _pickCoverPhoto() async {
    setState(() => _isUploadingCover = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final mime = _mimeTypeFromBytes(file.bytes!);
      setState(
        () => _coverPhotoUrl = 'data:$mime;base64,${base64Encode(file.bytes!)}',
      );
    } catch (e) {
      if (mounted) _snack('Failed to load image: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  Future<void> _pickAdviserPhoto() async {
    setState(() => _isUploadingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final mime = _mimeTypeFromBytes(file.bytes!);
      setState(
        () =>
            _adviserPhotoUrl = 'data:$mime;base64,${base64Encode(file.bytes!)}',
      );
    } catch (e) {
      if (mounted) _snack('Failed to load image: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    final emailFields = <String, String>{
      'Primary adviser': _a1EmailCtrl.text.trim(),
      if (_hasSecondAdviser) 'Second adviser': _a2EmailCtrl.text.trim(),
      if (_hasThirdAdviser) 'Third adviser': _a3EmailCtrl.text.trim(),
    };
    for (final entry in emailFields.entries) {
      if (entry.value.isNotEmpty && !_emailPattern.hasMatch(entry.value)) {
        _snack(
          '${entry.key} email is not a valid email address.',
          isError: true,
        );
        return;
      }
    }
    if (_a1NameCtrl.text.trim().isEmpty) {
      _snack('Primary adviser name is required.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    final advisers = <AdviserInfo>[
      AdviserInfo(
        name: _a1NameCtrl.text.trim(),
        title: _a1TitleCtrl.text.trim(),
        email: _a1EmailCtrl.text.trim(),
        phone: _a1PhoneCtrl.text.trim(),
        type: _a1Type,
      ),
      if (_hasSecondAdviser && _a2NameCtrl.text.trim().isNotEmpty)
        AdviserInfo(
          name: _a2NameCtrl.text.trim(),
          title: _a2TitleCtrl.text.trim(),
          email: _a2EmailCtrl.text.trim(),
          phone: _a2PhoneCtrl.text.trim(),
          type: _a2Type,
        ),
      if (_hasThirdAdviser && _a3NameCtrl.text.trim().isNotEmpty)
        AdviserInfo(
          name: _a3NameCtrl.text.trim(),
          title: _a3TitleCtrl.text.trim(),
          email: _a3EmailCtrl.text.trim(),
          phone: _a3PhoneCtrl.text.trim(),
          type: _a3Type,
        ),
    ].where((a) => !a.isEmpty).toList();
    final primary = advisers.isNotEmpty ? advisers.first : const AdviserInfo();

    final payload = {
      'description': _descCtrl.text.trim(),
      // Legacy singular fields mirror the primary adviser — admin's
      // organization_management screen and other places that still read
      // these directly keep working unchanged.
      'adviserName': primary.name,
      'adviserTitle': primary.title,
      'adviserEmail': primary.email,
      'adviserPhone': primary.phone,
      'advisers': advisers.map((a) => a.toMap()).toList(),
      if (_adviserPhotoUrl != null) 'adviserPhotoUrl': _adviserPhotoUrl,
      'facebook': _fbCtrl.text.trim(),
      'instagram': _igCtrl.text.trim(),
      'twitter': _twCtrl.text.trim(),
      'gmail': _gmCtrl.text.trim(),
      if (_logoUrl != null) 'logoUrl': _logoUrl,
      if (_coverPhotoUrl != null) 'coverPhotoUrl': _coverPhotoUrl,
    };
    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .update(payload);
      await _syncAdviserRoleDocs(payload);
      await activity_log.ActivityLogger.log(
        action: 'update_org_profile',
        module: 'org_profile',
        details: {'orgId': widget.orgId},
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _syncAdviserRoleDocs(Map<String, dynamic> payload) async {
    try {
      final roleSnap = await FirebaseFirestore.instance
          .collection('adviser_roles')
          .where('orgId', isEqualTo: widget.orgId)
          .get();
      final updates = <String, dynamic>{
        'adviserName': payload['adviserName'],
        'adviserTitle': payload['adviserTitle'],
        'adviserEmail': payload['adviserEmail'],
        'adviserPhone': payload['adviserPhone'],
      };
      if (payload.containsKey('adviserPhotoUrl'))
        updates['adviserPhotoUrl'] = payload['adviserPhotoUrl'];
      if (payload.containsKey('adviserTitle'))
        updates['adviserRank'] = payload['adviserTitle'];
      if (widget.shortName.isNotEmpty) updates['shortName'] = widget.shortName;
      if (payload.containsKey('logoUrl'))
        updates['logoUrl'] = payload['logoUrl'];
      for (final doc in roleSnap.docs) {
        await doc.reference.update(updates);
      }
    } catch (e) {
      debugPrint('Failed to sync adviser_roles: $e');
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: isError ? _C.error : _C.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  Widget _adviserFields({
    required TextEditingController nameCtrl,
    required TextEditingController titleCtrl,
    required TextEditingController phoneCtrl,
    required TextEditingController emailCtrl,
    required String type,
    required ValueChanged<String> onTypeChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _adviserTypeChip(
                label: 'Faculty Adviser',
                icon: Icons.school_outlined,
                selected: type == 'faculty',
                onTap: () => onTypeChanged('faculty'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _adviserTypeChip(
                label: 'Student Adviser',
                icon: Icons.badge_outlined,
                selected: type == 'student',
                onTap: () => onTypeChanged('student'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: nameCtrl,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.charcoal,
                ),
                decoration: _inputDecoration(
                  'Full Name',
                  hint: 'Adviser full name',
                  icon: Icons.person_outline,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: titleCtrl,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.charcoal,
                ),
                decoration: _inputDecoration(
                  'Title',
                  hint: 'e.g. Instructor',
                  icon: Icons.badge_outlined,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneCtrl,
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.charcoal),
          decoration: _inputDecoration(
            'Phone',
            hint: '+63 xxx xxx xxxx',
            icon: Icons.phone_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailCtrl,
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.charcoal),
          decoration: _inputDecoration(
            'Email',
            hint: 'adviser@example.com',
            icon: Icons.email_outlined,
          ),
        ),
      ],
    );
  }

  Widget _adviserTypeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _C.primaryDark.withOpacity(0.08) : _C.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _C.primaryDark.withOpacity(0.4) : _C.borderSoft,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? _C.primaryDark : _C.textFaint,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? _C.primaryDark : _C.darkGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
            decoration: const BoxDecoration(
              color: _C.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                        'Edit Organization Profile',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Update info, adviser details & social links',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
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
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  _sectionLabel(
                    'Organization Logo',
                    icon: Icons.image_outlined,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _C.surface,
                          borderRadius: BorderRadius.circular(_DS.radiusMd),
                          border: Border.all(color: _C.borderSoft),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _logoUrl != null
                            ? _buildImageWidget(
                                _logoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: const Icon(
                                  Icons.business,
                                  color: _C.textFaint,
                                ),
                              )
                            : const Icon(Icons.business, color: _C.textFaint),
                      ),
                      const SizedBox(width: 14),
                      OutlinedButton.icon(
                        onPressed: _isUploadingLogo ? null : _pickLogo,
                        icon: _isUploadingLogo
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_outlined, size: 16),
                        label: Text(
                          _isUploadingLogo ? 'Uploading…' : 'Upload Logo',
                          style: GoogleFonts.beVietnamPro(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _C.borderSoft),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          foregroundColor: _C.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Cover photo
                  _sectionLabel('Cover Photo', icon: Icons.panorama_outlined),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 110,
                    decoration: BoxDecoration(
                      color: _C.surface,
                      borderRadius: BorderRadius.circular(_DS.radiusMd),
                      border: Border.all(color: _C.borderSoft),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _coverPhotoUrl != null
                        ? _buildImageWidget(
                            _coverPhotoUrl!,
                            fit: BoxFit.cover,
                            errorWidget: const Icon(
                              Icons.panorama_outlined,
                              color: _C.textFaint,
                            ),
                          )
                        : const Icon(
                            Icons.panorama_outlined,
                            color: _C.textFaint,
                            size: 28,
                          ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isUploadingCover ? null : _pickCoverPhoto,
                    icon: _isUploadingCover
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined, size: 16),
                    label: Text(
                      _isUploadingCover ? 'Uploading…' : 'Upload Cover Photo',
                      style: GoogleFonts.beVietnamPro(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.borderSoft),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      foregroundColor: _C.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Org name (read-only)
                  _sectionLabel(
                    'Organization Name',
                    icon: Icons.business_outlined,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _C.surface,
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      border: Border.all(color: _C.borderSoft),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: _C.textFaint,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.orgName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: _C.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _sectionLabel(
                    'Description',
                    icon: Icons.description_outlined,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.charcoal,
                    ),
                    decoration: _inputDecoration('Organization description…'),
                  ),
                  const SizedBox(height: 22),

                  // Adviser section — up to 2 advisers per org
                  Row(
                    children: [
                      Expanded(
                        child: _sectionLabel(
                          'Primary Adviser',
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Adviser photo (primary adviser only)
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _C.primaryDark.withOpacity(0.10),
                          shape: BoxShape.circle,
                          border: Border.all(color: _C.borderSoft, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _adviserPhotoUrl != null
                            ? _buildImageWidget(
                                _adviserPhotoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: const Icon(
                                  Icons.person,
                                  color: _C.textFaint,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                color: _C.textFaint,
                                size: 28,
                              ),
                      ),
                      const SizedBox(width: 14),
                      OutlinedButton.icon(
                        onPressed: _isUploadingPhoto ? null : _pickAdviserPhoto,
                        icon: _isUploadingPhoto
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_outlined, size: 16),
                        label: Text(
                          _isUploadingPhoto ? 'Uploading…' : 'Upload Photo',
                          style: GoogleFonts.beVietnamPro(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _C.borderSoft),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          foregroundColor: _C.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _adviserFields(
                    nameCtrl: _a1NameCtrl,
                    titleCtrl: _a1TitleCtrl,
                    phoneCtrl: _a1PhoneCtrl,
                    emailCtrl: _a1EmailCtrl,
                    type: _a1Type,
                    onTypeChanged: (t) => setState(() => _a1Type = t),
                  ),
                  const SizedBox(height: 18),

                  if (_hasSecondAdviser) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _sectionLabel(
                            'Co-Adviser',
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove co-adviser',
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: _C.error,
                          ),
                          onPressed: () => setState(() {
                            _hasSecondAdviser = false;
                            _a2NameCtrl.clear();
                            _a2TitleCtrl.clear();
                            _a2EmailCtrl.clear();
                            _a2PhoneCtrl.clear();
                            _a2Type = 'faculty';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _adviserFields(
                      nameCtrl: _a2NameCtrl,
                      titleCtrl: _a2TitleCtrl,
                      phoneCtrl: _a2PhoneCtrl,
                      emailCtrl: _a2EmailCtrl,
                      type: _a2Type,
                      onTypeChanged: (t) => setState(() => _a2Type = t),
                    ),
                    const SizedBox(height: 18),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _hasSecondAdviser = true),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: Text(
                          'Add Second Adviser',
                          style: GoogleFonts.beVietnamPro(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _C.borderSoft),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          foregroundColor: _C.primaryDark,
                        ),
                      ),
                    ),

                  if (_hasThirdAdviser) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _sectionLabel(
                            'Third Adviser',
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove third adviser',
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: _C.error,
                          ),
                          onPressed: () => setState(() {
                            _hasThirdAdviser = false;
                            _a3NameCtrl.clear();
                            _a3TitleCtrl.clear();
                            _a3EmailCtrl.clear();
                            _a3PhoneCtrl.clear();
                            _a3Type = 'student';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _adviserFields(
                      nameCtrl: _a3NameCtrl,
                      titleCtrl: _a3TitleCtrl,
                      phoneCtrl: _a3PhoneCtrl,
                      emailCtrl: _a3EmailCtrl,
                      type: _a3Type,
                      onTypeChanged: (t) => setState(() => _a3Type = t),
                    ),
                  ] else if (_hasSecondAdviser)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _hasThirdAdviser = true),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                        'Add Third Adviser (max 3)',
                        style: GoogleFonts.beVietnamPro(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _C.borderSoft),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        foregroundColor: _C.primaryDark,
                      ),
                    ),
                  const SizedBox(height: 22),

                  // Social Media
                  _sectionLabel(
                    'Social Media Links',
                    icon: Icons.share_outlined,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fbCtrl,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.charcoal,
                    ),
                    decoration: _inputDecoration(
                      'Facebook',
                      hint: 'facebook.com/yourorg',
                      icon: Icons.facebook_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _igCtrl,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.charcoal,
                    ),
                    decoration: _inputDecoration(
                      'Instagram',
                      hint: '@yourorg',
                      icon: Icons.camera_alt_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _twCtrl,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.charcoal,
                    ),
                    decoration: _inputDecoration(
                      'Twitter / X',
                      hint: '@yourhandle',
                      icon: Icons.alternate_email_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gmCtrl,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.charcoal,
                    ),
                    decoration: _inputDecoration(
                      'Gmail',
                      hint: 'yourorg@gmail.com',
                      icon: Icons.mail_outline_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _C.border)),
              color: _C.surface,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.borderSoft),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.textMid,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save Changes',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Officer Modal
// ─────────────────────────────────────────────────────────────────────────────
class _OfficerModal extends StatefulWidget {
  final String orgId;
  final String orgName;
  final OfficerModel? existingOfficer;
  final VoidCallback onSuccess;

  const _OfficerModal({
    required this.orgId,
    required this.orgName,
    this.existingOfficer,
    required this.onSuccess,
  });

  @override
  State<_OfficerModal> createState() => _OfficerModalState();
}

class _OfficerModalState extends State<_OfficerModal> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _customPosCtrl = TextEditingController();

  String? _photoUrl;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  bool _useCustomPosition = false;
  String? _selectedPosition;

  static const List<String> _standardPositions = [
    'President',
    'Vice President',
    'Secretary',
    'Treasurer',
    'Business Manager',
    'Board Member',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existingOfficer;
    if (e != null) {
      _nameCtrl.text = e.name;
      _emailCtrl.text = e.email;
      _phoneCtrl.text = e.phone;
      _photoUrl = e.photoUrl.isNotEmpty ? e.photoUrl : null;
      if (_standardPositions.contains(e.position)) {
        _selectedPosition = e.position;
        _useCustomPosition = false;
      } else {
        _customPosCtrl.text = e.position;
        _useCustomPosition = true;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _phoneCtrl, _customPosCtrl])
      c.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _isUploadingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final mime = _mimeTypeFromBytes(file.bytes!);
      setState(
        () => _photoUrl = 'data:$mime;base64,${base64Encode(file.bytes!)}',
      );
    } catch (e) {
      if (mounted) _snack('Failed to load image: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  String get _resolvedPosition => _useCustomPosition
      ? _customPosCtrl.text.trim()
      : (_selectedPosition ?? '');

  // This used to always default to 0 for new officers regardless of the
  // position picked, so every newly added officer piled into the top tier
  // and the chart rendered as a single flat row instead of a hierarchy.
  int get _resolvedPositionRank =>
      _useCustomPosition ? 3 : (_standardPositionRanks[_selectedPosition] ?? 3);

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _resolvedPosition.isEmpty) {
      _snack('Name and position are required', isError: true);
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !_emailPattern.hasMatch(email)) {
      _snack('Enter a valid email address', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    final data = {
      'name': _nameCtrl.text.trim(),
      'position': _resolvedPosition,
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'positionRank': _resolvedPositionRank,
      'isCaptain': widget.existingOfficer?.isCaptain ?? false,
      'photoUrl': _photoUrl ?? '',
    };
    try {
      final col = FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .collection('officers');
      if (widget.existingOfficer != null) {
        await col.doc(widget.existingOfficer!.id).update(data);
        await activity_log.ActivityLogger.log(
          action: 'edit_officer',
          module: 'org_profile',
          details: {
            'orgId': widget.orgId,
            'officerId': widget.existingOfficer!.id,
          },
        );
      } else {
        await col.add(data);
        await activity_log.ActivityLogger.log(
          action: 'add_officer',
          module: 'org_profile',
          details: {'orgId': widget.orgId},
        );
      }
      await _syncOfficers();

      // Officers are students first — tag their existing student account
      // (matched by email) instead of creating a new login. If no student
      // account exists yet with that email, the officer is still saved;
      // the tag just won't apply until they have one with a matching email.
      final tagged = await _syncOfficerUserTag(
        orgId: widget.orgId,
        orgName: widget.orgName,
        email: _emailCtrl.text.trim(),
        position: _resolvedPosition,
        isCaptain: widget.existingOfficer?.isCaptain ?? false,
      );

      widget.onSuccess();
      if (mounted) {
        _snack(
          tagged
              ? 'Officer saved and tagged on their student account.'
              : 'Officer saved. No student account found for that email yet — '
                    'the mobile-app tag will apply once one signs up with it.',
          isError: !tagged,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _syncOfficers() async {
    final orgDoc = FirebaseFirestore.instance
        .collection('organizations')
        .doc(widget.orgId);
    final snap = await orgDoc.collection('officers').orderBy('name').get();
    final officers = snap.docs.map((d) {
      final dd = d.data();
      return {
        'name': dd['name'] ?? '',
        'role': dd['position'] ?? '',
        'email': dd['email'] ?? '',
        'phone': dd['phone'] ?? '',
        'photoUrl': dd['photoUrl'] ?? '',
      };
    }).toList();
    await orgDoc.update({'officers': officers});
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: isError ? _C.error : _C.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingOfficer != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                color: _C.primaryDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit Officer' : 'Add New Officer',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          isEdit
                              ? 'Update officer information'
                              : 'Add a new officer to your organization',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
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
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo picker
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickPhoto,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: _C.primaryDark.withOpacity(0.08),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _C.borderSoft,
                                  width: 2,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _isUploadingPhoto
                                  ? const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _C.primaryDark,
                                        ),
                                      ),
                                    )
                                  : _photoUrl != null
                                  ? _buildImageWidget(
                                      _photoUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: const Icon(
                                        Icons.camera_alt_outlined,
                                        color: _C.textFaint,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 28,
                                      color: _C.textFaint,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap to upload photo',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: _C.darkGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name
                    TextField(
                      controller: _nameCtrl,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.charcoal,
                      ),
                      decoration: _inputDecoration(
                        'Full Name *',
                        hint: 'Officer\'s full name',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Position type toggle
                    Text(
                      'Position Type',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.darkGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _posTypeBtn(
                            'Standard',
                            Icons.list_alt_rounded,
                            !_useCustomPosition,
                            () => setState(() => _useCustomPosition = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _posTypeBtn(
                            'Custom',
                            Icons.edit_outlined,
                            _useCustomPosition,
                            () => setState(() => _useCustomPosition = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (!_useCustomPosition)
                      _PositionDropdown(
                        positions: _standardPositions,
                        selected: _selectedPosition,
                        onSelected: (p) =>
                            setState(() => _selectedPosition = p),
                      )
                    else
                      TextField(
                        controller: _customPosCtrl,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: _C.charcoal,
                        ),
                        decoration: _inputDecoration(
                          'Custom Position',
                          hint: 'e.g. Social Media Manager',
                          icon: Icons.work_outline_rounded,
                        ),
                      ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: _emailCtrl,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.charcoal,
                      ),
                      decoration: _inputDecoration(
                        'Email',
                        hint: 'officer@example.com',
                        icon: Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.charcoal,
                      ),
                      decoration: _inputDecoration(
                        'Phone',
                        hint: '+63 912 345 6789',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _C.border)),
                color: _C.surface,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _C.borderSoft),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _C.textMid,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isEdit ? 'Update Officer' : 'Add Officer',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
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
    );
  }

  Widget _posTypeBtn(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _C.primaryDark.withOpacity(0.08) : _C.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _C.primaryDark.withOpacity(0.4) : _C.borderSoft,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? _C.primaryDark : _C.textFaint,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? _C.primaryDark : _C.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Position Dropdown (preserved, styled to match)
// ─────────────────────────────────────────────────────────────────────────────
class _PositionDropdown extends StatefulWidget {
  final List<String> positions;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _PositionDropdown({
    required this.positions,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_PositionDropdown> createState() => _PositionDropdownState();
}

class _PositionDropdownState extends State<_PositionDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(_DS.radiusSm),
              border: Border.all(
                color: _open ? _C.primaryDark : _C.borderSoft,
                width: _open ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.work_outline_rounded,
                  size: 18,
                  color: _C.textFaint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.selected ?? 'Choose a position',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: widget.selected != null
                          ? _C.charcoal
                          : _C.textFaint,
                    ),
                  ),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _C.textFaint,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: _C.white,
              borderRadius: BorderRadius.circular(_DS.radiusSm),
              border: Border.all(color: _C.borderSoft),
              boxShadow: _DS.cardShadow,
            ),
            child: Column(
              children: widget.positions.map((pos) {
                final isSelected = widget.selected == pos;
                return InkWell(
                  onTap: () {
                    widget.onSelected(pos);
                    setState(() => _open = false);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: isSelected
                        ? _C.primaryDark.withOpacity(0.06)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 15,
                          color: isSelected ? _C.primaryDark : _C.textFaint,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          pos,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected ? _C.primaryDark : _C.charcoal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Officer Model — preserved exactly
// ─────────────────────────────────────────────────────────────────────────────
class OfficerModel {
  final String id;
  final String name;
  final String position;
  final String email;
  final String phone;
  final int positionRank;
  final bool isCaptain;
  final String photoUrl;

  const OfficerModel({
    required this.id,
    required this.name,
    required this.position,
    required this.email,
    required this.phone,
    required this.positionRank,
    this.isCaptain = false,
    this.photoUrl = '',
  });

  factory OfficerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OfficerModel(
      id: doc.id,
      name: data['name'] ?? '',
      position: data['position'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      positionRank: data['positionRank'] ?? 0,
      isCaptain: data['isCaptain'] ?? false,
      photoUrl: data['photoUrl'] ?? '',
    );
  }
}
