// lib/screens/student/student_announcements_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uprise/models/event_model.dart';
import '../../services/org_directory.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/action_tile.dart';
import '../../widgets/common/announcement_filter_bar.dart';
import '../../widgets/common/image_viewer.dart';
import '../../widgets/student/app_image.dart';
import 'student_events_screen.dart';

// ─────────────────────────────────────────────────────────────
//  NAVIGATE TO LINKED EVENT
// ─────────────────────────────────────────────────────────────
Future<void> _goToLinkedEvent(
  BuildContext context,
  AnnouncementData ann,
) async {
  if (ann.linkedEventId.isEmpty) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: AppColors.primaryDark),
    ),
  );

  try {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(ann.linkedEventId)
        .get();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This event is no longer available.')),
      );
      return;
    }

    final event = EventModel.fromFirestore(doc);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          onRegistered: () {},
          isPastEvent: event.isPast,
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open event: $e')));
  }
}

// ─────────────────────────────────────────────────────────────
//  SHOULD SHOW ANNOUNCEMENT
// ─────────────────────────────────────────────────────────────
bool shouldShowAnnouncementToStudent(Map<String, dynamic> data) {
  if (data['isArchived'] == true) {
    return false;
  }

  // Scheduled posts are written with isPublished: false at creation time and
  // nothing ever flips it back to true — there's no cron/Cloud Function that
  // does it — so isPublished can't be trusted for these. Whether a scheduled
  // post is visible depends entirely on whether scheduledPublishDate has
  // already passed.
  final isScheduled = data['isScheduled'] == true;
  if (isScheduled) {
    final scheduledPublishDate = data['scheduledPublishDate'];
    if (scheduledPublishDate is Timestamp) {
      return !scheduledPublishDate.toDate().isAfter(DateTime.now());
    }
    if (scheduledPublishDate is DateTime) {
      return !scheduledPublishDate.isAfter(DateTime.now());
    }
    return true;
  }

  return data['isPublished'] != false;
}

// ─────────────────────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────────────────────
class AnnouncementData {
  final String id;
  final String title;
  final String org;

  /// The posting org's id — the only stable handle back to its profile. The
  /// name and logo are resolved through it rather than read off the post.
  final String orgId;
  final String orgSub;
  final String category;
  final String date;
  final String time;
  final DateTime timestamp;
  final bool isPinned;
  final String tag;
  final String imageUrl;
  final String logoUrl;
  final String body;
  final List<String> hashtags;
  final List<Map<String, String>> attachments;
  final String linkedEventId;
  final String linkedProposalId;
  final String linkedEventTitle;
  final String authorId;
  final String authorName;

  AnnouncementData({
    required this.id,
    required this.title,
    required this.org,
    this.orgId = '',
    required this.orgSub,
    this.category = '',
    required this.date,
    required this.time,
    required this.timestamp,
    required this.isPinned,
    required this.tag,
    required this.imageUrl,
    required this.logoUrl,
    required this.body,
    required this.hashtags,
    required this.attachments,
    this.linkedEventId = '',
    this.linkedProposalId = '',
    this.linkedEventTitle = '',
    this.authorId = '',
    this.authorName = '',
  });

  factory AnnouncementData.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final timestamp = d['timestamp'];
    final dateTime = timestamp is Timestamp
        ? timestamp.toDate()
        : timestamp is DateTime
        ? timestamp
        : DateTime.now();

    // First non-empty, not `??`: `??` falls through only on null, so an
    // announcement stored with an empty imageBase64 and a real imageUrl
    // rendered nothing at all.
    final rawImage = firstNonEmptyImageSource([
      d['imageBase64'] as String?,
      d['imageUrl'] as String?,
    ]);

    // Resolve the org through its id, not through what the post recorded.
    // `authorName` was frozen at post time from `shortName ?? name`, so it
    // goes stale the moment an org renames itself, and `logoUrl` is never
    // written onto an announcement at all — it was always empty here.
    // Both fall back to the post's own copy for an org that no longer exists.
    final orgId = (d['orgId'] ?? '').toString();
    final authorName = (d['authorName'] as String? ?? '').trim();
    final directoryName = OrgDirectory.nameFor(orgId);
    final directoryLogo = OrgDirectory.logoFor(orgId);

