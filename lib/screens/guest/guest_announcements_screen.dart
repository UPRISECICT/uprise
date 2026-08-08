import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class GuestAnnouncementsScreen extends StatelessWidget {
  const GuestAnnouncementsScreen({super.key});

  // Guests never see 'CICT Only' content — that audience tag gates content
  // to verified CICT students, which a guest by definition isn't. This
  // matches guest_events_screen.dart's classificationAllowsAudience(),
  // which excludes 'CICT Only'/'Members Only' from guests the same way.
  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('announcements')
      .where('isPublished', isEqualTo: true)
      .where('targetAudience', isEqualTo: 'Public')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),

      appBar: AppBar(title: const Text('Announcements')),

      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No announcements available'));
          }

          final announcements = snapshot.data!.docs;

          announcements.sort((a, b) {
            final aTime = (a['timestamp'] as Timestamp?) ?? Timestamp.now();

            final bTime = (b['timestamp'] as Timestamp?) ?? Timestamp.now();

            return bTime.compareTo(aTime);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final doc = announcements[index];
              final data = doc.data() as Map<String, dynamic>;

              final title = data['title'] ?? '';
              final content = data['content'] ?? '';
              final authorName = data['authorName'] ?? 'Unknown';
              final imageBase64 = data['imageBase64'] ?? '';
              final isPinned = data['pinned'] ?? false;
              final audience = data['targetAudience'] ?? 'Public';

              return Container(
                margin: const EdgeInsets.only(bottom: 18),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // IMAGE
                    if (imageBase64.toString().isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),

                        child: Image.memory(
                          base64Decode(imageBase64),

                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,

                          errorBuilder: (_, __, ___) {
                            return Container(
                              height: 220,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(18),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // PINNED
                          if (isPinned)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),

                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),

                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(20),
                              ),

                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.push_pin,
                                    color: Colors.white,
                                    size: 14,
                                  ),

                                  const SizedBox(width: 6),

                                  Text(
                                    'Pinned',
                                    style: GoogleFonts.beVietnamPro(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // TITLE
                          Text(
                            title,

                            style: GoogleFonts.beVietnamPro(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // AUTHOR
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.orange.withOpacity(
                                  0.15,
                                ),

                                child: Text(
                                  authorName.isNotEmpty
                                      ? authorName[0].toUpperCase()
                                      : '?',

                                  style: GoogleFonts.beVietnamPro(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: Text(
                                  authorName,

                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),

                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),

                                child: Text(
                                  audience,

                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // CONTENT
                          Text(
                            content,

                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              height: 1.6,
                              color: Colors.grey.shade800,
                            ),
                          ),

                          // ATTACHMENTS COUNT
                          if ((data['attachmentsBase64'] as List?)
                                  ?.isNotEmpty ==
                              true)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),

                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.attach_file,
                                    size: 18,
                                    color: Colors.blue,
                                  ),

                                  const SizedBox(width: 6),

                                  Text(
                                    '${(data['attachmentsBase64'] as List).length} attachment(s)',

                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
