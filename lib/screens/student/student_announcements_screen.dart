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
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
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
  if (data['isPublished'] == false) {
    return false;
  }

  final isScheduled = data['isScheduled'] == true;
  if (!isScheduled) {
    return true;
  }

  final scheduledPublishDate = data['scheduledPublishDate'];
  if (scheduledPublishDate is Timestamp) {
    return !scheduledPublishDate.toDate().isAfter(DateTime.now());
  }
  if (scheduledPublishDate is DateTime) {
    return !scheduledPublishDate.isAfter(DateTime.now());
  }

  return true;
}

// ─────────────────────────────────────────────────────────────
//  ORGANIZATION LOGO CACHE
// ─────────────────────────────────────────────────────────────
class OrgLogoCache {
  static final Map<String, String> _cache = {};

  static Future<void> loadAllOrganizations() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim().toLowerCase();

        // Try all possible field names
        String logo = data['logouUrl'] as String? ?? '';
        if (logo.isEmpty) logo = data['logoUrl'] as String? ?? '';
        if (logo.isEmpty) logo = data['logo'] as String? ?? '';
        if (logo.isEmpty) logo = data['imageUrl'] as String? ?? '';
        if (logo.isEmpty) logo = data['profileImage'] as String? ?? '';

        if (logo.isNotEmpty) {
          _cache[name] = logo;
        }
      }

      print('✅ Loaded ${_cache.length} organization logos');
      print('📋 Available organizations: ${_cache.keys.join(", ")}');
    } catch (e) {
      print('❌ Error loading organizations: $e');
    }
  }

  static String? getLogo(String orgName) {
    if (orgName.isEmpty) return null;
    final key = orgName.trim().toLowerCase();
    return _cache[key];
  }

  static bool get isLoaded => _cache.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────────────────────
class AnnouncementData {
  final String id;
  final String title;
  final String org;
  final String orgSub;
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
    required this.orgSub,
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

    final rawImage =
        d['imageBase64'] as String? ?? d['imageUrl'] as String? ?? '';

    String logoUrl = d['logoUrl'] as String? ?? '';

    return AnnouncementData(
      id: doc.id,
      title: d['title'] as String? ?? '',
      org: d['authorName'] as String? ?? 'Organization',
      orgSub: (d['category'] as String?)?.toUpperCase() ?? 'ANNOUNCEMENT',
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
  bool _orgsLoaded = false;

  late final Stream<QuerySnapshot> _announcementsStream = FirebaseFirestore
      .instance
      .collection('announcements')
      .orderBy('timestamp', descending: true)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  Future<void> _loadOrganizations() async {
    await OrgLogoCache.loadAllOrganizations();
    if (mounted) {
      setState(() {
        _orgsLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const StudentAppBar(title: 'Announcements'),
      body: StreamBuilder<QuerySnapshot>(
        stream: _announcementsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              !_orgsLoaded) {
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

          final docs = (snapshot.data?.docs ?? []).where((d) {
            final data = d.data() as Map<String, dynamic>;
            return shouldShowAnnouncementToStudent(data);
          }).toList();

          if (docs.isEmpty) {
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

          // Pinned first, each group keeping the query's existing
          // timestamp-descending order — a manual partition instead of
          // .sort() because List.sort() isn't guaranteed stable, and an
          // unstable sort here would shuffle same-pin-status posts out of
          // date order. Mirrors the pin-to-top behavior org_announcements.dart
          // (web) already does for the org's own view of this same data.
          final pinned = <AnnouncementData>[];
          final unpinned = <AnnouncementData>[];
          for (final doc in docs) {
            final ann = AnnouncementData.fromFirestore(doc);
            (ann.isPinned ? pinned : unpinned).add(ann);
          }
          final items = [...pinned, ...unpinned];

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final ann = items[index];
              return _AnnouncementCard(ann: ann);
            },
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

class _AnnouncementCard extends StatefulWidget {
  final AnnouncementData ann;

  const _AnnouncementCard({required this.ann});

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;

  AnnouncementData get ann => widget.ann;

  String? get _logoUrl {
    if (ann.logoUrl.isNotEmpty) return ann.logoUrl;
    final cachedLogo = OrgLogoCache.getLogo(ann.org);
    if (cachedLogo != null && cachedLogo.isNotEmpty) return cachedLogo;
    return null;
  }

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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ann.isPinned
                ? AppColors.primaryDark.withOpacity(0.35)
                : const Color(0xFFEDEDEF),
            width: ann.isPinned ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pinned strip ──
            if (ann.isPinned)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: const Color(0xFFFFFBEB),
                child: Row(
                  children: [
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 13,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Pinned Announcement',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

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
            if (ann.imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
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

  String? get _logoUrl {
    if (announcement.logoUrl.isNotEmpty) return announcement.logoUrl;
    final cachedLogo = OrgLogoCache.getLogo(announcement.org);
    if (cachedLogo != null && cachedLogo.isNotEmpty) return cachedLogo;
    return null;
  }

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
              background: Stack(
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

                  Container(
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
