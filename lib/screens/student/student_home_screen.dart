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
import '../../widgets/common/feed_cards.dart'; // for feedCategoryColor
import '../../widgets/student/announcements_feed.dart';
import '../../widgets/student/profile_summary.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';

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
  static const double radius = 12;
  static const Color divider = AppColors.divider;
  static const Color cardBorder = AppColors.divider;
  static const Color mutedText = AppColors.textSecondary;
  static const Color headingText = AppColors.textPrimary;

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration card({double radiusOverride = radius}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radiusOverride),
    border: Border.all(color: cardBorder, width: 1),
    boxShadow: subtleShadow,
  );
}

// Helper widget to display base64 images
class Base64Image extends StatelessWidget {
  final String base64String;
  final double height;
  final double width;
  final BoxFit fit;

  const Base64Image({
    super.key,
    required this.base64String,
    this.height = 100,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return AppImage(
      source: base64String,
      height: height,
      width: width,
      fit: fit,
      placeholderBackgroundColor: AppColors.primaryDark.withOpacity(0.1),
      placeholderIconColor: Colors.grey,
      placeholderIconSize: 40,
    );
  }
}

// Reusable section header used across Events / Announcements
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 11,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom Nav Bar - Integrated
// ─────────────────────────────────────────────────────────────
class BottomNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const BottomNavItem(this.icon, this.selectedIcon, this.label);
}

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavItem> items;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: _UiTokens.divider, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = currentIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryDark.withOpacity(0.06)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected
                              ? AppColors.primaryDark
                              : _UiTokens.mutedText,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        // FittedBox instead of overflow:visible — a label
                        // longer than "Announce" (e.g. "Announcements")
                        // would otherwise spill past its Expanded slot and
                        // overlap the neighboring tab instead of shrinking
                        // to fit.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.primaryDark
                                    : _UiTokens.mutedText,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
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
  // My Organizations preview and the audience-eligibility check on
  // Upcoming Events, fetched once and shared between them.
  late final Future<Map<String, dynamic>?> _studentDataFuture =
      _loadStudentData();

  // Membership is still a single orgId on students/{uid} today (not an
  // array) — wrapped as a 0-1 item "my organizations" list here so the UI
  // is already shaped for multiple memberships whenever the backend
  // actually supports it, without inventing a new field now.
  late final Future<_MyOrgPreview?> _myOrgFuture = _loadMyOrgPreview();

  // Chained off _myOrgFuture and cached the same way — without this, the
  // inline `.get()` call that used to sit directly in build() re-fired a
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

  Future<_MyOrgPreview?> _loadMyOrgPreview() async {
    final data = await _studentDataFuture;
    if (data == null) return null;
    final orgId = (data['orgId'] ?? '').toString();
    if (orgId.isEmpty) return null;

    String logoUrl = '';
    try {
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
      logoUrl = (orgDoc.data()?['logoUrl'] ?? '').toString();
    } catch (_) {
      // Org preview still works without a logo.
    }

    return _MyOrgPreview(
      orgId: orgId,
      orgName: (data['orgName'] ?? '').toString(),
      isOfficer: data['isOrgOfficer'] == true,
      logoUrl: logoUrl,
    );
  }

  Future<List<QueryDocumentSnapshot>> _loadMerchPreview() async {
    final org = await _myOrgFuture;
    if (org == null) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('orgId', isEqualTo: org.orgId)
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
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('date', isGreaterThanOrEqualTo: Timestamp.now())
          .orderBy('date', descending: false)
          .limit(20)
          .get();

      final studentData = await _studentDataFuture;
      final course = studentData?['course'] as String?;

      return snap.docs
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
          .take(5)
          .toList();
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

      // 3. Filter and sort for future events
      final now = DateTime.now();
      final futureEvents =
          allEvents.where((e) => e.fullDateTime.isAfter(now)).toList()
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
              child: Divider(height: 1, thickness: 1, color: _UiTokens.divider),
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
                    color: Color(0xFFBE4700),
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
                      ? snapshot.data!.docs.length
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
              fetchMyRegisteredEvents: FirebaseAuth.instance.currentUser != null
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
                      child: _SectionHeader(
                        title: 'Organizations for you',
                        actionLabel: 'View all',
                        onAction: () => widget.onNavigateToTab(2),
                      ),
                    ),
                    SizedBox(
                      height: 108,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final org = docs[index].data() as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _OrgPreviewCard(
                              name: (org['name'] ?? 'Organization').toString(),
                              logoUrl: org['logoUrl'] as String?,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentOrganizationsDetailsScreen(
                                    orgId: docs[index].id,
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
              },
            ),
          ),

          // Upcoming Events Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: _SectionHeader(
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
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: SkeletonLoader(count: 2, height: 120),
                  );
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data!.isEmpty) {
                  // Collapses to nothing rather than an empty-state card —
                  // matches the My Organizations/Merchandise previews below.
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: _UpcomingEventsCarousel(
                    events: snapshot.data!,
                    onTap: _navigateToEventDetail,
                  ),
                );
              },
            ),
          ),

          // Announcements Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
              child: _SectionHeader(
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

          // My Organizations preview — hidden entirely when the student
          // has no org yet, same "don't show empty previews" rule as
          // Merchandise below (the full Organizations tab still has a
          // proper empty state for this; this is just a Home preview).
          SliverToBoxAdapter(
            child: FutureBuilder<_MyOrgPreview?>(
              future: _myOrgFuture,
              builder: (context, snapshot) {
                final org = snapshot.data;
                if (org == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                      child: _SectionHeader(
                        title: 'My Organizations',
                        actionLabel: 'View all',
                        onAction: () => widget.onNavigateToTab(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _MyOrgPreviewTile(
                        org: org,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentOrganizationsDetailsScreen(
                              orgId: org.orgId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
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
                      child: _SectionHeader(
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
                            child: _MerchPreviewCard(
                              name: (data['name'] ?? '').toString(),
                              price: ((data['price'] ?? 0) as num).toDouble(),
                              imageBase64: (data['imageBase64'] ?? '')
                                  .toString(),
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
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.explore_outlined,
                        label: 'Events',
                        // Discover tab is index 0 within Events.
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onNavigateToTab(1, eventsSubTab: 0);
                        },
                      ),
                    ),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.event_available_outlined,
                        label: 'My Events',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onNavigateToTab(1, eventsSubTab: 2);
                        },
                      ),
                    ),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.badge_outlined,
                        label: 'Digital ID',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PersonalIdentityScreen(profile: ProfileModel()),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _QuickAction(
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

// One card in the Upcoming Events carousel — white rounded card with a
// top-inset banner, then a date/time row, title, and location row below it.
class _UpcomingEventCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _UpcomingEventCard({required this.event, required this.onTap});

  String get _location => event.location.trim();

  String get _orgName => event.orgName.trim();

  // Matches the date/time format FeedEventCard used to show, e.g.
  // "Fri, Jul 3 · 4:00 PM".
  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${wdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}'
        ' · $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final bannerUrl = event.bannerUrl ?? '';
    final catColor = feedCategoryColor(event.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: bannerUrl.isNotEmpty
                    ? Base64Image(
                        base64String: bannerUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppColors.primaryDark.withAlpha(31),
                        child: const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.primaryDark,
                            size: 32,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            // ── Date + time ──────────────────────────────────
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 13, color: catColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _formatDateTime(event.fullDateTime),
                    style: TextStyle(
                      fontSize: 12,
                      color: catColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: catColor, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _UiTokens.headingText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            if (_location.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 13,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _UiTokens.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_orgName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 13,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _orgName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _UiTokens.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Swipeable one-card-at-a-time carousel over every upcoming event, with
// arrow-button navigation and a page-dot indicator.
class _UpcomingEventsCarousel extends StatefulWidget {
  final List<EventModel> events;
  final void Function(EventModel event) onTap;

  const _UpcomingEventsCarousel({required this.events, required this.onTap});

  @override
  State<_UpcomingEventsCarousel> createState() => _UpcomingEventsCarouselState();
}

class _UpcomingEventsCarouselState extends State<_UpcomingEventsCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _navArrow({required IconData icon, required VoidCallback? onTap}) {
    return Opacity(
      opacity: onTap != null ? 1 : 0.35,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: AppColors.primaryDark),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 350,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: widget.events.length,
                itemBuilder: (context, index) {
                  final event = widget.events[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _UpcomingEventCard(
                      event: event,
                      onTap: () => widget.onTap(event),
                    ),
                  );
                },
              ),
            ),
            if (widget.events.length > 1) ...[
              Positioned(
                left: 6,
                child: _navArrow(
                  icon: Icons.chevron_left,
                  onTap: _page > 0 ? () => _goToPage(_page - 1) : null,
                ),
              ),
              Positioned(
                right: 6,
                child: _navArrow(
                  icon: Icons.chevron_right,
                  onTap: _page < widget.events.length - 1
                      ? () => _goToPage(_page + 1)
                      : null,
                ),
              ),
            ],
          ],
        ),
        // A single upcoming event needs no page indicator.
        if (widget.events.length > 1) ...[
          const SizedBox(height: 8),
          // Scrollable rather than a plain centered Row — the full
          // upcoming-events list has no cap, so a long list of dots could
          // otherwise overflow the screen width.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.events.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 10,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryDark
                        : AppColors.primaryDark.withAlpha(51),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

// Compact icon-shortcut, not a card — Home's Quick Actions row.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_UiTokens.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primaryDark, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _UiTokens.headingText,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// Membership is a single orgId on students/{uid} today, not an array —
// this just gives Home's preview a typed 0-1-item shape to render, so the
// UI doesn't have to change if that ever becomes a real list.
class _MyOrgPreview {
  final String orgId;
  final String orgName;
  final bool isOfficer;
  final String logoUrl;

  const _MyOrgPreview({
    required this.orgId,
    required this.orgName,
    required this.isOfficer,
    required this.logoUrl,
  });
}

class _MyOrgPreviewTile extends StatelessWidget {
  final _MyOrgPreview org;
  final VoidCallback onTap;

  const _MyOrgPreviewTile({required this.org, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_UiTokens.radius),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: _UiTokens.card(),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: org.logoUrl.isNotEmpty
                  ? Base64Image(
                      base64String: org.logoUrl,
                      height: 44,
                      width: 44,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 44,
                      width: 44,
                      color: AppColors.primaryDark.withOpacity(0.08),
                      child: const Icon(
                        Icons.groups_outlined,
                        color: AppColors.primaryDark,
                        size: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                org.orgName.isNotEmpty ? org.orgName : 'My Organization',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _UiTokens.headingText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.08),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                org.isOfficer ? 'Officer' : 'Member',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgPreviewCard extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final VoidCallback onTap;

  const _OrgPreviewCard({
    required this.name,
    required this.logoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final logoImage = AppImage.provider(logoUrl ?? '');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_UiTokens.radius),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
                image: logoImage != null
                    ? DecorationImage(image: logoImage, fit: BoxFit.cover)
                    : null,
              ),
              child: logoImage == null
                  ? Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _UiTokens.headingText,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchPreviewCard extends StatelessWidget {
  final String name;
  final double price;
  final String imageBase64;
  final VoidCallback onTap;

  const _MerchPreviewCard({
    required this.name,
    required this.price,
    required this.imageBase64,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        decoration: _UiTokens.card(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageBase64.isNotEmpty
                ? Base64Image(
                    base64String: imageBase64,
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 90,
                    width: double.infinity,
                    color: AppColors.primaryDark.withOpacity(0.08),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primaryDark,
                      size: 28,
                    ),
                  ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'Product',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _UiTokens.headingText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₱${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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
  }
}
