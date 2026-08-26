// lib/screens/guest/guest_certificate_repository_screen.dart
//
// GUEST CERTIFICATE REPOSITORY — Only meaningful for authenticated guests.
//
// Mirrors lib/screens/student/student_certificates_screen.dart's query
// pattern (fetch `certificates`, filter client-side) but scoped to this
// guest's email via the `isGuest`/`recipientEmail` fields written by
// org_certificates.dart's distribution flow — never the student
// "recipientUid == null" broadcast-fallback branch.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../utils/platform_file_utils.dart' as platform_file_utils;
import 'guest_auth_service.dart';
import '../../widgets/student/app_colors.dart';
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
      final docs = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': data['eventName'] ?? 'Untitled Certificate',
          'organization': data['organization'] ?? '',
          'category': data['type'] ?? data['templateType'] ?? 'General',
          'issuedAt': data['issuedAt'],
          'verificationCode': data['verificationCode'] ?? '',
          'imageUrl': data['imageUrl'] ?? '',
          'templateFileUrl': data['templateFileUrl'] ?? '',
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

  bool _isBase64Image(String url) =>
      url.startsWith('data:image') || (!url.startsWith('http') && url.isNotEmpty);

  Widget _buildImage(String imageUrl, {double height = 160}) {
    if (imageUrl.isEmpty) {
      return Container(
        height: height,
        color: _kOrangeLight,
        child: const Center(
            child: Icon(Icons.workspace_premium_outlined, size: 40, color: _kOrange)),
      );
    }
    if (_isBase64Image(imageUrl)) {
      try {
        final base64Str = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        return Image.memory(base64Decode(base64Str),
            height: height, width: double.infinity, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    return Image.network(imageUrl,
        height: height, width: double.infinity, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }

  Future<void> _download(Map<String, dynamic> cert) async {
    final imageUrl = (cert['imageUrl'] ?? '').toString();
    final fileUrl = (cert['templateFileUrl'] ?? '').toString();
    final fileName = '${cert['title']}.${imageUrl.isNotEmpty ? 'png' : 'pdf'}';
    try {
      Uint8List? bytes;
      if (imageUrl.isNotEmpty && _isBase64Image(imageUrl)) {
        final b64 = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        bytes = base64Decode(b64);
      } else {
        final url = imageUrl.isNotEmpty ? imageUrl : fileUrl;
        if (url.isEmpty) throw Exception('No downloadable file for this certificate.');
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) throw Exception('Download failed');
        bytes = res.bodyBytes;
      }
      await platform_file_utils.saveBytesToTempAndOpen(bytes, fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e', style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _openPreview(Map<String, dynamic> cert) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: _buildImage(cert['imageUrl'], height: 220),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cert['title'], style: GoogleFonts.beVietnamPro(
                      fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(cert['organization'], style: GoogleFonts.beVietnamPro(
                      fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Issued ${_formatDate(cert['issuedAt'])}', style: GoogleFonts.beVietnamPro(
                      fontSize: 12, color: Colors.grey)),
                  if ((cert['verificationCode'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Verification: ${cert['verificationCode']}', style: GoogleFonts.beVietnamPro(
                        fontSize: 11, color: Colors.grey)),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _download(cert),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange, foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
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
                            onTap: () => _openPreview(cert),
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
