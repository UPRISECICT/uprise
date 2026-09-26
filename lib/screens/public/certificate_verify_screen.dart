import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// The `?verify=CODE` query parameter, or null when the page was opened
/// normally. Certificate QR codes link to `https://org.uprisecict.site/?verify=`,
/// so every web entry point checks this before showing its landing page.
String? certificateVerifyCodeFromUrl() {
  final code = Uri.base.queryParameters['verify']?.trim();
  return (code == null || code.isEmpty) ? null : code;
}

/// Standalone app for the public verification page — no auth required.
/// Same setup main_web.dart uses, shared by main_org.dart and main_admin.dart
/// (the entry points actually deployed to org./admin.uprisecict.site).
class CertificateVerifyApp extends StatelessWidget {
  final String verificationCode;
  const CertificateVerifyApp({super.key, required this.verificationCode});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UPRISE - Certificate Verification',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFB45309),
        fontFamily: 'BeVietnamPro',
        useMaterial3: true,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFB45309),
        ),
      ),
      home: CertificateVerifyScreen(verificationCode: verificationCode),
    );
  }
}

class CertificateVerifyScreen extends StatefulWidget {
  final String verificationCode;
  const CertificateVerifyScreen({super.key, required this.verificationCode});

  @override
  State<CertificateVerifyScreen> createState() => _CertificateVerifyScreenState();
}

class _CertificateVerifyScreenState extends State<CertificateVerifyScreen> {
  Map<String, dynamic>? _cert;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _loadCert();
  }

  Future<void> _loadCert() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('certificates')
          .where('verificationCode', isEqualTo: widget.verificationCode)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        setState(() { _notFound = true; _loading = false; });
        return;
      }
      final data = snap.docs.first.data();
      setState(() { _cert = data; _loading = false; });
    } catch (_) {
      setState(() { _notFound = true; _loading = false; });
    }
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) return DateFormat('MMMM dd, yyyy').format(ts.toDate());
    return ts.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB45309),
        title: Text('Certificate Verification',
            style: GoogleFonts.beVietnamPro(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _loading
                ? const CircularProgressIndicator(color: Color(0xFFB45309))
                : _notFound
                    ? _buildNotFound()
                    : _buildVerified(),
          ),
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 36),
        ),
        const SizedBox(height: 20),
        Text('Certificate Not Found',
            style: GoogleFonts.beVietnamPro(
                fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1A202C))),
        const SizedBox(height: 8),
        Text('The verification code "${widget.verificationCode}" does not match any certificate in our records.',
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(fontSize: 14, color: const Color(0xFF64748B))),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('This certificate may be invalid, expired, or the code was entered incorrectly.',
                  style: GoogleFonts.beVietnamPro(fontSize: 13, color: const Color(0xFFDC2626))),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildVerified() {
    final cert = _cert!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Verified badge
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 38),
        ),
        const SizedBox(height: 16),
        Text('Certificate Verified',
            style: GoogleFonts.beVietnamPro(
                fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
        const SizedBox(height: 6),
        Text('This is an authentic UPRISE certificate.',
            style: GoogleFonts.beVietnamPro(fontSize: 14, color: const Color(0xFF64748B))),
        const SizedBox(height: 28),

        // Certificate details card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8ECF0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Recipient', cert['recipientName']?.toString() ?? '—'),
              const SizedBox(height: 14),
              _row('Event', cert['eventName']?.toString() ?? '—'),
              const SizedBox(height: 14),
              _row('Organization', cert['organization']?.toString() ?? '—'),
              const SizedBox(height: 14),
              _row('Certificate Type', cert['type']?.toString() ?? 'Participation'),
              const SizedBox(height: 14),
              _row('Issued On', _formatDate(cert['issuedAt'])),
              const SizedBox(height: 14),
              _row('Verification Code', widget.verificationCode,
                  mono: true, color: const Color(0xFFB45309)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Validity banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('This certificate is valid and was issued by CICT UPRISE.',
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 13, color: const Color(0xFF059669), fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool mono = false, Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value,
              style: mono
                  ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      fontFamily: 'monospace', letterSpacing: 1.2, color: Color(0xFFB45309))
                  : GoogleFonts.beVietnamPro(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: color ?? const Color(0xFF1A202C))),
        ),
      ],
    );
  }
}
