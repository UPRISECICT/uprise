// lib/screens/guest/guest_digital_id_screen.dart
//
// GUEST DIGITAL ID — Only visible to authenticated guests.
//
// Displays a ticket-style digital identity card with:
//   • Guest's name, email, school, course
//   • VERIFIED GUEST badge
//   • QR code (payload: UPRISE|GUEST|docId|FIRST|LAST|email)
//   • Fullscreen QR viewer
//   • "Download Pass" (scaffold action — wire up image_gallery_saver)
//
// Firestore: external_requests/{docId}  (streamed live)
//

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'guest_auth_service.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

// ─────────────────────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────────────────────
const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kDark        = Color(0xFF1A1A2E);
const _kBg = AppColors.background;
const _kSuccess = AppColors.success;
const _kSuccessBg = AppColors.successBg;


// ─────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────
class GuestDigitalIdScreen extends StatelessWidget {
  const GuestDigitalIdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc   = GuestAuthService();
    final docId = svc.docId;

    if (docId == null || docId.isEmpty) {
      return const _NotAuthView();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('external_requests')
          .doc(docId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: _kBg,
            body: Center(
                child: CircularProgressIndicator(color: _kOrange)),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return const _NotAuthView();
        }

        final data   = snap.data!.data() as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'pending';

        if (status != 'approved') {
          return _PendingView(status: status);
        }

        return _IdCardView(docId: docId, data: data);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ID CARD VIEW
// ─────────────────────────────────────────────────────────────
class _IdCardView extends StatelessWidget {
  final String               docId;
  final Map<String, dynamic> data;

  const _IdCardView({required this.docId, required this.data});

  String get _fullName  => (data['userName']   as String?) ?? 'Guest';
  String get _email     => (data['email']       as String?) ?? '';
  String get _school    => (data['university']  as String?) ?? '';
  String get _phone     => (data['phone']       as String?) ?? '';
  String get _course    => (data['course']      as String?) ?? '';
  String get _photoUrl  => (data['photoUrl']    as String?) ?? '';
  String get _firstName =>
      (data['firstName'] as String?) ?? _fullName.split(' ').first;
  String get _lastName  =>
      (data['lastName']  as String?) ??
      (_fullName.split(' ').length > 1 ? _fullName.split(' ').last : '');

  String get _initials {
    final parts = _fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'G';
  }

  String get _qrPayload =>
      'UPRISE|GUEST|$docId|${_firstName.toUpperCase()}|${_lastName.toUpperCase()}|$_email';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Digital ID'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          children: [
            // ── Instruction banner ─────────────────────────
            _InfoBanner(),

            const SizedBox(height: 18),

            // ── ID Card ────────────────────────────────────
            _DigitalIdCard(
              docId:      docId,
              fullName:   _fullName,
              firstName:  _firstName,
              lastName:   _lastName,
              email:      _email,
              school:     _school,
              phone:      _phone,
              course:     _course,
              initials:   _initials,
              photoUrl:   _photoUrl,
              qrPayload:  _qrPayload,
              onFullscreen: () => _openFullscreen(context),
            ),

            const SizedBox(height: 14),

            // ── Fullscreen hint ────────────────────────────
            GestureDetector(
              onTap: () => _openFullscreen(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_full_rounded,
                        size: 16, color: _kOrange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tap to show full-screen QR for easy scanning',
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Contact section ────────────────────────────
            _ContactSection(
              email:  _email,
              phone:  _phone,
              school: _school,
              course: _course,
            ),

            const SizedBox(height: 14),

            // ── Download button ────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _onDownload(context),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text('Download ID',
                    style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenQrScreen(
          fullName:  _fullName,
          qrPayload: _qrPayload,
        ),
      ),
    );
  }

  void _onDownload(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('ID saved to your gallery',
                style: GoogleFonts.beVietnamPro(fontSize: 13)),
          ],
        ),
        backgroundColor: _kOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  INFO BANNER
// ─────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange.withAlpha(64)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is your verified guest identity card. Present it or show the QR code to CICT event staff.',
              style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF7A3300)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DIGITAL ID CARD  (ticket-style, matching Figma design)
