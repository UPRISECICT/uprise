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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../student/student_login.dart';
import 'guest_announcements_screen.dart';
import 'guest_auth_service.dart'; // GuestMode enum
import 'guest_calendar_screen.dart';
import 'guest_digital_id_notice.dart';
import 'guest_events_screen.dart';
import 'guest_merchandise_screen.dart';
import 'guest_profile_screen.dart';

// ─────────────────────────────────────────────────────────────
//  THEME CONSTANTS
// ─────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFFBE4700);
const _kPrimaryBg = Color(0xFFF5E3D9);

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
            color: Colors.black.withOpacity(0.08),
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
                              ? _kPrimary.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? _kPrimary : Colors.black38,
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
                          color: isActive ? _kPrimary : Colors.black38,
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
//  CATEGORY COLOUR MAP
// ─────────────────────────────────────────────────────────────
const _catColors = <String, Color>{
  'Workshop': Color(0xFF8B5CF6),
  'Seminar': Color(0xFF3B82F6),
  'Competition': Color(0xFFEF4444),
  'General Assembly': Color(0xFFF97316),
  'Social': Color(0xFFEC4899),
  'Outreach': Color(0xFF10B981),
  'Sports': Color(0xFF14B8A6),
  'Academic': Color(0xFF6366F1),
  'Technical': Color(0xFF06B6D4),
  'Cultural': Color(0xFFD946EF),
};
Color _catColor(String cat) => _catColors[cat] ?? const Color(0xFF6B7280);

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
      backgroundColor: const Color(0xFFF0F2F5),
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
                    color: _kPrimary,
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
                    color: _kPrimary,
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
                  color: _kPrimary,
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
                        color: const Color(0xFF059669).withOpacity(0.4),
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
                        color: _kPrimary,
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

          if (_loadingFeed) ...[
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _kPrimary)),
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
                  ? const _EmptySection(
                      icon: Icons.calendar_today_outlined,
                      message: 'No upcoming events right now.',
                    )
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
                            child: _EventCard(
                              item: events[i],
                              timeAgo: _timeAgo(events[i].timestamp),
                              onTap: () => _switchTab(2),
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
                child: _EmptySection(
                  icon: Icons.campaign_outlined,
                  message: 'No announcements yet.',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AnnouncementCard(
                      item: announcements[i],
                      timeAgo: _timeAgo(announcements[i].timestamp),
                      onOrgTap: () => _switchTab(1),
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
              color: _kPrimary,
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
          color: outlined ? Colors.transparent : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: outlined ? color.withOpacity(0.5) : color.withOpacity(0.2),
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
//  ANNOUNCEMENT FEED CARD  (Facebook-post style)
// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
//  SHARED CARD IMAGE BANNER  (full-width, gradient placeholder)
// ─────────────────────────────────────────────────────────────
class _CardImageBanner extends StatelessWidget {
  final String imageBase64; // may be empty — shows placeholder
  final String orgName; // used to pick placeholder gradient
  final String badgeLabel; // e.g. "NEW" / "POPULAR" / "UPCOMING"
  final Color badgeColor;
  final double height;

  const _CardImageBanner({
    required this.imageBase64,
    required this.orgName,
    required this.badgeLabel,
    required this.badgeColor,
    this.height = 190,
  });

  // Deterministic gradient from the org name hash
  List<Color> get _gradientColors {
    final hash = orgName.hashCode.abs();
    const palettes = [
      [Color(0xFF1A237E), Color(0xFF283593)],
      [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      [Color(0xFF880E4F), Color(0xFFC2185B)],
      [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      [Color(0xFF0D47A1), Color(0xFF1565C0)],
      [Color(0xFF37474F), Color(0xFF546E7A)],
      [Color(0xFFBF360C), Color(0xFFE64A19)],
      [Color(0xFF006064), Color(0xFF00838F)],
    ];
    return palettes[hash % palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: real image or gradient placeholder ──
          if (imageBase64.isNotEmpty)
            _tryDecodeImage(imageBase64, height)
          else
            _GradientPlaceholder(
              colors: _gradientColors,
              initial: orgName.isNotEmpty ? orgName[0].toUpperCase() : '?',
            ),

          // ── Subtle bottom scrim so text below stays readable ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.35), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Status badge top-left ──────────────────────────
          if (badgeLabel.isNotEmpty)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _tryDecodeImage(String b64, double height) {
    try {
      final bytes = base64Decode(b64);
      return Image.memory(
        bytes,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

class _GradientPlaceholder extends StatelessWidget {
  final List<Color> colors;
  final String initial;
  const _GradientPlaceholder({required this.colors, required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w900,
            color: Colors.white.withOpacity(0.12),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ANNOUNCEMENT FEED CARD
// ─────────────────────────────────────────────────────────────
class _AnnouncementCard extends StatefulWidget {
  final _FeedItem item;
  final String timeAgo;
  final VoidCallback onOrgTap;

  const _AnnouncementCard({
    required this.item,
    required this.timeAgo,
    required this.onOrgTap,
  });

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;

  String get _badgeLabel {
    if (widget.item.isPinned) return 'PINNED';
    final diff = DateTime.now().difference(widget.item.timestamp);
    if (diff.inHours < 24) return 'NEW';
    return '';
  }

  Color get _badgeColor {
    if (widget.item.isPinned) return _kPrimary;
    return const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full-width image / placeholder ────────────────
          _CardImageBanner(
            imageBase64: item.imageBase64,
            orgName: item.orgName,
            badgeLabel: _badgeLabel,
            badgeColor: _badgeColor,
            height: 200,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Org row ────────────────────────────────
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      size: 13,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${item.orgName} · ${widget.timeAgo}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.audience
                        .split(',')
                        .map((s) => s.trim())
                        .contains('CICT Only'))
                      _MiniChip(label: 'CICT', color: const Color(0xFF1565C0)),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Title ──────────────────────────────────
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                ),

                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666666),
                      height: 1.5,
                    ),
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  if (!_expanded && item.body.length > 140)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = true),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'See more',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 14),

                // ── Action row ─────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onOrgTap,
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'View Announcement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _kPrimaryBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kPrimary.withAlpha(64)),
                      ),
                      child: const Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: _kPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE4E6EA)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EVENT FEED CARD  (image-first, matches reference design)
// ─────────────────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  final _FeedItem item;
  final String timeAgo;
  final VoidCallback onTap;

  const _EventCard({
    required this.item,
    required this.timeAgo,
    required this.onTap,
  });

  String get _badgeLabel {
    if (item.isSoon) return 'UPCOMING';
    final diff = DateTime.now().difference(item.timestamp);
    if (diff.inHours < 48) return 'NEW';
    // Rough "popular" signal: recently created events in high-traffic categories
    if (['Competition', 'General Assembly', 'Sports'].contains(item.category))
      return 'POPULAR';
    return '';
  }

  Color get _badgeColor {
    switch (_badgeLabel) {
      case 'UPCOMING':
        return const Color(0xFFF59E0B);
      case 'NEW':
        return const Color(0xFF059669);
      case 'POPULAR':
        return const Color(0xFF8B5CF6);
      default:
        return _kPrimary;
    }
  }

  String _formatEventDate(DateTime dt) {
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

  @override
  Widget build(BuildContext context) {
    final catColor = _catColor(item.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.09),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full-width image / gradient placeholder ────
            _CardImageBanner(
              imageBase64: item.imageBase64,
              orgName: item.orgName,
              badgeLabel: _badgeLabel,
              badgeColor: _badgeColor,
              height: 190,
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Date + time ──────────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: catColor,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          item.eventDate != null
                              ? _formatEventDate(item.eventDate!)
                              : 'Date TBA',
                          style: TextStyle(
                            fontSize: 12,
                            color: catColor,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Category dot
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: catColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ── Title ────────────────────────────────
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ── Location ─────────────────────────────
                  if (item.location.isNotEmpty && item.location != 'TBA')
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
                            item.location,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  // ── Description ───────────────────────────
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF666666),
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Action row (full-width button + share) ─
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kPrimaryBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kPrimary.withAlpha(64)),
                        ),
                        child: const Icon(
                          Icons.share_outlined,
                          size: 18,
                          color: _kPrimary,
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
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final int maxLines;

  const _DetailRow({
    required this.icon,
    required this.color,
    required this.text,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color == Colors.grey
                  ? const Color(0xFF666666)
                  : Colors.black87,
              height: 1.4,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MINI CHIP  (audience badge)
// ─────────────────────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
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
      color: const Color(0xFFF0F2F5),
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
                    color: _kPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: _kPrimary,
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
//  EMPTY SECTION  (inline placeholder row)
// ─────────────────────────────────────────────────────────────
class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptySection({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDEF)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kPrimaryBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: _kPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
              height: 1.4,
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
              color: _kPrimaryBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school_rounded, size: 34, color: _kPrimary),
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
                backgroundColor: _kPrimary,
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
            color: _kPrimaryBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _kPrimary),
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
