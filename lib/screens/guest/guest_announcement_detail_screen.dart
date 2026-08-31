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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../widgets/student/app_colors.dart';
import '../../widgets/common/image_viewer.dart';
import '../../widgets/student/app_image.dart';
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
    // Both fields, first non-empty wins — `??` would let an empty
    // imageBase64 beat a populated imageUrl.
    final imageSource = firstNonEmptyImageSource([
      data['imageBase64']?.toString(),
      data['imageUrl']?.toString(),
    ]);
    final ts = data['timestamp'];
    final date = ts is Timestamp ? ts.toDate() : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const StudentAppBar(title: 'Announcement'),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (imageSource.isNotEmpty) _Banner(imageSource: imageSource),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

/// Announcement banner with a graceful fallback. Announcement images are
/// usually stored inline as base64, but not always — AppImage takes base64
/// (with or without a data: prefix) and http(s) URLs alike, and returns the
/// placeholder instead of throwing on a malformed payload.
class _Banner extends StatelessWidget {
  final String imageSource;
  const _Banner({required this.imageSource});

  @override
  Widget build(BuildContext context) {
    // Tappable: the banner crops to 230px with BoxFit.cover, so the whole
    // picture is only visible in the fullscreen viewer.
    return expandableImage(
      context: context,
      source: imageSource,
      child: AppImage(
        source: imageSource,
        width: double.infinity,
        height: 230,
        fit: BoxFit.cover,
        placeholder: _placeholder(),
      ),
    );
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
