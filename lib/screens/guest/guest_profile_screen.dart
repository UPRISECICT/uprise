// lib/screens/guest/guest_profile_screen.dart
//
// GUEST PROFILE — Cleaned-up, matches StudentProfileScreen layout.
//
// States:
//   1. Not registered  → Hero banner + "Apply for Access" button
//   2. Registered / pending / rejected → Status card + details (read-only)
//   3. Approved        → Messenger-style menu hub (Digital ID, Certificate
//      Repository, Registered/Participated Events, Submitted Feedback,
//      Settings, Logout)
//
// Firestore collection: `external_requests`
// SharedPreferences key: 'external_request_doc_id'
//
// Dependencies: cloud_firestore, google_fonts, shared_preferences
//

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/activity_logger.dart' as activity_log;
import '../../widgets/common/app_intro.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/terms_and_conditions.dart';
import 'guest_auth_service.dart';
import 'guest_certificate_repository_screen.dart';
import 'guest_digital_id_screen.dart';
import 'guest_feedback_screen.dart';
import 'guest_participated_events_screen.dart';
import 'guest_profile_information_screen.dart';
import 'guest_registered_events_screen.dart';
import 'guest_settings_screen.dart';
import '../student/student_login.dart';
import '../../widgets/common/action_tile.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

// ─────────────────────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────────────────────
const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;
const _kSuccess = AppColors.success;
const _kSuccessBg = AppColors.successBg;
const _kWarning = AppColors.warning;
const _kWarningBg = AppColors.warningBg;
const _kError = AppColors.error;
const _kErrorBg = AppColors.errorBg;

// SharedPreferences key
const _kPrefKey = 'external_request_doc_id';

// ─────────────────────────────────────────────────────────────
//  MAIN SCREEN  (router)
// ─────────────────────────────────────────────────────────────
class GuestProfileScreen extends StatefulWidget {
  const GuestProfileScreen({super.key});

  @override
  State<GuestProfileScreen> createState() => _GuestProfileScreenState();
}

class _GuestProfileScreenState extends State<GuestProfileScreen> {
  String? _savedDocId;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    // Re-evaluate whenever GuestAuthService logs in or out so the
    // Profile tab updates instantly without requiring a hot-restart.
    GuestAuthService().addListener(_onAuthChanged);
    _checkSavedApplication();
  }

  @override
  void dispose() {
    GuestAuthService().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) _checkSavedApplication();
  }

  /// Resolution priority:
  ///  1. GuestAuthService  — set when the guest logs in via GuestLoginScreen
  ///                         (persisted under 'guest_auth_doc_id')
  ///  2. Legacy pref key   — set when a visitor submits the RegistrationScreen
  ///                         form without logging in (persisted under
  ///                         'external_request_doc_id')
  Future<void> _checkSavedApplication() async {
    if (mounted) setState(() => _checking = true);

    final svc = GuestAuthService();
    if (!svc.loaded) await svc.load();

    if (svc.isAuthenticated && (svc.docId?.isNotEmpty ?? false)) {
      if (mounted)
        setState(() {
          _savedDocId = svc.docId;
          _checking = false;
        });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final docId = prefs.getString(_kPrefKey);
    if (mounted)
      setState(() {
        _savedDocId = docId;
        _checking = false;
      });
  }

  Future<void> _onSubmitted(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, docId);
    if (mounted) setState(() => _savedDocId = docId);
  }

  Future<void> _onWithdraw() async {
    // Always clear the auth service on any withdraw/logout action so both
    // storage keys are cleaned up at once.
    await GuestAuthService.clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
    if (mounted) setState(() => _savedDocId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(backgroundColor: _kBg, body: UpriseLoader());
    }

    // Not registered (visitor mode) → show the "no account" landing
    if (_savedDocId == null) {
      return _NotRegisteredScreen(onApply: () => _openRegistration(context));
    }

    // Has a doc ID → stream Firestore to determine approval status
    return _ProfileRouter(
      docId: _savedDocId!,
      onWithdraw: _onWithdraw,
      onApply: () => _openRegistration(context),
      onLogout: _logout,
    );
  }

  void _openRegistration(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrationScreen(onSubmitted: _onSubmitted),
      ),
    );
  }

  Future<void> _logout() async {
    await GuestAuthService.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StudentLogin()),
      (route) => false,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  PROFILE ROUTER  (streams status from Firestore)
