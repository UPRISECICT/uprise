import 'dart:async';
import '../../../widgets/stat_cards.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uprise/screens/web/admin/activity_logs.dart';
import '../../../auth_service.dart';
import 'admin_login.dart';
import 'organization_management.dart';
import 'student_accounts.dart';
import 'adviser_roles.dart';
import 'event_proposals.dart';
import 'event_calendar.dart';
import 'letter_request.dart';
import 'external_account.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import 'reports_management.dart';
import 'settings.dart';
import 'admin_profile.dart';
import 'export_pdf.dart' show AdminExportPdf;
import 'export_util.dart';
import 'export_excel.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/app_confirmation_dialog.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../services/firestore_collections.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — mirrors student_accounts.dart exactly
// ─────────────────────────────────────────────────────────────────────────────
class UpriseColors {
  // CICT professional scheme: gray is the primary brand color; blue (info,
  // below) and orange (accent) are used sparingly for interactive/highlight
  // moments rather than spread across every element. Deepened to slate-800
  // so the primary reads distinctly richer than the blue/orange accents.
  static const Color primaryDark = Color(0xFF1E293B);
  static const Color primaryLight = Color(0xFF475569);
  static const Color accent = Color(0xFFF97316);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF9FAFB);
  static const Color mediumGray = Color(0xFFE5E7EB);
  static const Color darkGray = Color(0xFF6B7280);
  static const Color charcoal = Color(0xFF111827);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFFB923C);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
}

class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar nav items
// ─────────────────────────────────────────────────────────────────────────────
const List<Map<String, dynamic>> _navItems = [
  {'label': 'Dashboard', 'icon': Icons.dashboard_outlined},
  {'label': 'Org Management', 'icon': Icons.business_outlined},
  {'label': 'Student Accounts', 'icon': Icons.people_outline},
  {'label': 'Adviser Roles', 'icon': Icons.school_outlined},
  {'label': 'Event Proposals', 'icon': Icons.pending_actions_outlined},
  {'label': 'College Event Calendar', 'icon': Icons.calendar_today_outlined},
  {'label': 'Letter Request', 'icon': Icons.mail_outline},
  {'label': 'External Account', 'icon': Icons.link_outlined},
  {'label': 'Reports & Analytics', 'icon': Icons.assessment_outlined},
  {'label': 'Activity Logs', 'icon': Icons.history_outlined},
];

// Sidebar groups: standalone items render directly, grouped items nest
// under a collapsible parent (indices refer to _navItems / _screens).
const List<int> _standaloneTop = [0];
const List<int> _standaloneBottom = [9];
const Map<String, Map<String, dynamic>> _navGroups = {
  'requests': {
    'label': 'Requests',
    'icon': Icons.assignment_outlined,
    'children': [4, 6],
  },
  'org': {
    'label': 'Organization Management',
    'icon': Icons.business_outlined,
    'children': [1, 5, 3, 8],
  },
  'accounts': {
    'label': 'Accounts Management',
    'icon': Icons.manage_accounts_outlined,
    'children': [2, 7],
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar nav — isolated so expand/collapse of a submenu only rebuilds this
// small widget, not the whole dashboard (which would otherwise re-trigger
// every visited screen's build() — and any inline StreamBuilder in them —
// making it look like the active page "refreshed").
// ─────────────────────────────────────────────────────────────────────────────
class _SidebarNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  // Nav index -> live "needs action" count stream. Only indices with a
  // genuine pending/unread concept get an entry — everything else renders
  // with no badge at all. Mirrors the org portal's sidebar badge pattern.
  final Map<int, Stream<int>> badgeStreams;
  const _SidebarNav({
    required this.selectedIndex,
    required this.onSelect,
    this.badgeStreams = const {},
  });

  @override
  State<_SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<_SidebarNav> {
  // Now using a Set to allow multiple groups to be open at once
  Set<String> _openGroups = {};

  // Latest known count per badge index, kept current for the whole
  // lifetime of the sidebar via one persistent subscription each (started
  // in initState, never cancelled/recreated) — read synchronously by both
  // _navTile and _groupHeaderTile. A per-widget StreamBuilder was used
  // here originally, but its subscription only lives as long as that
  // particular badge widget is mounted: expanding a group unmounts the
  // header's combined-badge StreamBuilder and mounts a fresh one on the
  // now-visible individual row, and a brand-new Firestore listener has no
  // value until the next actual change — so the number visibly vanished
  // on expand instead of just relocating. Decoupling "have we ever heard
  // a count" from "is this particular badge currently on screen" fixes it.
  final Map<int, int> _badgeCounts = {};
  final List<StreamSubscription<int>> _badgeSubs = [];
  // The live count as of the moment each index was last opened — a badge
  // is hidden once its live count drops to/stays at this baseline (i.e.
  // everything visible when you opened the page), and only reappears once
  // the live count climbs past it (a genuinely new pending item), not
  // just because the underlying item you already saw is still unresolved.
  // Persisted to SharedPreferences (keyed by uid) — kept only in memory
  // originally, so a reload/restart wiped every dismissal and every badge
  // you'd already opened came right back, even with nothing new pending.
  final Map<int, int> _dismissedAtCount = {};

  String _dismissKey(String uid, int index) =>
      'sidebar_badge_seen_${uid}_$index';

  Future<void> _loadDismissedBaselines() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final loaded = <int, int>{};
    for (final index in widget.badgeStreams.keys) {
      final v = prefs.getInt(_dismissKey(uid, index));
      if (v != null) loaded[index] = v;
    }
    if (mounted && loaded.isNotEmpty) {
      setState(() => _dismissedAtCount.addAll(loaded));
    }
  }

  Future<void> _persistDismissed(int index, int value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissKey(uid, index), value);
  }

  @override
  void initState() {
    super.initState();
    final initialGroup = _groupContaining(widget.selectedIndex);
    if (initialGroup != null) _openGroups.add(initialGroup);
    for (final entry in widget.badgeStreams.entries) {
      _badgeSubs.add(
        entry.value.listen((v) {
          if (mounted) setState(() => _badgeCounts[entry.key] = v);
        }),
      );
    }
    _loadDismissedBaselines();
  }

  @override
  void dispose() {
    for (final s in _badgeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final match = _groupContaining(widget.selectedIndex);
      if (match != null) _openGroups.add(match);
      final baseline = _badgeCounts[widget.selectedIndex] ?? 0;
      _dismissedAtCount[widget.selectedIndex] = baseline;
      if (widget.badgeStreams.containsKey(widget.selectedIndex)) {
        _persistDismissed(widget.selectedIndex, baseline);
      }
    }
  }

  int _visibleCount(int index) {
    final live = _badgeCounts[index] ?? 0;
    final baseline = _dismissedAtCount[index];
    if (baseline != null && live <= baseline) return 0;
    return live;
  }

  int _groupCount(String groupKey) {
    final children = _navGroups[groupKey]!['children'] as List<int>;
    return children.fold<int>(0, (a, i) => a + _visibleCount(i));
  }

  String? _groupContaining(int index) {
    for (final entry in _navGroups.entries) {
      if ((entry.value['children'] as List<int>).contains(index))
        return entry.key;
    }
    return null;
  }

  Widget _badgePill(int count, {bool onSelected = false}) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        // White pill on the selected (already-tinted) row so it stays
        // legible against that lighter background; solid red otherwise —
        // same "needs attention" red as the top-bar notification bell.
        color: onSelected ? Colors.white : const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: GoogleFonts.beVietnamPro(
          color: onSelected ? const Color(0xFFEF4444) : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _navTile(int index, {double indent = 14}) {
    final item = _navItems[index];
    final isSelected = widget.selectedIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSelect(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            vertical: 10,
          ).copyWith(left: indent, right: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? UpriseColors.accent.withAlpha(46)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: UpriseColors.accent.withAlpha(130),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item['icon'] as IconData,
                color: isSelected
                    ? UpriseColors.accent
                    : Colors.white.withAlpha(166),
                size: 17,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['label'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withAlpha(191),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.badgeStreams.containsKey(index))
                _badgePill(_visibleCount(index), onSelected: isSelected),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: UpriseColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupHeaderTile(
    String groupKey,
    String label,
    IconData icon,
    bool expanded,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() {
          // Toggle: if expanded, remove it; if not expanded, add it
          if (expanded) {
            _openGroups.remove(groupKey);
          } else {
            _openGroups.add(groupKey);
          }
        }),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withAlpha(191), size: 17),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    color: Colors.white.withAlpha(179),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!expanded) _badgePill(_groupCount(groupKey)),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                color: Colors.white.withAlpha(166),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final i in _standaloneTop) _navTile(i),
        for (final entry in _navGroups.entries) ...[
          _groupHeaderTile(
            entry.key,
            entry.value['label'] as String,
            entry.value['icon'] as IconData,
            _openGroups.contains(entry.key), // ✅ FIXED: use contains, not ==
          ),
          if (_openGroups.contains(entry.key)) // ✅ FIXED: use contains
            for (final i in entry.value['children'] as List<int>)
              _navTile(i, indent: 30),
        ],
        for (final i in _standaloneBottom) _navTile(i),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shell chrome animation helpers
// ─────────────────────────────────────────────────────────────────────────────
// Fades the active tab's content in on every switch instead of the
// IndexedStack's instant, jarring swap — deliberately animates only this
// wrapper's opacity rather than rebuilding/rekeying the IndexedStack, so
// every screen underneath keeps the exact same "stay mounted, don't
// re-fetch" behavior it already relies on.
class _FadeOnChange extends StatefulWidget {
  final Object watch;
  final Widget child;
  const _FadeOnChange({required this.watch, required this.child});

  @override
  State<_FadeOnChange> createState() => _FadeOnChangeState();
}

class _FadeOnChangeState extends State<_FadeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..value = 1;

  @override
  void didUpdateWidget(covariant _FadeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watch != widget.watch) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: widget.child,
    );
  }
}

