// lib/screens/guest/guest_home_screen.dart
//
// GUEST MODE – public-only access
// Tabs: Home | Announcements | Events | QR Attendance | Profile
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

import '../../models/event_model.dart';
import '../../widgets/common/countdown_section.dart';
import '../../widgets/common/feed_cards.dart';
import '../../widgets/student/app_colors.dart';
import '../student/student_login.dart';
import 'guest_announcements_screen.dart';
import 'guest_auth_service.dart'; // GuestMode enum
import 'guest_calendar_screen.dart';
import 'guest_digital_id_notice.dart';
import 'guest_events_screen.dart';
import 'guest_merchandise_screen.dart';
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

  // Screens are the same for both modes; the Profile tab handles the
  // authenticated vs visitor distinction internally via GuestProfileScreen.
  List<Widget> get _screens => [
    _GuestHomeContent(mode: widget.mode),
    const GuestAnnouncementsScreen(),
    const GuestEventsScreen(),
    const GuestCalendarScreen(),
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

  void switchTab(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _GuestBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BOTTOM NAV
// ─────────────────────────────────────────────────────────────
class _GuestBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GuestBottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavItem(Icons.campaign_outlined, Icons.campaign_rounded, 'Announcement'),
    _NavItem(
      Icons.calendar_today_outlined,
      Icons.calendar_today_rounded,
      'Events',
    ),
    _NavItem(
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      'Calendar',
    ),
    _NavItem(Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = currentIndex == i;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primaryDark.withAlpha(31)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive
                              ? AppColors.primaryDark
                              : Colors.black38,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isActive ? AppColors.primaryDark : Colors.black38,
                        ),
                      ),
                    ],
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

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

// ─────────────────────────────────────────────────────────────
//  FEED ITEM MODEL  (unified announcement + event)
// ─────────────────────────────────────────────────────────────
enum _FeedType { announcement, event }

class _FeedItem {
  final String id;
  final _FeedType type;
  final String title;
  final String body; // content / description
  final String orgName;
  final String orgInitial;
  final String imageBase64; // announcement image
  final String category; // event category
  final String audience; // Public / CICT Only
  final bool isPinned;
  final DateTime timestamp;
  final DateTime? eventDate;
  final String location;
  final bool isSoon;

  const _FeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.orgName,
    required this.orgInitial,
    required this.imageBase64,
    required this.category,
    required this.audience,
    required this.isPinned,
    required this.timestamp,
    this.eventDate,
    this.location = '',
    this.isSoon = false,
  });
}

// ─────────────────────────────────────────────────────────────
//  HOME CONTENT  (social-media feed)
// ─────────────────────────────────────────────────────────────
class _GuestHomeContent extends StatefulWidget {
  final GuestMode mode;
  const _GuestHomeContent({this.mode = GuestMode.visitor});

  @override
  State<_GuestHomeContent> createState() => _GuestHomeContentState();
}

class _GuestHomeContentState extends State<_GuestHomeContent> {
  bool get _isAuthenticated => widget.mode == GuestMode.authenticated;

  // Feed data
  final List<_FeedItem> _feed = [];
  bool _loadingFeed = true;

  // Firestore streams
  StreamSubscription<QuerySnapshot>? _annSub;
  StreamSubscription<QuerySnapshot>? _evtSub;

  final Map<String, _FeedItem> _annMap = {};
  final Map<String, _FeedItem> _evtMap = {};

  // Default to the most restrictive tier — same logic as
  // guest_events_screen.dart / guest_calendar_screen.dart — so an
  // unregistered/visitor guest, or one not classified BulSUan, never sees
  // Bulsuan-only or CICT/Members-only events in the feed either.
  String _guestClassification = 'Outsider';

  // An event can target more than one audience at once (org side stores
  // them comma-joined in the same field, e.g. "CICT Only, Bulsuan") — a
  // guest can see it if ANY one of the listed audiences would individually
  // allow them.
  bool _singleAudienceAllowed(String audience) {
    switch (audience) {
      case 'BulSUan':
        return _guestClassification == 'BulSUan';
      case 'CICT Only':
      case 'Members Only':
        return false;
      default:
        return true;
    }
  }