// ─────────────────────────────────────────────────────────────
class _ProfileRouter extends StatelessWidget {
  final String docId;
  final VoidCallback onWithdraw;
  final VoidCallback onApply;
  final VoidCallback onLogout;

  const _ProfileRouter({
    required this.docId,
    required this.onWithdraw,
    required this.onApply,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('external_requests')
          .doc(docId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: _kBg,
            body: Center(child: CircularProgressIndicator(color: _kOrange)),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          // Document was deleted (e.g. admin removed it)
          return _NotRegisteredScreen(
            onApply: onApply,
            showDeletedNotice: true,
          );
        }

        final data = snap.data!.data() as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'pending';

        if (status == 'approved') {
          return _ApprovedProfileScreen(
            docId: docId,
            data: data,
            onWithdraw: onWithdraw,
            onLogout: onLogout,
          );
        }

        // pending / rejected
        return _PendingRejectedScreen(
          docId: docId,
          data: data,
          status: status,
          onWithdraw: onWithdraw,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  STATE 1 — NOT REGISTERED
// ─────────────────────────────────────────────────────────────
class _NotRegisteredScreen extends StatelessWidget {
  final VoidCallback onApply;
  final bool showDeletedNotice;

  const _NotRegisteredScreen({
    required this.onApply,
    this.showDeletedNotice = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: Column(
          children: [
            // ── Avatar placeholder ──────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kOrangeLight,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 44,
                      color: _kOrange,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Guest',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No account yet',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (showDeletedNotice) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _kWarningBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kWarning.withAlpha(77)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: _kWarning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your previous request was removed. You can apply again.',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: const Color(0xFF78350F),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(
                        'Apply for Event Access',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── What you get card ───────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What you get after approval',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _BenefitRow(
                    icon: Icons.qr_code_2_rounded,
                    title: 'QR Attendance Pass',
                    sub: 'Generated from your registration details',
                  ),
                  const _Divider(),
                  _BenefitRow(
                    icon: Icons.calendar_today_outlined,
                    title: 'Public Event Access',
                    sub: 'Browse and register for CICT public events',
                  ),
                  const _Divider(),
                  _BenefitRow(
                    icon: Icons.campaign_outlined,
                    title: 'Announcements',
                    sub: 'Stay updated on CICT news and activities',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── How it works ────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it works',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _StepRow(
                    step: '1',
                    icon: Icons.edit_note_outlined,
                    text: 'Fill out the registration form',
                  ),
                  const SizedBox(height: 10),
                  _StepRow(
                    step: '2',
                    icon: Icons.manage_search_outlined,
                    text: 'Admin reviews your request',
                  ),
                  const SizedBox(height: 10),
                  _StepRow(
                    step: '3',
                    icon: Icons.check_circle_outline_rounded,
                    text: 'Get approved and access events',
                  ),
                  const SizedBox(height: 10),
                  _StepRow(
                    step: '4',
                    icon: Icons.qr_code_2_rounded,
                    text: 'Use your QR pass for attendance',
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

// ─────────────────────────────────────────────────────────────
//  STATE 2 — PENDING / REJECTED (clean profile-style layout)
// ─────────────────────────────────────────────────────────────
class _PendingRejectedScreen extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String status;
  final VoidCallback onWithdraw;

  const _PendingRejectedScreen({
    required this.docId,
    required this.data,
    required this.status,
    required this.onWithdraw,
  });

  String get _displayName => (data['userName'] as String?) ?? 'Guest';
  String get _email => (data['email'] as String?) ?? '';
  String get _school => (data['university'] as String?) ?? '';
  String get _initials {
    final parts = _displayName.trim().split(' ');
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'G';
  }

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    final statusColor = isPending ? _kWarning : _kError;
    final statusBg = isPending ? _kWarningBg : _kErrorBg;
    final statusLabel = isPending ? 'PENDING REVIEW' : 'REJECTED';
    final statusIcon = isPending
        ? Icons.hourglass_top_rounded
        : Icons.cancel_outlined;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Profile'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header card (mirrors student profile header) ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  // Avatar with initials
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kOrangeLight,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _initials,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _kOrange,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _displayName,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _school.isNotEmpty ? _school : 'External Applicant',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _email,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _kOrange,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withAlpha(77)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Status message ──────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Request Status',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(64)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isPending
                                ? 'Your request is currently under review by the CICT admin team. This usually takes 1–2 business days.'
                                : 'Your request was not approved. ${(data['reviewNote'] as String?)?.isNotEmpty == true ? (data['reviewNote'] as String) : 'No specific reason was provided.'} You may withdraw and re-apply with updated information.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: isPending
                                  ? const Color(0xFF78350F)
                                  : const Color(0xFF991B1B),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Request details ─────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Information',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ContactRow(
                    icon: Icons.email_outlined,
                    label: 'EMAIL',
                    value: _email.isNotEmpty ? _email : '—',
                  ),
                  const SizedBox(height: 12),
                  _ContactRow(
                    icon: Icons.school_outlined,
                    label: 'SCHOOL / INSTITUTION',
                    value: _school.isNotEmpty ? _school : '—',
                  ),
                  const SizedBox(height: 12),
                  _ContactRow(
                    icon: Icons.phone_outlined,
                    label: 'PHONE',
                    value: (data['phone'] as String?)?.isNotEmpty == true
                        ? data['phone'] as String
                        : 'Not provided',
                  ),
                  const SizedBox(height: 12),
                  _ContactRow(
                    icon: Icons.description_outlined,
                    label: 'PURPOSE',
                    value: (data['purpose'] as String?) ?? '—',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Withdraw / re-apply button ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextButton.icon(
                onPressed: () => _confirmWithdraw(context),
                icon: const Icon(Icons.close, color: _kError),
                label: Text(
                  'Withdraw Request',
                  style: GoogleFonts.beVietnamPro(
                    color: _kError,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmWithdraw(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Withdraw Request?',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will delete your pending request. You can re-apply later.',
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.beVietnamPro(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('external_requests')
                  .doc(docId)
                  .delete();
              onWithdraw();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kError,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Withdraw',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  STATE 3 — APPROVED PROFILE (mirrors StudentProfileScreen)
// ─────────────────────────────────────────────────────────────
class _ApprovedProfileScreen extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onWithdraw;
  final VoidCallback onLogout;

  const _ApprovedProfileScreen({
    required this.docId,
    required this.data,
    required this.onWithdraw,
    required this.onLogout,
  });

  String get _fullName => (data['userName'] as String?) ?? 'Guest';
  String get _email => (data['email'] as String?) ?? '';
  String get _school => (data['university'] as String?) ?? '';
  String get _photoUrl => (data['photoUrl'] as String?) ?? '';
  String get _initials {
    final parts = _fullName.trim().split(' ');
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'G';
  }

  ImageProvider? get _avatarImage {
    if (_photoUrl.isEmpty) return null;
    if (_photoUrl.startsWith('data:image')) {
      try {
        final b64 = _photoUrl.contains(',')
            ? _photoUrl.split(',').last
            : _photoUrl;
        return MemoryImage(base64Decode(b64));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(_photoUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Profile'),
      // Vertical padding only: kActionTile supplies its own horizontal 16
      // margin, so padding the scroll view too would double-inset every row.
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 20, bottom: 32),
        child: Column(
          children: [
            // ── Header card — same card treatment as student Profile ──
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: kCardDecoration(radius: 18),
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kOrangeLight,
                      border: Border.all(color: Colors.white, width: 3),
                      image: _avatarImage != null
                          ? DecorationImage(
                              image: _avatarImage!,
                              fit: BoxFit.cover,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _avatarImage == null
                        ? Center(
                            child: Text(
                              _initials,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: _kOrange,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _fullName,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _email,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kSuccessBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kSuccess.withAlpha(77)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 12,
                          color: _kSuccess,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'VERIFIED GUEST',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _kSuccess,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GuestDigitalIdScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: Text(
                        'View Digital ID',
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Menu list ─────────────────────────────────────
            // Stacked kActionTiles, the same rows the student profile page
            // and both Settings screens use — this was a _MenuSection of
            // hairline-divided ListTiles, which is the one place guest chrome
            // still looked like a different app.
            const SizedBox(height: 6),
            kActionTile(
              icon: Icons.person_outline_rounded,
              title: 'Profile Information',
              subtitle: 'Edit your details',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GuestProfileInformationScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            kActionTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Certificate Repository',
              subtitle: 'View and download certificates',
              iconColor: const Color(0xFF16A34A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GuestCertificateRepositoryScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            kActionTile(
              icon: Icons.event_note_outlined,
              title: 'Registered Events',
              subtitle: 'Upcoming and past registrations',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GuestRegisteredEventsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            kActionTile(
              icon: Icons.event_available_outlined,
              title: 'Participated Events',
              subtitle: 'Your attendance history',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GuestParticipatedEventsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            kActionTile(
              icon: Icons.rate_review_outlined,
              title: 'Submitted Feedback',
              subtitle: 'Feedback you\'ve given for events',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuestFeedbackScreen()),
              ),
            ),
            const SizedBox(height: 10),
            kActionTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Password, notifications, privacy',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GuestSettingsScreen(
                    fullName: _fullName,
                    email: _email,
                    school: _school,
                    docId: docId,
                    onLogout: () => _confirmLogout(context),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Logout ──────────────────────────────────────
            // Full-width red button, matching student Settings. Still routes
            // through _confirmLogout, which already asks before signing out.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmLogout(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log Out?',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'You will be returned to the guest landing screen.',
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.beVietnamPro(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              onLogout(); // clears this screen's own pref → back to not-registered state
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
//  REGISTRATION SCREEN (3-step form — unchanged logic)
// ─────────────────────────────────────────────────────────────
class RegistrationScreen extends StatefulWidget {
  final Future<void> Function(String docId) onSubmitted;
  const RegistrationScreen({required this.onSubmitted});

  @override
  State<RegistrationScreen> createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  // BulSUan-only fields.
  final _collegeCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  // Outsider-only field — replaces "School/University", since an outsider
  // guest isn't necessarily a student anywhere.
  final _affiliationCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  static const List<String> yearLevels = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year',
  ];
  String _yearLevel = yearLevels.first;

  bool _isLoading = false;
  bool _agreedToTerms = false;
  int _currentStep = 0;
  // Shown once per visit to this screen, ahead of Personal Info — this
  // screen can be reached repeatedly (withdraw-and-reapply is a supported
  // guest flow), so a returning applicant sees the guide again each time
  // rather than needing a persisted "seen" flag.
  bool _showIntro = true;
  // Drives both which fields this signup collects (BulSUan needs
  // college/year/section; Outsider needs an affiliation instead) and which
  // event/announcement audiences the guest can see once approved
  // (guest_events_screen.dart's classificationAllowsAudience) — previously
  // this field was only ever read, never written anywhere, so every guest
  // was permanently 'Outsider' regardless of real affiliation.
  String _classification = 'Outsider';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _collegeCtrl,
      _sectionCtrl,
      _affiliationCtrl,
      _reasonCtrl,
    ]) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _isBulSUanEmail =>
      _emailCtrl.text.trim().toLowerCase().endsWith('@ms.bulsu.edu.ph');
  bool get _isGmailEmail =>
      _emailCtrl.text.trim().toLowerCase().endsWith('@gmail.com');

  void _nextStep() {
    if (_currentStep == 0) {
      if (_firstNameCtrl.text.trim().isEmpty ||
          _lastNameCtrl.text.trim().isEmpty ||
          _emailCtrl.text.trim().isEmpty ||
          !_emailCtrl.text.contains('@')) {
        _snack('Please complete all personal information fields.');
        return;
      }
      // The email domain has to match the selected guest type — a BulSUan
      // guest is claiming a real BulSU Microsoft account, and an outsider
      // must use a Gmail address instead.
      if (_classification == 'BulSUan' && !_isBulSUanEmail) {
        _snack('BulSUan guests must sign up with an @ms.bulsu.edu.ph email.');
        return;
      }
      if (_classification == 'Outsider' && !_isGmailEmail) {
        _snack(
          _isBulSUanEmail
              ? 'This looks like a BulSU email — switch your guest type to '
                    'BulSUan, or use a Gmail address instead.'
              : 'Outsider guests must sign up with a @gmail.com email.',
        );
        return;
      }
    }
    if (_currentStep == 1) {
      if (_reasonCtrl.text.trim().isEmpty) {
        _snack('Please complete all fields before proceeding.');
        return;
      }
      if (_classification == 'BulSUan') {
        if (_collegeCtrl.text.trim().isEmpty ||
            _sectionCtrl.text.trim().isEmpty) {
          _snack('Please complete all fields before proceeding.');
          return;
        }
      } else {
        if (_affiliationCtrl.text.trim().isEmpty) {
          _snack('Please complete all fields before proceeding.');
          return;
        }
      }
      if (_reasonCtrl.text.trim().length < 20) {
        _snack('Please describe your purpose in at least 20 characters.');
        return;
      }
    }
    _fadeCtrl.reset();
    setState(() => _currentStep++);
    _fadeCtrl.forward();
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _prevStep() {
    _fadeCtrl.reset();
    setState(() => _currentStep--);
    _fadeCtrl.forward();
  }

  void _snack(String msg, {Color bg = _kError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_agreedToTerms) {
      _snack('Please agree to the Terms and Conditions to continue.');
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final email = _emailCtrl.text.trim().toLowerCase();

      // Duplicate check
      final dup = await FirebaseFirestore.instance
          .collection('external_requests')
          .where('email', isEqualTo: email)
          .where('status', whereIn: ['pending', 'approved'])
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          _snack('A request with this email already exists.', bg: _kWarning);
          await widget.onSubmitted(dup.docs.first.id);
          if (mounted) Navigator.pop(context);
        }
        return;
      }

      // Block signup if this email already belongs to a real account of
      // any role — a CICT student (or org/admin, or an already-approved
      // guest) shouldn't be able to register a second, duplicate guest
      // identity; they should log in through their actual account instead.
      // Checked against both the as-typed and lowercased email: account
      // creation elsewhere in this app never normalizes case, so an
      // exact-match query on the wrong casing would silently miss a real
      // match instead of erroring.
      final typedEmail = _emailCtrl.text.trim();
      QueryDocumentSnapshot<Map<String, dynamic>>? existingUser;
      for (final variant in {email, typedEmail}) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: variant)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          existingUser = snap.docs.first;
          break;
        }
      }
      if (existingUser != null) {
        final role = (existingUser.data()['role'] ?? '').toString();
        final roleLabel = switch (role) {
          'student' => 'a student account',
          'org' => 'an organization account',
          'admin' => 'an admin account',
          'guest' => 'a guest account',
          _ => 'an existing account',
        };
        if (mounted) {
          setState(() => _isLoading = false);
          _snack(
            role == 'guest'
                ? 'You already have a guest account with this email — please log in instead of registering again.'
                : 'This email already belongs to $roleLabel. Please log in through the correct app instead of registering as a guest.',
          );
        }
        return;
      }

      final userName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';

      final docRef = await FirebaseFirestore.instance
          .collection('external_requests')
          .add({
            'userId': '',
            'userName': userName,
            'email': email,
            // 'university' is kept populated for the Outsider guest — the
            // existing, already-working Outsider credentials email template
            // reads {{university}} and must not break — it now carries
            // whatever the guest entered as their affiliation/organization
            // instead of a school name, since an outsider isn't necessarily
            // a student anywhere.
            'university': _classification == 'Outsider'
                ? _affiliationCtrl.text.trim()
                : 'Bulacan State University',
            'affiliation': _affiliationCtrl.text.trim(),
            'college': _collegeCtrl.text.trim(),
            'yearLevel': _classification == 'BulSUan' ? _yearLevel : '',
            'section': _sectionCtrl.text.trim(),
            'purpose': _reasonCtrl.text.trim(),
            'status': 'pending',
            'requestDate': FieldValue.serverTimestamp(),
            'firstName': _firstNameCtrl.text.trim(),
            'lastName': _lastNameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'type': 'guest',
            'classification': _classification,
          });

      await activity_log.ActivityLogger.log(
        action: 'Guest access requested: $userName',
        module: 'Authentication',
        severity: 'info',
        details: {'requestId': docRef.id, 'email': email},
      );

      if (mounted) {
        setState(() => _isLoading = false);
        await widget.onSubmitted(docRef.id);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Submission failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro) {
      return AppIntroScreen(
        slides: kGuestIntroSlides,
        onDone: () => setState(() => _showIntro = false),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Guest Registration'),
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _StepIndicator(current: _currentStep),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildStep(),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _PersonalStep(
          firstNameCtrl: _firstNameCtrl,
          lastNameCtrl: _lastNameCtrl,
          emailCtrl: _emailCtrl,
          phoneCtrl: _phoneCtrl,
          classification: _classification,
          onClassificationChanged: (v) => setState(() => _classification = v),
          onNext: _nextStep,
        );
      case 1:
        return _DetailsStep(
          collegeCtrl: _collegeCtrl,
          sectionCtrl: _sectionCtrl,
          affiliationCtrl: _affiliationCtrl,
          reasonCtrl: _reasonCtrl,
          classification: _classification,
          yearLevel: _yearLevel,
          onYearLevelChanged: (v) => setState(() => _yearLevel = v),
          onNext: _nextStep,
          onBack: _prevStep,
        );
      case 2:
        return _ReviewStep(
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          college: _collegeCtrl.text.trim(),
          yearLevel: _yearLevel,
          section: _sectionCtrl.text.trim(),
          affiliation: _affiliationCtrl.text.trim(),
          reason: _reasonCtrl.text.trim(),
          classification: _classification,
          isLoading: _isLoading,
          agreedToTerms: _agreedToTerms,
          onAgreedChanged: (v) => setState(() => _agreedToTerms = v),
          onSubmit: _submit,
          onBack: _prevStep,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  REGISTRATION STEP WIDGETS (unchanged logic, cleaner style)
// ─────────────────────────────────────────────────────────────
class _PersonalStep extends StatelessWidget {
  final TextEditingController firstNameCtrl, lastNameCtrl, emailCtrl, phoneCtrl;
  final String classification;
  final ValueChanged<String> onClassificationChanged;
  final VoidCallback onNext;
  const _PersonalStep({
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.classification,
    required this.onClassificationChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isBulSUan = classification == 'BulSUan';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormCard(
          title: 'Guest Type',
          icon: Icons.badge_outlined,
          children: [
            Text(
              'This determines your email requirement and which events/'
              'announcements you can see.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            _ClassificationOption(
              label: 'BulSUan',
              description:
                  'I\'m affiliated with Bulacan State University — alumni, '
                  'family of a student/faculty, or similar. Requires an '
                  '@ms.bulsu.edu.ph email.',
              icon: Icons.school_rounded,
              selected: isBulSUan,
              onTap: () => onClassificationChanged('BulSUan'),
            ),
            const SizedBox(height: 10),
            _ClassificationOption(
              label: 'Outsider',
              description:
                  'I have no affiliation with Bulacan State University. '
                  'Requires a @gmail.com email.',
              icon: Icons.public_rounded,
              selected: !isBulSUan,
              onTap: () => onClassificationChanged('Outsider'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FormCard(
          title: 'Personal Information',
          icon: Icons.person_outline_rounded,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'First Name',
                    controller: firstNameCtrl,
                    hint: 'Juan',
                    icon: Icons.badge_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: 'Last Name',
                    controller: lastNameCtrl,
                    hint: 'Dela Cruz',
                    icon: Icons.badge_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Email Address',
              controller: emailCtrl,
              hint: isBulSUan
                  ? 'yourname@ms.bulsu.edu.ph'
                  : 'yourname@gmail.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Phone Number',
              controller: phoneCtrl,
              hint: '+63 9XX XXX XXXX',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isRequired: false,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PrimaryBtn(label: 'Next: Details →', onTap: onNext),
      ],
    );
  }
}

class _DetailsStep extends StatelessWidget {
  final TextEditingController collegeCtrl, sectionCtrl, affiliationCtrl;
  final TextEditingController reasonCtrl;
  final String classification;
  final String yearLevel;
  final ValueChanged<String> onYearLevelChanged;
  final VoidCallback onNext, onBack;
  const _DetailsStep({
    required this.collegeCtrl,
    required this.sectionCtrl,
    required this.affiliationCtrl,
    required this.reasonCtrl,
    required this.classification,
    required this.yearLevel,
    required this.onYearLevelChanged,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isBulSUan = classification == 'BulSUan';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBulSUan)
          _FormCard(
            title: 'BulSU Details',
            icon: Icons.school_outlined,
            children: [
              _Field(
                label: 'College',
                controller: collegeCtrl,
                hint:
                    'e.g. College of Information and Communications Technology',
                icon: Icons.account_balance_outlined,
              ),
              const SizedBox(height: 14),
              Text(
                'Year Level',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: yearLevel,
                items: RegistrationScreenState.yearLevels
                    .map(
                      (y) => DropdownMenuItem(
                        value: y,
                        child: Text(
                          y,
                          style: GoogleFonts.beVietnamPro(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onYearLevelChanged(v);
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.stairs_outlined,
                    size: 18,
                    color: Colors.grey,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Field(
                label: 'Section',
                controller: sectionCtrl,
                hint: 'e.g. 4H-G1',
                icon: Icons.groups_outlined,
              ),
            ],
          )
        else
          _FormCard(
            title: 'Affiliation',
            icon: Icons.school_outlined,
            children: [
              _Field(
                label: 'Affiliation / Organization',
                controller: affiliationCtrl,
                hint: 'e.g. DLSU, ABC Company, Self-employed',
                icon: Icons.account_balance_outlined,
              ),
            ],
          ),
        const SizedBox(height: 14),
        _FormCard(
          title: 'Purpose',
          icon: Icons.description_outlined,
          children: [
            _Field(
              label: 'Why do you want to join CICT events?',
              controller: reasonCtrl,
              hint: 'e.g. Networking, learning new skills…',
              icon: Icons.comment_outlined,
              maxLines: 4,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _SecondaryBtn(label: '← Back', onTap: onBack),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _PrimaryBtn(label: 'Review →', onTap: onNext),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClassificationOption extends StatelessWidget {
  final String label, description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ClassificationOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _kOrangeLight : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kOrange : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? _kOrange : Colors.grey.shade500,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? _kOrange : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? _kOrange : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final String firstName, lastName, email, phone, reason;
  final String college, yearLevel, section, affiliation;
  final String classification;
  final bool isLoading;
  final bool agreedToTerms;
  final ValueChanged<bool> onAgreedChanged;
  final VoidCallback onSubmit, onBack;
  const _ReviewStep({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.college,
    required this.yearLevel,
    required this.section,
    required this.affiliation,
    required this.reason,
    required this.classification,
    required this.isLoading,
    required this.agreedToTerms,
    required this.onAgreedChanged,
    required this.onSubmit,
    required this.onBack,
  });

  String get _initials {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    return firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _kOrangeLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _kOrange.withAlpha(77),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _kOrange,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$firstName $lastName',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _kOrangeLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kOrange.withAlpha(77)),
                      ),
                      child: Text(
                        'EXTERNAL APPLICANT',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _kOrange,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReviewGroup(
          title: 'Contact',
          rows: [_ReviewPair('Phone', phone.isEmpty ? 'Not provided' : phone)],
        ),
        const SizedBox(height: 10),
        _ReviewGroup(
          title: 'Affiliation',
          rows: classification == 'BulSUan'
              ? [
                  _ReviewPair('Guest Type', classification),
                  _ReviewPair('College', college),
                  _ReviewPair('Year Level', yearLevel),
                  _ReviewPair('Section', section),
                ]
              : [
                  _ReviewPair('Guest Type', classification),
                  _ReviewPair('Affiliation', affiliation),
                ],
        ),
        const SizedBox(height: 10),
        _ReviewGroup(title: 'Purpose', rows: [_ReviewPair('Reason', reason)]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _kWarningBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kWarning.withAlpha(64)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 16,
                color: _kWarning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'After submission your request will be reviewed by the CICT admin.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: const Color(0xFF78350F),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TermsAgreementCheckbox(
          value: agreedToTerms,
          onChanged: onAgreedChanged,
          accent: _kOrange,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SecondaryBtn(
                label: '← Edit',
                onTap: isLoading ? null : onBack,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _PrimaryBtn(
                label: isLoading ? 'Submitting…' : 'Submit Request',
                onTap: (isLoading || !agreedToTerms) ? null : onSubmit,
                isLoading: isLoading,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────

// _AppBarLine removed — StudentAppBar draws the same hairline itself, in
// AppColors.divider rather than this file's slightly lighter 0xFFF0F0F0.

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kOrangeLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: _kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  sub,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: Colors.grey,
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.grey.shade100);
}

class _StepRow extends StatelessWidget {
  final String step;
  final IconData icon;
  final String text;
  const _StepRow({required this.step, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: _kOrange,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: GoogleFonts.beVietnamPro(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kOrangeLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: _kOrange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _FormCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 15, color: _kOrange),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ReviewGroup extends StatelessWidget {
  final String title;
  final List<_ReviewPair> rows;
  const _ReviewGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

class _ReviewPair extends StatelessWidget {
  final String label, value;
  const _ReviewPair(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});
  static const _labels = ['Personal Info', 'Details', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(_labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = current > i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: done ? _kOrange : const Color(0xFFE2E8F0),
              ),
            );
          }
          final idx = i ~/ 2;
          final isActive = current == idx;
          final isDone = current > idx;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDone
                      ? _kSuccess
                      : isActive
                      ? _kOrange
                      : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${idx + 1}',
                          style: GoogleFonts.beVietnamPro(
                            color: isActive
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[idx],
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  fontWeight: (isActive || isDone)
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isActive
                      ? _kOrange
                      : isDone
                      ? _kSuccess
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool isRequired;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.isRequired = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: _kOrange),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.beVietnamPro(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFFBBBBBB),
            ),
            prefixIcon: maxLines == 1
                ? Icon(icon, size: 18, color: Colors.grey)
                : null,
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 14 : 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kOrange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  const _PrimaryBtn({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: onTap == null ? Colors.grey.shade300 : _kOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SecondaryBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black54,
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
