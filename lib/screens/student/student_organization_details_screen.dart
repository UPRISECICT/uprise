// lib/screens/student/student_organization_details_screen.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/social_link_util.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/common/announcement_filter_bar.dart';
import '../../widgets/common/feed_cards.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/org_browsing_config.dart';
import 'package:uprise/models/event_model.dart';
import 'student_broadcast_screen.dart';
import 'student_events_screen.dart';
import 'student_announcements_screen.dart';
import 'student_merchandise_screen.dart';

// Shared design tokens for this screen — mirrors the private _UiTokens in
// student_organizations_screen.dart so both org screens read as one system
// instead of each repeating literal white/grey.shade200 card decorations.
class _UiTokens {
  static const Color cardBorder = AppColors.divider;
  static const Color mutedText = AppColors.textSecondary;
  static const Color headingText = AppColors.textPrimary;
  static const Color faintText = AppColors.textMuted;

  static const double radius = 14;

  static List<BoxShadow> get subtleShadow => const [
    BoxShadow(
      color: Color(0x0D000000), // black @ 5%
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// The one card surface used across both org screens (mirrors the same
  /// helper in student_organizations_screen.dart).
  static BoxDecoration card({double radiusOverride = radius}) => BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(radiusOverride),
    border: Border.all(color: cardBorder),
    boxShadow: subtleShadow,
  );
}

// ─────────────────────────────────────────────────────────────
//  SHARED NAVIGATION HELPERS
//
//  Top-level (not State methods) so the org feed in
//  student_organizations_screen.dart can reuse them — it already imports
//  this file. They only ever needed a BuildContext.
// ─────────────────────────────────────────────────────────────
Future<void> openEventById(BuildContext context, String eventId) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  try {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
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

Future<void> openAnnouncementById(
  BuildContext context,
  String announcementId,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  try {
    final doc = await FirebaseFirestore.instance
        .collection('announcements')
        .doc(announcementId)
        .get();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This announcement is no longer available.'),
        ),
      );
      return;
    }

    final announcement = AnnouncementData.fromFirestore(doc);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(announcement: announcement),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open announcement: $e')));
  }
}

// ─────────────────────────────────────────────────────────────
//  MEMBERSHIP PILL
//
//  Following is gone — every org's profile is open to every viewer, so there
//  is nothing to opt into here. What the header still needs to say is whether
//  *this* is the viewer's own org, which is the same Member/Officer pill the
//  All Organizations cards render.
//
//  Self-contained StatefulWidget on purpose: its setState must not rebuild
//  the parent, which would resubscribe the cached _orgStream and flash the
//  whole screen (see the caching note on _orgStream).
// ─────────────────────────────────────────────────────────────
class _MembershipPill extends StatefulWidget {
  final String orgId;
  final OrgBrowsingConfig config;
  const _MembershipPill({required this.orgId, required this.config});

  @override
  State<_MembershipPill> createState() => _MembershipPillState();
}

