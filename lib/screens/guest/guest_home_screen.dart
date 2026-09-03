// lib/screens/guest/guest_home_screen.dart
//
// GUEST MODE – public-only access
// Tabs: Home | Events | Orgs | Profile  (mirrors the student shell)
//
// Announcements is a Home section rather than a tab, and Calendar is an
// Events sub-tab — the freed slot went to Organizations.
//
// GuestMode.visitor      → no Firebase Auth session (browse-only)
// GuestMode.authenticated → signed in via Firebase Auth with admin-issued
//                           credentials (full guest feature set)
//
// GuestMode enum is defined in guest_auth_service.dart and re-exported
// from there so both this file and guest_access_gateway_screen share it.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uprise/models/event_model.dart';
import '../../services/guest_event_registration.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/countdown_section.dart';
import '../../widgets/common/home_sections.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/organization_card.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/student/announcements_feed.dart';
import '../../widgets/student/app_colors.dart';
import '../student/student_home_screen.dart' show homeCarouselData;
import '../student/student_login.dart';
import '../student/student_organization_details_screen.dart';
import 'guest_announcements_screen.dart';
import 'guest_auth_service.dart'; // GuestMode enum
import 'guest_certificate_repository_screen.dart';
import 'guest_digital_id_notice.dart';
import 'guest_digital_id_screen.dart';
import 'guest_events_screen.dart';
import 'guest_merchandise_screen.dart';
import 'guest_organizations_screen.dart';
import 'guest_profile_screen.dart';

// ─────────────────────────────────────────────────────────────
//  GUEST SHELL
// ─────────────────────────────────────────────────────────────
class GuestHomeScreen extends StatefulWidget {
  /// Defaults to [GuestMode.visitor] so existing call-sites that omit
  /// the parameter keep compiling unchanged.
  final GuestMode mode;

