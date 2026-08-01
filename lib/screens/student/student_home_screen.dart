// lib/screens/student/student_home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Models
import 'package:uprise/models/event_model.dart';
import '../../models/announcement_model.dart'; // for AnnouncementData

// Providers (if still needed – remove if unused)
// import 'package:provider/provider.dart'; // removed – not used

// Widgets
import '../../widgets/common/loading_widget.dart'; // for SkeletonLoader, UpriseErrorState, UpriseEmptyState
import '../../widgets/student/announcements_feed.dart';
import '../../widgets/student/profile_summary.dart';
import '../../widgets/student/countdown_widget.dart';
import '../../widgets/student/app_colors.dart';

// Screens (navigation targets)
import 'student_events_screen.dart';
import 'student_organizations_screen.dart';
import 'student_certificates_screen.dart';
import 'student_profile_screen.dart';
import 'student_announcements_screen.dart';
import 'student_notifications_screen.dart';
import 'student_merchandise_screen.dart';
import 'student_feedback_prompt.dart';
import 'student_new_event_promo.dart';
import 'student_events_screen.dart'; // adjust if needed
import 'student_announcements_screen.dart'; // adjust if needed

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
    try {
      String base64Data = base64String;
      if (base64String.startsWith('data:image')) {
        final commaIndex = base64String.indexOf(',');
        if (commaIndex != -1) {
          base64Data = base64String.substring(commaIndex + 1);
        }
      }

      final bytes = base64Decode(base64Data);
      return Image.memory(
        bytes,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            width: width,
            color: AppColors.primaryDark.withOpacity(0.1),
            child: const Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: 40,
            ),
          );
        },
      );
    } catch (e) {
      return Container(
        height: height,
        width: width,
        color: AppColors.primaryDark.withOpacity(0.1),
        child: const Icon(
          Icons.image_not_supported,
          color: Colors.grey,
          size: 40,
        ),
      );
    }
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
        Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _UiTokens.headingText,
                letterSpacing: 0.1,
              ),
            ),
          ],
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
            Icons.announcement_outlined,
            Icons.announcement,
            'Announcements',
          ),
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

  List<Widget> get _screens => [
    _HomeContent(key: _homeKey, userName: _userName, onNavigateToTab: _goToTab),
    const StudentAnnouncementsScreen(),
    StudentEventsScreen(
      initialTabIndex: _eventsSubTab,
      jumpToken: _eventsJumpToken,
    ),
    const StudentOrganizationsScreen(),
    StudentProfileScreen(
      onViewAllRegistrations: () => _goToTab(2, eventsSubTab: 1),
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

  // Cached future for registered events – prevents duplicate queries.
  Future<List<EventModel>>? _registeredEventsFuture;

  @override
  void initState() {
    super.initState();
    _refreshRegisteredEvents();

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

  // Refresh the cached future for registered events.
  void _refreshRegisteredEvents() {
    setState(() {
      _registeredEventsFuture = _fetchRegisteredEvents();
    });
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
    _refreshRegisteredEvents();
    // Also force rebuild of UI to reflect any other changes.
    setState(() {});
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

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'TBA';
    final date = timestamp.toDate();
    return DateFormat('MMM dd, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = widget.userName.isNotEmpty
        ? widget.userName
        : user?.displayName ?? user?.email?.split('@').first ?? 'Student';

    return Container(
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
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userId', isEqualTo: user?.uid)
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
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

          // ⭐ COUNTDOWN SECTION – using the cached future
          SliverToBoxAdapter(
            child: FutureBuilder<List<EventModel>>(
              future: _registeredEventsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Matches the loaded state's 240px height so this section
                  // doesn't visibly jump/reflow once data arrives.
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: SkeletonLoader(count: 1, height: 220),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final events = snapshot.data!;
                if (events.isEmpty) {
                  return const SizedBox.shrink();
                }

                return SizedBox(
                  height: 240, // Increased from 150
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 400,
                          child: CountdownWidget(event: event),
                        ),
                      );
                    },
                  ),
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
                onAction: () => widget.onNavigateToTab(2, eventsSubTab: 1),
              ),
            ),
          ),

          // Upcoming Events - Horizontal Scroll Cards
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('events')
                  .where('date', isGreaterThanOrEqualTo: Timestamp.now())
                  .orderBy('date', descending: false)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: SkeletonLoader(count: 2, height: 120),
                  );
                }

                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: UpriseErrorState(message: 'Could not load events.'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: UpriseEmptyState(
                      icon: Icons.calendar_today_outlined,
                      title: 'No upcoming events',
                      subtitle:
                          'Check back later for new events from your organizations.',
                    ),
                  );
                }

                final events = snapshot.data!.docs;

                return SizedBox(
                  height: 240,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final doc = events[index];
                      final eventData = EventModel.fromFirestore(doc);
                      final data = doc.data() as Map<String, dynamic>;
                      final bannerUrl = data['bannerUrl'] as String? ?? '';
                      final eventDate = data['date'] as Timestamp?;
                      final formattedDate = _formatDate(eventDate);

                      return GestureDetector(
                        onTap: () => _navigateToEventDetail(eventData),
                        child: Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: _UiTokens.card(),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bannerUrl.isNotEmpty
                                  ? Base64Image(
                                      base64String: bannerUrl,
                                      height: 100,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      height: 100,
                                      width: double.infinity,
                                      color: AppColors.primaryDark.withOpacity(
                                        0.1,
                                      ),
                                      child: const Icon(
                                        Icons.image_not_supported,
                                        color: Colors.grey,
                                        size: 40,
                                      ),
                                    ),
                              Padding(
                                padding: const EdgeInsets.all(11),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['title'] ?? 'Untitled Event',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _UiTokens.headingText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            formattedDate,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            data['startTime'] ?? 'TBA',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: Colors.grey.shade600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            data['location'] ?? 'TBA',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: Colors.grey.shade600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                      );
                    },
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
                onAction: () => widget.onNavigateToTab(1),
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

          const SliverToBoxAdapter(child: SizedBox(height: 84)),
        ],
      ),
    );
  }
}
