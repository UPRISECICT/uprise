// lib/screens/student/student_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Models
import 'package:uprise/models/event_model.dart';
import '../../models/announcement_model.dart'; // for AnnouncementData

// Providers (if still needed – remove if unused)
// import 'package:provider/provider.dart'; // removed – not used

// Widgets
import '../../widgets/common/loading_widget.dart'; // for SkeletonLoader
import '../../widgets/common/countdown_section.dart';
import '../../widgets/common/bottom_nav_bar.dart'; // BottomNavBar / BottomNavItem
import '../../widgets/common/section_header.dart';
import '../../widgets/common/event_card.dart';
import '../../widgets/common/home_sections.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/common/organization_card.dart';
import '../../widgets/student/announcements_feed.dart';
import '../../widgets/student/profile_summary.dart';
import '../../widgets/student/app_colors.dart';

// Screens (navigation targets)
import 'student_events_screen.dart';
import 'student_organizations_screen.dart';
import 'student_organization_details_screen.dart';
import 'student_certificates_screen.dart';
import 'student_profile_screen.dart';
import 'student_announcements_screen.dart';
import 'student_notifications_screen.dart';
import 'student_merchandise_screen.dart';
import 'student_feedback_prompt.dart';
import 'student_new_event_promo.dart';

// ─────────────────────────────────────────────────────────────
// Shared style tokens
// ─────────────────────────────────────────────────────────────
class _UiTokens {
  // Thin aliases onto the shared AppColors scale — see the same pattern in
  // student_organizations_screen.dart; keeps this file's existing call sites
  // working while the actual values live in one place.
  //
  // `radius`, `cardBorder`, `subtleShadow` and `card()` left with the section
  // widgets — the card decoration is now homeCardDecoration() in
  // widgets/common/home_sections.dart.
  static const Color divider = AppColors.divider;
  static const Color mutedText = AppColors.textSecondary;
  static const Color headingText = AppColors.textPrimary;
}

// Base64Image left with the section widgets too — it was a thin wrapper over
// AppImage that only they used, and they now call AppImage directly.

// _SectionHeader now lives in widgets/common/section_header.dart as the public
// SectionHeader, so the guest home feed uses the same one.
// BottomNavBar / BottomNavItem now live in widgets/common/bottom_nav_bar.dart
// so the guest shell can share the same nav chrome.
// The dashboard sections themselves — UpcomingEventsCarousel, HomeQuickAction,
// MerchPreviewCard, OrgPreviewCard — now live in
// widgets/common/home_sections.dart and organization_card.dart, so guest Home
// renders the same dashboard instead of its own merged-feed layout.

/// Maps an [EventModel] onto the carousel card's data struct.
///
/// The carousel wants one combined "Fri, Aug 30 · 4:00 PM" label where the
/// events-list card wants a separate date and time — [EventCardData] holds
/// pre-formatted strings precisely so each surface can choose, so the combined
/// form goes in `dateLabel` and `timeLabel` is left empty.
EventCardData homeCarouselData(EventModel e) => EventCardData(
  title: e.title,
  category: e.category,
  imageUrl: e.bannerUrl ?? '',
  dateLabel: _formatCarouselDateTime(e.fullDateTime),
  location: e.location,
  orgName: e.orgName,
);

String _formatCarouselDateTime(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final min = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  return '${wdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}'
      ' · $h:$min $ampm';
}

