// lib/widgets/student/announcements_feed.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../screens/student/student_announcements_screen.dart';
import '../common/feed_cards.dart';
import '../common/loading_widget.dart';

class AnnouncementsFeed extends StatefulWidget {
  final Function(AnnouncementData)? onTap;

  const AnnouncementsFeed({super.key, this.onTap});

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

  String _formatTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SkeletonLoader(count: 2, height: 76),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox();
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((d) {
              final data = d.data() as Map<String, dynamic>;
              return data['isPublished'] != false && data['isArchived'] != true;
            })
            .take(4)
            .toList();
        if (docs.isEmpty) {
          return const SizedBox();
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];

            // Convert to AnnouncementData
            final announcement = AnnouncementData.fromFirestore(doc);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FeedAnnouncementCard(
                data: FeedAnnouncementCardData(
                  title: announcement.title,
                  body: announcement.body,
                  orgName: announcement.org,
                  imageBase64: announcement.imageUrl,
                  isPinned: announcement.isPinned,
                  timestamp: announcement.timestamp,
                ),
                timeAgo: _formatTime(announcement.timestamp),
                onTap: () => widget.onTap?.call(announcement),
              ),
            );
          },
        );
      },
    );
  }
}