    final logoUrl = directoryLogo.isNotEmpty
        ? directoryLogo
        : (d['logoUrl'] as String? ?? '');

    return AnnouncementData(
      id: doc.id,
      title: d['title'] as String? ?? '',
      org: directoryName.isNotEmpty
          ? directoryName
          : (authorName.isNotEmpty ? authorName : 'Organization'),
      orgId: orgId,
      orgSub: (d['category'] as String?)?.toUpperCase() ?? 'ANNOUNCEMENT',
      category: (d['category'] as String? ?? '').trim(),
      date: DateFormat('MMM dd, yyyy').format(dateTime),
      time: DateFormat('h:mm a').format(dateTime),
      timestamp: dateTime,
      isPinned: d['pinned'] as bool? ?? false,
      tag:
          (d['targetAudience'] as String?)?.toUpperCase() ??
          (d['category'] as String?)?.toUpperCase() ??
          'ANNOUNCEMENT',
      imageUrl: rawImage,
      logoUrl: logoUrl,
      body: d['content'] as String? ?? '',
      hashtags: [],
      attachments: ((d['attachmentsBase64'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(
            (att) => {
              'name': att['name'] as String? ?? '',
              'type': _guessType(att['name'] as String? ?? ''),
              'base64': att['base64'] as String? ?? '',
              'size': att['size'] as String? ?? '',
            },
          )
          .toList(),
      linkedEventId: d['linkedEventId'] as String? ?? '',
      linkedProposalId: d['linkedProposalId'] as String? ?? '',
      linkedEventTitle: d['linkedEventTitle'] as String? ?? '',
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
    );
  }

  static String _guessType(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'pdf') return 'pdf';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
    return 'file';
  }
}

// ─────────────────────────────────────────────────────────────
//  MAIN LIST SCREEN
// ─────────────────────────────────────────────────────────────
class StudentAnnouncementsScreen extends StatefulWidget {
  const StudentAnnouncementsScreen({super.key});