// ─────────────────────────────────────────────────────────────
// Student Home Screen
// ─────────────────────────────────────────────────────────────
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _currentIndex = 0;
  int _eventsSubTab = 0;
  int _eventsJumpToken = 0;
  String _userName = '';

  void _goToTab(int index, {int? eventsSubTab}) {
    setState(() {
      _currentIndex = index;
      if (eventsSubTab != null) {
        _eventsSubTab = eventsSubTab;
        _eventsJumpToken++;
      }
    });
  }

  final GlobalKey<_HomeContentState> _homeKey = GlobalKey<_HomeContentState>();

  @override
  void initState() {
    super.initState();
    _loadUserName();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await maybeShowFeedbackPrompt(context);
      if (!mounted) return;
      await maybeShowNewEventPromo(context);
    });
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('students')
            .doc(user.uid)
            .get();

        if (!mounted) return;

        if (doc.exists) {
          final data = doc.data()!;
          final firstName = (data['firstName'] ?? '').toString().trim();
          final middleName = (data['middleName'] ?? '').toString().trim();

          final greetingName = [
            firstName,
            middleName,
          ].where((p) => p.isNotEmpty).join(' ');

          setState(() {
            _userName = greetingName.isNotEmpty
                ? greetingName
                : (user.displayName ??
                      user.email?.split('@').first ??
                      'Student');
          });
        }
      } catch (_) {
        // Keep default name
      }
    }
  }

  void _refreshUserName() async {
    await _loadUserName();
    if (_homeKey.currentState != null) {
      _homeKey.currentState!.refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // IndexedStack (not a direct index-swap) so every tab's State — most
      // importantly Profile's ProfileModel — is built once and kept alive
      // for the rest of the session instead of being torn down and
      // recreated (re-fetching from Firestore, briefly showing blank
      // placeholders) every single time the student switches away and
      // back. It also means Profile's fetch starts immediately alongside
      // Home's on login, so by the time the student actually taps the
      // Profile tab the data has usually already arrived.
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });

          if (index == 0) {
            _refreshUserName();
          }
        },
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

  // Announcements is no longer a bottom-nav tab (it's a Home preview
  // section + notification bell now), so the tab indices shifted down by
  // one: Events moved from 2 to 1, Orgs from 3 to 2, Profile from 4 to 3.
  List<Widget> get _screens => [
    _HomeContent(key: _homeKey, userName: _userName, onNavigateToTab: _goToTab),
    StudentEventsScreen(
      initialTabIndex: _eventsSubTab,
      jumpToken: _eventsJumpToken,
    ),
    const StudentOrganizationsScreen(),
    StudentProfileScreen(
      // Events tab order is Discover(0) / Calendar(1) / My Events(2).
      onViewAllRegistrations: () => _goToTab(1, eventsSubTab: 2),
    ),
  ];
}

class _HomeContent extends StatefulWidget {
  final String userName;
  final void Function(int tabIndex, {int? eventsSubTab}) onNavigateToTab;

  const _HomeContent({
    super.key,
    required this.userName,
    required this.onNavigateToTab,
  });

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  bool _isOffline = false;
  StreamSubscription<QuerySnapshot>? _cacheMonitor;

  // Bumped whenever refreshData() runs — used as a ValueKey on the
  // countdown widget to force it to recreate its State (and therefore
  // refetch), since PersonalOrNextEventCountdown otherwise only fetches
  // once in its own initState.
  int _countdownRefreshToken = 0;

  // Cached future for upcoming events — replaces a live stream so
  // status/audience filtering (see _fetchUpcomingEvents) can happen
  // client-side without needing a new Firestore composite index.
  Future<List<EventModel>>? _upcomingEventsFuture;

  // The signed-in student's own students/{uid} doc — needed for both the
  // Merchandise preview and the audience-eligibility check on Upcoming
  // Events, fetched once and shared between them.
  late final Future<Map<String, dynamic>?> _studentDataFuture =
      _loadStudentData();

  // Chained off _studentDataFuture and cached the same way — without this,
  // the inline `.get()` call that used to sit directly in build() re-fired a
  // fresh Firestore query on every rebuild of this widget (e.g. every
  // scroll-triggered sliver rebuild), not just on first load.
  late final Future<List<QueryDocumentSnapshot>> _merchPreviewFuture =
      _loadMerchPreview();

  // "Organizations for you" — cached the same way as _merchPreviewFuture so
  // scroll-triggered sliver rebuilds don't re-fire the query.
  late final Future<List<QueryDocumentSnapshot>> _orgsPreviewFuture =
      _loadOrgsPreview();

  // Used to be created inline inside build() as
  // `stream: FirebaseFirestore.instance....snapshots()`. A new Stream
  // object has a different identity every time, so StreamBuilder treated
  // every rebuild as a brand-new subscription and reset to "waiting" —
  // which is why the unread badge flashed its loading skeleton on every
  // scroll frame and every time this tab was revisited. Caching the
  // Stream once (same fix as the futures above) keeps the same live
  // subscription across rebuilds.
  late final Stream<QuerySnapshot> _unreadNotifStream = FirebaseFirestore
      .instance
      .collection('notifications')
      .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
      .where('isRead', isEqualTo: false)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _upcomingEventsFuture = _fetchUpcomingEvents();

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