  bool _audienceAllowed(String audience) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (values.isEmpty) return true;
    return values.any(_singleAudienceAllowed);
  }

  Future<void> _loadGuestClassification() async {
    final svc = GuestAuthService();
    if (!svc.isAuthenticated || svc.docId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('external_requests')
          .doc(svc.docId)
          .get();
      if (doc.data()?['classification'] == 'BulSUan') {
        _guestClassification = 'BulSUan';
      }
    } catch (_) {}
  }

  // Countdown-for-events data source when authenticated — mirrors
  // guest_registered_events_screen.dart's email+isGuest-keyed query (guest
  // registrations aren't keyed by uid like student's are).
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

      final now = DateTime.now();
      final events = eventDocs
          .where((d) => d.exists)
          .map(EventModel.fromFirestore)
          .where((e) => e.fullDateTime.isAfter(now))
          .toList()
        ..sort((a, b) => a.fullDateTime.compareTo(b.fullDateTime));

      return events;
    } catch (_) {
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGuestClassification().then((_) => _subscribeFeed());
  }

  @override
  void dispose() {
    _annSub?.cancel();
    _evtSub?.cancel();
    super.dispose();
  }

  void _subscribeFeed() {
    // ── Announcements ──────────────────────────────────────
    _annSub = FirebaseFirestore.instance
        .collection('announcements')
        .where('isPublished', isEqualTo: true)
        .where('targetAudience', whereIn: ['Public', 'CICT Only'])
        .snapshots()
        .listen((snap) {
          for (final doc in snap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            if (d['isArchived'] == true) {
              _annMap.remove(doc.id);
              continue;
            }
            final ts = d['timestamp'] as Timestamp?;
            final orgName = (d['authorName'] as String?) ?? 'UPRISE';
            _annMap[doc.id] = _FeedItem(
              id: doc.id,
              type: _FeedType.announcement,
              title: (d['title'] as String?) ?? '',
              body: (d['content'] as String?) ?? '',
              orgName: orgName,
              orgInitial: orgName.isNotEmpty ? orgName[0].toUpperCase() : 'U',
              imageBase64: (d['imageBase64'] as String?) ?? '',
              category: '',
              audience: (d['targetAudience'] as String?) ?? 'Public',
              isPinned: (d['pinned'] as bool?) ?? false,
              timestamp: ts?.toDate() ?? DateTime.now(),
            );
          }
          final ids = snap.docs.map((d) => d.id).toSet();
          _annMap.removeWhere((k, _) => !ids.contains(k));
          _rebuildFeed();
        });

    // ── Events ─────────────────────────────────────────────
    _evtSub = FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snap) {
          for (final doc in snap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final aud = (d['audience'] as String?) ?? 'Public';
            if (!_audienceAllowed(aud)) {
              _evtMap.remove(doc.id);
              continue;
            }
            final dateField = d['date'];
            final evDate = dateField is Timestamp
                ? dateField.toDate()
                : DateTime.now();
            final created = d['createdAt'] as Timestamp?;
            final orgName = (d['orgName'] as String?) ?? 'Organization';
            _evtMap[doc.id] = _FeedItem(
              id: doc.id,
              type: _FeedType.event,
              title: (d['title'] as String?) ?? 'Untitled',
              body: (d['description'] as String?) ?? '',
              orgName: orgName,
              orgInitial: orgName.isNotEmpty ? orgName[0].toUpperCase() : 'O',
              imageBase64: '',
              category: (d['category'] as String?) ?? 'Other',
              audience: aud,
              isPinned: false,
              timestamp: created?.toDate() ?? evDate,
              eventDate: evDate,
              location: (d['location'] as String?) ?? 'TBA',
              isSoon:
                  evDate.difference(DateTime.now()).inDays <= 7 &&
                  evDate.isAfter(DateTime.now()),
            );
          }
          final ids = snap.docs.map((d) => d.id).toSet();
          _evtMap.removeWhere((k, _) => !ids.contains(k));
          _rebuildFeed();
        });
  }

  void _rebuildFeed() {
    if (!mounted) return;

    // Keep events and announcements separate for the two-section layout
    final evts = _evtMap.values.toList()
      ..sort(
        (a, b) =>
            (a.eventDate ?? a.timestamp).compareTo(b.eventDate ?? b.timestamp),
      ); // upcoming first

    final anns = _annMap.values.toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.timestamp.compareTo(a.timestamp); // newest first
      });

    // _feed is still used to gate the loading state
    final all = <_FeedItem>[...evts, ...anns];
    setState(() {
      _feed
        ..clear()
        ..addAll(all);
      _loadingFeed = false;
    });
  }

  List<_FeedItem> get _events => _evtMap.values.toList()
    ..sort(
      (a, b) =>
          (a.eventDate ?? a.timestamp).compareTo(b.eventDate ?? b.timestamp),
    );

  List<_FeedItem> get _announcements => _annMap.values.toList()
    ..sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  void _switchTab(int index) {
    final s = context.findAncestorStateOfType<_GuestHomeScreenState>();
    if (s != null) s.switchTab(index);
  }

  void _showSignInPrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _SignInPromptSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    final announcements = _announcements;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'UPRISE',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 1.5,
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
                      builder: (context) => const GuestMerchandiseScreen(),
                    ),
                  );
                },
              ),
              if (_isAuthenticated)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF059669).withAlpha(102),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 12,
                          color: Color(0xFF059669),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Verified',
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: const Color(0xFFE4E6EA)),
            ),
          ),

          // ── Quick nav chips ───────────────────────────────
          SliverToBoxAdapter(
            child: _QuickNavRow(
              isAuthenticated: _isAuthenticated,
              onEvents: () => _switchTab(2),
              onAnnouncements: () => _switchTab(1),
              onCalendar: () => _switchTab(3),
              onSignIn: _showSignInPrompt,
            ),
          ),

          // ── Countdown — registered events if signed in, else the
          //     soonest public event overall ─────────────────
          SliverToBoxAdapter(
            child: PersonalOrNextEventCountdown(
              fetchMyRegisteredEvents:
                  _isAuthenticated ? _fetchMyRegisteredEvents : null,
            ),
          ),

          if (_loadingFeed) ...[
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryDark),
              ),
            ),
          ] else ...[
            // ════════════════════════════════════════════════
            //  SECTION 1 — UPCOMING EVENTS (horizontal scroll)
            // ════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Upcoming Events',
                actionLabel: 'View all',
                onAction: () => _switchTab(2),
              ),
            ),

            SliverToBoxAdapter(
              child: events.isEmpty
                  ? const SizedBox.shrink()
                  : SizedBox(
                      // card height: 190 image + ~130 content = 320
                      height: 320,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        itemCount: events.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 260,
                            child: FeedEventCard(
                              data: FeedEventCardData(
                                title: events[i].title,
                                orgName: events[i].orgName,
                                imageBase64: events[i].imageBase64,
                                category: events[i].category,
                                location: events[i].location,
                                audience: events[i].audience,
                                eventDate: events[i].eventDate,
                                createdAt: events[i].timestamp,
                              ),
                              onTap: () => _switchTab(2),
                              onShare: () {},
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

            // ════════════════════════════════════════════════
            //  SECTION 2 — ANNOUNCEMENTS (vertical feed)
            // ════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Announcements',
                actionLabel: 'See all',
                onAction: () => _switchTab(1),
              ),
            ),

            if (announcements.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyFeedSection(
                  icon: Icons.campaign_outlined,
                  message: 'No announcements yet.',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FeedAnnouncementCard(
                      data: FeedAnnouncementCardData(
                        title: announcements[i].title,
                        body: announcements[i].body,
                        orgName: announcements[i].orgName,
                        imageBase64: announcements[i].imageBase64,
                        audience: announcements[i].audience,
                        isPinned: announcements[i].isPinned,
                        timestamp: announcements[i].timestamp,
                      ),
                      timeAgo: _timeAgo(announcements[i].timestamp),
                      onTap: () => _switchTab(1),
                      onShare: () {},
                    ),
                  ),
                  childCount: announcements.length,
                ),
              ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  QUICK NAV ROW  (Stories-style horizontal scroll)
// ─────────────────────────────────────────────────────────────
class _QuickNavRow extends StatelessWidget {
  final bool isAuthenticated;
  final VoidCallback onEvents;
  final VoidCallback onAnnouncements;
  final VoidCallback onCalendar;
  final VoidCallback onSignIn;

  const _QuickNavRow({
    required this.isAuthenticated,
    required this.onEvents,
    required this.onAnnouncements,
    required this.onCalendar,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickNavChip(
              icon: Icons.calendar_today_rounded,
              label: 'Events',
              color: AppColors.primaryDark,
              onTap: onEvents,
            ),
            const SizedBox(width: 8),
            _QuickNavChip(
              icon: Icons.campaign_rounded,
              label: 'Announcements',
              color: const Color(0xFF1565C0),
              onTap: onAnnouncements,
            ),
            const SizedBox(width: 8),
            _QuickNavChip(
              icon: Icons.calendar_month_rounded,
              label: 'Calendar',
              color: const Color(0xFF2E7D32),
              onTap: onCalendar,
            ),
            if (!isAuthenticated) ...[
              const SizedBox(width: 8),
              _QuickNavChip(
                icon: Icons.login_rounded,
                label: 'Sign In',
                color: const Color(0xFF6A1B9A),
                onTap: onSignIn,
                outlined: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickNavChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _QuickNavChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withAlpha(26),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: outlined ? color.withAlpha(128) : color.withAlpha(51),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SECTION HEADER  (title + "View all" action)
// ─────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 10),
      child: Row(
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
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: AppColors.primaryDark,
                ),
              ],
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
          _SheetFeatureRow(
            icon: Icons.groups_outlined,
            text: 'Organizations & Clubs',
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