  const GuestHomeScreen({super.key, this.mode = GuestMode.visitor});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> {
  int _currentIndex = 0;

  /// Which Events sub-tab a deep-link asked for, and a token that changes on
  /// every request. The token is what makes a *repeat* jump to the same
  /// sub-tab register — without it, asking for Calendar twice would look
  /// unchanged and be ignored.
  int _eventsSubTab = 0;
  int _eventsJumpToken = 0;

  // Screens are the same for both modes; the Profile tab handles the
  // authenticated vs visitor distinction internally via GuestProfileScreen.
  //
  // Now four tabs, matching the student shell: Announcements demoted to a
  // Home section (it was already previewed there) and Calendar folded into
  // Events as a sub-tab, freeing a slot for Organizations.
  List<Widget> get _screens => [
    _GuestHomeContent(mode: widget.mode),
    GuestEventsScreen(
      initialTabIndex: _eventsSubTab,
      jumpToken: _eventsJumpToken,
    ),
    const GuestOrganizationsScreen(),
    const GuestProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.mode == GuestMode.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowGuestDigitalIdNotice(context);
      });
    }
  }

  void switchTab(int index, {int? eventsSubTab}) => setState(() {
    _currentIndex = index;
    if (eventsSubTab != null) {
      _eventsSubTab = eventsSubTab;
      _eventsJumpToken++;
    }
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      // The shared bar, with the student shell's exact item list — this used
      // to be a hand-rolled _GuestBottomNav that had drifted (62px fixed
      // height, a drop shadow instead of the divider, a pill behind only the
      // icon) purely because the component lived in a student-only file.
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavItem(Icons.home_outlined, Icons.home, 'Home'),
          BottomNavItem(
            Icons.calendar_today_outlined,
            Icons.calendar_today,
            'Events',
          ),
          BottomNavItem(Icons.groups_outlined, Icons.groups, 'Orgs'),
          BottomNavItem(Icons.person_outline, Icons.person, 'Profile'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HOME CONTENT  (student dashboard, guest data)
// ─────────────────────────────────────────────────────────────
// Section-for-section the student Home layout. What used to be here was a
// merged event+announcement feed with a chip strip; that is gone.
//
// Two things are deliberately NOT copied from student Home:
//
//   • The notification bell. Nothing in the app ever sends a notification to a
//     guest and there is no guest notifications screen, so it would be a
//     permanently-empty icon leading nowhere.
//   • EventModel.audienceAllowsMember. Guests gate on
//     classificationAllowsAudience instead — see _fetchUpcomingEvents.
//
// One section is remapped rather than dropped, because a guest has no
// membership: Merchandise shows the sitewide catalogue instead of one org's
// products. Student Home's "My Organizations" section has no guest analogue
// at all now that following is gone — membership lives in the Orgs tab.
class _GuestHomeContent extends StatefulWidget {
  final GuestMode mode;
  const _GuestHomeContent({this.mode = GuestMode.visitor});

  @override
  State<_GuestHomeContent> createState() => _GuestHomeContentState();
}

class _GuestHomeContentState extends State<_GuestHomeContent> {
  bool get _isAuthenticated => widget.mode == GuestMode.authenticated;

  bool _isOffline = false;
  StreamSubscription<QuerySnapshot>? _cacheMonitor;

  // Bumped by refreshData() and used as a ValueKey on the countdown, which
  // otherwise only fetches once in its own initState.
  int _countdownRefreshToken = 0;

  // Default to the most restrictive tier so a Bulsuan-only event can't flash
  // into view for an Outsider while the classification is still resolving.
  String _guestClassification = 'Outsider';
  bool _classificationReady = false;

  // Rebuilt once the classification lands — the audience filter depends on it,
  // so it cannot be a `late final` initialised at field-declaration time the
  // way the others are.
  Future<List<EventModel>>? _upcomingEventsFuture;

  // Cached, not built inline in build(): a fresh Future/Stream object on every
  // rebuild makes FutureBuilder/StreamBuilder treat each scroll frame as a new
  // subscription and flash its loading state. Same fix as student Home.
  late final Future<GuestIdentity?> _identityFuture = resolveGuestIdentity();
  late final Future<List<QueryDocumentSnapshot>> _merchPreviewFuture =
      _loadMerchPreview();
  late final Future<List<QueryDocumentSnapshot>> _orgsPreviewFuture =
      _loadOrgsPreview();

  @override
  void initState() {
    super.initState();
    _loadGuestClassification();

    _cacheMonitor = FirebaseFirestore.instance
        .collection('events')
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          if (mounted && snap.metadata.isFromCache != _isOffline) {
            setState(() => _isOffline = snap.metadata.isFromCache);
          }
        });
  }

  @override
  void dispose() {
    _cacheMonitor?.cancel();
    super.dispose();
  }

  Future<void> _loadGuestClassification() async {
    final svc = GuestAuthService();
    if (svc.isAuthenticated && svc.docId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('external_requests')
            .doc(svc.docId)
            .get();
        if (doc.data()?['classification'] == 'BulSUan') {
          _guestClassification = 'BulSUan';
        }
      } catch (_) {
        // Stays 'Outsider' — the safe direction.
      }
    }
    if (!mounted) return;
    setState(() {
      _classificationReady = true;
      _upcomingEventsFuture = _fetchUpcomingEvents();
    });
  }

  /// Upcoming events a guest is allowed to see.
  ///
  /// Mirrors student Home's query — single-field `date` filter capped at 20,
  /// with status/audience applied client-side so no composite index is needed —
  /// but gates on [classificationAllowsAudience], NOT
  /// `EventModel.audienceAllowsMember`. The student gate grants CICT-Only to
  /// BSIT/BSIS/BLIS students and Members-Only to org members; a guest gets
  /// neither, and gets BulSUan only when classified BulSUan.
  Future<List<EventModel>> _fetchUpcomingEvents() async {
    try {
      // `date` is only the calendar day (local midnight), so comparing it to
      // Timestamp.now() would skip everything later today. Query from the
      // start of today and let timeStatus do the real start/end check — the
      // times live in the startTime/endTime strings, which Firestore can't
      // compare against.
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
          )
          .orderBy('date', descending: false)
          .limit(20)
          .get();

      final events =
          snap.docs
              .map(EventModel.fromFirestore)
              .where((e) => e.status == 'approved')
              .where(
                (e) =>
                    classificationAllowsAudience(e.audience, _guestClassification),
              )
              .where((e) => e.timeStatus != EventTimeStatus.completed)
              .toList()
            // orderBy('date') only orders by day, so sort on the real start
            // time before capping — otherwise the cap spends itself on later
            // same-day events.
            ..sort((a, b) => a.fullDateTime.compareTo(b.fullDateTime));

      return events.take(5).toList();
    } catch (e) {
      debugPrint('❌ Error fetching upcoming events: $e');
      return [];
    }
  }

  /// Guest merch has no org to scope to — a guest isn't a member of anything —
  /// so this previews the same sitewide catalogue GuestMerchandiseScreen lists.
  Future<List<QueryDocumentSnapshot>> _loadMerchPreview() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('isArchived', isEqualTo: false)
          .limit(6)
          .get();
      return snap.docs;
    } catch (_) {
      return [];
    }
  }

  Future<List<QueryDocumentSnapshot>> _loadOrgsPreview() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();
      return snap.docs;
    } catch (_) {
      return [];
    }
  }

  // Countdown data source when authenticated — guest registrations are keyed
  // by email + isGuest, not by uid the way student's are.
  Future<List<EventModel>> _fetchMyRegisteredEvents() async {
    final email = (GuestAuthService().email ?? '').toLowerCase();
    if (email.isEmpty) return [];

    try {
      final regSnap = await FirebaseFirestore.instance
          .collection('registrations')
          .where('email', isEqualTo: email)
          .where('isGuest', isEqualTo: true)
          .get();

      final eventIds = regSnap.docs
          .map((d) => (d.data())['eventId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (eventIds.isEmpty) return [];

      final eventDocs = await Future.wait(
        eventIds.map(
          (id) => FirebaseFirestore.instance.collection('events').doc(id).get(),
        ),
      );

      // Keep an in-progress event — CountdownWidget renders it as
      // "Event has started!"; drop it only once it's actually over.
      final events = eventDocs
          .where((d) => d.exists)
          .map(EventModel.fromFirestore)
          .where((e) => e.timeStatus != EventTimeStatus.completed)
          .toList()
        ..sort((a, b) => a.fullDateTime.compareTo(b.fullDateTime));

      return events;
    } catch (_) {
      return [];
    }
  }

  void refreshData() {
    setState(() {
      _countdownRefreshToken++;
      _upcomingEventsFuture = _fetchUpcomingEvents();
    });
  }

  void _switchTab(int index, {int? eventsSubTab}) {
    final s = context.findAncestorStateOfType<_GuestHomeScreenState>();
    if (s != null) s.switchTab(index, eventsSubTab: eventsSubTab);
  }

  /// Announcements lost its bottom-nav slot to Organizations, so the full
  /// list is a push now rather than a tab switch. Home still previews it.
  void _openAnnouncements() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const GuestAnnouncementsScreen()),
  );

  void _showSignInPrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _SignInPromptSheet(),
    );
  }

  void _openEventDetail(EventModel event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuestEventDetailScreen(
          event: FirestoreEvent.fromEventModel(event),
        ),
      ),
    );
  }

  /// Passes the guest config explicitly. Without it the shared profile screen
  /// falls back to OrgBrowsingConfig.student, which would hand a guest the
  /// member-only broadcast icon and unfiltered CICT-Only / Members-Only
  /// content.
  void _openOrg(String orgId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentOrganizationsDetailsScreen(
          orgId: orgId,
          config: guestOrgBrowsingConfig(_guestClassification),
        ),
      ),
    );
  }

  void _openMerch() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const GuestMerchandiseScreen()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Padding(
        // Bottom clearance so the FAB clears the outer Scaffold's BottomNavBar,
        // which this nested Scaffold doesn't know about.
        padding: const EdgeInsets.only(bottom: 40),
        child: FloatingActionButton(
          backgroundColor: AppColors.primaryDark,
          onPressed: () => _showQuickActionsSheet(context),
          child: const Icon(Icons.bolt_outlined, color: Colors.white),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: 44,
                  width: 44,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.school,
                    color: AppColors.primaryDark,
                    size: 38,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'UPRISE',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.primaryDark,
                  size: 22,
                ),
                onPressed: _openMerch,
              ),
              // Guest-only, kept: student Home has no equivalent for these two
              // states, so there's nothing for them to conflict with.
              if (_isAuthenticated)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: _VerifiedChip(),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: _showSignInPrompt,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: AppColors.divider),
            ),
          ),

          // ── Offline indicator ─────────────────────────────
          if (_isOffline)
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFFF6EEDD),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 14,
                      color: Color(0xFF8A6D1F),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Offline — showing cached data',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A6D1F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Welcome ───────────────────────────────────────
          // A visitor has no name to greet, so the whole block collapses
          // rather than falling back to "Good day, Guest".
          SliverToBoxAdapter(
            child: FutureBuilder<GuestIdentity?>(
              future: _identityFuture,
              builder: (context, snap) {
                final name = snap.data?.fullName.trim() ?? '';
                if (name.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Good day, ',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(text: name),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Here\'s what\'s happening on campus today.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Countdown ─────────────────────────────────────
          SliverToBoxAdapter(
            child: PersonalOrNextEventCountdown(
              key: ValueKey(_countdownRefreshToken),
              fetchMyRegisteredEvents: _isAuthenticated
                  ? _fetchMyRegisteredEvents
                  : null,
            ),
          ),

          // ── Organizations for you ─────────────────────────
          SliverToBoxAdapter(
            child: FutureBuilder<List<QueryDocumentSnapshot>>(
              future: _orgsPreviewFuture,
              builder: (context, orgSnap) {
                final docs = orgSnap.data ?? [];
                if (docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: SectionHeader(
                        title: 'Organizations for you',
                        actionLabel: 'View all',
                        onAction: () => _switchTab(2),
                      ),
                    ),
                    OrgPreviewRail(
                      children: [
                        for (final doc in docs)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: OrgPreviewCard(
                              name:
                                  ((doc.data()
                                              as Map<String, dynamic>)['name'] ??
                                          'Organization')
                                      .toString(),
                              logoUrl:
                                  (doc.data()
                                      as Map<String, dynamic>)['logoUrl']
                                  as String?,
                              onTap: () => _openOrg(doc.id),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Upcoming Events ───────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: SectionHeader(
                title: 'Upcoming Events',
                actionLabel: 'View all',
                onAction: () => _switchTab(1, eventsSubTab: 0),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: FutureBuilder<List<EventModel>>(
              future: _upcomingEventsFuture,
              builder: (context, snapshot) {
                if (!_classificationReady ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: SkeletonLoader(count: 2, height: 120),
                  );
                }

                // Re-filter on every rebuild, not just on fetch: the future is
                // built once and this State is kept alive by the IndexedStack,
                // so without this an event that ends while the app is open
                // would linger on the carousel.
                final events =
                    snapshot.data
                        ?.where((e) => e.timeStatus != EventTimeStatus.completed)
                        .toList() ??
                    const <EventModel>[];

                if (snapshot.hasError || events.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: UpcomingEventsCarousel(
                    events: events.map(homeCarouselData).toList(),
                    onTap: (i) => _openEventDetail(events[i]),
                  ),
                );
              },
            ),
          ),

          // ── Announcements ─────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
              child: SectionHeader(
                title: 'Announcements',
                actionLabel: 'See all',
                onAction: _openAnnouncements,
              ),
            ),
          ),

          // Public-only. AnnouncementsFeed applies no audience filter of its
          // own, so without this a guest would see Members-Only posts. Same
          // rule OrgBrowsingConfig.publicAnnouncementsOnly enforces.
          SliverToBoxAdapter(
            child: AnnouncementsFeed(
              allowedAudiences: const {'Public'},
              onTap: (_) => _openAnnouncements(),
            ),
          ),

          // ── Merchandise ───────────────────────────────────
          SliverToBoxAdapter(
            child: FutureBuilder<List<QueryDocumentSnapshot>>(
              future: _merchPreviewFuture,
              builder: (context, productSnap) {
                final docs = productSnap.data ?? [];
                if (docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                      child: SectionHeader(
                        title: 'Merchandise',
                        actionLabel: 'View all',
                        onAction: _openMerch,
                      ),
                    ),
                    SizedBox(
                      height: 168,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: MerchPreviewCard(
                              name: (data['name'] ?? '').toString(),
                              price: ((data['price'] ?? 0) as num).toDouble(),
                              imageBase64: (data['imageBase64'] ?? '')
                                  .toString(),
                              onTap: _openMerch,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 84)),
        ],
      ),
    );
  }

  /// The same four shortcuts student Home offers, each pointing at the guest
  /// screen for it.
  void _showQuickActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // No "Events" tile here — Events is a top-level nav tab,
                    // so a shortcut to it would just duplicate the bar below.
                    Expanded(
                      child: HomeQuickAction(
                        icon: Icons.event_available_outlined,
                        label: 'My Events',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _switchTab(1, eventsSubTab: 2);
                        },
                      ),
                    ),
                    Expanded(
                      child: HomeQuickAction(
                        icon: Icons.badge_outlined,
                        label: 'Digital ID',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GuestDigitalIdScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: HomeQuickAction(
                        icon: Icons.workspace_premium_outlined,
                        label: 'Certificates',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const GuestCertificateRepositoryScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The approved-guest badge in the app bar. Guest-only — student Home has no
/// verification state to show.
class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withAlpha(102)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
//  SIGN IN PROMPT SHEET
// ─────────────────────────────────────────────────────────────
class _SignInPromptSheet extends StatelessWidget {
  const _SignInPromptSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 22),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 34,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'CICT Student Access',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in with your CICT credentials\nto unlock full access.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 24),
          _SheetFeatureRow(
            icon: Icons.badge_outlined,
            text: 'Digital ID & Profile',
          ),
          const SizedBox(height: 8),
          // Guests browse every organization the same as students, so this
          // row no longer claims orgs are student-only — formal membership
          // and the org message threads still are.
          _SheetFeatureRow(
            icon: Icons.groups_outlined,
            text: 'Org Membership & Broadcasts',
          ),
          const SizedBox(height: 8),
          _SheetFeatureRow(
            icon: Icons.workspace_premium_outlined,
            text: 'Certificates & Merch',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentLogin()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Sign In as CICT Student',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Continue browsing as Guest',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SheetFeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Color(0xFF2E7D32),
        ),
      ],
    );
  }
}