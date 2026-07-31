// lib/widgets/student/announcements_feed.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../screens/student/student_announcements_screen.dart';
import '../common/loading_widget.dart';
import 'app_colors.dart';

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

  String _formatTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final diff = DateTime.now().difference(timestamp.toDate());
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }
    return 'Just now';
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
              return data['isPublished'] != false;
            })
            .take(4)
            .toList();
        if (docs.isEmpty) {
          return const SizedBox();
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>? ?? {};

            // Convert to AnnouncementData
            final announcement = AnnouncementData.fromFirestore(doc);

            final title = data['title'] as String? ?? 'Untitled announcement';
            final content = data['content'] as String? ?? '';
            final timestamp = data['timestamp'];

            return GestureDetector(
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!(announcement);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromRGBO(158, 158, 158, 0.05),
                      spreadRadius: 1,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 107, 53, 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.campaign, color: AppColors.primaryDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            content,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