class _MembershipPillState extends State<_MembershipPill> {
  // Null until loaded, and for every org that isn't the viewer's own.
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.config.showMembership) return;
    try {
      final info = await widget.config.membershipStore.load();
      if (!mounted) return;
      if (info.orgId != widget.orgId) return;
      setState(() => _label = info.membershipLabel);
    } catch (_) {
      // No pill is the right fallback — it claims nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  PINNED TAB BAR
//
//  Standard SliverPersistentHeaderDelegate wrapper so the tab bar can pin
//  under the AppBar once the cover header scrolls past.
// ─────────────────────────────────────────────────────────────
class _OrgTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _OrgTabBarDelegate(this.tabBar);

  // +1 for the hairline below, which is laid out rather than drawn as a
  // border so the TabBar itself still gets its full preferred height.
  double get _height => tabBar.preferredSize.height + 1;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: AppColors.cardBg,
      child: Column(
        children: [
          Expanded(child: tabBar),
          Container(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_OrgTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

// ─────────────────────────────────────────────────────────────
//  ORGANIZATION DETAILS SCREEN
// ─────────────────────────────────────────────────────────────
class StudentOrganizationsDetailsScreen extends StatefulWidget {
  final String orgId;

  /// How this role browses orgs — where membership is read from, visibility
  /// gates, and which detail screens open. Defaults to full student access.
  final OrgBrowsingConfig config;

  const StudentOrganizationsDetailsScreen({
    super.key,
    required this.orgId,
    this.config = OrgBrowsingConfig.student,
  });

  @override
  State<StudentOrganizationsDetailsScreen> createState() =>
      _StudentOrganizationsDetailsScreenState();
}

class _StudentOrganizationsDetailsScreenState
    extends State<StudentOrganizationsDetailsScreen> {
  bool _coverImageFailed = false;

  // Cached once instead of created inline in build() — a fresh Stream
  // object there would resubscribe (and flash the whole screen, cover
  // image included) on every local setState, e.g. _coverImageFailed.
  late final Stream<DocumentSnapshot> _orgStream = FirebaseFirestore.instance
      .collection('organizations')
      .doc(widget.orgId)
      .snapshots();

  ImageProvider? _buildLogoImage(String? logoUrl) {
    return AppImage.provider(logoUrl ?? '');
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDark.withAlpha(77),
            AppColors.primaryDark.withAlpha(26),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 48,
              color: AppColors.primaryDark.withAlpha(51),
            ),
            const SizedBox(height: 8),
            Text(
              'No Cover Image',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryDark.withAlpha(77),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Routed through the config so a guest opening an event or announcement
  // from this org lands on their own screen, never the student one — which
  // would offer student-only actions.
  void _navigateToEventDetail(String eventId) =>
      (widget.config.onOpenEvent ?? openEventById)(context, eventId);

  void _navigateToAnnouncementDetail(String announcementId) =>
      (widget.config.onOpenAnnouncement ?? openAnnouncementById)(
        context,
        announcementId,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _orgStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const UpriseLoader();
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.business_center_outlined,
                    size: 64,
                    color: _UiTokens.faintText,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Organization not found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _UiTokens.headingText,
                    ),
                  ),
                ],
              ),
            );
          }

          final org = snapshot.data!.data() as Map<String, dynamic>;
          // Ordered to match the web "Organization Hierarchy" chart
          // (President/VP tier, then Secretary/Treasurer, then everyone
          // else, each ordered the way the org arranged them) instead of
          // whatever order Firestore happened to return — this list used
          // to be flat/unordered on mobile.
          final officers =
              List<Map<String, dynamic>>.from(
                (org['officers'] as List? ?? []).whereType<Map>().map(
                  (o) => Map<String, dynamic>.from(o),
                ),
              )..sort((a, b) {
                final rankCompare = ((a['positionRank'] as num?) ?? 0)
                    .compareTo((b['positionRank'] as num?) ?? 0);
                if (rankCompare != 0) return rankCompare;
                return ((a['order'] as num?) ?? 0).compareTo(
                  (b['order'] as num?) ?? 0,
                );
              });

          // The feed-style cards carry an org header row, so every tab needs
          // the org's identity. Both come off the snapshot already loaded —
          // no per-card lookup.
          final orgName = (org['name'] ?? 'Organization').toString();
          final orgLogoUrl = (org['logoUrl'] ?? '').toString();

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: StudentAppBar(
              title: 'Organization',
              actions: [
                // Membership shows in the header as a pill; the broadcast
                // shortcut stays here — but broadcasts are a member-only
                // channel, so guests don't get the entry point at all.
                if (widget.config.enableBroadcast) ...[
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentBroadcastScreen(
                            orgId: widget.orgId,
                            orgName: org['name'] ?? 'Organization',
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            body: DefaultTabController(
              length: 4,
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _buildHeader(org)),
                  // The absorber/injector pair is what keeps the first row of
                  // each tab from hiding behind the pinned tab bar once the
                  // header scrolls away.
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                    sliver: SliverPersistentHeader(
                      pinned: true,
                      delegate: _OrgTabBarDelegate(
                        TabBar(
                          // Scrollable + start-aligned so "Announcements"
                          // can't be squeezed into an overflowing quarter of
                          // the width on a narrow phone.
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          indicatorColor: AppColors.primaryDark,
                          labelColor: AppColors.primaryDark,
                          unselectedLabelColor: AppColors.textSecondary,
                          indicatorWeight: 3,
                          dividerColor: Colors.transparent,
                          labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: const [
                            Tab(text: 'About'),
                            Tab(text: 'Events'),
                            Tab(text: 'Announcements'),
                            Tab(text: 'Merch'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _AboutTab(
                      org: org,
                      officers: officers,
                      orgId: widget.orgId,
                      orgName: orgName,
                      orgLogoUrl: orgLogoUrl,
                      onAnnouncementTap: _navigateToAnnouncementDetail,
                      config: widget.config,
                    ),
                    _EventsTab(
                      orgId: widget.orgId,
                      orgName: orgName,
                      orgLogoUrl: orgLogoUrl,
                      onEventTap: _navigateToEventDetail,
                      config: widget.config,
                    ),
                    _AnnouncementsTab(
                      orgId: widget.orgId,
                      orgName: orgName,
                      orgLogoUrl: orgLogoUrl,
                      onAnnouncementTap: _navigateToAnnouncementDetail,
                      config: widget.config,
                    ),
                    _OrgShopTab(orgId: widget.orgId, config: widget.config),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Cover, logo, name/category, ACCREDITED badge and the membership pill —
  /// everything that scrolls away above the tab bar.
  Widget _buildHeader(Map<String, dynamic> org) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── COVER IMAGE WITH LOGO OVERLAY ──
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child:
                  (org['coverPhotoUrl'] == null ||
                      (org['coverPhotoUrl'] as String).isEmpty ||
                      _coverImageFailed)
                  ? _buildCoverPlaceholder()
                  : _OrgCoverImage(
                      source: org['coverPhotoUrl'] as String,
                      onError: () {
                        if (mounted) setState(() => _coverImageFailed = true);
                      },
                    ),
            ),

            Positioned.fill(
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(51)],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: -35,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(38),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.white,
                  backgroundImage: _buildLogoImage(org['logoUrl']),
                  child:
                      (org['logoUrl'] == null ||
                          (org['logoUrl'] as String).isEmpty)
                      ? Text(
                          (org['name'] ?? 'O')[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 50),

        // ── Organization Info ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          org['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _UiTokens.headingText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          org['category'] ?? 'Student Organization',
                          style: TextStyle(
                            fontSize: 14,
                            color: _UiTokens.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _MembershipPill(
                      orgId: widget.orgId,
                      config: widget.config,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'ACCREDITED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 1 — ABOUT
//
//  Everything here comes off the org map already loaded by the parent's
//  StreamBuilder, plus the pre-sorted officers list — no reads of its own.
// ─────────────────────────────────────────────────────────────
class _AboutTab extends StatelessWidget {
  final Map<String, dynamic> org;
  final List<Map<String, dynamic>> officers;
  final String orgId;
  final String orgName;
  final String orgLogoUrl;
  final Function(String) onAnnouncementTap;

  final OrgBrowsingConfig config;

  const _AboutTab({
    required this.org,
    required this.officers,
    required this.orgId,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onAnnouncementTap,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final description = (org['description'] ?? '').toString().trim();

    return CustomScrollView(
      key: const PageStorageKey('org-about'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── Description — nothing at all when the field is blank,
              // rather than a "No description available" placeholder. ──
              if (description.isNotEmpty) ...[
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ── Organization Adviser(s) ──
              Builder(
                builder: (context) {
                  final adviserList = (org['advisers'] as List?)
                      ?.whereType<Map<String, dynamic>>()
                      .toList();
                  final hasMultiple =
                      adviserList != null && adviserList.isNotEmpty;
                  final photoUrl = org['adviserPhotoUrl'] as String?;
                  final photoProvider = AppImage.provider(photoUrl ?? '');
                  final advisersToShow = hasMultiple
                      ? adviserList
                      : [
                          {
                            'name': org['adviserName'] ?? 'No adviser listed',
                            'title': org['adviserTitle'],
                          },
                        ];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _UiTokens.card(radiusOverride: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final adv in advisersToShow)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                photoProvider != null
                                    ? CircleAvatar(
                                        radius: 20,
                                        backgroundImage: photoProvider,
                                      )
                                    : Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryDark
                                              .withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.person_outline,
                                          color: AppColors.primaryDark,
                                          size: 20,
                                        ),
                                      ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Organization Adviser',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (adv['name'] ?? 'No adviser listed')
                                            .toString(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _UiTokens.headingText,
                                        ),
                                      ),
                                      if ((adv['title'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Text(
                                          (adv['title']).toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _UiTokens.mutedText,
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
              const SizedBox(height: 24),

              // ── Connect / Social Links ──
              if ([
                org['facebook'],
                org['instagram'],
                org['twitter'],
                org['tiktok'],
                org['gmail'],
              ].any((v) => (v ?? '').toString().trim().isNotEmpty)) ...[
                const Text(
                  'Connect',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _UiTokens.headingText,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if ((org['facebook'] ?? '').toString().trim().isNotEmpty)
                      _SocialChip(
                        icon: Icons.facebook_rounded,
                        label: 'Facebook',
                        url: normalizeSocialUrl(
                          'facebook',
                          org['facebook'].toString(),
                        ),
                      ),
                    if ((org['instagram'] ?? '').toString().trim().isNotEmpty)
                      _SocialChip(
                        icon: Icons.camera_alt_outlined,
                        label: 'Instagram',
                        url: normalizeSocialUrl(
                          'instagram',
                          org['instagram'].toString(),
                        ),
                      ),
                    if ((org['twitter'] ?? '').toString().trim().isNotEmpty)
                      _SocialChip(
                        icon: Icons.alternate_email_rounded,
                        label: 'Twitter/X',
                        url: normalizeSocialUrl(
                          'twitter',
                          org['twitter'].toString(),
                        ),
                      ),
                    if ((org['tiktok'] ?? '').toString().trim().isNotEmpty)
                      _SocialChip(
                        icon: Icons.music_note_rounded,
                        label: 'TikTok',
                        url: normalizeSocialUrl(
                          'tiktok',
                          org['tiktok'].toString(),
                        ),
                      ),
                    if ((org['gmail'] ?? '').toString().trim().isNotEmpty)
                      _SocialChip(
                        icon: Icons.email_outlined,
                        label: org['gmail'],
                        url: normalizeSocialUrl(
                          'gmail',
                          org['gmail'].toString(),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // ── Executive Officers ──
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Executive Officers',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _UiTokens.headingText,
                      ),
                    ),
                  ),
                  if (officers.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showOrgChartSheet(
                        context,
                        orgName: orgName,
                        officers: officers,
                      ),
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('Org Chart'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (officers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _UiTokens.card(radiusOverride: 12),
                  child: Center(
                    child: Text(
                      'No officers listed',
                      style: TextStyle(color: _UiTokens.mutedText),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: officers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 0, color: Colors.grey),
                  itemBuilder: (context, index) {
                    final officer = officers[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primaryDark.withAlpha(
                              20,
                            ),
                            backgroundImage: AppImage.provider(
                              (officer['photoUrl'] ?? '').toString(),
                            ),
                            child:
                                (officer['photoUrl'] == null ||
                                    (officer['photoUrl'] as String?)?.isEmpty ==
                                        true)
                                ? Text(
                                    // Guard the empty string — a
                                    // blank name used to throw
                                    // RangeError on [0].
                                    (officer['name'] ?? '').toString().isEmpty
                                        ? '?'
                                        : officer['name']
                                              .toString()[0]
                                              .toUpperCase(),
                                    style: TextStyle(
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  officer['name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: _UiTokens.headingText,
                                  ),
                                ),
                                Text(
                                  officer['position'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _UiTokens.mutedText,
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

              // ── Pinned announcements (hides itself when there are none) ──
              _PinnedAnnouncements(
                orgId: orgId,
                orgName: orgName,
                orgLogoUrl: orgLogoUrl,
                onAnnouncementTap: onAnnouncementTap,
                config: config,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 2 — EVENTS
// ─────────────────────────────────────────────────────────────
class _EventsTab extends StatelessWidget {
  final String orgId;
  final String orgName;
  final String orgLogoUrl;
  final Function(String) onEventTap;
  final OrgBrowsingConfig config;

  const _EventsTab({
    required this.orgId,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onEventTap,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('org-events'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          sliver: _UpcomingEventsList(
            orgId: orgId,
            orgName: orgName,
            orgLogoUrl: orgLogoUrl,
            onEventTap: onEventTap,
            config: config,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 3 — ANNOUNCEMENTS
// ─────────────────────────────────────────────────────────────

/// One announcement in the Organizations-feed card style. Shared by the
/// Announcements tab and the pinned section on About so the two can't drift.
Widget _announcementCard({
  required Map<String, dynamic> data,
  required DateTime date,
  required VoidCallback onTap,
  required String orgName,
  required String orgLogoUrl,
  bool pinned = false,
}) {
  // The badge is the org's own category now that Urgent is no longer a
  // hardcoded axis — orgs can still make an "Urgent" category, it just stops
  // being special-cased. Urgent still outranks pinned, since the pinned
  // section already carries a "Pinned" heading of its own.
  final category = (data['category'] ?? '').toString().trim();
  final urgent = category.toLowerCase() == 'urgent';
  return CompactFeedCard(
    // First non-empty, not `??`: `??` falls through only on null, so an empty
    // imageBase64 used to beat a populated imageUrl.
    imageSource: firstNonEmptyImageSource([
      data['imageBase64']?.toString(),
      data['imageUrl']?.toString(),
    ]),
    orgName: orgName,
    orgLogoUrl: orgLogoUrl,
    badgeLabel: urgent
        ? 'URGENT'
        : pinned
        ? 'PINNED'
        : category.isNotEmpty
        ? category.toUpperCase()
        : 'ANNOUNCEMENT',
    badgeColor: urgent
        ? const Color(0xFFDC2626)
        : pinned
        ? AppColors.primaryDark
        : AppColors.accent,
    title: (data['title'] ?? 'Untitled').toString(),
    snippet: (data['content'] ?? '').toString(),
    timeAgo: DateFormat('MMM dd, yyyy').format(date),
    onTap: onTap,
  );
}

/// Pinned announcements, shown on About below Executive Officers. Renders
/// nothing at all when the org has none — it's a secondary section, so an
/// empty state would be noise.
class _PinnedAnnouncements extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgLogoUrl;
  final Function(String) onAnnouncementTap;

  final OrgBrowsingConfig config;

  const _PinnedAnnouncements({
    required this.orgId,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onAnnouncementTap,
    required this.config,
  });

  @override
  State<_PinnedAnnouncements> createState() => _PinnedAnnouncementsState();
}

class _PinnedAnnouncementsState extends State<_PinnedAnnouncements> {
  // Three equality filters and no orderBy — Firestore serves that by merging
  // single-field indexes, so this needs no composite index, same discipline
  // as the announcements query above. Sorted client-side.
  //
  // The Firestore field is `pinned`, NOT `isPinned` — AnnouncementData maps
  // `d['pinned']` onto its `isPinned` property, and querying the Dart-side
  // name would silently match nothing.
  late final Stream<QuerySnapshot> _pinnedStream = FirebaseFirestore.instance
      .collection('announcements')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isPublished', isEqualTo: true)
      .where('pinned', isEqualTo: true)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _pinnedStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final docs =
            snapshot.data!.docs
                .where(
                  (d) => widget.config.allowsAnnouncement(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList()
              ..sort((a, b) {
                final ta =
                    (a.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                final tb =
                    (b.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });
        if (docs.isEmpty) return const SizedBox.shrink();

        final items = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          final ts = data['timestamp'] as Timestamp?;
          return (id: d.id, data: data, date: ts?.toDate() ?? DateTime.now());
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  size: 15,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Pinned Announcements',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _UiTokens.headingText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _announcementCard(
                data: items[i].data,
                date: items[i].date,
                onTap: () => widget.onAnnouncementTap(items[i].id),
                orgName: widget.orgName,
                orgLogoUrl: widget.orgLogoUrl,
                pinned: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnnouncementsTab extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgLogoUrl;
  final Function(String) onAnnouncementTap;

  final OrgBrowsingConfig config;

  const _AnnouncementsTab({
    required this.orgId,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onAnnouncementTap,
    required this.config,
  });

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  /// The selected category, or [kAnnouncementFilterAll] for no filter.
  ///
  /// Categories are whatever this org actually posts under — orgs define and
  /// manage their own on the web side — so there is no fixed list to enumerate
  /// here. Same reasoning as announcementCategoryOptions()'s doc comment.
  String _filter = kAnnouncementFilterAll;

  // Cached once, and owned by the tab rather than the list below, because the
  // chip row and the list are both built from it — one subscription feeds
  // both, and a chip tap only re-filters what's already in hand.
  late final Stream<QuerySnapshot> _announcementsStream = FirebaseFirestore
      .instance
      .collection('announcements')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isPublished', isEqualTo: true)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;

        // Audience-gated first: guests only ever see Public announcements,
        // the same rule the standalone guest announcements screen applies.
        final docs =
            (snapshot.data?.docs ?? [])
                .where(
                  (d) => widget.config.allowsAnnouncement(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList()
              ..sort((a, b) {
                final dateA =
                    (a.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                final dateB =
                    (b.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;

                if (dateA == null && dateB == null) return 0;
                if (dateA == null) return 1;
                if (dateB == null) return -1;

                return dateB.compareTo(dateA);
              });

        final categories = announcementCategoryOptions(
          docs.map((d) => d.data() as Map<String, dynamic>).toList(),
        );

        // A selected category can vanish under us — the org edits the category
        // off its last post — which would otherwise leave the list empty with
        // the chip that emptied it gone from the row. Same guard
        // AnnouncementFilterBar._dropdown makes for the same reason.
        final selected =
            _filter == kAnnouncementFilterAll || categories.contains(_filter)
            ? _filter
            : kAnnouncementFilterAll;

        // Filter after the sort, client-side — no second query, no composite
        // index. Matches AnnouncementFilters.matches()'s trim-and-compare so
        // this tab and the global feed can't disagree about a category.
        final visible = selected == kAnnouncementFilterAll
            ? docs
            : docs
                  .where(
                    (d) =>
                        ((d.data() as Map<String, dynamic>)['category'] ?? '')
                            .toString()
                            .trim() ==
                        selected,
                  )
                  .toList();

        // A lone "All" chip says nothing — the row only earns its space once
        // the org posts under more than one category.
        final showChips = categories.length > 1;

        return CustomScrollView(
          key: const PageStorageKey('org-announcements'),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (showChips)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      _pill(kAnnouncementFilterAll, 'All', selected),
                      for (final c in categories) ...[
                        const SizedBox(width: 8),
                        _pill(c, c, selected),
                      ],
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, showChips ? 0 : 14, 16, 32),
              sliver: _RecentAnnouncementsList(
                docs: visible,
                loading: loading,
                hasError: snapshot.hasError,
                emptyTitle: selected == kAnnouncementFilterAll
                    ? 'No announcements yet'
                    : 'No announcements in $selected',
                orgName: widget.orgName,
                orgLogoUrl: widget.orgLogoUrl,
                onAnnouncementTap: widget.onAnnouncementTap,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Same recipe as _FeedFilterPills on the Organizations tab.
  Widget _pill(String value, String label, String selected) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryDark
              : AppColors.primaryDark.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryDark
                : AppColors.primaryDark.withAlpha(41),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: isSelected ? Colors.white : AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  UPCOMING EVENTS LIST (CLICKABLE)
// ─────────────────────────────────────────────────────────────
class _UpcomingEventsList extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgLogoUrl;
  final Function(String) onEventTap;
  final OrgBrowsingConfig config;

  const _UpcomingEventsList({
    required this.orgId,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onEventTap,
    required this.config,
  });

  @override
  State<_UpcomingEventsList> createState() => _UpcomingEventsListState();
}

class _UpcomingEventsListState extends State<_UpcomingEventsList> {
  // Cached once — was being created inline in build() before, so every
  // rebuild of the parent org screen resubscribed and flashed the loading
  // spinner again.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('events')
      .where('orgId', isEqualTo: widget.orgId)
      .where('date', isGreaterThanOrEqualTo: Timestamp.now())
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(
            child: Container(
              height: 80,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryDark,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _UiTokens.card(radiusOverride: 12),
              child: Center(
                child: Text(
                  'Failed to load events',
                  style: TextStyle(color: _UiTokens.mutedText),
                ),
              ),
            ),
          );
        }

        // No 5-item cap any more — this is a full tab, not a preview strip.
        // Audience-gated first: a guest browsing any org must not see that
        // org's CICT-Only or Members-Only events.
        final docs = (snapshot.data?.docs ?? [])
            .where(
              (d) => widget.config.allowsEventAudience(
                ((d.data() as Map<String, dynamic>)['audience'] ?? 'Public')
                    .toString(),
              ),
            )
            .toList();

        docs.sort((a, b) {
          final dateA = (a.data() as Map<String, dynamic>)['date'] as Timestamp;
          final dateB = (b.data() as Map<String, dynamic>)['date'] as Timestamp;
          return dateA.compareTo(dateB);
        });

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: UpriseEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No upcoming events',
              subtitle: 'Check back when this org schedules something new.',
            ),
          );
        }

        return SliverList.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp).toDate();

            // The old card's date block, start time and location all have to
            // land somewhere on the feed card: the date takes the time slot,
            // and time + location become the snippet.
            final startTime = (data['startTime'] ?? '').toString().trim();
            final location = (data['location'] ?? '').toString().trim();

            return CompactFeedCard(
              imageSource: (data['bannerUrl'] ?? '').toString(),
              orgName: widget.orgName,
              orgLogoUrl: widget.orgLogoUrl,
              badgeLabel: 'EVENT',
              badgeColor: AppColors.primaryDark,
              title: (data['title'] ?? 'Untitled Event').toString(),
              snippet: [
                if (startTime.isNotEmpty) startTime,
                if (location.isNotEmpty) location,
              ].join(' · '),
              // These are all upcoming, so a relative "x ago" would read
              // "Just now" for every one of them.
              timeAgo: DateFormat('MMM dd').format(date),
              onTap: () => widget.onEventTap(doc.id),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RECENT ANNOUNCEMENTS LIST (CLICKABLE)
// ─────────────────────────────────────────────────────────────
/// The announcements sliver. Deliberately owns no stream of its own: the tab
/// above holds the single subscription and hands down the docs already
/// audience-gated, sorted and category-filtered, so the chip row and this list
/// can never disagree about what's showing.
class _RecentAnnouncementsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final bool loading;
  final bool hasError;

  /// Depends on the selected category, so it's the tab's to phrase.
  final String emptyTitle;

  final Function(String) onAnnouncementTap;
  final String orgName;
  final String orgLogoUrl;

  const _RecentAnnouncementsList({
    required this.docs,
    required this.loading,
    required this.hasError,
    required this.emptyTitle,
    required this.orgName,
    required this.orgLogoUrl,
    required this.onAnnouncementTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SliverToBoxAdapter(
        child: Container(
          height: 80,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryDark,
          ),
        ),
      );
    }

    if (hasError) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _UiTokens.card(radiusOverride: 12),
          child: Center(
            child: Text(
              'Failed to load announcements',
              style: TextStyle(color: _UiTokens.mutedText),
            ),
          ),
        ),
      );
    }

    if (docs.isEmpty) {
      return SliverToBoxAdapter(
        child: UpriseEmptyState(
          icon: Icons.campaign_outlined,
          title: emptyTitle,
        ),
      );
    }

    return SliverList.separated(
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp?;
        final date = timestamp != null ? timestamp.toDate() : DateTime.now();

        return _announcementCard(
          data: data,
          date: date,
          onTap: () => onAnnouncementTap(doc.id),
          orgName: orgName,
          orgLogoUrl: orgLogoUrl,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 4 — SHOP
//
//  The full-grid replacement for what used to be a 6-item horizontal
//  preview strip with a "View all" button. The tab label says Shop, so
//  there's no section heading here.
// ─────────────────────────────────────────────────────────────
class _OrgShopTab extends StatefulWidget {
  final String orgId;
  final OrgBrowsingConfig config;

  const _OrgShopTab({required this.orgId, required this.config});

  @override
  State<_OrgShopTab> createState() => _OrgShopTabState();
}

class _OrgShopTabState extends State<_OrgShopTab> {
  // Cached once in State rather than an inline `.get()` in build(): the org
  // profile's StreamBuilder rebuilds this on every snapshot event, including
  // metadata-only ones, which would otherwise re-run the query and flash the
  // loader each time. Same query as the old preview strip, minus .limit(6).
  late final Future<QuerySnapshot> _productsFuture = FirebaseFirestore.instance
      .collection('products')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isArchived', isEqualTo: false)
      .get();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('org-shop'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        FutureBuilder<QuerySnapshot>(
          future: _productsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SliverToBoxAdapter(
                child: Container(
                  height: 120,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryDark,
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            // A tab can't collapse to nothing the way the embedded preview
            // did — say so instead.
            if (docs.isEmpty) {
              return const SliverToBoxAdapter(
                child: UpriseEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No merchandise yet',
                  subtitle: 'This org hasn\'t listed anything for sale.',
                ),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString();
                  final price = ((data['price'] ?? 0) as num).toDouble();
                  final imageSource = productCoverImageSource(data);

                  return GestureDetector(
                    // The catalog browses app-wide and can't yet open to a
                    // specific product. Guests route to their own view-only
                    // catalog rather than the student one.
                    onTap: () {
                      final open = widget.config.onOpenMerch;
                      if (open != null) {
                        open(context);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentMerchandiseScreen(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: _UiTokens.card(radiusOverride: 12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Expanded, not a fixed height: the tile's height
                          // comes from the grid, so the image has to absorb
                          // whatever is left after the text.
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: AppImage(
                                source: imageSource,
                                fit: BoxFit.cover,
                                showLoadingIndicator: false,
                                placeholderIcon: Icons.shopping_bag_outlined,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty ? name : 'Item',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _UiTokens.headingText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₱${price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: docs.length),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SOCIAL CHIP
// ─────────────────────────────────────────────────────────────
class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _SocialChip({
    required this.icon,
    required this.label,
    required this.url,
  });

  // No canLaunchUrl() gate: on Android 11+ it answers false for any scheme
  // not declared in the manifest's <queries>, which is what left these chips
  // dead. launchUrl itself reports failure (false or a PlatformException), so
  // it alone decides whether to show the snackbar.
  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null && uri.hasScheme) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AppColors.primaryDark.withAlpha(51)),
    );
    // Material + Ink so the tap ripple draws on top of the tinted fill rather
    // than hidden underneath an opaque Container.
    return Material(
      color: AppColors.primaryDark.withAlpha(20),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _UiTokens.headingText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Org cover photo, shown whole — never cropped.
///
/// Orgs upload covers at any aspect ratio (the web upload has no crop step),
/// so a fixed 180-high `BoxFit.cover` box cut the sides off wide banners. This
/// reads the image's real size and makes the box match it at full width.
///
/// The height is kept between [_minHeight] and [_maxHeight] so an extreme
/// ratio can't turn the header into a sliver or swallow the screen. When a
/// clamp kicks in, the image is still drawn whole (`contain`) and the leftover
/// space is filled with a blurred copy of itself instead of blank bars.
class _OrgCoverImage extends StatefulWidget {
  final String source;
  final VoidCallback onError;

  const _OrgCoverImage({required this.source, required this.onError});

  @override
  State<_OrgCoverImage> createState() => _OrgCoverImageState();
}

class _OrgCoverImageState extends State<_OrgCoverImage> {
  static const double _minHeight = 140;
  static const double _maxHeight = 260;
  static const double _loadingHeight = 180;

  // Cached per source: AppImage.provider decodes base64 into a fresh
  // MemoryImage on every call, which would miss the image cache and flash
  // the cover on each rebuild of the screen.
  ImageProvider? _provider;
  String? _resolvedSource;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      final w = info.image.width, h = info.image.height;
      if (!mounted || w == 0 || h == 0) return;
      setState(() => _aspectRatio = w / h);
    },
    onError: (_, __) => widget.onError(),
  );

  /// width / height of the loaded image; null until it has decoded.
  double? _aspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _OrgCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _resolve();
  }

  void _resolve() {
    if (_resolvedSource == widget.source && _stream != null) return;
    _resolvedSource = widget.source;
    _stream?.removeListener(_listener);
    _aspectRatio = null;
    _provider = AppImage.provider(widget.source);
    if (_provider == null) {
      _stream = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError());
      return;
    }
    _stream = _provider!.resolve(createLocalImageConfiguration(context))
      ..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final aspect = _aspectRatio;
        final naturalHeight = aspect == null ? _loadingHeight : width / aspect;
        final height = naturalHeight.clamp(_minHeight, _maxHeight);
        // Only a clamped box leaves space around a `contain`ed image.
        final needsBackdrop = aspect != null && height != naturalHeight;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: height,
          width: double.infinity,
          color: AppColors.primaryDark.withAlpha(20),
          child: provider == null || aspect == null
              ? null
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (needsBackdrop)
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 20,
                          sigmaY: 20,
                        ),
                        child: Image(image: provider, fit: BoxFit.cover),
                      ),
                    Image(image: provider, fit: BoxFit.contain),
                  ],
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ORG CHART (About › Executive Officers › "Org Chart")
// ─────────────────────────────────────────────────────────────
// Mobile rendering of the chart the org builds on its web profile
// (org_profile.dart's _HierarchyTree). Same structure, same data: it reads the
// denormalized `officers` array already on the org doc — positionRank, order
// and parentId are all synced there — so opening it costs no extra read.
//
//   • Officers with a valid "Reports To" parent sit nested under that officer.
//   • Everyone else is grouped by exact positionRank, one row per rank, top to
//     bottom (President, then VP, then Secretary, ...), each row by `order`.
//   • An officer whose parent no longer exists falls back to the rank rows
//     rather than disappearing.

void _showOrgChartSheet(
  BuildContext context, {
  required String orgName,
  required List<Map<String, dynamic>> officers,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Off so a vertical pan moves the chart instead of dragging the sheet
    // shut; the close button and a tap on the dimmed area still dismiss it.
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _OrgChartSheet(orgName: orgName, officers: officers),
    ),
  );
}

/// Same "A.Y. 2026 - 2027" label the web chart prints — the academic year
/// starts in August (see the Semester Logic table in CLAUDE.md).
String _academicYearLabel() {
  final now = DateTime.now();
  final startYear = now.month >= 8 ? now.year : now.year - 1;
  return '$startYear - ${startYear + 1}';
}

class _ChartOfficer {
  final String id;
  final String name;
  final String position;
  final String photoUrl;
  final int rank;
  final int order;
  final String? parentId;

  const _ChartOfficer({
    required this.id,
    required this.name,
    required this.position,
    required this.photoUrl,
    required this.rank,
    required this.order,
    required this.parentId,
  });

  factory _ChartOfficer.fromMap(Map<String, dynamic> m, int index) {
    final parent = (m['parentId'] ?? '').toString().trim();
    final id = (m['id'] ?? '').toString();
    return _ChartOfficer(
      // An entry with no id can't be anyone's parent; the index keeps it
      // unique so it still renders.
      id: id.isEmpty ? '__officer_$index' : id,
      name: (m['name'] ?? '').toString(),
      position: (m['position'] ?? '').toString(),
      photoUrl: (m['photoUrl'] ?? '').toString(),
      rank: (m['positionRank'] as num?)?.toInt() ?? 0,
      order: (m['order'] as num?)?.toInt() ?? 0,
      parentId: parent.isEmpty ? null : parent,
    );
  }
}

class _OrgChartSheet extends StatefulWidget {
  final String orgName;
  final List<Map<String, dynamic>> officers;

  const _OrgChartSheet({required this.orgName, required this.officers});

  @override
  State<_OrgChartSheet> createState() => _OrgChartSheetState();
}

class _OrgChartSheetState extends State<_OrgChartSheet> {
  final TransformationController _transform = TransformationController();
  final GlobalKey _chartKey = GlobalKey();
  late final List<_ChartOfficer> _officers = [
    for (var i = 0; i < widget.officers.length; i++)
      _ChartOfficer.fromMap(widget.officers[i], i),
  ];
  Size? _viewport;
  bool _fitted = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Scales the chart down (never up) so its full width fits the screen and
  /// centers it horizontally. Runs once after the first layout, and again from
  /// the "fit" button after the user has zoomed around.
  void _fitToWidth() {
    final chartSize = _chartKey.currentContext?.size;
    final viewport = _viewport;
    if (chartSize == null || viewport == null || chartSize.width == 0) return;
    const margin = 16.0;
    final scale = ((viewport.width - margin * 2) / chartSize.width).clamp(
      0.2,
      1.0,
    );
    final dx = (viewport.width - chartSize.width * scale) / 2;
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(dx, margin, 0);
    if (!_fitted) setState(() => _fitted = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
          child: Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                color: AppColors.primaryDark,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Org Chart',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _UiTokens.headingText,
                      ),
                    ),
                    Text(
                      widget.orgName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _UiTokens.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fit to screen',
                onPressed: _fitToWidth,
                icon: const Icon(
                  Icons.fit_screen_outlined,
                  color: _UiTokens.mutedText,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.close_rounded,
                  color: _UiTokens.headingText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: _UiTokens.cardBorder),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              if (!_fitted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _fitToWidth();
                });
              }
              return ClipRect(
                child: InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.2,
                  maxScale: 3,
                  // Hidden until fitted so it doesn't flash at full size in
                  // the corner for a frame first.
                  child: Opacity(
                    opacity: _fitted ? 1 : 0,
                    child: KeyedSubtree(
                      key: _chartKey,
                      child: _OrgChart(
                        orgName: widget.orgName,
                        officers: _officers,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

const double _chartCardWidth = 104;
const double _chartSpacing = 16;
const double _chartLinkHeight = 16;
final Color _chartLineColor = AppColors.primaryDark.withAlpha(76);

class _OrgChart extends StatelessWidget {
  final String orgName;
  final List<_ChartOfficer> officers;

  const _OrgChart({required this.orgName, required this.officers});

  @override
  Widget build(BuildContext context) {
    final validIds = officers.map((o) => o.id).toSet();
    final childrenByParent = <String, List<_ChartOfficer>>{};
    for (final o in officers) {
      final parent = o.parentId;
      if (parent != null && parent != o.id && validIds.contains(parent)) {
        childrenByParent.putIfAbsent(parent, () => []).add(o);
      }
    }
    final roots = officers.where((o) {
      final parent = o.parentId;
      return parent == null || parent == o.id || !validIds.contains(parent);
    });

    final byRank = <int, List<_ChartOfficer>>{};
    for (final o in roots) {
      byRank.putIfAbsent(o.rank, () => []).add(o);
    }
    final ranks = byRank.keys.toList()..sort();
    final tiers = [
      for (final rank in ranks)
        byRank[rank]!..sort((a, b) => a.order.compareTo(b.order)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDark.withAlpha(15),
            AppColors.accent.withAlpha(10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 300,
            child: Text(
              '${orgName.toUpperCase()} OFFICERS',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _UiTokens.headingText,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A.Y. ${_academicYearLabel()}',
            style: const TextStyle(fontSize: 12.5, color: _UiTokens.mutedText),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < tiers.length; i++) ...[
            if (i > 0) const _ChartTrunk(),
            _ChartRow(
              officers: tiers[i],
              childrenByParent: childrenByParent,
              isTop: i == 0,
              linked: i > 0,
              visited: const {},
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of siblings. When [linked], each sibling gets its own stub up to a
/// shared bus line — drawn per sibling rather than from a fixed box width, so
/// the lines still meet each box when a sibling carries a wide sub-tree.
class _ChartRow extends StatelessWidget {
  final List<_ChartOfficer> officers;
  final Map<String, List<_ChartOfficer>> childrenByParent;
  final bool isTop;
  final bool linked;

  /// Ancestors already on this branch — guards against a parentId cycle
  /// (A reports to B reports to A) recursing forever.
  final Set<String> visited;

  const _ChartRow({
    required this.officers,
    required this.childrenByParent,
    required this.isTop,
    required this.linked,
    required this.visited,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < officers.length; i++)
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (linked)
                  SizedBox(
                    height: _chartLinkHeight,
                    child: CustomPaint(
                      painter: _SiblingLinkPainter(
                        isFirst: i == 0,
                        isLast: i == officers.length - 1,
                        color: _chartLineColor,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _chartSpacing / 2,
                  ),
                  child: _ChartNode(
                    officer: officers[i],
                    childrenByParent: childrenByParent,
                    isTop: isTop,
                    visited: visited,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// An officer's card plus, recursively, their direct reports underneath.
class _ChartNode extends StatelessWidget {
  final _ChartOfficer officer;
  final Map<String, List<_ChartOfficer>> childrenByParent;
  final bool isTop;
  final Set<String> visited;

  const _ChartNode({
    required this.officer,
    required this.childrenByParent,
    required this.isTop,
    required this.visited,
  });

  @override
  Widget build(BuildContext context) {
    final card = _OrgChartCard(officer: officer, isTop: isTop);
    final path = {...visited, officer.id};
    final children =
        (childrenByParent[officer.id] ?? const <_ChartOfficer>[])
            .where((c) => !path.contains(c.id))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (children.isEmpty) return Center(child: card);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        const _ChartTrunk(),
        _ChartRow(
          officers: children,
          childrenByParent: childrenByParent,
          isTop: false,
          linked: true,
          visited: path,
        ),
      ],
    );
  }
}

/// Vertical line from a parent (or a whole tier) down to the bus below it.
class _ChartTrunk extends StatelessWidget {
  const _ChartTrunk();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 2,
        height: _chartLinkHeight,
        color: _chartLineColor,
      ),
    );
  }
}

/// A sibling's slice of the bus: the horizontal line across its own width
/// (only from its center inward when it is the first or last sibling), plus
/// the stub down into its card. Adjacent slices touch, so together they read
/// as one continuous bus between the outermost siblings.
class _SiblingLinkPainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color color;

  const _SiblingLinkPainter({
    required this.isFirst,
    required this.isLast,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final cx = size.width / 2;
    const y = 1.0;
    if (!(isFirst && isLast)) {
      final left = isFirst ? cx : 0.0;
      final right = isLast ? cx : size.width;
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _SiblingLinkPainter old) =>
      old.isFirst != isFirst || old.isLast != isLast || old.color != color;
}

/// Portrait photo card with name and position, matching the web chart's box.
class _OrgChartCard extends StatelessWidget {
  final _ChartOfficer officer;
  final bool isTop;

  const _OrgChartCard({required this.officer, required this.isTop});

  @override
  Widget build(BuildContext context) {
    final initials = Center(
      child: Text(
        officer.name.isNotEmpty ? officer.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );

    return SizedBox(
      width: _chartCardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _chartCardWidth,
            height: _chartCardWidth * 1.15,
            decoration: BoxDecoration(
              color: AppColors.primaryDark.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isTop ? AppColors.primaryDark : _UiTokens.cardBorder,
                width: isTop ? 1.6 : 1.2,
              ),
              boxShadow: _UiTokens.subtleShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: officer.photoUrl.isEmpty
                ? initials
                : AppImage(
                    source: officer.photoUrl,
                    width: _chartCardWidth,
                    height: _chartCardWidth * 1.15,
                    fit: BoxFit.cover,
                    showLoadingIndicator: false,
                    placeholder: initials,
                  ),
          ),
          const SizedBox(height: 6),
          Container(
            width: _chartCardWidth,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _UiTokens.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  officer.name.isEmpty ? 'Unnamed' : officer.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  officer.position,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _UiTokens.mutedText,
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
