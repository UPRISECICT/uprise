// lib/screens/guest/guest_certificate_repository_screen.dart
//
// GUEST CERTIFICATE REPOSITORY — Only meaningful for authenticated guests.
//
// Mirrors lib/screens/student/student_certificates_screen.dart's query
// pattern (fetch `certificates`, filter client-side) but scoped to this
// guest's email via the `isGuest`/`recipientEmail` fields written by
// org_certificates.dart's distribution flow — never the student
// "recipientUid == null" broadcast-fallback branch.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'guest_auth_service.dart';
import '../student/student_certificates_screen.dart' show CertificateDetailScreen;
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;

class GuestCertificateRepositoryScreen extends StatefulWidget {
  const GuestCertificateRepositoryScreen({super.key});

  @override
  State<GuestCertificateRepositoryScreen> createState() =>
      _GuestCertificateRepositoryScreenState();
}

class _GuestCertificateRepositoryScreenState
    extends State<GuestCertificateRepositoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _certificates = [];
  final _searchCtrl = TextEditingController();

  String get _email => (GuestAuthService().email ?? '').toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_email.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('certificates')
          .where('isGuest', isEqualTo: true)
          .where('recipientEmail', isEqualTo: _email)
          .get();
      // Same field shape as the student viewer's _docToMap, because opening a
      // certificate hands this map to the shared CertificateDetailScreen. The
      // org writes the template as `templateFileUrl` (never `imageUrl`), and
      // the recipient name and signatures are overlaid at render time — so
      // reading only `imageUrl` and downloading the raw template file, as
      // this screen used to, produced a blank certificate with no name.
      final docs = snap.docs
          .where((d) => (d.data()['status'] ?? '') != 'draft')
          .map((d) {
        final data = d.data();
        return <String, dynamic>{
          'id': d.id,
          'title': (data['eventName'] ?? 'Untitled Certificate').toString(),
          'date': _formatDate(data['issuedAt']),
          'category': data['type'] ?? data['templateType'] ?? 'General',
          'organization': (data['organization'] ?? '').toString(),
          'recipientName': (data['recipientName'] ?? '').toString(),
          'signatories':
              data['signatories'] is List ? data['signatories'] : const [],
          'templateType': data['templateType'] ?? data['type'] ?? 'modern',
          'imageUrl':
              (data['templateFileUrl'] ?? data['imageUrl'] ?? '').toString(),
          'namePlacement':
              data['namePlacement'] is Map ? data['namePlacement'] : null,
          'signatoryPlacements': data['signatoryPlacements'] is Map
              ? data['signatoryPlacements']
              : null,
          'isUploaded': false,
          'verificationCode': (data['verificationCode'] ?? '').toString(),
          'eventId': data['eventId'] ?? '',
          'templateData': data['templateData'] is Map
              ? data['templateData']
              : <String, dynamic>{},
          'issuedAt': data['issuedAt'],
        };
      }).toList();

      docs.sort((a, b) {
        final aTs = a['issuedAt'], bTs = b['issuedAt'];
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return (bTs as Timestamp).compareTo(aTs as Timestamp);
      });

      if (mounted) setState(() { _certificates = docs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _certificates;
    return _certificates.where((c) =>
        c['title'].toString().toLowerCase().contains(q) ||
        c['organization'].toString().toLowerCase().contains(q)).toList();
  }

  String _formatDate(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final dt = ts.toDate();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // AppImage rather than a local base64/network split. Certificate templates
  // uploaded as PDFs are stored as a Cloudinary .pdf URL, which no Image widget
  // can decode as pixels; AppImage re-requests the same asset as .jpg so the
  // first page rasterizes. The student certificates screen already renders
  // these correctly for exactly that reason — this one showed nothing.
  //
  // A broken image now lands on the same placeholder as an empty one, rather
  // than the old SizedBox.shrink() that collapsed the card's image slot.
  Widget _buildImage(String imageUrl, {double height = 160}) {
    return AppImage(
      source: imageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: Container(
        height: height,
        color: _kOrangeLight,
        child: const Center(
            child: Icon(Icons.workspace_premium_outlined, size: 40, color: _kOrange)),
      ),
    );
  }

  // Opens the same detail screen and download sheet CICT students use, so a
  // guest's certificate renders with their name, the signatures, and the
  // verification QR — and downloads as that rendered certificate, not the
  // blank template file.
  void _openCertificate(Map<String, dynamic> cert) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CertificateDetailScreen(certificate: cert),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Certificate Repository'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kOrange,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search certificates…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Column(children: [
                            const Icon(Icons.workspace_premium_outlined, size: 56, color: Color(0xFFD1D5DB)),
                            const SizedBox(height: 14),
                            Text('No certificates yet', style: GoogleFonts.beVietnamPro(
                                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                            const SizedBox(height: 6),
                            Text('Certificates you earn from attending and evaluating events will appear here.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey)),
                          ]),
                        )
                      else
                        ..._filtered.map((cert) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _openCertificate(cert),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFF0F0F0)),
                              ),
                              child: Row(children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                  child: SizedBox(width: 80, height: 80, child: _buildImage(cert['imageUrl'], height: 80)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cert['title'], maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 3),
                                        Text(cert['organization'], maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text(_formatDate(cert['issuedAt']),
                                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: _kOrange, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(right: 12),
                                  child: Icon(Icons.chevron_right_rounded, color: Colors.grey),
                                ),
                              ]),
                            ),
                          ),
                        )),
                    ],
                  ),
                ),
    );
  }
}
