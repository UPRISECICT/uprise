// lib/screens/guest/guest_digital_id_screen.dart
//
// GUEST DIGITAL ID — Only visible to authenticated guests.
//
// Displays a ticket-style digital identity card with:
//   • Guest's name, email, school, course
//   • VERIFIED GUEST badge
//   • QR code (payload: UPRISE|GUEST|docId|FIRST|LAST|email)
//   • Fullscreen QR viewer
//   • "Download ID" — preview sheet that captures the card and shares it as a PDF
//
// Firestore: external_requests/{docId}  (streamed live)
//
// The card's look is kept in step with the student Digital ID
// (student_profile_screen.dart, _StudentIdCard): same gradient bands, stacked
// detail rows, full-bleed dashed divider and download flow. The QR payload is
// deliberately NOT shared — org_attendance_qr.dart routes anything without the
// `UPRISE|GUEST|` prefix to the student lookup.
//

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
const _kDark = Color(0xFF1A1A2E);
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
    final svc = GuestAuthService();
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
            body: Center(child: CircularProgressIndicator(color: _kOrange)),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return const _NotAuthView();
        }

        final data = snap.data!.data() as Map<String, dynamic>;
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
  final String docId;
  final Map<String, dynamic> data;

  const _IdCardView({required this.docId, required this.data});

  String get _fullName => (data['userName'] as String?) ?? 'Guest';
  String get _email => (data['email'] as String?) ?? '';
  String get _school => (data['university'] as String?) ?? '';
  String get _phone => (data['phone'] as String?) ?? '';
  String get _course => (data['course'] as String?) ?? '';
  String get _photoUrl => (data['photoUrl'] as String?) ?? '';
  String get _firstName =>
      (data['firstName'] as String?) ?? _fullName.split(' ').first;
  String get _lastName =>
      (data['lastName'] as String?) ??
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
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Instruction banner ─────────────────────────
            _InfoBanner(),

            const SizedBox(height: 18),

            // ── ID Card ────────────────────────────────────
            _DigitalIdCard(
              docId: docId,
              fullName: _fullName,
              email: _email,
              school: _school,
              phone: _phone,
              course: _course,
              initials: _initials,
              photoUrl: _photoUrl,
              qrPayload: _qrPayload,
              onFullscreen: () => _openFullscreen(context),
            ),

            const SizedBox(height: 14),

            // ── Fullscreen hint ────────────────────────────
            GestureDetector(
              onTap: () => _openFullscreen(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: _kOrange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tap to show full-screen QR for easy scanning',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Download button ────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showDownloadPreview(context),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  'Download ID',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenQrScreen(fullName: _fullName, qrPayload: _qrPayload),
      ),
    );
  }

  void _showDownloadPreview(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GuestIdDownloadSheet(
        docId: docId,
        fullName: _fullName,
        email: _email,
        school: _school,
        phone: _phone,
        course: _course,
        initials: _initials,
        photoUrl: _photoUrl,
        qrPayload: _qrPayload,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DOWNLOAD PREVIEW SHEET
//
//  Mirrors the student ID's _IdDownloadPreviewSheet: show the card as it will
//  be exported, capture it off a RepaintBoundary, wrap it in a one-page A4 PDF
//  and hand it to the platform share sheet.
// ─────────────────────────────────────────────────────────────
class _GuestIdDownloadSheet extends StatefulWidget {
  final String docId;
  final String fullName;
  final String email;
  final String school;
  final String phone;
  final String course;
  final String initials;
  final String photoUrl;
  final String qrPayload;

  const _GuestIdDownloadSheet({
    required this.docId,
    required this.fullName,
    required this.email,
    required this.school,
    required this.phone,
    required this.course,
    required this.initials,
    required this.photoUrl,
    required this.qrPayload,
  });

  @override
  State<_GuestIdDownloadSheet> createState() => _GuestIdDownloadSheetState();
}

class _GuestIdDownloadSheetState extends State<_GuestIdDownloadSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isGenerating = false;

  Future<Uint8List?> _captureCard(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  Future<void> _downloadAsPdf() async {
    setState(() => _isGenerating = true);

    try {
      // Give a remote avatar a chance to decode before the capture — an
      // undecoded AppImage falls back to the initials placeholder in the PDF.
      await Future.delayed(const Duration(milliseconds: 150));

      final cardBytes = await _captureCard(_cardKey);
      if (cardBytes == null) {
        throw Exception('Could not capture the ID card.');
      }

      final cardImage = pw.MemoryImage(cardBytes);
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) =>
              pw.Center(child: pw.Image(cardImage, fit: pw.BoxFit.contain)),
        ),
      );

      final pdfBytes = await doc.save();
      final fileName = 'UPRISE_GUEST_ID_${widget.docId}.pdf';

      if (!mounted) return;
      setState(() => _isGenerating = false);
      Navigator.pop(context);

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate ID PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE8E8E8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            RepaintBoundary(
              key: _cardKey,
              // No onFullscreen: the exported card shows "Scan to verify"
              // instead of a tap affordance that means nothing on paper.
              child: _DigitalIdCard(
                docId: widget.docId,
                fullName: widget.fullName,
                email: widget.email,
                school: widget.school,
                phone: widget.phone,
                course: widget.course,
                initials: widget.initials,
                photoUrl: widget.photoUrl,
                qrPayload: widget.qrPayload,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGenerating ? null : _downloadAsPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kOrange.withAlpha(153),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isGenerating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Download',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
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
          const Icon(Icons.info_outline_rounded, size: 18, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is your verified guest identity card. Present it or show the QR code to CICT event staff.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF7A3300),
              ),
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
  final String docId;
  final String fullName;
  final String email;
  final String school;
  final String phone;
  final String course;
  final String initials;
  final String photoUrl;
  final String qrPayload;

  /// Opens the full-screen QR. Null when the card is being rendered for the
  /// PDF capture, which swaps "Tap to enlarge" for "Scan to verify".
  final VoidCallback? onFullscreen;

  const _DigitalIdCard({
    required this.docId,
    required this.fullName,
    required this.email,
    required this.school,
    required this.phone,
    required this.course,
    required this.initials,
    required this.photoUrl,
    required this.qrPayload,
    this.onFullscreen,
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
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _kOrange.withAlpha(15),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header band ──────────────────────────────────
          Container(
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kOrange, Color(0xFFD47A00)]),
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
                          Image.asset(
                            'assets/images/logo.png',
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'UPRISE',
                            style: GoogleFonts.beVietnamPro(
                              color: _kOrange,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${docId.length >= 8 ? docId.substring(0, 8).toUpperCase() : docId.toUpperCase()}…',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        fullName.toUpperCase(),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          letterSpacing: 0.3,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Verified badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
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
                              size: 10,
                              color: _kSuccess,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'VERIFIED GUEST',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _kSuccess,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            color: const Color(0xFFAAAAAA),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar — photo if available, otherwise initials
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _kOrangeLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _kOrange.withAlpha(64),
                      width: 1.5,
                    ),
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
                      child: Text(
                        initials,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: _kOrange,
                        ),
                      ),
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
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kSuccessBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kSuccess.withAlpha(102)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 10,
                              color: _kSuccess,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'APPROVED',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _kSuccess,
                                letterSpacing: 0.6,
                              ),
                            ),
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
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrPayload,
                          version: QrVersions.auto,
                          size: 100,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: _kDark,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: _kDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (onFullscreen == null)
                        Text(
                          'Scan to verify',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 9,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_full_rounded,
                              size: 9,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Tap to enlarge',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 9,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w600,
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

          // ── Bottom strip ──────────────────────────────────
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kOrange, Color(0xFFD47A00)]),
            ),
          ),
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

  const _FullscreenQrScreen({required this.fullName, required this.qrPayload});

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
            child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Guest ID — Scan QR',
          style: GoogleFonts.beVietnamPro(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              fullName.toUpperCase(),
              style: GoogleFonts.beVietnamPro(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'VERIFIED GUEST',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: _kOrange,
              fontWeight: FontWeight.w600,
            ),
          ),
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
                  spreadRadius: 5,
                ),
              ],
            ),
            child: QrImageView(
              data: qrPayload,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: _kDark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: _kDark,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _kOrange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Show to event staff for scanning',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
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
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _kOrangeLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  size: 46,
                  color: _kOrange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Not Logged In',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Log in as a verified guest to access your digital ID.',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),
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
                width: 90,
                height: 90,
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
                isPending ? 'Awaiting Approval' : 'Application Rejected',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
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
                  height: 1.5,
                ),
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
/// Label-over-value row on the ID card, matching the student ID's
/// `_IdDetailRow` (student_profile_screen.dart).
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFAAAAAA),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value.trim().isNotEmpty ? value.toUpperCase() : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEEEEEE)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashW = 5.0;
    const gapW = 4.0;
    double x = 0;
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
