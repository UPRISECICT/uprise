import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/common/action_tile.dart';
import '../../widgets/common/announcement_filter_bar.dart';
import '../../widgets/common/image_viewer.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

// Stateful only to hold the filter selections — the query itself is unchanged
// and still streams every public announcement.
class GuestAnnouncementsScreen extends StatefulWidget {
  const GuestAnnouncementsScreen({super.key});

  @override
  State<GuestAnnouncementsScreen> createState() =>
      _GuestAnnouncementsScreenState();
}

class _GuestAnnouncementsScreenState extends State<GuestAnnouncementsScreen> {
  AnnouncementFilters _filters = const AnnouncementFilters();

  // Guests never see 'CICT Only' content — that audience tag gates content
  // to verified CICT students, which a guest by definition isn't. This
  // matches guest_events_screen.dart's classificationAllowsAudience(),
  // which excludes 'CICT Only'/'Members Only' from guests the same way.
  //
  // Created once, not a getter: rebuilding it on every filter keystroke would
  // re-subscribe to Firestore from scratch.
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('announcements')
      .where('isPublished', isEqualTo: true)
      .where('targetAudience', isEqualTo: 'Public')
      .snapshots();

  /// Shown when there are posts but none match the active filters — distinct
  /// from "No announcements available", which means there is nothing to read.
  Widget _noMatchesState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            'No matching announcements',
            style: GoogleFonts.beVietnamPro(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different keyword, organization,\nor category.',
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () =>
                setState(() => _filters = const AnnouncementFilters()),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    ),
  );

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
          // when one isn't provisioned. The search/org/category filters ride
          // along for the same reason.
          final visible = snapshot.data!.docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isArchived'] != true;
          }).toList();

          if (visible.isEmpty) {
            return const Center(child: Text('No announcements available'));
          }

          visible.sort((a, b) {
            final aTime = (a['timestamp'] as Timestamp?) ?? Timestamp.now();

            final bTime = (b['timestamp'] as Timestamp?) ?? Timestamp.now();

            return bTime.compareTo(aTime);
          });

          // Options come from what's visible, so a guest is never offered an
          // org or category whose posts they can't see.
          final visibleMaps = visible
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
          final announcements = visible
              .where((d) => _filters.matches(d.data() as Map<String, dynamic>))
              .toList();

          return Column(
            children: [
              AnnouncementFilterBar(
                filters: _filters,
                onChanged: (f) => setState(() => _filters = f),
                orgOptions: announcementOrgOptions(visibleMaps),
                categoryOptions: announcementCategoryOptions(visibleMaps),
                resultCount: announcements.length,
              ),
              Expanded(
                child: announcements.isEmpty
                    ? _noMatchesState()
                    : ListView.builder(
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

                            // Same borderless card token the student
                            // announcements list uses; radius stays 18 to
                            // keep this screen's existing geometry.
                            decoration: kCardDecoration(radius: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // IMAGE — AppImage rather than a bare
                                // Image.memory(base64Decode(...)): a stored `data:image`
                                // URI made base64Decode throw while building the argument,
                                // which errorBuilder can't catch (it only handles failures
                                // inside the codec), so the card rendered a red error box.
                                // AppImage also handles network URLs, which this never did.
                                // Tappable: the banner crops to 220px with BoxFit.cover,
                                // so the whole picture is only visible full-screen.
                                if (imageSource.isNotEmpty)
                                  expandableImage(
                                    context: context,
                                    source: imageSource,
                                    child: ClipRRect(
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
                                  ),

                                Padding(
                                  padding: const EdgeInsets.all(18),

                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            backgroundColor: AppColors
                                                .primaryDark
                                                .withAlpha(38),

                                            child: Text(
                                              authorName.isNotEmpty
                                                  ? authorName[0].toUpperCase()
                                                  : '?',

                                              style: GoogleFonts.beVietnamPro(
                                                color: AppColors
                                                    .primaryDark
                                                    .shade800,
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
                                              color: AppColors.primaryDark
                                                  .withAlpha(26),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),

                                            child: Text(
                                              audience,

                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11,
                                                color: AppColors
                                                    .primaryDark
                                                    .shade900,
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
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),

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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