  Future<Map<String, dynamic>?> _loadStudentData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<List<QueryDocumentSnapshot>> _loadMerchPreview() async {
    final data = await _studentDataFuture;
    final orgId = (data?['orgId'] ?? '').toString();
    if (orgId.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('orgId', isEqualTo: orgId)
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

  // Buffered (status/audience filtered client-side below) so this stays a
  // single-field query — matches the Discover tab's own eligibility rules
  // (EventModel.audienceAllowsMember) instead of the old unfiltered stream,
  // which could leak pending or audience-restricted events onto Home.
  Future<List<EventModel>> _fetchUpcomingEvents() async {
    try {
      // `date` holds only the calendar day (local midnight), so comparing it
      // against `Timestamp.now()` would drop everything happening later
      // today. Query from the start of today and let the client-side
      // `timeStatus` check below do the real start/end filtering — the
      // time-of-day lives in the `startTime`/`endTime` strings, which
      // Firestore can't compare against.
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

      final studentData = await _studentDataFuture;
      final course = studentData?['course'] as String?;

      final events =
          snap.docs
              .map(EventModel.fromFirestore)
              .where((e) => e.status == 'approved')
              .where(
                (e) => EventModel.audienceAllowsMember(
                  audience: e.audience,
                  eventOrgId: e.orgId,
                  userData: studentData,
                  course: course,
                ),
              )
              // Upcoming and ongoing both belong here; only drop it once the
              // event has actually ended.
              .where((e) => e.timeStatus != EventTimeStatus.completed)
              .toList()
            // `orderBy('date')` only orders by day, so sort on the real start
            // time before capping — otherwise the cap can spend itself on
            // later same-day events.
            ..sort((a, b) => a.fullDateTime.compareTo(b.fullDateTime));

      return events.take(5).toList();
    } catch (e) {
      debugPrint('❌ Error fetching upcoming events: $e');
      return [];
    }
  }

  // Single method that fetches and returns the list of future registered events.
  Future<List<EventModel>> _fetchRegisteredEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // 1. Fetch registration IDs
      final regSnap = await FirebaseFirestore.instance
          .collection('registrations')
          .where('userId', isEqualTo: user.uid)
          .get();

      final eventIds = regSnap.docs
          .map((doc) => doc['eventId'] as String)
          .toSet();
      if (eventIds.isEmpty) return [];

      // 2. Fetch event documents in batches of 30
      final idsList = eventIds.toList();
      final allEvents = <EventModel>[];

      for (var i = 0; i < idsList.length; i += 30) {
        final batch = idsList.sublist(
          i,
          i + 30 > idsList.length ? idsList.length : i + 30,
        );
        if (batch.isEmpty) continue;

        final snap = await FirebaseFirestore.instance
            .collection('events')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snap.docs) {
          allEvents.add(EventModel.fromFirestore(doc));
        }
      }

      // 3. Filter and sort — an in-progress event stays (CountdownWidget
      // renders it as "Event has started!"); drop it only once it's over.
      final futureEvents =
          allEvents
              .where((e) => e.timeStatus != EventTimeStatus.completed)
              .toList()
            ..sort((a, b) => a.fullDateTime.compareTo(b.fullDateTime));

      return futureEvents;
    } catch (e) {
      debugPrint('❌ Error fetching registered events: $e');
      return [];
    }
  }

  void refreshData() {
    setState(() {
      _countdownRefreshToken++;
      _upcomingEventsFuture = _fetchUpcomingEvents();
    });
  }

  void _navigateToEventDetail(EventModel event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(
          event: event,
          onRegistered: () {
            refreshData();
          },
          isPastEvent: event.isPast,
        ),
      ),
    );
  }

  void _navigateToAnnouncementDetail(AnnouncementData announcement) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AnnouncementDetailScreen(announcement: announcement),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = widget.userName.isNotEmpty
        ? widget.userName
        : user?.displayName ?? user?.email?.split('@').first ?? 'Student';

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Padding(
        // Bottom clearance so the FAB clears the outer Scaffold's
        // BottomNavBar, which this nested Scaffold doesn't know about.
        padding: const EdgeInsets.only(bottom: 40),
        child: FloatingActionButton(
          backgroundColor: AppColors.primaryDark,
          onPressed: () => _showQuickActionsSheet(context),
          child: const Icon(Icons.bolt_outlined, color: Colors.white),
        ),
      ),
      body: Container(
        color: AppColors.background,
        child: CustomScrollView(
          slivers: [
            // App Bar with Logo
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: _UiTokens.divider,
                ),
              ),
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
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StudentMerchandiseScreen(),
                      ),
                    );
                  },
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: _unreadNotifStream,
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.hasData
                        ? snapshot.data!.docs.where((doc) {
                            final portal =
                                (doc.data() as Map<String, dynamic>)['portal'];
                            return portal == null ||
                                portal == '' ||
                                portal == 'student';
                          }).length
                        : 0;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: AppColors.primaryDark,
                            size: 22,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const StudentNotificationsScreen(),
                              ),
                            );
                          },
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC0392B),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Center(
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 6),
              ],
            ),

            // Offline indicator
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

            // Welcome Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _UiTokens.headingText,
                          height: 1.2,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Good day, ',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: _UiTokens.mutedText,
                            ),
                          ),
                          TextSpan(
                            text: userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _UiTokens.headingText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Here\'s what\'s happening on campus today.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _UiTokens.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Countdown — my registered events, refetched via
            //     refreshData() (see _countdownRefreshToken above) ─────
            SliverToBoxAdapter(
              child: PersonalOrNextEventCountdown(
                key: ValueKey(_countdownRefreshToken),
                fetchMyRegisteredEvents:
                    FirebaseAuth.instance.currentUser != null
                    ? _fetchRegisteredEvents
                    : null,
              ),
            ),

            // Organizations for you — horizontal browse row, replaces the old
            // Quick Actions row (those 4 shortcuts now live behind the FAB).
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
                          onAction: () => widget.onNavigateToTab(2),
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
                                                as Map<
                                                  String,
                                                  dynamic
                                                >)['name'] ??
                                            'Organization')
                                        .toString(),
                                logoUrl:
                                    (doc.data()
                                            as Map<String, dynamic>)['logoUrl']
                                        as String?,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StudentOrganizationsDetailsScreen(
                                          orgId: doc.id,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

            // Upcoming Events Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: SectionHeader(
                  title: 'Upcoming Events',
                  actionLabel: 'View all',
                  // Discover tab is index 0 within Events.
                  onAction: () => widget.onNavigateToTab(1, eventsSubTab: 0),
                ),
              ),
            ),

            // Upcoming Events — swipeable one-card carousel with arrow nav.
            SliverToBoxAdapter(
              child: FutureBuilder<List<EventModel>>(
                future: _upcomingEventsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      child: SkeletonLoader(count: 2, height: 120),
                    );
                  }

                  // Re-filter on every rebuild, not just on fetch: the future is
                  // built once in initState and this State is kept alive by the
                  // IndexedStack, so without this an event that ends while the
                  // app is open would linger on the carousel.
                  final events =
                      snapshot.data
                          ?.where(
                            (e) => e.timeStatus != EventTimeStatus.completed,
                          )
                          .toList() ??
                      const <EventModel>[];

                  if (snapshot.hasError || events.isEmpty) {
                    // Collapses to nothing rather than an empty-state card —
                    // matches the Merchandise preview below.
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: UpcomingEventsCarousel(
                      events: events.map(homeCarouselData).toList(),
                      onTap: (i) => _navigateToEventDetail(events[i]),
                    ),
                  );
                },
              ),
            ),

            // Announcements Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: SectionHeader(
                  title: 'Announcements',
                  actionLabel: 'See all',
                  // Announcements is no longer a bottom-nav tab — this is
                  // Home's preview of it, so "See all" pushes the full
                  // announcements screen instead of jumping tabs.
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentAnnouncementsScreen(),
                    ),
                  ),
                ),
              ),
            ),

            // Announcements Feed
            SliverToBoxAdapter(
              child: AnnouncementsFeed(
                onTap: (announcementData) {
                  _navigateToAnnouncementDetail(announcementData);
                },
              ),
            ),

            // Merchandise preview — only for the student's own org, and only
            // when that org actually has active products. Merch belongs to
            // a specific organization, not a sitewide catalog, so this stays
            // empty (and hidden) for students not in an org, or whose org
            // hasn't listed anything.
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
                          onAction: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StudentMerchandiseScreen(),
                            ),
                          ),
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
                                imageSource: productCoverImageSource(data),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentMerchandiseScreen(),
                                  ),
                                ),
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
      ),
    );
  }

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
                    color: _UiTokens.headingText,
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
                          widget.onNavigateToTab(1, eventsSubTab: 2);
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
                              builder: (_) => PersonalIdentityScreen(
                                profile: ProfileModel(),
                              ),
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
                              builder: (_) => const StudentCertificatesScreen(),
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