  @override
  State<StudentAnnouncementsScreen> createState() =>
      _StudentAnnouncementsScreenState();
}

class _StudentAnnouncementsScreenState
    extends State<StudentAnnouncementsScreen> {
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  AnnouncementFilters _filters = const AnnouncementFilters();

  late final Stream<QuerySnapshot> _announcementsStream = FirebaseFirestore
      .instance
      .collection('announcements')
      .orderBy('timestamp', descending: true)
      .snapshots();

  @override
  void initState() {
    super.initState();
    OrgDirectory.start();
    // Org names and logos are resolved at card-build time, so the feed has to
    // rebuild when the directory's first snapshot lands — otherwise every card
    // keeps the fallback name it was built with.
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

  /// Shown when the feed has posts but none survive the active filters —
  /// deliberately different from the "No announcements yet" state, which means
  /// there is nothing to read at all.
  Widget _noMatchesState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          const Text(
            'No matching announcements',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different keyword, organization,\nor category.',
            textAlign: TextAlign.center,
            style: TextStyle(
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
        stream: _announcementsStream,
        builder: (context, snapshot) {
          // Deliberately not gated on the org directory: a card whose org
          // hasn't resolved yet falls back to the name stored on the post and
          // corrects itself on the next revision, which beats holding the whole
          // feed behind a spinner that never clears if that listener fails.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryDark),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load announcements',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Audience gate first, then the user's filters — the dropdown
          // options are built from what's already visible, so a student is
          // never offered an org or category they can't actually see.
          final visible = (snapshot.data?.docs ?? []).where((d) {
            final data = d.data() as Map<String, dynamic>;
            return shouldShowAnnouncementToStudent(data);
          }).toList();

          final visibleMaps = visible
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
          final docs = visible
              .where((d) => _filters.matches(d.data() as Map<String, dynamic>))
              .toList();

          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.campaign_outlined,
                        size: 48,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No announcements yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New posts from your organizations\nwill appear here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Straight timestamp-descending, exactly as the query returns them.
          // Pinned posts used to be partitioned to the top here; pin status is
          // an org-level curation signal now, surfaced only on that org's
          // profile, so this feed treats every post the same.
          final items = docs.map(AnnouncementData.fromFirestore).toList();

          return Column(
            children: [
              AnnouncementFilterBar(
                filters: _filters,
                onChanged: (f) => setState(() => _filters = f),
                orgOptions: announcementOrgOptions(visibleMaps),
                categoryOptions: announcementCategoryOptions(visibleMaps),
                resultCount: items.length,
              ),
              Expanded(
                child: items.isEmpty
                    // Distinct from "no announcements yet" above: there are
                    // posts, they just don't match what was typed or picked.
                    ? _noMatchesState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final ann = items[index];
                          return _AnnouncementCard(ann: ann);
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

// ─────────────────────────────────────────────────────────────
//  ANNOUNCEMENT CARD - WITH ORGANIZATION LOGO
// ─────────────────────────────────────────────────────────────
/// "x ago" — mirrors org_announcements.dart's web feed exactly, so the same
/// post reads the same way on both platforms.
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return DateFormat('MMM dd, yyyy').format(dt);
}

// Same category → color/icon mapping as org_announcements.dart's
// _categoryThemes, so a post tagged "Training" (say) reads as the same blue
// on both the org's web feed and here — the only place students could tell
// posts apart by category before this was the plain-text tag pill.
class _CategoryTheme {
  final Color bg, fg;
  final IconData icon;
  const _CategoryTheme(this.bg, this.fg, this.icon);
}

const Map<String, _CategoryTheme> _categoryThemes = {
  'General': _CategoryTheme(
    Color(0xFFF1F5F9),
    Color(0xFF475569),
    Icons.campaign_outlined,
  ),
  'New Hire': _CategoryTheme(
    Color(0xFFECFDF5),
    Color(0xFF059669),
    Icons.person_add_alt_1_rounded,
  ),
  'SOP Updates': _CategoryTheme(
    Color(0xFFEFF6FF),
    Color(0xFF2563EB),
    Icons.fact_check_outlined,
  ),
  'Policy Updates': _CategoryTheme(
    Color(0xFFF3E8FF),
    Color(0xFF7C3AED),
    Icons.policy_outlined,
  ),
  'Promotion': _CategoryTheme(
    Color(0xFFFFFBEB),
    Color(0xFFFB923C),
    Icons.trending_up_rounded,
  ),
  'Transfer': _CategoryTheme(
    Color(0xFFFFE4E6),
    Color(0xFFE11D48),
    Icons.swap_horiz_rounded,
  ),
  'Training': _CategoryTheme(
    Color(0xFFE0F2FE),
    Color(0xFF0284C7),
    Icons.school_outlined,
  ),
  'Special': _CategoryTheme(
    Color(0xFFFCE7F3),
    Color(0xFFDB2777),
    Icons.star_outline_rounded,
  ),
};

_CategoryTheme _categoryTheme(String category) =>
    _categoryThemes[category] ??
    const _CategoryTheme(
      Color(0xFFF1F5F9),
      Color(0xFF475569),
      Icons.label_outline_rounded,
    );

Widget _categoryBadge(String category) {
  final t = _categoryTheme(category);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: t.bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(t.icon, size: 10, color: t.fg),
        const SizedBox(width: 4),
        Text(
          category,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: t.fg,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );
}

class _AnnouncementCard extends StatefulWidget {
  final AnnouncementData ann;

  const _AnnouncementCard({required this.ann});

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;

  AnnouncementData get ann => widget.ann;

  // Already resolved through OrgDirectory when the model was built.
  String? get _logoUrl => ann.logoUrl.isNotEmpty ? ann.logoUrl : null;

  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(announcement: ann),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = _logoUrl;
    final isLong =
        ann.body.length > 220 || '\n'.allMatches(ann.body).length > 4;
    final truncated = isLong && !_expanded;

    return GestureDetector(
      onTap: () => _navigateToDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        // The shared borderless card token — white, soft shadow, no outline.
        // The category is already carried by _categoryBadge() in the header;
        // the 4px category-colored accent bar that used to sit on the left
        // edge read as a near-black rule for every unmapped category (they
        // all fall back to #475569) and was reported as a border bug.
        decoration: kCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Post header: avatar + org name + time + tag ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryDark.withOpacity(0.1),
                    ),
                    child: ClipOval(
                      child:
                          (logoUrl != null &&
                              logoUrl.isNotEmpty &&
                              AppImage.provider(logoUrl) != null)
                          ? Image(
                              image: AppImage.provider(logoUrl)!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  ann.org.isNotEmpty
                                      ? ann.org[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                ann.org.isNotEmpty
                                    ? ann.org[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ann.org,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _timeAgo(ann.timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                            if (ann.category.isNotEmpty)
                              _categoryBadge(ann.category),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                ann.tag,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Title ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                ann.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.3,
                ),
              ),
            ),

            // ── Body (expandable, like the web feed) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRichContent(
                    truncated
                        ? '${ann.body.substring(0, ann.body.length.clamp(0, 220))}…'
                        : ann.body,
                    TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade700,
                      height: 1.55,
                    ),
                  ),
                  if (isLong) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? 'See less' : 'See more',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Go to linked event ──
            if (ann.linkedEventId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _goToLinkedEvent(context, ann),
                    icon: Icon(
                      Icons.event_available_rounded,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    label: Text(
                      'View Event: ${ann.linkedEventTitle}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                        color: AppColors.primaryDark.withOpacity(0.3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Photo — shown in full, never cropped or covered ──
            // Tappable: the card caps the photo at 420px, so a tall
            // image still needs the fullscreen viewer to be read.
            if (ann.imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              expandableImage(
                context: context,
                source: ann.imageUrl,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 420),
                  color: const Color(0xFFF8F9FB),
                  child: AppImage.provider(ann.imageUrl) != null
                      ? Image(
                          image: AppImage.provider(ann.imageUrl)!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: const Color(0xFFF8F9FB),
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        )
                      : Container(
                          height: 200,
                          color: const Color(0xFFF8F9FB),
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Turns URLs in the body text into tappable links — no line-clamping so
  /// the full (or "See more"-expanded) text always renders completely.
  Widget _buildRichContent(String text, TextStyle baseStyle) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: baseStyle.copyWith(
            color: AppColors.primaryDark,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DETAIL SCREEN
// ─────────────────────────────────────────────────────────────
class AnnouncementDetailScreen extends StatelessWidget {
  final AnnouncementData announcement;

  const AnnouncementDetailScreen({super.key, required this.announcement});

  // Already resolved through OrgDirectory when the model was built.
  String? get _logoUrl =>
      announcement.logoUrl.isNotEmpty ? announcement.logoUrl : null;

  @override
  Widget build(BuildContext context) {
    final ann = announcement;
    final logoUrl = _logoUrl;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // ── App Bar with Hero Image ──
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: Colors.black,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              // Tappable: the hero crops with BoxFit.cover, so the whole
              // picture is only visible in the fullscreen viewer.
              //
              // The handler wraps the entire Stack rather than just the image.
              // The scrim and badges layered over it are Containers with a
              // BoxDecoration, and BoxDecoration.hitTest returns true for a
              // plain rectangle — so as siblings painted above the image they
              // swallowed every tap. An ancestor still receives what a child
              // absorbs, so hanging the gesture above the Stack makes the
              // whole hero tappable instead of fighting each overlay.
              background: expandableImage(
                context: context,
                source: ann.imageUrl,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    (ann.imageUrl.isNotEmpty &&
                            AppImage.provider(ann.imageUrl) != null)
                        ? Image(
                            image: AppImage.provider(ann.imageUrl)!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primaryDark,
                                    AppColors.primaryDark.withOpacity(0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.image_outlined,
                                size: 80,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primaryDark,
                                  AppColors.primaryDark.withOpacity(0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(
                              Icons.image_outlined,
                              size: 80,
                              color: Colors.white,
                            ),
                          ),

                    // IgnorePointer: this scrim and the badge below it are
                    // decoration, but a Container with a decoration is opaque to
                    // hit-testing, so they were swallowing every tap meant for
                    // the image underneath and the hero never opened.
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.4),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Tag Badge ──
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ann.tag,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Date on Image ──
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ann.date,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ann.time,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Organization Row with Logo ──
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryDark.withOpacity(0.1),
                        ),
                        child: ClipOval(
                          child:
                              (logoUrl != null &&
                                  logoUrl.isNotEmpty &&
                                  AppImage.provider(logoUrl) != null)
                              ? Image(
                                  image: AppImage.provider(logoUrl)!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.business_center_outlined,
                                    size: 24,
                                    color: AppColors.primaryDark,
                                  ),
                                )
                              : Icon(
                                  Icons.business_center_outlined,
                                  size: 24,
                                  color: AppColors.primaryDark,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ann.org,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              ann.orgSub,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFF0F0F0), thickness: 1),
                  const SizedBox(height: 20),

                  // ── Title ──
                  Text(
                    ann.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Body ──
                  _buildRichContent(
                    ann.body,
                    TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade800,
                      height: 1.8,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Go to Linked Event ──
                  if (ann.linkedEventId.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryDark.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                color: AppColors.primaryDark,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Event Registration',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This announcement is linked to ${ann.linkedEventTitle}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _goToLinkedEvent(context, ann),
                              icon: const Icon(
                                Icons.event_available_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'View Event',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryDark,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Hashtags ──
                  if (ann.hashtags.isNotEmpty) ...[
                    const Text(
                      'Tags',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: ann.hashtags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Attachments ──
                  if (ann.attachments.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text(
                          'Attachments',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryDark.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${ann.attachments.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(
                        children: ann.attachments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final att = entry.value;
                          return Column(
                            children: [
                              _AttachmentTile(attachment: att, index: index),
                              if (index < ann.attachments.length - 1)
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEEEEEE),
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichContent(String text, TextStyle baseStyle) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: baseStyle.copyWith(
            color: AppColors.primaryDark,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ATTACHMENT TILE
// ─────────────────────────────────────────────────────────────
class _AttachmentTile extends StatefulWidget {
  final Map<String, String> attachment;
  final int index;

  const _AttachmentTile({required this.attachment, required this.index});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _isDownloading = false;

  Future<void> _downloadAttachment() async {
    setState(() => _isDownloading = true);

    try {
      final fileName = widget.attachment['name'] ?? 'file_${widget.index}';
      final base64Data = widget.attachment['base64'] ?? '';

      if (base64Data.isEmpty) {
        throw Exception('Attachment data is empty');
      }

      final bytes = base64Decode(base64Data);

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Downloaded: $fileName');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloaded: $fileName',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Download failed: ${e.toString().replaceAll('Exception: ', '')}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  IconData get _icon {
    switch (widget.attachment['type']) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'image':
        return Icons.image_outlined;
      default:
        return Icons.attach_file;
    }
  }

  Color get _iconColor {
    switch (widget.attachment['type']) {
      case 'pdf':
        return Colors.red.shade600;
      case 'image':
        return Colors.blue.shade600;
      default:
        return Colors.grey;
    }
  }

  String _getFileSize() {
    final size = widget.attachment['size'];
    if (size != null && size.isNotEmpty) return size;
    final base64Data = widget.attachment['base64'] ?? '';
    if (base64Data.isEmpty) return '';
    final bytes = (base64Data.length * 3 / 4).round();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, size: 20, color: _iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.attachment['name'] ?? 'File',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _getFileSize(),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          _isDownloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryDark,
                  ),
                )
              : GestureDetector(
                  onTap: _downloadAttachment,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
