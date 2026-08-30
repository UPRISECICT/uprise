import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

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
      backgroundColor: AppColors.background,

      appBar: const StudentAppBar(title: 'Announcements'),

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

          // Filtered client-side rather than adding a 3rd .where() to the
          // query above — that would need a new composite index, and this
          // app has been bitten before by queries silently returning empty
          // when one isn't provisioned.
          final announcements = snapshot.data!.docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isArchived'] != true;
          }).toList();

          if (announcements.isEmpty) {
            return const Center(child: Text('No announcements available'));
          }

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
              final audience = data['targetAudience'] ?? 'Public';
              // Both fields, first non-empty wins — an announcement's photo
              // can be stored inline or as a URL, and `??` would let an empty
              // imageBase64 beat a populated imageUrl.
              final imageSource = firstNonEmptyImageSource([
                data['imageBase64']?.toString(),
                data['imageUrl']?.toString(),
              ]);

              return Container(
                margin: const EdgeInsets.only(bottom: 18),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // IMAGE — AppImage rather than a bare
                    // Image.memory(base64Decode(...)): a stored `data:image`
                    // URI made base64Decode throw while building the argument,
                    // which errorBuilder can't catch (it only handles failures
                    // inside the codec), so the card rendered a red error box.
                    // AppImage also handles network URLs, which this never did.
                    if (imageSource.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),

                        child: AppImage(
                          source: imageSource,

                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,

                          // Default spinner rather than the placeholder while
                          // loading: the source can now be a URL, and a
                          // broken-image icon that later turns into a photo
                          // claims a failure that hasn't happened.
                          placeholder: Container(
                            height: 220,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(18),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                backgroundColor: AppColors.primaryDark
                                    .withAlpha(38),

                                child: Text(
                                  authorName.isNotEmpty
                                      ? authorName[0].toUpperCase()
                                      : '?',

                                  style: GoogleFonts.beVietnamPro(
                                    color: AppColors.primaryDark.shade800,
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
                                  color: AppColors.primaryDark.withAlpha(26),
                                  borderRadius: BorderRadius.circular(20),
                                ),

                                child: Text(
                                  audience,

                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    color: AppColors.primaryDark.shade900,
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
