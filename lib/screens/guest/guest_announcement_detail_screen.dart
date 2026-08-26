// lib/screens/guest/guest_announcement_detail_screen.dart
//
// Full view of a single announcement, for guests.
//
// The standalone guest announcements list renders each post inline and in
// full, so it never needed a detail route. The org profile's announcement
// cards are compact previews, though, and tapping one has to open something —
// and it must not be the student AnnouncementDetailScreen, which sits in the
// student navigation stack.
//
// Read-only by construction: there is nothing here to act on, which is exactly
// the guest's relationship to an announcement.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

class GuestAnnouncementDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const GuestAnnouncementDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Untitled').toString();
    final content = (data['content'] ?? '').toString();
    final author = (data['authorName'] ?? '').toString();
    final orgName = (data['orgName'] ?? '').toString();
    final imageBase64 = (data['imageBase64'] ?? '').toString();
    final ts = data['timestamp'];
    final date = ts is Timestamp ? ts.toDate() : null;
    final isPinned = data['pinned'] == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const StudentAppBar(title: 'Announcement'),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (imageBase64.isNotEmpty)
            _Banner(imageBase64: imageBase64),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPinned)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PINNED',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (orgName.isNotEmpty) orgName,
                    if (author.isNotEmpty) author,
                    if (date != null) DateFormat('MMM d, y').format(date),
                  ].join(' · '),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  content.isNotEmpty
                      ? content
                      : 'No further details were provided.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14.5,
                    height: 1.7,
                    color: Colors.black87,
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

/// Base64 banner with a graceful fallback — announcement images are stored
/// inline rather than as URLs, and a malformed payload shouldn't blank the
/// whole screen.
class _Banner extends StatelessWidget {
  final String imageBase64;
  const _Banner({required this.imageBase64});

  @override
  Widget build(BuildContext context) {
    try {
      return Image.memory(
        base64Decode(
          imageBase64.contains(',')
              ? imageBase64.split(',').last
              : imageBase64,
        ),
        width: double.infinity,
        height: 230,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() => Container(
    height: 230,
    color: AppColors.primarySoft,
    child: const Icon(
      Icons.campaign_outlined,
      size: 48,
      color: AppColors.primaryDark,
    ),
  );
}
