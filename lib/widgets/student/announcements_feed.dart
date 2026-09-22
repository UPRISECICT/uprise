// lib/widgets/student/announcements_feed.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../screens/student/student_announcements_screen.dart';
import '../../services/org_directory.dart';
import '../common/feed_cards.dart';
import '../common/loading_widget.dart';
import 'app_colors.dart';

class AnnouncementsFeed extends StatefulWidget {
  final Function(AnnouncementData)? onTap;

  /// Which `targetAudience` values may be shown. Null — the default, and what
  /// the student side passes — means no audience filtering at all.
  ///
  /// Guests must pass `{'Public'}`. Without it this feed would put Members-Only
  /// and CICT-Only announcements in front of a guest, since the query below
  /// deliberately carries no audience `where` clause. Same rule
  /// `OrgBrowsingConfig.publicAnnouncementsOnly` and guest_announcements_screen
  /// already enforce.
  ///
  /// Filtered client-side alongside the isPublished/isArchived checks rather
  /// than in the query, for the composite-index reason described below.
  final Set<String>? allowedAudiences;

  const AnnouncementsFeed({super.key, this.onTap, this.allowedAudiences});

  @override
  State<AnnouncementsFeed> createState() => _AnnouncementsFeedState();
}

class _AnnouncementsFeedState extends State<AnnouncementsFeed> {
  // Created once, not a getter — re-evaluating .snapshots() on every
  // rebuild (this widget sits on the home screen, which rebuilds often)
  // was re-subscribing to Firestore from scratch each time.
  //
  // Deliberately NOT combining a `where('isPublished', ...)` filter with
  // this `orderBy` — that pairing needs a composite Firestore index, and
  // without it deployed the query fails outright. Scheduled/draft
  // announcements (isPublished: false) are filtered out client-side below
  // instead; fetches a few extra so there's still room for 4 after that.
  late final Stream<QuerySnapshot> _announcementsStream = FirebaseFirestore
      .instance
      .collection('announcements')
      .orderBy('timestamp', descending: true)
      .limit(10)
      .snapshots();

  @override
  void initState() {
    super.initState();
    // Cards resolve their org name and logo through OrgDirectory at build
    // time, so this has to rebuild once that index loads.
    OrgDirectory.start();
    OrgDirectory.revision.addListener(_onOrgDirectoryChanged);
  }

  @override
  void dispose() {
    OrgDirectory.revision.removeListener(_onOrgDirectoryChanged);
    super.dispose();
  }

  void _onOrgDirectoryChanged() {
    if (mounted) setState(() {});
  }

  String _formatTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _isNew(AnnouncementData a) =>
      DateTime.now().difference(a.timestamp).inHours < 24;

  // NEW says something the reader can't infer; everything else falls back to
  // the Organizations tab's plain ANNOUNCEMENT badge. Pin status deliberately
  // isn't surfaced here — it's an org-level curation signal, so it only shows
  // on that org's profile (the Pinned Announcements section on its About tab).
  String _badgeLabel(AnnouncementData a) {
    if (_isNew(a)) return 'NEW';
    return 'ANNOUNCEMENT';
  }

  Color _badgeColor(AnnouncementData a) {
    if (_isNew(a)) return const Color(0xFF059669);
    return AppColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Sized to the new card (160 banner + ~90 of text), not the 76 of
          // the compact row this used to render.
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: SkeletonLoader(count: 2, height: 240, borderRadius: 14),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox();
        }

        final allowed = widget.allowedAudiences;
        final docs = (snapshot.data?.docs ?? [])
            .where((d) {
              final data = d.data() as Map<String, dynamic>;
              if (!shouldShowAnnouncementToStudent(data)) {
                return false;
              }
              if (allowed == null) return true;
              // Missing/blank targetAudience is treated as Public, matching
              // how the rest of the app reads this field.
              final audience = (data['targetAudience'] ?? 'Public').toString();
              return allowed.contains(
                audience.trim().isEmpty ? 'Public' : audience.trim(),
              );
            })
            .take(4)
            .toList();
        if (docs.isEmpty) {
          return const SizedBox();
        }

        // Horizontal padding matches Home's section headers (20), since the
        // card this replaced was full-bleed and needed none.
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final doc = docs[index];

            // Convert to AnnouncementData
            final announcement = AnnouncementData.fromFirestore(doc);

            return CompactFeedCard(
              imageSource: announcement.imageUrl,
              orgName: announcement.org,
              orgLogoUrl: announcement.logoUrl,
              badgeLabel: _badgeLabel(announcement),
              badgeColor: _badgeColor(announcement),
              title: announcement.title,
              snippet: announcement.body,
              timeAgo: _formatTime(announcement.timestamp),
              onTap: () => widget.onTap?.call(announcement),
            );
          },
        );
      },
    );
  }
}