// ─────────────────────────────────────────────────────────────
class _DigitalIdCard extends StatelessWidget {
  final String   docId;
  final String   fullName;
  final String   firstName;
  final String   lastName;
  final String   email;
  final String   school;
  final String   phone;
  final String   course;
  final String   initials;
  final String   photoUrl;
  final String   qrPayload;
  final VoidCallback onFullscreen;

  const _DigitalIdCard({
    required this.docId,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.school,
    required this.phone,
    required this.course,
    required this.initials,
    required this.photoUrl,
    required this.qrPayload,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(26),
              blurRadius: 20,
              offset: const Offset(0, 6)),
          BoxShadow(
              color: _kOrange.withAlpha(15),
              blurRadius: 32,
              offset: const Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header band ──────────────────────────────────
          Container(
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_kOrange, Color(0xFFD47A00)]),
            ),
          ),

          // ── Top section: branding + avatar + name ────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // UPRISE branding
                      Row(
                        children: [
                          Container(
                            width: 22, height: 22,
                            decoration: const BoxDecoration(
                                color: _kOrange,
                                shape: BoxShape.circle),
                            child: const Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 13),
                          ),
                          const SizedBox(width: 6),
                          Text('UPRISE',
                              style: GoogleFonts.beVietnamPro(
                                  color: _kOrange,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 1.4)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${docId.length >= 8 ? docId.substring(0, 8).toUpperCase() : docId.toUpperCase()}…',
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            color: const Color(0xFF999999),
                            letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        fullName.toUpperCase(),
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                            letterSpacing: 0.3,
                            height: 1.15),
                      ),
                      const SizedBox(height: 3),
                      // Verified badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kSuccessBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _kSuccess.withAlpha(77)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 10, color: _kSuccess),
                            const SizedBox(width: 4),
                            Text('VERIFIED GUEST',
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _kSuccess,
                                    letterSpacing: 0.6)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(email,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              color: const Color(0xFFAAAAAA),
                              letterSpacing: 0.2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar — photo if available, otherwise initials
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    color: _kOrangeLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _kOrange.withAlpha(64),
                        width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // AppImage rather than Image + a local provider: it takes the
                  // empty, unreadable and no-photo cases through the same
                  // `placeholder`, so the initials fallback is written once
                  // instead of duplicated across an errorBuilder and an else.
                  // It also reads raw base64 and the malformed `dataimage...`
                  // variant, both of which used to fall through to
                  // NetworkImage and fail.
                  child: AppImage(
                    source: photoUrl,
                    fit: BoxFit.cover,
                    showLoadingIndicator: false,
                    placeholder: Center(
                      child: Text(initials,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: _kOrange)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Dashed divider ────────────────────────────────
          _DashedDivider(),

          // ── Bottom: details + QR ─────────────────────────
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (school.isNotEmpty) ...[
                        _DetailRow(label: 'SCHOOL', value: school),
                        const SizedBox(height: 6),
                      ],
                      if (phone.isNotEmpty) ...[
                        _DetailRow(label: 'PHONE', value: phone),
                        const SizedBox(height: 6),
                      ],
                      if (course.isNotEmpty) ...[
                        _DetailRow(label: 'COURSE', value: course),
                        const SizedBox(height: 6),
                      ],
                      _DetailRow(label: 'TYPE', value: 'External Guest'),
                      const SizedBox(height: 10),
                      // Approved chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kSuccessBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _kSuccess.withAlpha(102)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 10, color: _kSuccess),
                            const SizedBox(width: 4),
                            Text('APPROVED',
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _kSuccess,
                                    letterSpacing: 0.6)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // QR code
                GestureDetector(
                  onTap: onFullscreen,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFEEEEEE)),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    Colors.black.withAlpha(15),
                                blurRadius: 8,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: QrImageView(
                          data:            qrPayload,
                          version:         QrVersions.auto,
                          size:            100,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color:    _kDark,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color:           _kDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_full_rounded,
                              size: 10, color: _kOrange),
                          const SizedBox(width: 3),
                          Text('Tap to enlarge',
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 9,
                                  color: _kOrange,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom strip ──────────────────────────────────
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_kOrange, Color(0xFFD47A00)]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CONTACT SECTION
// ─────────────────────────────────────────────────────────────
class _ContactSection extends StatelessWidget {
  final String email;
  final String phone;
  final String school;
  final String course;

  const _ContactSection({
    required this.email,
    required this.phone,
    required this.school,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact Information',
              style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
          const SizedBox(height: 14),
          _ContactRow(
              icon: Icons.email_outlined,
              label: 'EMAIL',
              value: email.isNotEmpty ? email : '—'),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContactRow(
                icon: Icons.phone_outlined,
                label: 'PHONE',
                value: phone),
          ],
          if (school.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContactRow(
                icon: Icons.school_outlined,
                label: 'INSTITUTION',
                value: school),
          ],
          if (course.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContactRow(
                icon: Icons.menu_book_outlined,
                label: 'COURSE',
                value: course),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  FULLSCREEN QR SCREEN
// ─────────────────────────────────────────────────────────────
class _FullscreenQrScreen extends StatelessWidget {
  final String fullName;
  final String qrPayload;

  const _FullscreenQrScreen({
    required this.fullName,
    required this.qrPayload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back,
                size: 18, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Guest ID — Scan QR',
            style: GoogleFonts.beVietnamPro(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            fullName.toUpperCase(),
            style: GoogleFonts.beVietnamPro(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text('VERIFIED GUEST',
              style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _kOrange,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: _kOrange.withAlpha(64),
                    blurRadius: 40,
                    spreadRadius: 5),
              ],
            ),
            child: QrImageView(
              data:            qrPayload,
              version:         QrVersions.auto,
              size:            240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color:    _kDark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color:           _kDark,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: _kOrange, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('Show to event staff for scanning',
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 12, color: Colors.white54)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  NOT AUTHENTICATED VIEW
// ─────────────────────────────────────────────────────────────
class _NotAuthView extends StatelessWidget {
  const _NotAuthView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Digital ID'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                    color: _kOrangeLight, shape: BoxShape.circle),
                child: const Icon(Icons.badge_outlined,
                    size: 46, color: _kOrange),
              ),
              const SizedBox(height: 20),
              Text('Not Logged In',
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              Text(
                  'Log in as a verified guest to access your digital ID.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  PENDING VIEW
// ─────────────────────────────────────────────────────────────
class _PendingView extends StatelessWidget {
  final String status;
  const _PendingView({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Digital ID'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: isPending
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPending
                      ? Icons.hourglass_top_rounded
                      : Icons.cancel_outlined,
                  size: 46,
                  color: isPending
                      ? const Color(0xFFD97706)
                      : const Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isPending
                    ? 'Awaiting Approval'
                    : 'Application Rejected',
                style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                isPending
                    ? 'Your Digital ID will be available once the admin approves your guest application.'
                    : 'Your application was not approved. Please contact the CICT admin for details.',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: Colors.grey,
                    height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 0.5)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(value,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87)),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _ContactRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 13, color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 12, height: 12,
            decoration: const BoxDecoration(
                color: _kBg, shape: BoxShape.circle),
          ),
          Expanded(
            child: CustomPaint(
              painter: _DashedLinePainter(),
              child: const SizedBox(height: 1),
            ),
          ),
          Container(
            width: 12, height: 12,
            decoration: const BoxDecoration(
                color: _kBg, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = const Color(0xFFEEEEEE)
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;
    const dashW = 6.0;
    const gapW  = 4.0;
    double x    = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + dashW, size.width), 0),
        paint,
      );
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}