// Slow, gentle breathing pulse for the top bar's "live" status dot — a
// static dot next to a live clock read as inert; this makes the "live"
// framing actually visible at a glance.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, this.size = 5});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 1.0,
        end: 0.35,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard shell
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  // Screens are only actually mounted (and start their Firestore queries)
  // the first time their tab is opened, then kept alive in the IndexedStack
  // from then on — otherwise every screen would fire its queries at once on
  // dashboard load instead of spreading that cost out over time.
  final Set<int> _visitedIndices = {0};
  final AuthService _auth = AuthService();
  final GlobalKey _bellKey = GlobalKey();
  // Cached once instead of calling NotificationService.unreadCountStream()
  // inline in build() — this top bar is part of _AdminDashboardState's own
  // build(), which re-runs on every sidebar navigation click (switching
  // _selectedIndex), so an inline call there was tearing down and
  // re-subscribing a live Firestore listener on every single page
  // navigation across the whole admin portal.
  late final Stream<int> _unreadCountStream =
      FirebaseAuth.instance.currentUser != null
      ? NotificationService.unreadCountStream(
          FirebaseAuth.instance.currentUser!.uid,
        )
      : const Stream<int>.empty();
  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Below this width the fixed sidebar doesn't have room to sit next to the
  // content anymore — it collapses into a Drawer opened from a hamburger
  // button instead of squeezing both into a too-narrow viewport.
  static const double _sidebarBreakpoint = 900;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _notifications = [];
  String _adminName = 'Admin User';
  String _adminRole = 'Administrator';
  String _currentDateTime = '';
  String? _adminPhotoUrl;
  String? _adminPhotoBase64;
  late final List<Widget> _screens;

  // Live "needs action" counts for the sidebar's badge pills, keyed by the
  // same _navItems index used everywhere else in this file. Each stream
  // reuses the exact status field its own destination screen already
  // filters on, just counted admin-wide (no orgId scoping, unlike the org
  // portal's version of this same pattern) rather than duplicating new
  // tracking logic.
  late final Map<int, Stream<int>> _badgeStreams = {
    // Event Proposals — pending proposals awaiting admin approval/rejection.
    4: FirebaseFirestore.instance
        .collection('event_proposals')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length),
    // Letter Request — pending or resubmitted-after-revision requests.
    6: FirestoreCollections.letterRequests
        .where('status', whereIn: ['pending', 'resubmitted'])
        .snapshots()
        .map((s) => s.docs.length),
  };

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
    _fetchUnreadNotifications();
    _updateDateTime();
    _screens = [
      DashboardHome(onNavigateToTab: _selectTab),
      const OrganizationManagement(),
      const StudentAccounts(),
      const AdviserRoles(),
      const EventProposals(),
      const EventCalendar(),
      const AdminLetterRequestScreen(),
      const ExternalAccount(),
      const ReportsManagement(),
      const ActivityLogs(),
      const AdminSettings(), // index 10 — settings
      AdminProfile(onProfileUpdated: _fetchAdminData), // index 11 — my profile
    ];
  }

  void _updateDateTime() {
    setState(() {
      _currentDateTime = DateFormat(
        'EEE, MMM d, yyyy • h:mm a',
      ).format(DateTime.now());
    });
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) _updateDateTime();
    });
  }

  Widget _buildAdminAvatar() {
    final initial = Text(
      _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
      style: GoogleFonts.beVietnamPro(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: UpriseColors.primaryDark,
      ),
    );
    if (_adminPhotoBase64 != null && _adminPhotoBase64!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(_adminPhotoBase64!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(child: initial),
        );
      } catch (_) {
        return Center(child: initial);
      }
    }
    if (_adminPhotoUrl != null && _adminPhotoUrl!.isNotEmpty) {
      return Image.network(
        _adminPhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(child: initial),
      );
    }
    return Center(child: initial);
  }

  Future<void> _fetchAdminData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // Matches the fields admin_settings.dart actually writes to
      // users/{uid}: 'fullName' and 'photoBase64' (there is no separate
      // 'admins' collection anywhere else in the app).
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = uDoc.data();
      setState(() {
        _adminName = (data?['fullName'] as String?)?.trim().isNotEmpty == true
            ? data!['fullName'] as String
            : (user.displayName ?? 'Admin User');
        _adminRole = data?['role'] ?? 'Administrator';
        _adminPhotoBase64 = data?['photoBase64'] as String?;
        _adminPhotoUrl = data?['photoUrl'] as String? ?? user.photoURL;
      });
    } catch (_) {
      setState(
        () => _adminName =
            FirebaseAuth.instance.currentUser?.displayName ?? 'Admin User',
      );
    }
  }

  Future<void> _fetchUnreadNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .get();
      final all = snap.docs
          .map(
            (d) => {
              'id': d.id,
              'title': d.data()['title'] ?? 'New Notification',
              'message': d.data()['body'] ?? d.data()['message'] ?? '',
              'timestamp': d.data()['createdAt'],
              'isRead': d.data()['isRead'] ?? false,
              'type': d.data()['type'],
            },
          )
          .toList();
      all.sort((a, b) {
        final ta = a['timestamp'];
        final tb = b['timestamp'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return (tb as Timestamp).compareTo(ta as Timestamp);
      });
      setState(() {
        _notifications = all;
        _unreadNotifications = all.where((n) => n['isRead'] == false).length;
      });
    } catch (_) {}
  }

  Future<void> _markNotificationAsRead(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(id)
          .update({'isRead': true});
      if (mounted) {
        setState(() {
          final idx = _notifications.indexWhere((n) => n['id'] == id);
          if (idx != -1) {
            _notifications[idx] = Map<String, dynamic>.from(_notifications[idx])
              ..['isRead'] = true;
            _unreadNotifications = _notifications
                .where((n) => n['isRead'] == false)
                .length;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _markAllNotificationsAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // Was batching only the notifications already loaded into
      // _notifications (capped at the 50 most recent, see
      // _fetchUnreadNotifications) — an admin with more than 50 unread
      // notifications would have older unread ones sitting outside that
      // window, silently un-touched by "Mark all as read", while the
      // bell's badge (NotificationService.unreadCountStream, unbounded)
      // kept counting them — the badge stayed stuck nonzero after
      // "reading everything". NotificationService.markAllAsRead queries
      // every isRead==false doc for this user directly, no cap.
      await NotificationService.markAllAsRead(uid);
      if (mounted) {
        setState(() {
          _notifications = _notifications
              .map((n) => Map<String, dynamic>.from(n)..['isRead'] = true)
              .toList();
          _unreadNotifications = 0;
        });
        // Re-pull from Firestore right after the write so any mismatch
        // between "what we just wrote" and "what's actually there" (e.g.
        // a write that silently didn't apply to every doc) shows up
        // immediately instead of only on the next natural refresh.
        await _fetchUnreadNotifications();
      }
    } catch (e) {
      // Was silently swallowed — surfacing it is temporary but necessary:
      // the badge staying stuck after "Mark all as read" with no visible
      // error is exactly what an unnoticed Firestore permission-denied (or
      // any other write failure) looks like from the outside.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark notifications as read: $e')),
        );
      }
    }
  }

  // Maps a notification's type to the sidebar tab it's about, so clicking
  // one takes the admin straight to where it happened.
  static const Map<String, int> _notificationTypeToTabIndex = {
    'proposal_submission': 4, // EventProposals
    'letter_submission': 6, // AdminLetterRequestScreen
    'letter_resubmission': 6,
    'report_submission': 8, // ReportsManagement
  };

  void _handleNotificationTap(Map<String, dynamic> n) {
    final index = _notificationTypeToTabIndex[n['type']?.toString()];
    if (index != null) _selectTab(index);
  }

  // -1 is the "Settings" sentinel (maps to _screens[10]) and -2 is the
  // "My Profile" sentinel (maps to _screens[11]) — neither has a slot in
  // _navItems/the sidebar, since both are reached from the top-right
  // profile menu instead.
  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedIndices.add(_screenIndexFor(index));
    });
    // On narrow layouts the sidebar lives in a Drawer — close it after
    // picking a destination instead of leaving it open over the new page.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  int _screenIndexFor(int selectedIndex) {
    if (selectedIndex == -1) return 10;
    if (selectedIndex == -2) return 11;
    return selectedIndex;
  }

  // Reads the bell's real on-screen position (via _bellKey) so any overlay
  // anchored from this can sit consistently right under it, regardless of
  // window width — Flutter's built-in menu-positioning (PopupMenuButton's
  // offset + internal clamping) repositions itself differently depending
  // on how much room is left in the viewport, which is what made the
  // dropdown/"View All" land in inconsistent spots before.
  ({double top, double right, double maxHeight}) _bellAnchor(
    GlobalKey anchorKey, {
    required double preferredHeight,
  }) {
    final bellBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    double top = 76;
    double right = 28;
    if (bellBox != null) {
      final bellTopLeft = bellBox.localToGlobal(Offset.zero);
      final bellSize = bellBox.size;
      top = bellTopLeft.dy + bellSize.height + 12;
      right = (screenSize.width - (bellTopLeft.dx + bellSize.width) - 6).clamp(
        8.0,
        screenSize.width - 360,
      );
    }
    final maxHeight = (screenSize.height - top - 24).clamp(
      200.0,
      preferredHeight,
    );
    return (top: top, right: right, maxHeight: maxHeight);
  }

  void _showNotificationDropdown() {
    final anchor = _bellAnchor(_bellKey, preferredHeight: 480);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: 'Notifications',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim, secAnim) {
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: anchor.top, right: anchor.right),
            child: Material(
              color: Colors.white,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE8ECF0), width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 360,
                  minWidth: 360,
                  maxHeight: anchor.maxHeight,
                ),
                child: _AdminNotificationPanel(
                  notifications: List.from(_notifications),
                  onMarkRead: _markNotificationAsRead,
                  onMarkAllRead: _markAllNotificationsAsRead,
                  onNotificationTap: _handleNotificationTap,
                  onViewAll: () {
                    _showAllNotificationsDialog();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // A proper centered notification-center modal — not just the same
  // 360px corner dropdown stretched taller. Bigger, centered, and animates
  // in with a fade + scale so opening "View all" actually feels like
  // stepping into a fuller view instead of the same quick-glance popup.
  void _showAllNotificationsDialog() {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width < 520 ? screenSize.width - 40 : 460.0;
    final maxHeight = (screenSize.height * 0.78).clamp(420.0, 680.0);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'Notifications',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return Opacity(
          opacity: curved.value,
          child: Transform.scale(
            scale: 0.94 + (0.06 * curved.value),
            child: Center(
              child: Material(
                color: Colors.white,
                elevation: 16,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: dialogWidth,
                    minWidth: dialogWidth,
                    maxHeight: maxHeight,
                  ),
                  child: _AdminNotificationPanel(
                    notifications: List.from(_notifications),
                    onMarkRead: _markNotificationAsRead,
                    onMarkAllRead: _markAllNotificationsAsRead,
                    onNotificationTap: _handleNotificationTap,
                    listMaxHeight: maxHeight - 130,
                    width: dialogWidth,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showProfileMenu() {
    final anchor = _bellAnchor(_profileKey, preferredHeight: 210);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: 'Profile menu',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim, secAnim) {
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: anchor.top, right: anchor.right),
            child: Material(
              color: Colors.white,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE8ECF0), width: 0.5),
              ),
              child: SizedBox(
                width: 200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    _profileMenuItem(Icons.person_outline, 'My Profile', () {
                      Navigator.of(ctx).pop();
                      _selectTab(-2);
                    }),
                    _profileMenuItem(Icons.settings_outlined, 'Settings', () {
                      Navigator.of(ctx).pop();
                      _selectTab(-1);
                    }),
                    const Divider(height: 1, color: Color(0xFFE8ECF0)),
                    const SizedBox(height: 4),
                    _profileMenuItem(Icons.logout_rounded, 'Logout', () {
                      Navigator.of(ctx).pop();
                      _confirmLogout();
                    }, color: const Color(0xFFDC2626)),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profileMenuItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color ?? const Color(0xFF64748B)),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? UpriseColors.charcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminLogin()),
      );
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AppConfirmationDialog(
        title: 'Confirm Logout',
        message: 'Are you sure you want to logout from the admin panel?',
        confirmLabel: 'Logout',
        accentColor: const Color(0xFFDC2626),
        icon: Icons.logout_rounded,
        onConfirm: _logout,
      ),
    );
  }

  String _getCurrentTitle() {
    if (_selectedIndex == -1) return 'Settings';
    if (_selectedIndex == -2) return 'My Profile';
    const titles = [
      'Dashboard',
      'Organization Management',
      'Student Accounts',
      'Adviser Roles',
      'Event Proposals',
      'College Event Calendar',
      'Letter Request',
      'External Account',
      'Reports & Analytics',
      'Activity Logs',
    ];
    return titles[_selectedIndex];
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < _sidebarBreakpoint;

    final content = Expanded(
      // IndexedStack keeps every screen's state alive instead of
      // tearing it down and re-fetching Firestore data from
      // scratch on every tab switch — that re-fetch was the
      // cause of the lag on every click. _FadeOnChange only animates this
      // wrapper's opacity, not the IndexedStack's children/keys, so that
      // behavior is untouched.
      child: _FadeOnChange(
        watch: _selectedIndex,
        child: IndexedStack(
          index: _screenIndexFor(_selectedIndex),
          children: List.generate(
            _screens.length,
            (i) => _visitedIndices.contains(i)
                ? _screens[i]
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    if (isNarrow) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F9FB),
        drawer: Drawer(width: 256, child: _buildSidebar()),
        body: Column(children: [_buildTopBar(isNarrow: true), content]),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FB),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(children: [_buildTopBar(isNarrow: false), content]),
          ),
        ],
      ),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: UpriseColors.primaryDark,
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 20,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Brand panel — flat, same solid fill as the rest of the
          // sidebar (no gradient); the logo and wordmark below carry the
          // polish instead of the panel itself.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 22),
            color: UpriseColors.primaryDark,
            child: Row(
              children: [
                // Soft glow ring behind the logo disc — reads as a subtle
                // halo instead of the logo floating flat on the panel.
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(20),
                      ),
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withAlpha(70),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(55),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.school,
                          color: UpriseColors.primaryDark,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'UPRISE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(60),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Admin Panel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                color: Colors.white.withAlpha(178),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.4,
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

          // Fade-out divider instead of a flat translucent line — echoes
          // the same technique used for section dividers elsewhere in the
          // portal instead of inventing a new one-off treatment here.
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withAlpha(60),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Nav label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'NAVIGATION',
                style: GoogleFonts.beVietnamPro(
                  color: Colors.white.withAlpha(115),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          // Nav items
          Expanded(
            child: _SidebarNav(
              selectedIndex: _selectedIndex,
              onSelect: _selectTab,
              badgeStreams: _badgeStreams,
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar({required bool isNarrow}) {
    return Container(
      // Explicit instead of relying on the child Row's mainAxisSize.max to
      // infer full width — belt-and-suspenders so this can never end up
      // narrower than its Column sibling (the page content) again.
      width: double.infinity,
      height: 68,
      // Matches DashboardHome's own SingleChildScrollView padding
      // (EdgeInsets.fromLTRB(28, 24, 28, 32)) exactly, so the top bar's
      // right edge lines up with the cards/banner/chart below it instead
      // of using an unrelated, slightly-off value of its own.
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE8ECF0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isNarrow) ...[
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              color: UpriseColors.charcoal,
              tooltip: 'Menu',
            ),
            const SizedBox(width: 4),
          ],

          // Page title with accent bar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getCurrentTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: UpriseColors.charcoal,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'CICT Organization Management',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10.5,
                      color: const Color(0xFF9AA5B4),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(),

          // Datetime chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(_DS.radiusPill),
              border: Border.all(color: UpriseColors.primaryDark.withAlpha(60)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 12,
                  color: UpriseColors.primaryDark,
                ),
                const SizedBox(width: 6),
                Text(
                  _currentDateTime,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: UpriseColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Notification bell
          // A plain InkWell driving our own custom-positioned overlay
          // (same as "View All") instead of PopupMenuButton — Flutter's
          // built-in menu positioning clamps/repositions itself to fit the
          // viewport, which made the dropdown land in inconsistent spots
          // depending on window size instead of staying tucked under the
          // bell every time.
          Tooltip(
            message: 'Notifications',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _fetchUnreadNotifications();
                _showNotificationDropdown();
              },
              child: KeyedSubtree(
                key: _bellKey,
                child: StreamBuilder<int>(
                  // Live count so a new notification updates the badge
                  // immediately, without needing to reopen the dropdown.
                  stream: _unreadCountStream,
                  initialData: _unreadNotifications,
                  builder: (context, snapshot) {
                    final unread = snapshot.data ?? _unreadNotifications;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: unread > 0
                                ? UpriseColors.primaryDark.withAlpha(12)
                                : const Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: unread > 0
                                  ? UpriseColors.primaryDark.withAlpha(60)
                                  : const Color(0xFFE8ECF0),
                            ),
                          ),
                          child: Icon(
                            unread > 0
                                ? Icons.notifications_rounded
                                : Icons.notifications_none_rounded,
                            color: unread > 0
                                ? UpriseColors.primaryDark
                                : const Color(0xFF64748B),
                            size: 18,
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            right: -3,
                            top: -3,
                            child: Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFDC2626),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unread > 9 ? '9+' : '$unread',
                                style: GoogleFonts.beVietnamPro(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Divider
          Container(width: 1, height: 28, color: const Color(0xFFE8ECF0)),
          const SizedBox(width: 10),

          // Admin avatar (clickable — opens profile/settings/logout menu)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: _profileKey,
              onTap: _showProfileMenu,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: UpriseColors.primaryDark.withAlpha(50),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildAdminAvatar(),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _adminName,
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: UpriseColors.charcoal,
                        ),
                      ),
                      Text(
                        _adminRole,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          color: const Color(0xFF9AA5B4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF9AA5B4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Home
// ─────────────────────────────────────────────────────────────────────────────
// Replace the entire DashboardHome class with this fixed version:

// Replace the entire DashboardHome class with this fixed version:

class DashboardHome extends StatefulWidget {
  // Lets a panel jump straight to another admin tab — e.g. "Open in Event
  // Proposals" from the Pending Proposals table. Index values match
  // _AdminDashboardState._screens (4 = Event Proposals, 8 = Reports Management).
  final ValueChanged<int>? onNavigateToTab;
  const DashboardHome({super.key, this.onNavigateToTab});
  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

// Pastel bg / solid fg pair per category — same values as
// event_calendar.dart's CategoryColors, so a category's table badge here
// reads as the same color as its calendar chip.
class CategoryColors {
  static const Map<String, Color> bg = {
    'Workshop': Color(0xFFEDE9FE),
    'Seminar': Color(0xFFDBEAFE),
    'Competition': Color(0xFFFEE2E2),
    'General Assembly': Color(0xFFFFEDD5),
    'Social': Color(0xFFFCE7F3),
    'Outreach': Color(0xFFD1FAE5),
    'Sports': Color(0xFFCCFBF1),
    'Academic': Color(0xFFE0E7FF),
    'Technical': Color(0xFFCFFAFE),
    'Cultural': Color(0xFFFAE8FF),
    'Other': Color(0xFFF3F4F6),
  };
  static const Map<String, Color> fg = {
    'Workshop': Color(0xFF6D28D9),
    'Seminar': Color(0xFF1D4ED8),
    'Competition': Color(0xFFB91C1C),
    'General Assembly': Color(0xFFC2410C),
    'Social': Color(0xFFBE185D),
    'Outreach': Color(0xFF047857),
    'Sports': Color(0xFF0F766E),
    'Academic': Color(0xFF4338CA),
    'Technical': Color(0xFF0E7490),
    'Cultural': Color(0xFFA21CAF),
    'Other': Color(0xFF374151),
  };
  static Color getBg(String cat) => bg[cat] ?? bg['Other']!;
  static Color getFg(String cat) => fg[cat] ?? fg['Other']!;
}

class _DashboardHomeState extends State<DashboardHome> {
  int _selectedYear = DateTime.now().year;
  final GlobalKey _yearDropdownKey = GlobalKey();
  String _selectedMonth = '';
  List<int> _chartData = List.filled(12, 0);
  bool _chartLoading = true;

  // Which stat card is driving the panel below it — 0 Org Standings,
  // 1 Events, 2 Pending Proposals, 3 Overdue Reports, or null for
  // no card selected (shows the combined Analytics overview). Tapping the
  // already-selected card again clears it back to null.
  int? _selectedCard;
  // Cached once (not re-created per build) so switching cards back and
  // forth doesn't re-fire this Firestore read every time — see the
  // sidebar submenu fix earlier in this file for the same pattern.
  late final Future<List<_OrgPerformance>> _performanceFuture =
      _loadPerformanceSummary();
  late final Future<_OverdueSummary> _overdueFuture = _loadOverdueReports();

  // Shared orgId → shortName cache for the stat-card drill-down tables
  // (Events, Pending Proposals, Overdue Reports) so switching between them
  // doesn't re-fetch names for orgs already resolved this session.
  final Map<String, String> _dashboardOrgShortNameCache = {};

  Future<void> _ensureOrgShortNames(Iterable<String> orgIds) async {
    final missing = orgIds
        .where(
          (id) => id.isNotEmpty && !_dashboardOrgShortNameCache.containsKey(id),
        )
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    for (var i = 0; i < missing.length; i += 10) {
      final batch = missing.skip(i).take(10).toList();
      try {
        final snap = await FirebaseFirestore.instance
            .collection('organizations')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          _dashboardOrgShortNameCache[doc.id] =
              (doc.data()['shortName'] as String?) ?? '';
        }
      } catch (_) {}
      for (final id in batch) {
        _dashboardOrgShortNameCache.putIfAbsent(id, () => '');
      }
    }
    if (mounted) setState(() {});
  }

  late final Stream<QuerySnapshot> _organizationsStream;
  late final Stream<QuerySnapshot> _eventsStream;
  late final Stream<QuerySnapshot> _proposalsStream;

  // Dedicated streams for the Active Events / Pending Proposals table
  // panels — deliberately NOT the same stream instance as the stat cards
  // above. Firestore always sends the current snapshot immediately to a
  // brand-new .snapshots() listener, but sharing one Stream object
  // between two simultaneously-mounted StreamBuilders doesn't: whichever
  // one attaches second only sees future changes, not the snapshot that
  // already fired for the first — so it hangs on "loading" until the
  // collection actually changes. Lazily created on first use so we're
  // not running extra listeners before the card is ever opened.
  Stream<QuerySnapshot>? _activeEventsTableStream;
  Stream<QuerySnapshot> get _activeEventsTableStreamGetter =>
      _activeEventsTableStream ??= FirebaseFirestore.instance
          .collection('event_proposals')
          .where('status', isEqualTo: 'approved')
          .snapshots();

  Stream<QuerySnapshot>? _pendingProposalsTableStream;
  Stream<QuerySnapshot> get _pendingProposalsTableStreamGetter =>
      _pendingProposalsTableStream ??= FirebaseFirestore.instance
          .collection('event_proposals')
          .where('status', isEqualTo: 'pending')
          .snapshots();

  // Plain calendar years — no academic-year offset to keep in sync with.
  List<int> get _yearOptions {
    final y = DateTime.now().year;
    return [y - 1, y, y + 1];
  }

  String _monthLabel(int index) {
    const m = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return m[index];
  }

  // ── Init ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _selectedMonth = _monthLabel(DateTime.now().month - 1);

    _organizationsStream = FirebaseFirestore.instance
        .collection('organizations')
        .where('status', isEqualTo: 'active')
        .snapshots();
    _eventsStream = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('status', isEqualTo: 'approved')
        .snapshots();
    _proposalsStream = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('status', isEqualTo: 'pending')
        .snapshots();

    _fetchChartData();
  }

  // Overdue reports are never actually stored with a `status: overdue`
  // field — reports_management.dart computes "overdue" client-side, per
  // (org, finished event, report type), by comparing now() against a
  // deadline (event date + 7 days, or an admin override) and whether a
  // submission exists in `reports` for that exact org+event+type. This
  // mirrors that same logic so the count here matches what admins
  // actually see in Reports Management, instead of always reading 0
  // from a `status` value that's never written anywhere.
  Future<_OverdueSummary> _loadOverdueReports() async {
    try {
      final now = DateTime.now();

      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .where('status', isEqualTo: 'approved')
          .get();
      final eventsByOrg = <String, List<Map<String, dynamic>>>{};
      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final orgId = data['orgId']?.toString();
        final date = (data['date'] as Timestamp?)?.toDate();
        if (orgId == null ||
            orgId.isEmpty ||
            date == null ||
            !date.isBefore(now)) {
          continue;
        }
        eventsByOrg.putIfAbsent(orgId, () => []).add({
          'eventId': doc.id,
          'eventDate': date,
          'eventTitle': data['title']?.toString() ?? 'Untitled Event',
        });
      }
      if (eventsByOrg.isEmpty) {
        return const _OverdueSummary(totalOverdue: 0, overdueByOrgName: {});
      }

      // These three don't depend on each other — fetch them concurrently
      // instead of one-after-another so first load isn't the sum of all
      // four round trips.
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('report_deadline_overrides')
            .get(),
        FirebaseFirestore.instance.collection('reports').get(),
        FirebaseFirestore.instance.collection('organizations').get(),
      ]);
      final overridesSnap = results[0];
      final reportsSnap = results[1];
      final orgsSnap = results[2];

      final overrides = <String, DateTime>{};
      for (final doc in overridesSnap.docs) {
        final data = doc.data();
        final type = data['type']?.toString();
        final orgId = data['orgId']?.toString();
        final eventId = data['eventId']?.toString();
        final deadline = (data['deadline'] as Timestamp?)?.toDate();
        if (type == null ||
            orgId == null ||
            eventId == null ||
            eventId.isEmpty ||
            deadline == null) {
          continue;
        }
        overrides['${type}_${orgId}_$eventId'] = deadline;
      }

      // No `.where('type', ...)` here — we need both financial and
      // accomplishment docs, and legacy docs may not have `scope` set at
      // all (treated as event-scoped by default, same as reports_management.dart).
      final submittedKeys = <String>{};
      for (final doc in reportsSnap.docs) {
        final data = doc.data();
        final scope = (data['scope'] ?? 'event').toString();
        if (scope != 'event') continue;
        final type = data['type']?.toString();
        final orgId = data['orgId']?.toString();
        final eventId = data['eventId']?.toString();
        final submittedAt = data['submittedAt'] as Timestamp?;
        if (type == null ||
            orgId == null ||
            orgId.isEmpty ||
            eventId == null ||
            eventId.isEmpty ||
            submittedAt == null) {
          continue;
        }
        submittedKeys.add('${type}_${orgId}_$eventId');
      }

      final orgNames = {
        for (final doc in orgsSnap.docs)
          doc.id: (doc.data()['name'] as String?) ?? 'Organization',
      };
      final orgShortNames = {
        for (final doc in orgsSnap.docs)
          doc.id: (doc.data()['shortName'] as String?) ?? '',
      };

      var total = 0;
      final byOrg = <String, int>{};
      final items = <_OverdueItem>[];
      for (final entry in eventsByOrg.entries) {
        final orgId = entry.key;
        final orgName = orgNames[orgId] ?? 'Organization';
        final orgShortName = orgShortNames[orgId] ?? '';
        for (final ev in entry.value) {
          final eventId = ev['eventId'] as String;
          final eventDate = ev['eventDate'] as DateTime;
          final eventTitle = ev['eventTitle'] as String;
          for (final type in const ['financial', 'accomplishment']) {
            final key = '${type}_${orgId}_$eventId';
            final deadline =
                overrides[key] ?? eventDate.add(const Duration(days: 7));
            final isSubmitted = submittedKeys.contains(key);
            final isOverdue = !isSubmitted && now.isAfter(deadline);
            if (isOverdue) {
              total++;
              byOrg[orgName] = (byOrg[orgName] ?? 0) + 1;
              items.add(
                _OverdueItem(
                  orgId: orgId,
                  orgName: orgName,
                  orgShortName: orgShortName,
                  eventTitle: eventTitle,
                  type: type,
                  deadline: deadline,
                ),
              );
            }
          }
        }
      }
      items.sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));

      return _OverdueSummary(
        totalOverdue: total,
        overdueByOrgName: byOrg,
        items: items,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[admin_dashboard] _loadOverdueReports error: $e');
      return const _OverdueSummary(totalOverdue: 0, overdueByOrgName: {});
    }
  }

  // Stock DropdownButton centers its menu on the selected item instead of
  // simply dropping below the button, which looks chaotic on a scrolled
  // page (it can land above, mid-screen, or off to the side). This anchors
  // a small custom menu directly under the button instead, same technique
  // as the profile/notification dropdowns.
  void _showYearDropdown() {
    final box =
        _yearDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    double top = 100;
    double left = 100;
    double width = 90;
    if (box != null) {
      final topLeft = box.localToGlobal(Offset.zero);
      width = box.size.width;
      top = topLeft.dy + box.size.height + 6;
      left = topLeft.dx;
    }
    final maxHeight = (screenSize.height - top - 24).clamp(80.0, 220.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: 'Select year',
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, anim, secAnim) {
        return Stack(
          children: [
            Positioned(
              top: top,
              left: left,
              width: width < 72 ? 72 : width,
              child: Material(
                color: Colors.white,
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final y in _yearOptions)
                        InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            if (y != _selectedYear) {
                              setState(() {
                                _selectedYear = y;
                                _fetchChartData();
                              });
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            color: y == _selectedYear
                                ? const Color(0xFFF1F5F9)
                                : Colors.transparent,
                            child: Text(
                              '$y',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: y == _selectedYear
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: y == _selectedYear
                                    ? UpriseColors.primaryDark
                                    : const Color(0xFF374151),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _fetchChartData() {
    setState(() {
      _chartLoading = true;
    });
    final startDate = DateTime(_selectedYear, 1, 1);
    final endDate = DateTime(_selectedYear + 1, 1, 1);

    FirebaseFirestore.instance
        .collection('event_proposals')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .get()
        .then((snap) {
          final counts = List.filled(12, 0);
          for (final doc in snap.docs) {
            final ts = doc.data()['date'] as Timestamp?;
            if (ts == null) continue;
            final idx = ts.toDate().month - 1;
            counts[idx]++;
          }
          if (mounted) {
            setState(() {
              _chartData = counts;
              _chartLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _chartLoading = false);
        });
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;

    // Desktop keeps the dashboard context and KPI cards visible while the
    // data-heavy panel below has its own scroll area. Mobile retains the
    // single-page scroll because its stacked cards need the vertical room.
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(true),
            const SizedBox(height: 20),
            _buildStatCards(true, isTablet),
            const SizedBox(height: 20),
            _buildDynamicPanel(true),
            const SizedBox(height: 20),
            _buildTopOrgsCard(true),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeHeader(false),
              const SizedBox(height: 20),
              _buildStatCards(false, isTablet),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
            child: _buildDynamicPanel(false),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeHeader(bool isMobile) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: const BoxDecoration(
          color: UpriseColors.primaryDark,
          boxShadow: [
            BoxShadow(
              color: Color(0x401E293B),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(12),
                ),
              ),
            ),
            Positioned(
              right: 70,
              bottom: -28,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(8),
                ),
              ),
            ),
            Positioned(
              left: -10,
              bottom: -16,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(7),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLivePill(),
                        const SizedBox(height: 10),
                        Text(
                          'Administrator Dashboard',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'CICT Organization Management  •  Welcome back.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            color: Colors.white.withAlpha(180),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withAlpha(35),
                            ),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLivePill(),
                              const SizedBox(height: 10),
                              Text(
                                'Administrator Dashboard',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'CICT Organization Management  •  Welcome back.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12.5,
                                  color: Colors.white.withAlpha(180),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withAlpha(35),
                            ),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 34,
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

  Widget _buildLivePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live Dashboard',
            style: GoogleFonts.beVietnamPro(
              color: Colors.white.withAlpha(220),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(bool isMobile, bool isTablet) {
    final cardWidgets = [
      _buildStatCard(
        0,
        'Org Standings',
        _organizationsStream,
        UpriseColors.primaryDark,
        Icons.business_rounded,
      ),
      _buildStatCard(
        1,
        'Events',
        _eventsStream,
        UpriseColors.success,
        Icons.event_rounded,
      ),
      _buildStatCard(
        2,
        'Pending Proposals',
        _proposalsStream,
        UpriseColors.warning,
        Icons.pending_actions_rounded,
      ),
      _buildOverdueStatCard(
        3,
        'Overdue Reports',
        UpriseColors.error,
        Icons.warning_amber_rounded,
      ),
    ];

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var card in cardWidgets) ...[card, const SizedBox(height: 10)],
        ],
      );
    }

    final width = MediaQuery.of(context).size.width;
    if (isTablet) {
      return SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cardWidgets.length; i++) ...[
                SizedBox(
                  width: math.min(320.0, width * 0.45),
                  child: cardWidgets[i],
                ),
                if (i != cardWidgets.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cardWidgets.length; i++) ...[
          Expanded(child: cardWidgets[i]),
          if (i != cardWidgets.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  // Adapter over the shared [StatCard] — keeps the cardIndex/stream call
  // shape used by _buildStatCards while the card visual lives in one place.
  Widget _buildStatCard(
    int cardIndex,
    String label,
    Stream<QuerySnapshot> stream,
    Color color,
    IconData icon,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (ctx, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final isSelected = _selectedCard == cardIndex;
        return StatCard(
          adminLayout: true,
          label: label,
          value: loading ? '—' : '${snap.data?.docs.length ?? 0}',
          icon: icon,
          color: color,
          selected: isSelected,
          onTap: () =>
              setState(() => _selectedCard = isSelected ? null : cardIndex),
        );
      },
    );
  }

  // Same card shell as _buildStatCard, but driven by the computed
  // _overdueFuture instead of a simple Firestore count stream.
  // Same adapter, but sourced from the overdue summary future.
  Widget _buildOverdueStatCard(
    int cardIndex,
    String label,
    Color color,
    IconData icon,
  ) {
    return FutureBuilder<_OverdueSummary>(
      future: _overdueFuture,
      builder: (ctx, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final isSelected = _selectedCard == cardIndex;
        return StatCard(
          adminLayout: true,
          label: label,
          value: loading ? '—' : '${snap.data?.totalOverdue ?? 0}',
          icon: icon,
          color: color,
          selected: isSelected,
          onTap: () =>
              setState(() => _selectedCard = isSelected ? null : cardIndex),
        );
      },
    );
  }

  Widget _buildTopOrgsCard(bool isMobile) {
    final now = DateTime.now();
    final semesterStart = now.month >= 8
        ? DateTime(now.year, 8, 1)
        : now.month >= 2
        ? DateTime(now.year, 2, 1)
        : DateTime(now.year - 1, 8, 1);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.leaderboard_rounded,
                  color: UpriseColors.primaryDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Organizations',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: UpriseColors.accent,
                    ),
                  ),
                  Text(
                    'Most active orgs this semester by approved events',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<QuerySnapshot>(
            // Standardized on event_proposals for "approved" counts — this
            // used to read the `events` collection (only populated once an
            // org separately "publishes" an approved proposal), which could
            // disagree with the Active Events stat card and Org Standings
            // table elsewhere on this same dashboard.
            future: FirebaseFirestore.instance
                .collection('event_proposals')
                .where('status', isEqualTo: 'approved')
                .where(
                  'date',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(semesterStart),
                )
                .get(),
            builder: (ctx, evSnap) {
              if (!evSnap.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                );
              }

              // Count events per orgId
              final counts = <String, int>{};
              final orgNames = <String, String>{};
              for (final doc in evSnap.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                final oid = d['orgId']?.toString() ?? '';
                if (oid.isEmpty) continue;
                counts[oid] = (counts[oid] ?? 0) + 1;
                if (!orgNames.containsKey(oid)) {
                  orgNames[oid] = d['orgName']?.toString() ?? oid;
                }
              }

              if (counts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No events found this semester.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                  ),
                );
              }

              final sorted = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final top = sorted.take(isMobile ? 5 : 8).toList();
              final maxCount = top.first.value.toDouble();

              return Column(
                children: top.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final orgId = entry.value.key;
                  final count = entry.value.value;
                  final name = orgNames[orgId] ?? orgId;
                  final ratio = count / maxCount;

                  final rankColor = rank == 1
                      ? const Color(0xFFEAB308)
                      : rank == 2
                      ? const Color(0xFF94A3B8)
                      : rank == 3
                      ? const Color(0xFFCD7C37)
                      : const Color(0xFFCBD5E1);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '#$rank',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: rankColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircleAvatar(
                            backgroundColor: UpriseColors.primaryDark.withAlpha(
                              26,
                            ),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: UpriseColors.primaryDark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A202C),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  color: UpriseColors.primaryDark,
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: UpriseColors.primaryDark.withAlpha(20),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$count event${count > 1 ? 's' : ''}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: UpriseColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activity Overview',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: UpriseColors.accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'All event proposals per month this year',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Proposals',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  MouseRegion(
                    key: _yearDropdownKey,
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _showYearDropdown,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFFF8F9FB),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_selectedYear',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: const Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: Color(0xFF9AA5B4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 230,
            child: _chartLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: UpriseColors.primaryDark,
                    ),
                  )
                : _ActivityBarChart(
                    data: _chartData,
                    selectedMonth: _selectedMonth,
                    monthLabel: _monthLabel,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared: export + row-detail helpers for the table panels below ──
  Widget _panelHeader({
    required String title,
    required String subtitle,
    dynamic Function(String format)? onExport,
    VoidCallback? onBack,
    Widget? extraAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onBack,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Back to Overview',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: UpriseColors.accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
                ],
              ),
            ),
            if (onExport != null || extraAction != null) ...[
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (extraAction != null) ...[
                    extraAction,
                    if (onExport != null) const SizedBox(width: 10),
                  ],
                  if (onExport != null) AdminExportButton(onSelected: onExport),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Shared custom table row/header — matches the row-list style used
  // elsewhere in the app (student_accounts.dart etc.) instead of Flutter's
  // stock DataTable, which looked out of place here.
  // Matches the header-strip convention used by every other admin page's
  // table (event_proposals.dart etc.): amber-tinted background, brand-orange
  // bottom border, 20/13 padding — instead of the plain unstyled text row
  // this used to be.
  Widget _customTableHeader(
    List<MapEntry<String, int>> columns, {
    Set<int> rightAlign = const {},
    Set<int> centerAlign = const {},
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: columns[i].value,
              child: Text(
                columns[i].key,
                textAlign: rightAlign.contains(i)
                    ? TextAlign.right
                    : centerAlign.contains(i)
                    ? TextAlign.center
                    : TextAlign.left,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.7,
                ),
              ),
            ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  // Row is a StatefulBuilder (not a plain function-built widget) so it can
  // track its own hover flag and animate a highlight + left accent bar —
  // the old InkWell only gave a flat hoverColor with no left accent, and
  // couldn't also honor the "leader" tint on rank #1's row at the same time.
  Widget _customTableRow({
    required List<Widget> cells,
    required List<int> flexes,
    required VoidCallback onTap,
    bool isLast = false,
    bool alternate = false,
    bool highlight = false,
  }) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final baseColor = highlight
            ? const Color(0xFFFFFBEB)
            : (alternate ? const Color(0xFFFBFCFE) : Colors.white);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setLocalState(() => hovering = true),
          onExit: (_) => setLocalState(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: hovering ? const Color(0xFFF8F9FB) : baseColor,
                border: Border(
                  left: BorderSide(
                    color: hovering
                        ? UpriseColors.primaryDark
                        : Colors.transparent,
                    width: 3,
                  ),
                  bottom: isLast
                      ? BorderSide.none
                      : const BorderSide(color: Color(0xFFF1F5F9)),
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < cells.length; i++)
                    Expanded(flex: flexes[i], child: cells[i]),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    transform: Matrix4.translationValues(
                      hovering ? 2 : 0,
                      0,
                      0,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: hovering
                          ? UpriseColors.primaryDark
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cellText(
    String text, {
    bool bold = false,
    Color? color,
    bool numeric = false,
  }) {
    final child = Text(
      text,
      overflow: TextOverflow.ellipsis,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      style: GoogleFonts.beVietnamPro(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color ?? UpriseColors.charcoal,
      ),
    );
    return numeric
        ? Align(alignment: Alignment.centerRight, child: child)
        : child;
  }

  // Gold/silver/bronze circle for the top 3 rows of Organization Standings —
  // a plain "1/2/3" read the same as every other rank number, so the
  // leaderboard's top performers didn't stand out at a glance.
  static const Map<int, List<Color>> _rankMedalColors = {
    1: [Color(0xFFFEF3C7), Color(0xFFB45309)],
    2: [Color(0xFFF1F5F9), Color(0xFF64748B)],
    3: [Color(0xFFFFEDD5), Color(0xFFC2410C)],
  };

  Widget _rankBadge(int rank) {
    final colors = _rankMedalColors[rank];
    if (colors == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: Text(
            '$rank',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF9AA5B4),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors[0], shape: BoxShape.circle),
        child: Icon(Icons.emoji_events_rounded, size: 13, color: colors[1]),
      ),
    );
  }

  // Deterministic colored initials circle so the standings table reads more
  // like a roster than a spreadsheet — same hash-a-palette approach as
  // _categoryBadgeColor, just keyed on org name instead of event category.
  static const List<Color> _avatarPalette = [
    Color(0xFFB45309),
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFFC2410C),
    Color(0xFF4F46E5),
  ];

  Widget _orgAvatar(String name) {
    final trimmed = name.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
              .join();
    final color =
        _avatarPalette[trimmed.hashCode.abs() % _avatarPalette.length];
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // Small pill for count columns (Approved/Pending/Merch Items) — a plain
  // number blended into every other numeric column, so at a glance you
  // couldn't tell "0 pending" (good) from "12 pending" (needs attention)
  // without reading each digit. Zero renders as a plain dash to stay quiet.
  Widget _cellCountPill(
    int count, {
    required Color color,
    required IconData icon,
  }) {
    if (count <= 0) {
      return Align(
        alignment: Alignment.center,
        child: Text(
          '—',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFFCBD5E1),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: GoogleFonts.beVietnamPro(
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

  // [bg] overrides the default alpha-tinted background with a fixed color
  // — used for category badges, which use the same pastel bg / solid fg
  // pair as the calendar's category chips instead of a tint of [color].
  Widget _cellBadge(String text, Color color, {Color? bg}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg ?? color.withAlpha(24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Future<void> _exportTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required String fileNamePrefix,
    required String format,
  }) async {
    final ts = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      if (format == 'excel') {
        final bytes = AdminExportExcel.generateStyledTable(
          title: title,
          headers: headers,
          rows: rows,
        );
        final fileName = '${fileNamePrefix}_$ts.xlsx';
        await AdminExportUtil.saveBytes(
          bytes,
          fileName,
          mimeType: xlsxMimeType,
        );
        if (mounted) {
          AppToast.success(context, 'Exported $fileName');
        }
        return;
      }
      final bytes = await AdminExportPdf.generateTablePdf(
        title: title,
        headers: headers,
        rows: rows,
      );
      final fileName = '${fileNamePrefix}_$ts.pdf';
      await AdminExportUtil.saveBytes(
        bytes,
        fileName,
        mimeType: 'application/pdf',
      );
      if (mounted) {
        AppToast.success(context, 'Exported $fileName');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Export failed: $e');
      }
    }
  }

  // Sends one reminder per organization (not one per overdue row) covering
  // everything currently listed for that org, and points them at the
  // Submission Tracker tab in Reports Management — the actual screen
  // that tracks these obligations — rather than a vague "check your
  // reports" message.
  Future<void> _sendOverdueReminders(List<_OverdueItem> items) async {
    final byOrg = <String, List<_OverdueItem>>{};
    for (final item in items) {
      byOrg.putIfAbsent(item.orgId, () => []).add(item);
    }

    var sent = 0;
    var failed = 0;
    for (final entry in byOrg.entries) {
      final orgItems = entry.value;
      final orgName = orgItems.first.orgName;
      final count = orgItems.length;
      try {
        await NotificationService.sendToOrgMembers(
          orgId: entry.key,
          title: 'Overdue report reminder',
          body:
              'Your organization has $count report${count == 1 ? '' : 's'} '
              'overdue in the Submission Tracker (Reports Management). '
              'Please submit as soon as possible.',
          type: 'deadline_reminder',
        );
        sent++;
      } catch (e) {
        failed++;
        // ignore: avoid_print
        print('[admin_dashboard] reminder failed for $orgName: $e');
      }
    }

    await activity_log.ActivityLogger.log(
      action:
          'Sent overdue report reminders to $sent organization${sent == 1 ? '' : 's'}',
      module: 'Reports',
      severity: 'info',
      details: {'orgCount': sent, 'reportCount': items.length},
    );

    if (mounted) {
      final message = failed == 0
          ? 'Reminder sent to $sent organization${sent == 1 ? '' : 's'}.'
          : 'Sent to $sent organization${sent == 1 ? '' : 's'}, $failed failed.';
      if (failed == 0) {
        AppToast.success(context, message);
      } else {
        AppToast.warning(context, message);
      }
    }
  }

  // Short scalar values (Rank, Proposals, Dates, Category…) render as a
  // neutral 2-up stat grid; anything longer (Description) renders as a
  // plain full-width section below it. A per-field colored icon+tint was
  // tried here first and read as too busy for what's meant to be a quick
  // reference card — this keeps one accent color and lets layout (not
  // color) do the organizing.
  bool _isCompactField(String value) =>
      value.length <= 18 && !value.contains('\n');

  Widget _statBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF1F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9AA5B4),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: UpriseColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9AA5B4),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13.5,
              color: UpriseColors.charcoal,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDetailBody(List<MapEntry<String, String>> fields) {
    final compact = fields.where((f) => _isCompactField(f.value)).toList();
    final long = fields.where((f) => !_isCompactField(f.value)).toList();
    final widgets = <Widget>[];
    for (var i = 0; i < compact.length; i += 2) {
      final second = i + 1 < compact.length ? compact[i + 1] : null;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _statBox(compact[i].key, compact[i].value)),
              const SizedBox(width: 10),
              Expanded(
                child: second != null
                    ? _statBox(second.key, second.value)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    if (compact.isNotEmpty && long.isNotEmpty) {
      widgets.add(const SizedBox(height: 6));
    }
    for (final f in long) {
      widgets.add(_detailRow(f.key, f.value));
    }
    return widgets;
  }

  // Generic detail dialog: a title, a list of label/value rows, and an
  // optional "jump to the real screen" button for actions this dashboard
  // doesn't perform itself (approve/reject, send reminder, etc.). Used by
  // every table's row-tap across the dashboard (Org Standings, Events,
  // Pending Proposals, Overdue Reports) — one redesign here covers all of
  // them instead of a plain title+rows+Close block that looked the same
  // no matter which table it was opened from.
  void _showDetailDialog({
    required String title,
    required List<MapEntry<String, String>> fields,
    String? actionLabel,
    int? navigateToTabIndex,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      UpriseColors.primaryDark,
                      UpriseColors.primaryDark.withAlpha(225),
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(_DS.radiusLg),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Tooltip(
                        message: 'Close',
                        waitDuration: const Duration(milliseconds: 400),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildDetailBody(fields),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (actionLabel != null && navigateToTabIndex != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onNavigateToTab?.call(navigateToTabIndex);
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                        label: Text(
                          actionLabel,
                          style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: UpriseColors.primaryDark,
                        ),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UpriseColors.primaryDark,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_DS.radiusSm),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.beVietnamPro(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Loading/empty placeholder variant — just a centered message, no
  // header strip needed.
  Widget _tableCardSimple(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_DS.radiusLg),
      border: Border.all(color: const Color(0xFFE8ECF0)),
      boxShadow: _DS.cardShadow,
    ),
    child: child,
  );

  // `header` (title/subtitle/export) keeps its own padding; `table` (the
  // colored header strip + rows) spans edge-to-edge and relies on this
  // Container's clipBehavior to pick up the same rounded corners — matching
  // the header-strip + bordered-card convention used by every other admin
  // page's table instead of a single uniformly-padded block.
  Widget _tableCard({required Widget header, required Widget table}) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final tableParts = table is Column ? table.children : <Widget>[table];
    final tableHeader = tableParts.isEmpty
        ? const SizedBox.shrink()
        : tableParts.first;
    final tableRows = tableParts.length > 1
        ? tableParts.sublist(1)
        : const <Widget>[];

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: header,
          ),
          tableHeader,
          if (isDesktop)
            Expanded(child: ListView(children: tableRows))
          else
            ...tableRows,
        ],
      ),
    );
  }

  // ── Analytics overview — the default panel when no card is selected ──
  // On desktop this sits inside the dashboard's Expanded content area (see
  // build()), which gives it a fixed, viewport-dependent height — a bare
  // Column here doesn't shrink or scroll, so on a slightly shorter window
  // the chart card's natural height (padding + header + the chart's own
  // 230px) can come out a few pixels taller than what's actually
  // available, which renders as a hard "BOTTOM OVERFLOWED" banner instead
  // of just scrolling the extra bit out of view.
  Widget _buildAnalyticsOverview(bool isMobile) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildChartCard(isMobile)],
      ),
    );
  }

  Widget _buildDynamicPanel(bool isMobile) {
    switch (_selectedCard) {
      case 0:
        return _buildActiveOrgsPanel();
      case 1:
        return _buildActiveEventsPanel();
      case 2:
        return _buildPendingProposalsPanel();
      case 3:
        return _buildOverdueReportsPanel();
      default:
        return _buildAnalyticsOverview(isMobile);
    }
  }

  // ── "Org Standings" card → full standings table ───────────────────
  Widget _buildActiveOrgsPanel() {
    return FutureBuilder<List<_OrgPerformance>>(
      future: _performanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            Center(
              child: CircularProgressIndicator(color: UpriseColors.primaryDark),
            ),
          );
        }
        final items = [...(snapshot.data ?? [])]
          ..sort((a, b) => b.proposals.compareTo(a.proposals));
        if (items.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(
              Icons.dashboard_outlined,
              'No organization data available',
            ),
          );
        }

        return _tableCard(
          header: _panelHeader(
            title: 'Organization Standings',
            subtitle:
                'All active organizations ranked by proposal activity, ${items.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Organization Standings',
              headers: const [
                'Rank',
                'Organization',
                'Proposals',
                'Approved',
                'Pending',
                'Merch Items',
              ],
              rows: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    items[i].orgName,
                    '${items[i].proposals}',
                    '${items[i].approvedEvents}',
                    '${items[i].pendingProposals}',
                    '${items[i].merchItems}',
                  ],
              ],
              fileNamePrefix: 'org_standings',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(
                const [
                  MapEntry('#', 1),
                  MapEntry('Organization', 4),
                  MapEntry('Proposals', 2),
                  MapEntry('Approved', 2),
                  MapEntry('Pending', 2),
                  MapEntry('Merch Items', 2),
                ],
                rightAlign: const {2},
                centerAlign: const {3, 4, 5},
              ),
              for (var i = 0; i < items.length; i++)
                _customTableRow(
                  flexes: const [1, 4, 2, 2, 2, 2],
                  isLast: i == items.length - 1,
                  alternate: i.isOdd,
                  highlight: i == 0,
                  onTap: () => _showDetailDialog(
                    title: items[i].orgName,
                    fields: [
                      MapEntry('Rank', '#${i + 1}'),
                      MapEntry('Proposals', '${items[i].proposals}'),
                      MapEntry('Approved Events', '${items[i].approvedEvents}'),
                      MapEntry(
                        'Pending Proposals',
                        '${items[i].pendingProposals}',
                      ),
                      MapEntry('Merch Items', '${items[i].merchItems}'),
                    ],
                  ),
                  cells: [
                    _rankBadge(i + 1),
                    Row(
                      children: [
                        _orgAvatar(items[i].orgName),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Tooltip(
                            message: items[i].orgName,
                            child: _cellText(
                              items[i].orgShortName.isNotEmpty
                                  ? items[i].orgShortName
                                  : items[i].orgName,
                              bold: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _cellText(
                      '${items[i].proposals}',
                      numeric: true,
                      bold: true,
                    ),
                    _cellCountPill(
                      items[i].approvedEvents,
                      color: UpriseColors.success,
                      icon: Icons.check_circle_rounded,
                    ),
                    _cellCountPill(
                      items[i].pendingProposals,
                      color: UpriseColors.warning,
                      icon: Icons.hourglass_top_rounded,
                    ),
                    _cellCountPill(
                      items[i].merchItems,
                      color: const Color(0xFF7C3AED),
                      icon: Icons.shopping_bag_rounded,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ── "Events" card → approved-events table ─────────────────────────
  Widget _buildActiveEventsPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activeEventsTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            Center(
              child: CircularProgressIndicator(color: UpriseColors.primaryDark),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(Icons.event_outlined, 'No active events'),
          );
        }

        final rows =
            docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return {
                'title': (d['title'] as String?) ?? 'Untitled',
                'orgName': (d['orgName'] as String?) ?? '—',
                'orgId': (d['orgId'] as String?) ?? '',
                'category': (d['category'] as String?) ?? '—',
                'location': (d['location'] as String?) ?? 'TBA',
                'audience': (d['audience'] as String?) ?? '—',
                'description':
                    (d['description'] as String?) ?? 'No description provided.',
                'startTime': (d['startTime'] ?? d['time'] ?? '').toString(),
                'endTime': (d['endTime'] ?? '').toString(),
                'date': (d['date'] as Timestamp?)?.toDate(),
              };
            }).toList()..sort((a, b) {
              final da = a['date'] as DateTime?;
              final db = b['date'] as DateTime?;
              if (da == null || db == null) return 0;
              return da.compareTo(db);
            });

        _ensureOrgShortNames(rows.map((r) => r['orgId'] as String? ?? ''));

        String fmtDate(DateTime? d) =>
            d != null ? DateFormat('MMM d, yyyy').format(d) : 'TBA';

        return _tableCard(
          header: _panelHeader(
            title: 'Events',
            subtitle: 'Approved events, ${rows.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Events',
              headers: const [
                'Title',
                'Organization',
                'Category',
                'Date',
                'Location',
              ],
              rows: [
                for (final r in rows)
                  [
                    r['title'] as String,
                    r['orgName'] as String,
                    r['category'] as String,
                    fmtDate(r['date'] as DateTime?),
                    r['location'] as String,
                  ],
              ],
              fileNamePrefix: 'events',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Title', 3),
                MapEntry('Organization', 3),
                MapEntry('Category', 2),
                MapEntry('Date', 2),
                MapEntry('Location', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 3, 2, 2, 2],
                  isLast: i == rows.length - 1,
                  alternate: i.isOdd,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['title'] as String,
                    fields: [
                      MapEntry('Organization', rows[i]['orgName'] as String),
                      MapEntry('Category', rows[i]['category'] as String),
                      MapEntry(
                        'Date',
                        rows[i]['date'] != null
                            ? DateFormat(
                                'MMMM d, yyyy',
                              ).format(rows[i]['date'] as DateTime)
                            : 'TBA',
                      ),
                      MapEntry(
                        'Time',
                        (rows[i]['endTime'] as String).isNotEmpty
                            ? '${rows[i]['startTime']} – ${rows[i]['endTime']}'
                            : '${rows[i]['startTime']}',
                      ),
                      MapEntry('Location', rows[i]['location'] as String),
                      MapEntry('Audience', rows[i]['audience'] as String),
                      MapEntry('Description', rows[i]['description'] as String),
                    ],
                  ),
                  cells: [
                    _cellText(rows[i]['title'] as String, bold: true),
                    Tooltip(
                      message: rows[i]['orgName'] as String,
                      child: _cellText(
                        (_dashboardOrgShortNameCache[rows[i]['orgId']] ?? '')
                                .isNotEmpty
                            ? _dashboardOrgShortNameCache[rows[i]['orgId']]!
                            : rows[i]['orgName'] as String,
                      ),
                    ),
                    _cellBadge(
                      rows[i]['category'] as String,
                      CategoryColors.getFg(rows[i]['category'] as String),
                      bg: CategoryColors.getBg(rows[i]['category'] as String),
                    ),
                    _cellText(fmtDate(rows[i]['date'] as DateTime?)),
                    _cellText(rows[i]['location'] as String),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ── "Pending Proposals" card → review-queue table ────────────────
  Widget _buildPendingProposalsPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _pendingProposalsTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            Center(
              child: CircularProgressIndicator(color: UpriseColors.primaryDark),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(
              Icons.pending_actions_outlined,
              'No pending proposals',
            ),
          );
        }

        final rows =
            docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return {
                'title': (d['title'] as String?) ?? 'Untitled',
                'orgName': (d['orgName'] as String?) ?? '—',
                'orgId': (d['orgId'] as String?) ?? '',
                'category': (d['category'] as String?) ?? '—',
                'location': (d['location'] as String?) ?? 'TBA',
                'description':
                    (d['description'] as String?) ?? 'No description provided.',
                'submittedByEmail': (d['submittedByEmail'] as String?) ?? '—',
                'eventDate': (d['date'] as Timestamp?)?.toDate(),
                'createdAt': (d['createdAt'] as Timestamp?)?.toDate(),
              };
            }).toList()..sort((a, b) {
              final ca = a['createdAt'] as DateTime?;
              final cb = b['createdAt'] as DateTime?;
              if (ca == null || cb == null) return 0;
              return cb.compareTo(ca);
            });

        _ensureOrgShortNames(rows.map((r) => r['orgId'] as String? ?? ''));

        String fmtDate(DateTime? d) =>
            d != null ? DateFormat('MMM d, yyyy').format(d) : '—';

        return _tableCard(
          header: _panelHeader(
            title: 'Pending Proposals',
            subtitle:
                'Awaiting your review, ${rows.length} total. Click a row to view details and open it for approval.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Pending Proposals',
              headers: const [
                'Title',
                'Organization',
                'Event Date',
                'Submitted',
              ],
              rows: [
                for (final r in rows)
                  [
                    r['title'] as String,
                    r['orgName'] as String,
                    fmtDate(r['eventDate'] as DateTime?),
                    fmtDate(r['createdAt'] as DateTime?),
                  ],
              ],
              fileNamePrefix: 'pending_proposals',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Title', 3),
                MapEntry('Organization', 3),
                MapEntry('Event Date', 2),
                MapEntry('Submitted', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 3, 2, 2],
                  isLast: i == rows.length - 1,
                  alternate: i.isOdd,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['title'] as String,
                    fields: [
                      MapEntry('Organization', rows[i]['orgName'] as String),
                      MapEntry('Category', rows[i]['category'] as String),
                      MapEntry(
                        'Event Date',
                        rows[i]['eventDate'] != null
                            ? DateFormat(
                                'MMMM d, yyyy',
                              ).format(rows[i]['eventDate'] as DateTime)
                            : 'TBA',
                      ),
                      MapEntry('Location', rows[i]['location'] as String),
                      MapEntry(
                        'Submitted By',
                        rows[i]['submittedByEmail'] as String,
                      ),
                      MapEntry(
                        'Submitted On',
                        fmtDate(rows[i]['createdAt'] as DateTime?),
                      ),
                      MapEntry('Description', rows[i]['description'] as String),
                    ],
                    actionLabel: 'Open in Event Proposals →',
                    navigateToTabIndex: 4,
                  ),
                  cells: [
                    _cellText(rows[i]['title'] as String, bold: true),
                    Tooltip(
                      message: rows[i]['orgName'] as String,
                      child: _cellText(
                        (_dashboardOrgShortNameCache[rows[i]['orgId']] ?? '')
                                .isNotEmpty
                            ? _dashboardOrgShortNameCache[rows[i]['orgId']]!
                            : rows[i]['orgName'] as String,
                      ),
                    ),
                    _cellText(fmtDate(rows[i]['eventDate'] as DateTime?)),
                    _cellText(fmtDate(rows[i]['createdAt'] as DateTime?)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ── "Overdue Reports" card → per-obligation table ────────────────
  Widget _buildOverdueReportsPanel() {
    return FutureBuilder<_OverdueSummary>(
      future: _overdueFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            Center(
              child: CircularProgressIndicator(color: UpriseColors.primaryDark),
            ),
          );
        }
        final items = snapshot.data?.items ?? [];
        if (items.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(
              Icons.task_alt_outlined,
              'No overdue reports — every org is caught up',
            ),
          );
        }

        String typeLabel(String t) =>
            t == 'financial' ? 'Financial' : 'Accomplishment';

        return _tableCard(
          header: _panelHeader(
            title: 'Overdue Reports',
            subtitle:
                'Financial & accomplishment reports past their deadline, ${items.length} total. Click a row to open it for follow-up.',
            onBack: () => setState(() => _selectedCard = null),
            extraAction: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ElevatedButton.icon(
                onPressed: () => _sendOverdueReminders(items),
                icon: const Icon(Icons.notifications_active_outlined, size: 16),
                label: Text(
                  'Send Reminder to All',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: UpriseColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Overdue Reports',
              headers: const [
                'Organization',
                'Event',
                'Type',
                'Deadline',
                'Days Overdue',
              ],
              rows: [
                for (final it in items)
                  [
                    it.orgName,
                    it.eventTitle,
                    typeLabel(it.type),
                    DateFormat('MMM d, yyyy').format(it.deadline),
                    '${it.daysOverdue}',
                  ],
              ],
              fileNamePrefix: 'overdue_reports',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(
                const [
                  MapEntry('Organization', 3),
                  MapEntry('Event', 3),
                  MapEntry('Type', 2),
                  MapEntry('Deadline', 2),
                  MapEntry('Days Overdue', 2),
                ],
                rightAlign: const {4},
              ),
              for (var i = 0; i < items.length; i++)
                _customTableRow(
                  flexes: const [3, 3, 2, 2, 2],
                  isLast: i == items.length - 1,
                  alternate: i.isOdd,
                  onTap: () => _showDetailDialog(
                    title: items[i].eventTitle,
                    fields: [
                      MapEntry('Organization', items[i].orgName),
                      MapEntry('Report Type', typeLabel(items[i].type)),
                      MapEntry(
                        'Deadline',
                        DateFormat('MMMM d, yyyy').format(items[i].deadline),
                      ),
                      MapEntry(
                        'Days Overdue',
                        '${items[i].daysOverdue} day${items[i].daysOverdue == 1 ? '' : 's'}',
                      ),
                    ],
                    actionLabel: 'Open in Reports Management →',
                    navigateToTabIndex: 8,
                  ),
                  cells: [
                    Tooltip(
                      message: items[i].orgName,
                      child: _cellText(
                        items[i].orgShortName.isNotEmpty
                            ? items[i].orgShortName
                            : items[i].orgName,
                        bold: true,
                      ),
                    ),
                    _cellText(items[i].eventTitle),
                    _cellBadge(
                      typeLabel(items[i].type),
                      items[i].type == 'financial'
                          ? UpriseColors.info
                          : UpriseColors.warning,
                    ),
                    _cellText(
                      DateFormat('MMM d, yyyy').format(items[i].deadline),
                    ),
                    _cellText(
                      '${items[i].daysOverdue}d',
                      color: UpriseColors.error,
                      bold: true,
                      numeric: true,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<List<_OrgPerformance>> _loadPerformanceSummary() async {
    try {
      final snaps = await Future.wait([
        FirebaseFirestore.instance.collection('event_proposals').get(),
        FirebaseFirestore.instance
            .collection('products')
            .where('isArchived', isEqualTo: false)
            .get(),
        FirebaseFirestore.instance
            .collection('organizations')
            .where('status', isEqualTo: 'active')
            .get(),
      ]);
      final proposalsSnap = snaps[0];
      final productsSnap = snaps[1];
      final activeOrgsSnap = snaps[2];

      final proposalStats = <String, Map<String, dynamic>>{};
      final orderStats = <String, Map<String, dynamic>>{};
      // Seed with every active org first so orgs with zero proposals/orders
      // still show up — otherwise this list falls out of sync with the
      // "Active Orgs" stat card, which counts straight from `organizations`.
      final orgIds = <String>{for (final doc in activeOrgsSnap.docs) doc.id};
      final orgNameMap = <String, String>{
        for (final doc in activeOrgsSnap.docs)
          doc.id: (doc.data()['name'] as String?) ?? 'Organization',
      };
      final orgShortNameMap = <String, String>{
        for (final doc in activeOrgsSnap.docs)
          doc.id: (doc.data()['shortName'] as String?) ?? '',
      };

      for (final doc in proposalsSnap.docs) {
        final data = doc.data();
        final orgId = (data['orgId'] as String?)?.trim() ?? '';
        if (orgId.isEmpty) continue;
        orgIds.add(orgId);
        final orgName = (data['orgName'] as String?)?.trim() ?? '';
        final stat = proposalStats.putIfAbsent(
          orgId,
          () => {
            'orgName': orgName,
            'proposalCount': 0,
            'approvedCount': 0,
            'pendingCount': 0,
          },
        );
        if (orgName.isNotEmpty) {
          stat['orgName'] = orgName;
        }
        stat['proposalCount'] = (stat['proposalCount'] as int) + 1;
        final status = (data['status'] as String?)?.toLowerCase();
        if (status == 'approved') {
          stat['approvedCount'] = (stat['approvedCount'] as int) + 1;
        } else if (status == 'pending') {
          stat['pendingCount'] = (stat['pendingCount'] as int) + 1;
        }
      }

      for (final doc in productsSnap.docs) {
        final data = doc.data();
        final orgId = (data['orgId'] as String?)?.trim() ?? '';
        if (orgId.isEmpty) continue;
        orgIds.add(orgId);
        final stat = orderStats.putIfAbsent(orgId, () => {'itemCount': 0});
        stat['itemCount'] = (stat['itemCount'] as int) + 1;
      }

      final missingOrgIds = orgIds.where((id) {
        final stat = proposalStats[id];
        final hasName =
            (stat?['orgName'] as String?)?.isNotEmpty == true ||
            orgNameMap.containsKey(id);
        return !hasName;
      }).toList();

      for (var i = 0; i < missingOrgIds.length; i += 10) {
        final batch = missingOrgIds.skip(i).take(10).toList();
        if (batch.isEmpty) continue;
        final orgDocs = await FirebaseFirestore.instance
            .collection('organizations')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in orgDocs.docs) {
          orgNameMap[doc.id] =
              (doc.data()['name'] as String?) ?? 'Organization';
          orgShortNameMap[doc.id] = (doc.data()['shortName'] as String?) ?? '';
        }
      }

      return orgIds.map((orgId) {
        final proposalStat = proposalStats[orgId];
        final merchStat = orderStats[orgId];
        final orgName =
            (proposalStat?['orgName'] as String?)?.isNotEmpty == true
            ? proposalStat!['orgName'] as String
            : orgNameMap[orgId] ?? 'Organization';
        return _OrgPerformance(
          orgId: orgId,
          orgName: orgName,
          orgShortName: orgShortNameMap[orgId] ?? '',
          proposals: proposalStat?['proposalCount'] as int? ?? 0,
          approvedEvents: proposalStat?['approvedCount'] as int? ?? 0,
          pendingProposals: proposalStat?['pendingCount'] as int? ?? 0,
          merchItems: merchStat?['itemCount'] as int? ?? 0,
        );
      }).toList();
    } catch (e, s) {
      // ignore: avoid_print
      print('[admin_dashboard] _loadPerformanceSummary error: $e');
      // ignore: avoid_print
      print(s);
      return <_OrgPerformance>[];
    }
  }

  Widget _emptyPlaceholder(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26, color: const Color(0xFF9AA5B4)),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF9AA5B4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat card config helper
// ─────────────────────────────────────────────────────────────────────────────
class _StatConfig {
  final String label;
  final Stream<QuerySnapshot> stream;
  final Color color;
  final IconData icon;
  const _StatConfig(this.label, this.stream, this.color, this.icon);
}

class _OrgPerformance {
  final String orgId;
  final String orgName;
  final String orgShortName;
  final int proposals;
  final int approvedEvents;
  final int pendingProposals;
  // Was merchOrders/merchRevenue (summed from the `orders` collection) —
  // merch has no checkout anymore, so order counts/revenue are frozen and
  // meaningless. This now counts the org's active catalog listings instead.
  final int merchItems;

  const _OrgPerformance({
    required this.orgId,
    required this.orgName,
    this.orgShortName = '',
    required this.proposals,
    required this.approvedEvents,
    required this.pendingProposals,
    required this.merchItems,
  });
}

class _OverdueSummary {
  final int totalOverdue;
  final Map<String, int> overdueByOrgName;
  final List<_OverdueItem> items;
  const _OverdueSummary({
    required this.totalOverdue,
    required this.overdueByOrgName,
    this.items = const [],
  });
}

class _OverdueItem {
  final String orgId;
  final String orgName;
  final String orgShortName;
  final String eventTitle;
  final String type; // 'financial' | 'accomplishment'
  final DateTime deadline;
  const _OverdueItem({
    required this.orgId,
    required this.orgName,
    this.orgShortName = '',
    required this.eventTitle,
    required this.type,
    required this.deadline,
  });
  int get daysOverdue => DateTime.now().difference(deadline).inDays;
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification panel widget
// ─────────────────────────────────────────────────────────────────────────────
class _AdminNotificationPanel extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final void Function(Map<String, dynamic> n) onNotificationTap;
  final VoidCallback? onViewAll;
  final double listMaxHeight;
  final double width;

  const _AdminNotificationPanel({
    required this.notifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onNotificationTap,
    this.onViewAll,
    this.listMaxHeight = 400,
    this.width = 380,
  });

  @override
  State<_AdminNotificationPanel> createState() =>
      _AdminNotificationPanelState();
}

class _AdminNotificationPanelState extends State<_AdminNotificationPanel> {
  late List<Map<String, dynamic>> _notifs;

  @override
  void initState() {
    super.initState();
    _notifs = List.from(widget.notifications);
  }

  Future<void> _markRead(String id) async {
    setState(() {
      final idx = _notifs.indexWhere((n) => n['id'] == id);
      if (idx != -1) {
        _notifs[idx] = Map<String, dynamic>.from(_notifs[idx])
          ..['isRead'] = true;
      }
    });
    await widget.onMarkRead(id);
  }

  Future<void> _markAll() async {
    setState(() {
      _notifs = _notifs
          .map((n) => Map<String, dynamic>.from(n)..['isRead'] = true)
          .toList();
    });
    await widget.onMarkAllRead();
  }

  String _timeAgo(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as Timestamp).toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  String _dateGroup(dynamic ts) {
    if (ts == null) return 'Older';
    try {
      final dt = (ts as Timestamp).toDate();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final nDay = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(nDay).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      if (diff < 7) return 'This Week';
      return 'Older';
    } catch (_) {
      return 'Older';
    }
  }

  // Per-type icon + color so the list reads at a glance instead of every
  // row showing the same generic bell — mirrors _notificationTypeToTabIndex
  // in the parent state, just mapped to a look instead of a destination tab.
  static const Map<String, List<Object>> _notifTypeMeta = {
    'proposal_submission': [Icons.description_rounded, Color(0xFF2563EB)],
    'letter_submission': [Icons.mail_rounded, Color(0xFF7C3AED)],
    'letter_resubmission': [Icons.mail_rounded, Color(0xFF7C3AED)],
    'report_submission': [Icons.assignment_rounded, Color(0xFF0891B2)],
  };

  List<Object> _metaFor(String? type) =>
      _notifTypeMeta[type] ??
      const [Icons.notifications_rounded, UpriseColors.primaryDark];

  // Row is a StatefulBuilder (not a plain function-built widget) so it can
  // track its own hover flag, matching the hover treatment already used on
  // the dashboard's table rows instead of the flat, static look this had.
  Widget _buildNotifItem(Map<String, dynamic> n) {
    final isRead = n['isRead'] as bool? ?? false;
    final meta = _metaFor(n['type']?.toString());
    final icon = meta[0] as IconData;
    final color = meta[1] as Color;
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setLocalState(() => hovering = true),
          onExit: (_) => setLocalState(() => hovering = false),
          child: GestureDetector(
            onTap: () {
              if (!isRead) _markRead(n['id'] as String);
              widget.onNotificationTap(n);
              Navigator.of(context).pop();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(15, 12, 18, 12),
              decoration: BoxDecoration(
                color: hovering
                    ? const Color(0xFFF8F9FB)
                    : (isRead ? Colors.white : const Color(0xFFFFFBF5)),
                border: Border(
                  left: BorderSide(
                    color: isRead
                        ? Colors.transparent
                        : UpriseColors.primaryDark,
                    width: 3,
                  ),
                  bottom: const BorderSide(color: Color(0xFFF1F5F9)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withAlpha(isRead ? 16 : 28),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: isRead ? color.withAlpha(160) : color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                n['title']?.toString() ?? 'Notification',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                  color: isRead
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFF1A202C),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _timeAgo(n['timestamp']),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: const Color(0xFF9AA5B4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n['message']?.toString() ?? '',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                            height: 1.45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGroupedItems() {
    const groupOrder = ['Today', 'Yesterday', 'This Week', 'Older'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final n in _notifs) {
      final key = _dateGroup(n['timestamp']);
      groups.putIfAbsent(key, () => []).add(n);
    }
    final widgets = <Widget>[];
    for (final groupKey in groupOrder) {
      final items = groups[groupKey];
      if (items == null || items.isEmpty) continue;
      widgets.add(
        Container(
          width: double.infinity,
          color: const Color(0xFFFAFBFC),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
          child: Text(
            groupKey.toUpperCase(),
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9AA5B4),
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
      for (final n in items) {
        widgets.add(_buildNotifItem(n));
      }
    }
    return widgets;
  }

  Widget _buildFooter() {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setLocalState(() => hovering = true),
          onExit: (_) => setLocalState(() => hovering = false),
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              widget.onViewAll!();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: hovering ? const Color(0xFFFFF7ED) : Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View all notifications',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: UpriseColors.primaryDark,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifs.where((n) => n['isRead'] == false).length;

    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.beVietnamPro(
                    color: const Color(0xFF1A202C),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$unreadCount new',
                      style: GoogleFonts.beVietnamPro(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (unreadCount > 0)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: _markAll,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FB),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.done_all_rounded,
                              size: 14,
                              color: UpriseColors.primaryDark,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Mark all read',
                              style: GoogleFonts.beVietnamPro(
                                color: UpriseColors.primaryDark,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Body
          if (_notifs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF7ED),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 24,
                      color: UpriseColors.primaryDark.withAlpha(140),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "You're all caught up!",
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.listMaxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildGroupedItems(),
                  ),
                ),
              ),
            ),
          // Footer
          if (_notifs.isNotEmpty && widget.onViewAll != null) _buildFooter(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity bar chart — monthly proposal counts via fl_chart. A bar per month
// reads more clearly than a line for discrete counts, and fl_chart owns
// touch/tooltip/scaling, so there's no custom hit-testing math to get wrong.
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityBarChart extends StatelessWidget {
  final List<int> data;
  final String selectedMonth;
  final String Function(int) monthLabel;

  const _ActivityBarChart({
    required this.data,
    required this.selectedMonth,
    required this.monthLabel,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.isEmpty ? 0 : data.reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal < 4 ? 4 : maxVal).toDouble() * 1.25;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxY / 4,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  color: const Color(0xFF9AA5B4),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Default reservedSize (22) is just short of what a 6px top
              // padding plus a fontSize-10 label actually needs — the gap
              // was only ~3px, but fl_chart clips titles to a fixed box
              // instead of growing it, so that shortfall rendered as a
              // "BOTTOM OVERFLOWED" banner across the whole chart.
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final label = monthLabel(v.toInt());
                final isSelected = label == selectedMonth;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? UpriseColors.primaryDark
                          : const Color(0xFF9AA5B4),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A202C),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${monthLabel(group.x)}\n',
              GoogleFonts.beVietnamPro(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              children: [
                TextSpan(
                  text: '${rod.toY.toInt()} proposal(s)',
                  style: GoogleFonts.beVietnamPro(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        barGroups: List.generate(data.length, (i) {
          final isSelected = monthLabel(i) == selectedMonth;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: data[i].toDouble(),
                color: isSelected
                    ? UpriseColors.primaryDark
                    : UpriseColors.primaryDark.withAlpha(110),
                width: 35,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }
}
