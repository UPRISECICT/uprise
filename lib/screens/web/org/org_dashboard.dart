// lib/screens/web/org/org_dashboard.dart
//
// Redesigned to match AdminDashboard pattern exactly:
//  - Gradient welcome header card with icon
//  - 5-column stat cards (icon top-left, count top-right, label bottom)
//  - Line chart with semester dropdown + month pills
//  - Upcoming events panel + Recent activity panel (bottom row)
//  - Sidebar: NAVIGATION label, animated selection, dot indicator, logout button
//  - Top bar: title+subtitle, datetime pill, search, notification PopupMenu, org avatar
//  - Unified "org" role — no officer/adviser split

import 'dart:async';
import '../../../widgets/stat_cards.dart';
import '../../../widgets/app_confirmation_dialog.dart';
import '../../../widgets/app_toast.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:universal_html/html.dart' as html;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/change_password_screen.dart';
import 'org_event_proposals.dart';
import 'org_events_schedule.dart';
import 'org_attendance_qr.dart';
import 'org_registration_forms.dart';
import 'org_certificates.dart';
import 'org_event_analytics.dart';
import 'org_announcements.dart';
import 'org_broadcast.dart';
import 'org_profile.dart';
import 'org_letter_request.dart';
import 'org_reports.dart';
import 'org_finance.dart';
import 'org_merchandise.dart';
import 'org_settings.dart';
import 'export_pdf.dart';
import 'export_util.dart';
import 'export_excel.dart';
import '../../../services/notification_service.dart';
import '../../../services/firestore_collections.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/dashboard_overview_label.dart';
import '../../../services/app_sign_out.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (copied from report.dart for the countdown)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  // Deepened from orange-600 to orange-700 — same reasoning as
  // AdminColors.primaryDark's slate-700 -> slate-800 deepening: a richer,
  // less neon shade that reads as "brand primary" instead of "highlighter."
  static const Color primary = Color(0xFFC2410C);
  static const Color primaryBg = Color(0xFFFDEEE6);

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// OrgColors — org's dominant brand color is orange (mirrors how
// AdminColors' dominant color is gray), balanced with gray for structure,
// blue for interactive/selected moments, and white for surfaces — instead
// of every element being a shade of the same bright orange.
// ─────────────────────────────────────────────────────────────────────────────
class OrgColors {
  static const Color primaryDark = Color(0xFFC2410C);
  static const Color primaryLight = Color(0xFFEA580C);
  // Blue, not another orange — this is what makes a selected nav item or
  // highlighted moment actually pop against the orange-dominant chrome
  // instead of blending into it.
  static const Color accent = Color(0xFF2563EB);
  static const Color white = Color(0xFFFFFFFF);
  // Matches the 0xFFFBFCFE Scaffold background every other org screen
  // uses (finance, letter request, proposals, merchandise, etc.) instead
  // of a slightly different near-white.
  static const Color surface = Color(0xFFFBFCFE);
  static const Color lightGray = Color(0xFFF8F9FB);
  static const Color border = Color(0xFFE8ECF0);
  static const Color borderSoft = Color(0xFFE2E6EA);
  static const Color darkGray = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF9AA5B4);
  static const Color charcoal = Color(0xFF1A202C);
  static const Color textMid = Color(0xFF374151);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFFB923C);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF2563EB);
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown widget (stateful – updates itself, no parent rebuild)
// ─────────────────────────────────────────────────────────────────────────────
class _CountdownCard extends StatefulWidget {
  final DateTime eventDate;
  final String eventLabel;
  const _CountdownCard({required this.eventDate, required this.eventLabel});

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  Duration _remaining = Duration.zero;
  Timer? _timer;

  void _updateRemaining() {
    final diff = widget.eventDate.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  @override
  void didUpdateWidget(covariant _CountdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventDate != widget.eventDate) {
      _updateRemaining();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateRemaining(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    final d = _remaining.inDays;
    final h = _remaining.inHours % 24;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OrgColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OrgColors.border),
        boxShadow: _DS.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _DS.primaryBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: _DS.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expired
                    ? '${widget.eventLabel} has started!'
                    : 'Countdown to: ${widget.eventLabel}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: OrgColors.charcoal,
                ),
              ),
              Text(
                DateFormat('MMMM d, yyyy — h:mm a').format(widget.eventDate),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: OrgColors.darkGray,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!expired)
            Row(
              children: [
                _CountUnit(value: d, label: 'DAYS'),
                _Colon(),
                _CountUnit(value: h, label: 'HRS'),
                _Colon(),
                _CountUnit(value: m, label: 'MIN'),
                _Colon(),
                _CountUnit(value: s, label: 'SEC'),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: OrgColors.success.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Event Started!',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: OrgColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountUnit extends StatelessWidget {
  final int value;
  final String label;
  const _CountUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 48,
        height: 42,
        decoration: BoxDecoration(
          color: _DS.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          value.toString().padLeft(2, '0'),
          style: GoogleFonts.beVietnamPro(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 9,
          color: OrgColors.darkGray,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );
}

class _Colon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      ':',
      style: GoogleFonts.beVietnamPro(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: _DS.primary,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar nav items
// ─────────────────────────────────────────────────────────────────────────────
const List<Map<String, dynamic>> _navItems = [
  {'label': 'Dashboard', 'icon': Icons.dashboard_outlined},
  {'label': 'Event Proposals', 'icon': Icons.description_outlined},
  {'label': 'Events & Schedules', 'icon': Icons.calendar_month_outlined},
  {'label': 'Mark Attendance', 'icon': Icons.qr_code_scanner_outlined},
  {'label': 'Certificates', 'icon': Icons.verified_outlined},
  {'label': 'Analytics', 'icon': Icons.bar_chart_outlined},
  {'label': 'Announcements', 'icon': Icons.campaign_outlined},
  {'label': 'Messages', 'icon': Icons.chat_bubble_outline_rounded},
  {'label': 'Org Profile', 'icon': Icons.people_outline},
  {'label': 'Letter Requests', 'icon': Icons.mail_outline},
  {'label': 'Report Submissions', 'icon': Icons.summarize_outlined},
  {'label': 'Finance', 'icon': Icons.account_balance_wallet_outlined},
  {'label': 'Merchandise Catalog', 'icon': Icons.shopping_bag_outlined},
  {'label': 'Registration Forms', 'icon': Icons.assignment_outlined},
];

// Sidebar groups: standalone items render directly, grouped items nest
// under a collapsible parent (indices refer to _navItems / _screens).
// Org Profile (8) is deliberately absent — it's user-scoped now, reached
// only via the profile dropdown's "My Profile" entry.
// Regrouped into six labeled sections (Communication / Events & Requests /
// Event Analytics / Reports / Attendance & Certificates / Finance & Merch)
// per the portal-wide IA restructure — Dashboard is the only item left
// standalone at the top; everything else now lives under one of the six
// group headers below. This only changes which group each index is listed
// under — _navItems/_screens themselves keep their original index order,
// so _selectedIndex and every "jump to tab N" call site elsewhere in this
// file are untouched.
const List<int> _standaloneTop = [0];
const List<int> _standaloneBottom = [];
const Map<String, Map<String, dynamic>> _navGroups = {
  'communication': {
    'label': 'Communication',
    'icon': Icons.forum_outlined,
    'children': [6, 7],
  },
  'events': {
    'label': 'Events & Requests',
    'icon': Icons.event_note_outlined,
    // Proposals → Schedules → Registration mirrors the intended event
    // lifecycle (Proposal → Approval → Events & Schedules → Registration);
    // Letter Requests is a separate, non-event workflow, so it sits last
    // rather than interrupting that sequence.
    'children': [1, 2, 13, 9],
  },
  'analytics': {
    'label': 'Event Analytics',
    'icon': Icons.bar_chart_outlined,
    'children': [5],
  },
  'reports': {
    'label': 'Reports',
    'icon': Icons.summarize_outlined,
    'children': [10],
  },
  'attendance': {
    'label': 'Attendance & Certificates',
    'icon': Icons.fact_check_outlined,
    'children': [3, 4],
  },
  'finance': {
    'label': 'Finance & Merch',
    'icon': Icons.storefront_outlined,
    'children': [11, 12],
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
  // genuine pending/unread concept get an entry (see _buildBadgeStreams in
  // _OrgDashboardState) — everything else renders with no badge at all.
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
  final Set<String> _openGroups = {};

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
      if (match != null) {
        _openGroups.add(match);
      }
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
        // White pill on the selected (already-white-tinted) row so it stays
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
            // White, not a second accent hue — this sits directly on the
            // orange sidebar, so the selected state is a lighter/brighter
            // version of the same surface instead of clashing with it.
            color: isSelected ? Colors.white.withAlpha(38) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: Colors.white.withAlpha(90), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item['icon'] as IconData,
                color: isSelected ? Colors.white : Colors.white.withAlpha(166),
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
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
            _openGroups.contains(entry.key),
          ),
          if (_openGroups.contains(entry.key))
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
// OrgDashboard shell
// ─────────────────────────────────────────────────────────────────────────────
class OrgDashboard extends StatefulWidget {
  const OrgDashboard({super.key});

  @override
  State<OrgDashboard> createState() => _OrgDashboardState();
}

class _OrgDashboardState extends State<OrgDashboard> {
  int _selectedIndex = 0;
  // Mirrors _selectedIndex, but as a listenable — _screens below is built
  // once (see _buildScreens) and its widget instances are reused for the
  // rest of the session, so a plain int prop passed at construction time
  // would never update on tab switches. Screens that need to react to
  // becoming hidden/visible (e.g. EventManagementScreen stopping its QR
  // camera when the org navigates away) listen to this instead.
  final ValueNotifier<int> _selectedIndexNotifier = ValueNotifier(0);
  // Screens are only actually mounted (and start their Firestore queries)
  // the first time their tab is opened, then kept alive in the IndexedStack
  // from then on — otherwise all 15 screens would fire their queries at
  // once on dashboard load instead of spreading that cost out over time.
  final Set<int> _visitedIndices = {0};
  final GlobalKey _bellKey = GlobalKey();
  final GlobalKey _profileKey = GlobalKey();
  // Opens/closes the sidebar Drawer on narrow layouts — see build()'s
  // isMobile branch and the hamburger button in _buildTopBar().
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _orgId = '';
  String _orgName = '';
  String _orgShortName = '';
  String _orgEmail = '';
  String? _orgLogoUrl;
  bool _isLoading = true;
  String? _loadError;
  String _currentDateTime = '';

  final TextEditingController _searchController = TextEditingController();
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _notifications = [];
  // Cached once instead of calling NotificationService.unreadCountStream()
  // inline in build() — this top bar is part of _OrgDashboardState's own
  // build(), which re-runs on every sidebar navigation click, every 60s
  // clock tick (_updateDateTime), and every notification action's own
  // setState, so an inline call there was tearing down and re-subscribing
  // a live Firestore listener constantly. A freshly re-subscribed listener
  // isn't guaranteed to get pushed a fresh value right away, which is what
  // let the bell badge get stuck showing a stale count after actions like
  // "Mark all as read" that should have brought it to 0. Same fix already
  // applied to admin_dashboard.dart's identical bell.
  late final Stream<int> _unreadCountStream =
      FirebaseAuth.instance.currentUser != null
      ? NotificationService.unreadCountStream(
          FirebaseAuth.instance.currentUser!.uid,
        )
      : const Stream<int>.empty();

  late List<Widget> _screens;
  bool _screensBuilt = false;

  // Live "needs action" counts for the sidebar's badge pills — only built
  // once _orgId is known (first accessed from _buildSidebar, which only
  // renders once loading has finished), keyed by the same _navItems index
  // used everywhere else in this file. Each stream reuses the exact query
  // its own destination screen already runs, so no new tracking logic is
  // introduced here beyond the badge counting itself.
  late final Map<int, Stream<int>> _badgeStreams = {
    // Event Proposals — pending proposals awaiting admin action.
    1: FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: _orgId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length),
    // Certificates — event batches with certs generated but not fully sent.
    // Archived batches are excluded — archiving is the org's own "done,
    // hide it" action, and a batch stuck with a leftover draft placeholder
    // (from before that cleanup bug was fixed) could otherwise count as
    // "pending" forever with nothing actionable actually visible.
    4: FirebaseFirestore.instance
        .collection('certificates')
        .where('orgId', isEqualTo: _orgId)
        .snapshots()
        .map((s) {
          final records = s.docs
              .map((d) => CertificateRecord.fromFirestore(d))
              .toList();
          final batches = CertificateBatch.groupByEvent(records);
          return batches
              .where((b) => !b.isArchived && b.sentCount < b.totalRecipients)
              .length;
        }),
    // Messages — conversations with an unread reply from a student.
    7: FirebaseFirestore.instance
        .collection('conversations')
        .where('orgId', isEqualTo: _orgId)
        .where('unreadForOrg', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.length),
    // Letter Requests — awaiting admin action.
    9: FirestoreCollections.letterRequests
        .where('orgId', isEqualTo: _orgId)
        .where('isArchived', isEqualTo: false)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length),
    // Merchandise — GCash orders awaiting payment verification.
    12: FirebaseFirestore.instance
        .collection('orders')
        .where('orgId', isEqualTo: _orgId)
        .where('paymentMethod', isEqualTo: 'GCash')
        .where('paymentVerified', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length),
  };

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _loadOrgData();
  }

  void _updateDateTime() {
    if (!mounted) return;
    setState(() {
      _currentDateTime = DateFormat(
        'EEE, MMM d, yyyy  \u2022  h:mm a',
      ).format(DateTime.now());
    });
    Future.delayed(const Duration(seconds: 60), _updateDateTime);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _selectedIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadOrgData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        if (mounted) {
          setState(() {
            _loadError = 'User record not found. Please sign in again.';
            _isLoading = false;
          });
        }
        return;
      }

      final userData = userDoc.data()!;
      final orgId =
          (userData['orgId'] as String?) ??
          (userData['organizationId'] as String?);

      final bool needsChange =
          (userData['isFirstLogin'] == true) ||
          (userData['mustChangePassword'] == true) ||
          (userData['needsPasswordChange'] == true) ||
          (userData['firstLogin'] == true);

      if (needsChange) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ChangePasswordScreen(userId: user.uid, isFirstLogin: true),
          ),
        );
        return;
      }

      if (orgId == null || orgId.isEmpty) {
        if (mounted) {
          setState(() {
            _loadError =
                'This account is not linked to an organization.\nContact your administrator.';
            _isLoading = false;
          });
        }
        return;
      }

      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();

      if (!orgDoc.exists) {
        if (mounted) {
          setState(() {
            _loadError =
                'Organization data not found. Contact your administrator.';
            _isLoading = false;
          });
        }
        return;
      }

      final orgData = orgDoc.data()!;
      if (mounted) {
        setState(() {
          _orgId = orgId;
          _orgName = orgData['name'] as String? ?? 'Organization';
          _orgShortName = orgData['shortName'] as String? ?? 'ORG';
          _orgEmail = orgData['email'] as String? ?? '';
          _orgLogoUrl = orgData['logoUrl'] as String?;
          _buildScreens();
          _isLoading = false;
        });
        _fetchUnreadNotifications();
        _checkReminders();
      }
    } catch (e, st) {
      debugPrint('OrgDashboard load error: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError =
              'Unable to load dashboard.\nPlease refresh or sign in again.';
          _isLoading = false;
        });
      }
    }
  }

  void _buildScreens() {
    _screens = [
      _OrgDashboardHome(
        orgId: _orgId,
        orgName: _orgName,
        onViewMerchandise: () => _selectTab(12), // OrgMerchandiseScreen
        onNavigateToTab: _selectTab,
      ),
      OrgEventProposalsScreen(orgId: _orgId),
      OrgEventsScheduleScreen(orgId: _orgId),
      EventManagementScreen(
        orgId: _orgId,
        visibleTabIndex: _selectedIndexNotifier,
        myTabIndex: 3,
      ),
      OrgCertificatesScreen(orgId: _orgId),
      OrgEventAnalyticsScreen(orgId: _orgId),
      OrgAnnouncementsScreen(orgId: _orgId),
      OrgBroadcastScreen(orgId: _orgId),
      OrgProfileScreen(
        orgId: _orgId,
        orgName: _orgName,
        orgShortName: _orgShortName,
        orgEmail: _orgEmail,
      ),
      OrgLetterRequestScreen(orgId: _orgId),
      OrgReportsScreen(orgId: _orgId),
      OrgFinanceScreen(orgId: _orgId),
      OrgMerchandiseScreen(orgId: _orgId),
      OrgRegistrationFormsScreen(orgId: _orgId), // index 13
      OrgSettingsScreen(
        orgId: _orgId,
        orgName: _orgName,
        orgShortName: _orgShortName,
        orgEmail: _orgEmail,
      ), // index 14 — settings
    ];
    _screensBuilt = true;
  }

  // ── Reminder checks (run once per dashboard load) ──────────────────
  //
  // Date-based reminders (an approaching event, an approaching report
  // deadline) have no natural "action" to hang a notification off of, so
  // they're checked here instead — whenever the org opens their dashboard.
  // Each reminder is throttled to roughly once per day via a timestamp
  // field so reopening the dashboard repeatedly doesn't spam them.
  static const _reminderCooldown = Duration(hours: 20);
  static const _eventNearWindow = Duration(days: 3);
  static const _deadlineNearWindow = Duration(days: 3);

  bool _cooldownElapsed(Timestamp? last) {
    if (last == null) return true;
    return DateTime.now().difference(last.toDate()) > _reminderCooldown;
  }

  Future<void> _checkReminders() async {
    if (_orgId.isEmpty) return;
    try {
      await _checkUnpublishedEventReminders();
      await _checkReportDeadlineReminders();
    } catch (e) {
      debugPrint('Reminder check failed: $e');
    }
  }

  // Approved proposals whose event date is coming up but were never
  // published to students still need the org to hit "Publish".
  Future<void> _checkUnpublishedEventReminders() async {
    final snap = await FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: _orgId)
        .where('status', isEqualTo: 'approved')
        .get();

    final now = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();
      final publishedEventId = (data['publishedEventId'] ?? '').toString();
      if (publishedEventId.isNotEmpty) continue;

      final eventDate = (data['date'] as Timestamp?)?.toDate();
      if (eventDate == null) continue;
      final daysUntil = eventDate.difference(now);
      if (daysUntil > _eventNearWindow || daysUntil.isNegative) continue;

      if (!_cooldownElapsed(data['lastPublishReminderAt'] as Timestamp?)) {
        continue;
      }

      final title = (data['title'] ?? 'Your event').toString();
      final daysLabel = daysUntil.inDays <= 0
          ? 'today'
          : 'in ${daysUntil.inDays} day${daysUntil.inDays == 1 ? '' : 's'}';
      await NotificationService.sendToOrgMembers(
        orgId: _orgId,
        title: 'Event not yet published',
        body:
            '"$title" is happening $daysLabel and still hasn\'t been published to students. Publish it from Event Proposals.',
        type: 'publish_reminder',
        data: {'proposalId': doc.id},
      );
      await doc.reference.update({
        'lastPublishReminderAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Report deadlines are per (org, event): each finished event has its
  // own financial/accomplishment report obligation and its own deadline
  // (an admin override via "Edit Deadline" in reports_management.dart, or
  // the automatic 7-days-after-event default). An org that held several
  // events has several independent obligations — checked individually
  // here, instead of collapsing them into one org-wide check that only
  // looked at the single most-recent event.
  Future<void> _checkReportDeadlineReminders() async {
    final eventsSnap = await FirebaseFirestore.instance
        .collection('events')
        .where('orgId', isEqualTo: _orgId)
        .where('status', isEqualTo: 'approved')
        .get();
    final now = DateTime.now();
    final finishedEvents = <Map<String, dynamic>>[];
    for (final doc in eventsSnap.docs) {
      final date = (doc.data()['date'] as Timestamp?)?.toDate();
      if (date == null || !date.isBefore(now)) continue;
      finishedEvents.add({
        'id': doc.id,
        'title': doc.data()['title']?.toString() ?? 'Untitled Event',
        'date': date,
      });
    }
    if (finishedEvents.isEmpty) return;

    final orgDoc = await FirebaseFirestore.instance
        .collection('organizations')
        .doc(_orgId)
        .get();
    final orgData = orgDoc.data() ?? {};

    // One cooldown per org+type throttles how often we re-notify; it
    // doesn't change which event the notification is about — the first
    // finished event still missing a report (in date order) is reported.
    //
    // The override + report-existence lookups used to run one event at a
    // time in a sequential for-loop (N round trips awaited serially for an
    // org with N past events). They're independent per event, so fetch them
    // in parallel batches instead and just pick the first qualifying event
    // out of the already-resolved results, preserving the same ordering.
    Future<void> checkOne(String key, String label) async {
      final lastSentField =
          'last${key[0].toUpperCase()}${key.substring(1)}DeadlineReminderAt';
      if (!_cooldownElapsed(orgData[lastSentField] as Timestamp?)) return;

      final overrideDocs = await Future.wait(
        finishedEvents.map(
          (ev) => FirebaseFirestore.instance
              .collection('report_deadline_overrides')
              .doc('${_orgId}_${ev['id']}_$key')
              .get(),
        ),
      );

      final withDeadlines = <Map<String, dynamic>>[];
      for (var i = 0; i < finishedEvents.length; i++) {
        final ev = finishedEvents[i];
        final deadline =
            (overrideDocs[i].data()?['deadline'] as Timestamp?)?.toDate() ??
            (ev['date'] as DateTime).add(const Duration(days: 7));
        final daysUntil = deadline.difference(now);
        if (daysUntil > _deadlineNearWindow || daysUntil.isNegative) continue;
        withDeadlines.add({...ev, 'daysUntil': daysUntil});
      }
      if (withDeadlines.isEmpty) return;

      final reportSnaps = await Future.wait(
        withDeadlines.map(
          (ev) => FirebaseFirestore.instance
              .collection('reports')
              .where('orgId', isEqualTo: _orgId)
              .where('eventId', isEqualTo: ev['id'])
              .where('type', isEqualTo: key)
              .limit(1)
              .get(),
        ),
      );

      for (var i = 0; i < withDeadlines.length; i++) {
        if (reportSnaps[i].docs.isNotEmpty) continue;
        final ev = withDeadlines[i];
        final daysUntil = ev['daysUntil'] as Duration;
        final daysLabel = daysUntil.inDays <= 0
            ? 'today'
            : 'in ${daysUntil.inDays} day${daysUntil.inDays == 1 ? '' : 's'}';
        await NotificationService.sendToOrgMembers(
          orgId: _orgId,
          title: '$label report deadline approaching',
          body:
              'The $label report deadline for "${ev['title']}" is $daysLabel. Submit it from Reports if you haven\'t already.',
          type: 'deadline_reminder',
        );
        await FirebaseFirestore.instance
            .collection('organizations')
            .doc(_orgId)
            .update({lastSentField: FieldValue.serverTimestamp()});
        return;
      }
    }

    await checkOne('financial', 'Financial');
    await checkOne('accomplishment', 'Accomplishment');
  }

  Future<void> _fetchUnreadNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // Capped — this pulled the account's entire lifetime notification
      // history on every dashboard load and every bell-icon open, growing
      // unbounded with account age.
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      if (mounted) {
        final all = snap.docs
            .map(
              (d) => {
                'id': d.id,
                'title': d.data()['title'] ?? 'New Notification',
                'message': d.data()['body'] ?? d.data()['message'] ?? '',
                'isRead': d.data()['isRead'] ?? false,
                'timestamp': d.data()['createdAt'],
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
      }
    } catch (e) {
      // Was a bare catch (_) {} — a missing composite index (userId +
      // createdAt, required by the orderBy below) threw on every single
      // call with zero visible trace anywhere, making a real backend
      // failure look identical to "nothing was ever sent."
      debugPrint('org_dashboard: failed to fetch notifications: $e');
    }
  }

  void _showNotificationDropdown() {
    final bellBox = _bellKey.currentContext?.findRenderObject() as RenderBox?;
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
    final maxHeight = (screenSize.height - top - 24).clamp(200.0, 480.0);
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
            padding: EdgeInsets.only(top: top, right: right),
            child: Material(
              color: Colors.white,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: OrgColors.border, width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 360,
                  minWidth: 360,
                  maxHeight: maxHeight,
                ),
                child: _OrgNotificationPanel(
                  notifications: List.from(_notifications),
                  onMarkRead: _markNotificationAsRead,
                  onMarkAllRead: _markAllNotificationsAsRead,
                  onNotificationTap: _handleNotificationTap,
                  bellKey: _bellKey,
                ),
              ),
            ),
          ),
        );
      },
    );
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
      // _fetchUnreadNotifications) — an org with more than 50 unread
      // notifications (e.g. accumulated recurring deadline reminders)
      // would have older unread ones sitting outside that window,
      // silently un-touched by "Mark all as read", while the bell's badge
      // (NotificationService.unreadCountStream, unbounded) kept counting
      // them — the badge stayed stuck nonzero after "reading everything".
      // NotificationService.markAllAsRead queries every isRead==false doc
      // for this user directly, no cap.
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
        AppToast.error(context, 'Could not mark notifications as read: $e');
      }
    }
  }

  // Maps a notification's type to the sidebar tab it's about, so clicking
  // one takes the org straight to where it happened.
  static const Map<String, int> _notificationTypeToTabIndex = {
    'proposal_status': 1, // OrgEventProposalsScreen
    'proposal_revision': 1,
    'publish_reminder': 1,
    'letter_status': 9, // OrgLetterRequestScreen
    'deadline_reminder': 10, // OrgReportsScreen
    'private_message': 7, // OrgBroadcastScreen (Messages)
  };

  void _handleNotificationTap(Map<String, dynamic> n) {
    final index = _notificationTypeToTabIndex[n['type']?.toString()];
    if (index != null) _selectTab(index);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedIndices.add(index == -1 ? 14 : index);
    });
    _selectedIndexNotifier.value = index == -1 ? 14 : index;
    // On narrow layouts the sidebar lives in a Drawer — close it after a
    // selection so the newly-picked screen is actually visible instead of
    // staying hidden behind the still-open Drawer.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _showProfileMenu() {
    final box = _profileKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    double top = 76;
    double right = 28;
    if (box != null) {
      final topLeft = box.localToGlobal(Offset.zero);
      final size = box.size;
      top = topLeft.dy + size.height + 12;
      right = (screenSize.width - (topLeft.dx + size.width) - 6).clamp(
        8.0,
        screenSize.width - 200,
      );
    }
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
            padding: EdgeInsets.only(top: top, right: right),
            child: Material(
              color: Colors.white,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: OrgColors.border, width: 0.5),
              ),
              child: SizedBox(
                width: 200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    _profileMenuItem(Icons.person_outline, 'My Profile', () {
                      Navigator.of(ctx).pop();
                      _selectTab(8);
                    }),
                    _profileMenuItem(Icons.settings_outlined, 'Settings', () {
                      Navigator.of(ctx).pop();
                      _selectTab(-1);
                    }),
                    const Divider(height: 1, color: OrgColors.border),
                    const SizedBox(height: 4),
                    _profileMenuItem(Icons.logout_rounded, 'Sign Out', () {
                      Navigator.of(ctx).pop();
                      _confirmLogout();
                    }, color: OrgColors.error),
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
            Icon(icon, size: 17, color: color ?? OrgColors.darkGray),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? OrgColors.charcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await AppSignOut.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    // Force a reload on web to ensure the auth gate rebuilds to the landing/login page
    try {
      html.window.location.reload();
    } catch (_) {}
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AppConfirmationDialog(
        title: 'Confirm Logout',
        message:
            'Are you sure you want to sign out from the organization portal?',
        confirmLabel: 'Sign Out',
        accentColor: OrgColors.error,
        icon: Icons.logout_rounded,
        onConfirm: _logout,
      ),
    );
  }

  String _getCurrentTitle() {
    if (_selectedIndex == -1) return 'Settings';
    if (_selectedIndex >= 0 && _selectedIndex < _navItems.length) {
      return _navItems[_selectedIndex]['label'] as String;
    }
    return 'Dashboard';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: OrgColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: OrgColors.primaryDark.withAlpha(26),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: OrgColors.primaryDark,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: OrgColors.primaryDark,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Loading dashboard\u2026',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: OrgColors.darkGray,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: OrgColors.surface,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: OrgColors.white,
              borderRadius: BorderRadius.circular(_DS.radiusLg),
              border: Border.all(color: OrgColors.border),
              boxShadow: _DS.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: OrgColors.errorBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 30,
                    color: OrgColors.error,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to Load Dashboard',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: OrgColors.charcoal,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: OrgColors.darkGray,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadOrgData,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      'Try Again',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OrgColors.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_DS.radiusSm),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: OrgColors.borderSoft),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_DS.radiusSm),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Sign Out',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: OrgColors.textMid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OrgColors.surface,
      drawer: isMobile ? Drawer(width: 256, child: _buildSidebar()) : null,
      body: Stack(
        children: [
          Row(
            children: [
              if (!isMobile) _buildSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(isMobile),
                    Expanded(
                      // IndexedStack keeps every screen's state alive
                      // instead of tearing it down and re-fetching Firestore
                      // data from scratch on every tab switch — that
                      // re-fetch was the cause of the lag on every click.
                      child: !_screensBuilt
                          ? const SizedBox()
                          : _FadeOnChange(
                              watch: _selectedIndex,
                              child: IndexedStack(
                                index: _selectedIndex == -1
                                    ? 14
                                    : _selectedIndex,
                                children: List.generate(
                                  _screens.length,
                                  (i) => _visitedIndices.contains(i)
                                      ? _screens[i]
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: OrgColors.primaryDark,
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
            color: OrgColors.primaryDark,
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
                          Icons.school_rounded,
                          color: OrgColors.primaryDark,
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
                              'Organization Portal',
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

  Widget _buildTopBar(bool isMobile) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 720 ? 12.0 : 28.0;
    final isSmallMobile = screenWidth < 480;

    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: OrgColors.white,
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
          if (isMobile)
            Tooltip(
              message: 'Toggle Menu',
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: OrgColors.lightGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OrgColors.border),
                    ),
                    child: const Icon(
                      Icons.menu_rounded,
                      color: OrgColors.darkGray,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: OrgColors.primaryDark,
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
                    style: GoogleFonts.beVietnamPro(
                      fontSize: isSmallMobile ? 14 : 16,
                      fontWeight: FontWeight.w800,
                      color: OrgColors.charcoal,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (!isSmallMobile)
                    Text(
                      _orgName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        color: OrgColors.textFaint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Spacer(),
          if (!isSmallMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(_DS.radiusPill),
                border: Border.all(color: OrgColors.primaryDark.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 12,
                    color: OrgColors.primaryDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _currentDateTime,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: OrgColors.primaryDark,
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
          ],
          if (screenWidth >= 480) const SizedBox(width: 12),
          // A plain InkWell driving our own custom-positioned overlay
          // (same technique as "View All") instead of PopupMenuButton —
          // Flutter's built-in menu positioning clamps/repositions itself
          // to fit the viewport, which made the dropdown land in
          // inconsistent spots depending on window size instead of
          // staying tucked under the bell every time.
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
                // Live count so a new notification updates the badge
                // immediately, without needing to reopen the dropdown —
                // matches the admin bell instead of only refreshing on tap.
                child: StreamBuilder<int>(
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
                                ? OrgColors.primaryDark.withAlpha(12)
                                : OrgColors.lightGray,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: unread > 0
                                  ? OrgColors.primaryDark.withAlpha(60)
                                  : OrgColors.border,
                            ),
                          ),
                          child: Icon(
                            unread > 0
                                ? Icons.notifications_rounded
                                : Icons.notifications_none_rounded,
                            color: unread > 0
                                ? OrgColors.primaryDark
                                : OrgColors.darkGray,
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
                                color: OrgColors.error,
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
          if (screenWidth >= 480) ...[
            Container(width: 1, height: 28, color: OrgColors.border),
            const SizedBox(width: 10),
          ],
          if (screenWidth >= 480)
            Tooltip(
              message: 'Account Menu',
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
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
                          color: OrgColors.primaryDark.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: OrgColors.primaryDark.withAlpha(50),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _orgLogoUrl != null
                            ? Image.network(
                                _orgLogoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    _orgShortName.isNotEmpty
                                        ? _orgShortName[0].toUpperCase()
                                        : 'O',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: OrgColors.primaryDark,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  _orgShortName.isNotEmpty
                                      ? _orgShortName[0].toUpperCase()
                                      : 'O',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: OrgColors.primaryDark,
                                  ),
                                ),
                              ),
                      ),
                      if (screenWidth >= 600) ...[
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _orgShortName,
                              style: GoogleFonts.beVietnamPro(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: OrgColors.charcoal,
                              ),
                            ),
                            Text(
                              'Organization',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 10,
                                color: OrgColors.textFaint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: OrgColors.textFaint,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: OrgColors.primaryDark.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _orgShortName.isNotEmpty
                      ? _orgShortName[0].toUpperCase()
                      : 'O',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OrgColors.primaryDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Pastel bg / solid fg pair per category — same values as
// event_calendar.dart / org_events_schedule.dart's CategoryColors, so a
// category's table badge here reads as the same color as its calendar chip.
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

// ─────────────────────────────────────────────────────────────────────────────
// Org Dashboard Home (with countdown – no timer updates here)
// ─────────────────────────────────────────────────────────────────────────────
class _OrgDashboardHome extends StatefulWidget {
  final String orgId;
  final String orgName;
  final VoidCallback onViewMerchandise;
  final void Function(int)? onNavigateToTab;
  const _OrgDashboardHome({
    required this.orgId,
    required this.orgName,
    required this.onViewMerchandise,
    this.onNavigateToTab,
  });

  @override
  State<_OrgDashboardHome> createState() => _OrgDashboardHomeState();
}

class _OrgDashboardHomeState extends State<_OrgDashboardHome> {
  // Existing variables
  int _selectedYear = DateTime.now().year;
  String _selectedMonth = '';
  List<int> _chartData = List.filled(12, 0);
  bool _chartLoading = true;

  // Countdown – only store the event data, no timer here!
  DateTime? _eventDate;
  String _eventLabel = '';
  bool _eventLoaded = false;

  // Which stat card (if any) is driving the dynamic panel below — mirrors
  // AdminDashboard's stat-card-click-to-drill-down pattern.
  int? _selectedCard;

  // Existing streams
  late final Stream<QuerySnapshot> _approvedEventsStream;
  late final Stream<QuerySnapshot> _pendingProposalsStream;
  late final Stream<QuerySnapshot> _upcomingEventsStream;
  StreamSubscription<QuerySnapshot>? _chartDataSubscription;

  // Dedicated streams for the drill-down table panels — deliberately NOT
  // the same Stream instances as the stat cards above (mirrors
  // AdminDashboard's _activeEventsTableStreamGetter). Firestore sends the
  // current snapshot immediately to a brand-new .snapshots() listener, but
  // sharing one Stream object between two simultaneously-mounted
  // StreamBuilders doesn't — whichever one attaches second only sees
  // future changes, not the snapshot that already fired for the first, so
  // it sat on the loading spinner until the collection happened to change.
  // Lazily created on first use so we're not running extra listeners
  // before a card is ever opened.
  Stream<QuerySnapshot>? _activeEventsTableStream;
  Stream<QuerySnapshot> get _activeEventsTableStreamGetter =>
      _activeEventsTableStream ??= FirebaseFirestore.instance
          .collection('event_proposals')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .snapshots();

  Stream<QuerySnapshot>? _pendingProposalsTableStream;
  Stream<QuerySnapshot> get _pendingProposalsTableStreamGetter =>
      _pendingProposalsTableStream ??= FirebaseFirestore.instance
          .collection('event_proposals')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'pending')
          .snapshots();

  Stream<QuerySnapshot>? _upcomingEventsTableStream;
  Stream<QuerySnapshot> get _upcomingEventsTableStreamGetter =>
      _upcomingEventsTableStream ??= FirebaseFirestore.instance
          .collection('event_proposals')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()),
          )
          .orderBy('date')
          .snapshots();

  Stream<QuerySnapshot>? _merchSalesTableStream;
  Stream<QuerySnapshot> get _merchSalesTableStreamGetter =>
      _merchSalesTableStream ??= FirebaseFirestore.instance
          .collection('products')
          .where('orgId', isEqualTo: widget.orgId)
          .where('isArchived', isEqualTo: false)
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

  @override
  void initState() {
    super.initState();
    _selectedMonth = _monthLabel(DateTime.now().month - 1);
    final now = DateTime.now();

    _approvedEventsStream = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: widget.orgId)
        .where('status', isEqualTo: 'approved')
        .snapshots();

    _pendingProposalsStream = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: widget.orgId)
        .where('status', isEqualTo: 'pending')
        .snapshots();

    _upcomingEventsStream = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: widget.orgId)
        .where('status', isEqualTo: 'approved')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('date')
        .snapshots();

    _setupChartListener();

    // Load the next event for countdown (no timer inside)
    _loadEventDate();
  }

  @override
  void dispose() {
    _chartDataSubscription?.cancel();
    super.dispose();
  }

  // Load event date – only sets state, no timer
  Future<void> _loadEventDate() async {
    try {
      final now = DateTime.now();
      // Standardized on event_proposals for "approved" counts across the
      // dashboards — this used to read the `events` collection (only
      // populated once the org separately "publishes" an approved
      // proposal), which could disagree with the Active Events stat card
      // right above this countdown on the same screen.
      final snap = await FirebaseFirestore.instance
          .collection('event_proposals')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .get();

      DateTime? nextDate;
      String nextLabel = '';
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['date'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate();
        if (date.isBefore(now)) continue;
        if (nextDate == null || date.isBefore(nextDate)) {
          nextDate = date;
          nextLabel = data['title']?.toString() ?? 'Upcoming Event';
        }
      }

      if (nextDate != null) {
        setState(() {
          _eventDate = nextDate;
          _eventLabel = nextLabel;
          _eventLoaded = true;
        });
      } else {
        setState(() => _eventLoaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _eventLoaded = true);
    }
  }

  void _setupChartListener() {
    _chartDataSubscription?.cancel();
    setState(() => _chartLoading = true);
    final startDate = DateTime(_selectedYear, 1, 1);
    final endDate = DateTime(_selectedYear + 1, 1, 1);

    var query = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('orgId', isEqualTo: widget.orgId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate));

    _chartDataSubscription = query.snapshots().listen(
      (snap) {
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
      },
      onError: (_) {
        if (mounted) setState(() => _chartLoading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeHeader(isMobile),
          const SizedBox(height: 14),
          _buildStatCards(isMobile, isTablet),
          const SizedBox(height: 20),
          _selectedCard == null ? _buildChartCard() : _buildDynamicPanel(),
          const SizedBox(height: 20),
          // Countdown card – now stateful, doesn't cause parent rebuild
          if (_eventLoaded && _eventDate != null)
            _CountdownCard(eventDate: _eventDate!, eventLabel: _eventLabel),
        ],
      ),
    );
  }

  // ── Welcome header ────────────────────────────────────────────────
  Widget _buildWelcomeHeader(bool isMobile) {
    return const DashboardOverviewLabel(
      subtitle: 'Organization activity at a glance',
    );
  }

  // ── Stat cards ────────────────────────────────────────────────────
  Widget _buildStatCards(bool isMobile, bool isTablet) {
    Widget streamCard({
      required int cardIndex,
      required String label,
      required IconData icon,
      required Color color,
      required Stream<QuerySnapshot> stream,
    }) {
      return StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (_, snap) {
          // A query failure (e.g. a missing Firestore composite index for
          // one of these multi-filter queries) previously fell straight
          // through to count=0 here — indistinguishable from "genuinely
          // no data" even though the real cause was an unhandled error.
          // Logging it at least surfaces the real reason in the console
          // instead of silently looking like the data vanished.
          if (snap.hasError) {
            debugPrint('$label stat card stream error: ${snap.error}');
          }
          final loading = snap.connectionState == ConnectionState.waiting;
          final count = snap.hasData ? snap.data!.docs.length : 0;
          final isSelected = _selectedCard == cardIndex;
          return _StatCardWidget(
            label: label,
            icon: icon,
            color: color,
            count: count,
            loading: loading,
            isSelected: isSelected,
            onTap: () =>
                setState(() => _selectedCard = isSelected ? null : cardIndex),
          );
        },
      );
    }

    final cardWidgets = [
      streamCard(
        cardIndex: 0,
        label: 'Events',
        icon: Icons.event_rounded,
        color: OrgColors.info,
        stream: _approvedEventsStream,
      ),
      streamCard(
        cardIndex: 1,
        label: 'Pending Proposals',
        icon: Icons.pending_actions_rounded,
        color: OrgColors.warning,
        stream: _pendingProposalsStream,
      ),
      streamCard(
        cardIndex: 2,
        label: 'Upcoming Events',
        icon: Icons.upcoming_rounded,
        color: OrgColors.primaryDark,
        stream: _upcomingEventsStream,
      ),
      _MerchSalesStatCard(
        orgId: widget.orgId,
        isSelected: _selectedCard == 3,
        onTap: () =>
            setState(() => _selectedCard = _selectedCard == 3 ? null : 3),
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

    if (isTablet) {
      final width = MediaQuery.of(context).size.width;
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
          if (i != cardWidgets.length - 1) const SizedBox(width: 14),
        ],
      ],
    );
  }

  // ── Chart card ────────────────────────────────────────────────────
  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OrgColors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: OrgColors.border),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposals Activity Overview',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: OrgColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Event proposals per month this year (real-time)',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: OrgColors.textFaint,
                    ),
                  ),
                ],
              ),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: OrgColors.borderSoft),
                  borderRadius: BorderRadius.circular(_DS.radiusSm),
                  color: OrgColors.lightGray,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: OrgColors.textMid,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: OrgColors.textFaint,
                    ),
                    items: _yearOptions
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedYear = v;
                          _setupChartListener();
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Chart — bar-per-month is more legible than a line for discrete
          // monthly counts, and fl_chart handles touch/tooltips/scaling for us.
          SizedBox(
            height: 230,
            child: _chartLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: OrgColors.primaryDark,
                      strokeWidth: 2,
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

  Widget _buildTopMerchandise() {
    return Container(
      decoration: BoxDecoration(
        color: OrgColors.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: OrgColors.border),
        boxShadow: _DS.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Merchandise',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: OrgColors.charcoal,
                  ),
                ),
                InkWell(
                  onTap: widget.onViewMerchandise,
                  borderRadius: BorderRadius.circular(_DS.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: OrgColors.primaryDark.withAlpha(20),
                      borderRadius: BorderRadius.circular(_DS.radiusPill),
                    ),
                    child: Text(
                      'View All',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: OrgColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('orgId', isEqualTo: widget.orgId)
                  .where('isArchived', isEqualTo: false)
                  .snapshots(),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: OrgColors.primaryDark,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return _emptyPlaceholder(
                    Icons.shopping_bag_rounded,
                    'No merchandise yet',
                  );
                }
                // Was sorted by 'sold' descending ("Top Merchandise") — merch
                // has no checkout flow, so 'sold' is written once as 0 at
                // creation and never incremented, making every product tie
                // at 0 and the "top sellers" list just an arbitrary,
                // misleading subset. Recently-added is the honest ordering
                // given what this feature actually tracks.
                final products =
                    snap.data!.docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      return {
                        'name': d['name'] ?? 'Unnamed',
                        'stock': (d['stock'] as num?)?.toInt() ?? 0,
                        'price': (d['price'] as num?)?.toDouble() ?? 0.0,
                        'createdAt': (d['createdAt'] as Timestamp?)?.toDate(),
                      };
                    }).toList()..sort((a, b) {
                      final da = a['createdAt'] as DateTime?;
                      final db = b['createdAt'] as DateTime?;
                      if (da == null || db == null) return 0;
                      return db.compareTo(da);
                    });
                return Column(
                  children: products.take(5).map((product) {
                    return _MerchRow(
                      name: product['name'] as String,
                      stock: product['stock'] as int,
                      price: product['price'] as double,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
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
              child: Icon(icon, size: 26, color: OrgColors.textFaint),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: OrgColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dynamic panel — swaps in for the chart card when a stat card is
  // selected, matching AdminDashboard's drill-down pattern exactly. ────────
  Widget _buildDynamicPanel() {
    switch (_selectedCard) {
      case 0:
        return _buildActiveEventsPanel();
      case 1:
        return _buildPendingProposalsPanel();
      case 2:
        return _buildUpcomingEventsTablePanel();
      case 3:
        return _buildMerchSalesPanel();
      default:
        return _buildChartCard();
    }
  }

  String _fmtDate(DateTime? d) =>
      d != null ? DateFormat('MMM d, yyyy').format(d) : 'TBA';

  // A missing start time used to render as " - 5:00 PM" (leading dash with
  // nothing before it). Falls back to whichever side is actually present.
  String _fmtTimeRange(Object? start, Object? end) {
    final s = (start ?? '').toString().trim();
    final e = (end ?? '').toString().trim();
    if (s.isEmpty && e.isEmpty) return 'TBA';
    if (s.isEmpty) return e;
    if (e.isEmpty) return s;
    return '$s - $e';
  }

  Widget _buildActiveEventsPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activeEventsTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            const Center(
              child: CircularProgressIndicator(color: OrgColors.primaryDark),
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
                'category': (d['category'] as String?) ?? '—',
                'location': (d['location'] as String?) ?? 'TBA',
                'audience': (d['audience'] as String?) ?? '—',
                'description':
                    (d['description'] as String?) ?? 'No description provided.',
                'time': (d['time'] ?? '').toString(),
                'endTime': (d['endTime'] ?? '').toString(),
                'date': (d['date'] as Timestamp?)?.toDate(),
              };
            }).toList()..sort((a, b) {
              final da = a['date'] as DateTime?;
              final db = b['date'] as DateTime?;
              if (da == null || db == null) return 0;
              return da.compareTo(db);
            });

        return _tableCard(
          header: _panelHeader(
            title: 'Events',
            subtitle: 'Approved events, ${rows.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Events',
              headers: const ['Title', 'Category', 'Date', 'Location'],
              rows: [
                for (final r in rows)
                  [
                    r['title'] as String,
                    r['category'] as String,
                    _fmtDate(r['date'] as DateTime?),
                    r['location'] as String,
                  ],
              ],
              fileNamePrefix: 'active_events',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Title', 3),
                MapEntry('Category', 2),
                MapEntry('Date', 2),
                MapEntry('Location', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 2, 2, 2],
                  isLast: i == rows.length - 1,
                  isEven: i.isEven,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['title'] as String,
                    actionLabel: 'Open in Events & Schedules',
                    navigateToTabIndex: 2, // OrgEventsScheduleScreen
                    fields: [
                      MapEntry('Category', rows[i]['category'] as String),
                      MapEntry('Date', _fmtDate(rows[i]['date'] as DateTime?)),
                      MapEntry(
                        'Time',
                        _fmtTimeRange(rows[i]['time'], rows[i]['endTime']),
                      ),
                      MapEntry('Location', rows[i]['location'] as String),
                      MapEntry('Audience', rows[i]['audience'] as String),
                      MapEntry('Description', rows[i]['description'] as String),
                    ],
                  ),
                  cells: [
                    _cellText(rows[i]['title'] as String, bold: true),
                    _cellBadge(
                      rows[i]['category'] as String,
                      CategoryColors.getFg(rows[i]['category'] as String),
                      bg: CategoryColors.getBg(rows[i]['category'] as String),
                    ),
                    _cellText(_fmtDate(rows[i]['date'] as DateTime?)),
                    _cellText(rows[i]['location'] as String),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingProposalsPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _pendingProposalsTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            const Center(
              child: CircularProgressIndicator(color: OrgColors.primaryDark),
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
                'category': (d['category'] as String?) ?? '—',
                'description':
                    (d['description'] as String?) ?? 'No description provided.',
                'eventDate': (d['date'] as Timestamp?)?.toDate(),
                'submittedAt': (d['submittedAt'] as Timestamp?)?.toDate(),
              };
            }).toList()..sort((a, b) {
              final sa = a['submittedAt'] as DateTime?;
              final sb = b['submittedAt'] as DateTime?;
              if (sa == null && sb == null) return 0;
              if (sa == null) return 1;
              if (sb == null) return -1;
              return sb.compareTo(sa);
            });

        return _tableCard(
          header: _panelHeader(
            title: 'Pending Proposals',
            subtitle: 'Awaiting admin review, ${rows.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Pending Proposals',
              headers: const ['Title', 'Category', 'Event Date', 'Submitted'],
              rows: [
                for (final r in rows)
                  [
                    r['title'] as String,
                    r['category'] as String,
                    _fmtDate(r['eventDate'] as DateTime?),
                    _fmtDate(r['submittedAt'] as DateTime?),
                  ],
              ],
              fileNamePrefix: 'pending_proposals',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Title', 3),
                MapEntry('Category', 2),
                MapEntry('Event Date', 2),
                MapEntry('Submitted', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 2, 2, 2],
                  isLast: i == rows.length - 1,
                  isEven: i.isEven,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['title'] as String,
                    actionLabel: 'Open in Event Proposals',
                    navigateToTabIndex: 1, // OrgEventProposalsScreen
                    fields: [
                      MapEntry('Category', rows[i]['category'] as String),
                      MapEntry(
                        'Event Date',
                        _fmtDate(rows[i]['eventDate'] as DateTime?),
                      ),
                      MapEntry(
                        'Submitted',
                        _fmtDate(rows[i]['submittedAt'] as DateTime?),
                      ),
                      MapEntry('Description', rows[i]['description'] as String),
                    ],
                  ),
                  cells: [
                    _cellText(rows[i]['title'] as String, bold: true),
                    _cellBadge(
                      rows[i]['category'] as String,
                      CategoryColors.getFg(rows[i]['category'] as String),
                      bg: CategoryColors.getBg(rows[i]['category'] as String),
                    ),
                    _cellText(_fmtDate(rows[i]['eventDate'] as DateTime?)),
                    _cellText(_fmtDate(rows[i]['submittedAt'] as DateTime?)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingEventsTablePanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _upcomingEventsTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            const Center(
              child: CircularProgressIndicator(color: OrgColors.primaryDark),
            ),
          );
        }
        // Was falling straight through to the "No upcoming events" empty
        // state on any query error too (e.g. a missing Firestore
        // composite index for this 3-filter-plus-order query) — that
        // read as the data having vanished instead of the real cause.
        if (snapshot.hasError) {
          return _tableCardSimple(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load upcoming events: ${snapshot.error}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: OrgColors.error,
                ),
              ),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(Icons.upcoming_outlined, 'No upcoming events'),
          );
        }

        final rows = docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return {
            'title': (d['title'] as String?) ?? 'Untitled',
            'location': (d['location'] as String?) ?? 'TBA',
            'time': (d['time'] ?? '').toString(),
            'endTime': (d['endTime'] ?? '').toString(),
            'audience': (d['audience'] as String?) ?? '—',
            'date': (d['date'] as Timestamp?)?.toDate(),
          };
        }).toList();

        return _tableCard(
          header: _panelHeader(
            title: 'Upcoming Events',
            subtitle: 'Approved events still ahead, ${rows.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Upcoming Events',
              headers: const ['Title', 'Date', 'Time', 'Location'],
              rows: [
                for (final r in rows)
                  [
                    r['title'] as String,
                    _fmtDate(r['date'] as DateTime?),
                    _fmtTimeRange(r['time'], r['endTime']),
                    r['location'] as String,
                  ],
              ],
              fileNamePrefix: 'upcoming_events',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Title', 3),
                MapEntry('Date', 2),
                MapEntry('Time', 2),
                MapEntry('Location', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 2, 2, 2],
                  isLast: i == rows.length - 1,
                  isEven: i.isEven,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['title'] as String,
                    fields: [
                      MapEntry('Date', _fmtDate(rows[i]['date'] as DateTime?)),
                      MapEntry(
                        'Time',
                        _fmtTimeRange(rows[i]['time'], rows[i]['endTime']),
                      ),
                      MapEntry('Location', rows[i]['location'] as String),
                      MapEntry('Audience', rows[i]['audience'] as String),
                    ],
                  ),
                  cells: [
                    _cellText(rows[i]['title'] as String, bold: true),
                    _cellText(_fmtDate(rows[i]['date'] as DateTime?)),
                    _cellText(
                      _fmtTimeRange(rows[i]['time'], rows[i]['endTime']),
                    ),
                    _cellText(rows[i]['location'] as String),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // Was "Merch Sales" (Price/Sold/Revenue columns) — merch has no checkout
  // anymore, so those figures are permanently frozen/meaningless. This now
  // shows the catalog itself: what's listed and how much stock is left.
  Widget _buildMerchSalesPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _merchSalesTableStreamGetter,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _tableCardSimple(
            const Center(
              child: CircularProgressIndicator(color: OrgColors.primaryDark),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _tableCardSimple(
            _emptyPlaceholder(
              Icons.shopping_bag_outlined,
              'No merchandise listed yet',
            ),
          );
        }

        String money(double v) =>
            NumberFormat.currency(symbol: '₱', decimalDigits: 0).format(v);

        final rows =
            docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return {
                'name': (d['name'] as String?) ?? 'Untitled',
                'category': (d['category'] as String?) ?? '—',
                'price': ((d['price'] ?? 0) as num).toDouble(),
                'stock': ((d['stock'] ?? 0) as num).toInt(),
              };
            }).toList()..sort(
              (a, b) => (a['name'] as String).compareTo(b['name'] as String),
            );

        return _tableCard(
          header: _panelHeader(
            title: 'Merchandise',
            subtitle: 'All listed products, ${rows.length} total.',
            onBack: () => setState(() => _selectedCard = null),
            onExport: (format) => _exportTable(
              format: format,
              title: 'Merchandise',
              headers: const ['Product', 'Category', 'Price', 'Stock'],
              rows: [
                for (final r in rows)
                  [
                    r['name'] as String,
                    r['category'] as String,
                    money(r['price'] as double),
                    '${r['stock']}',
                  ],
              ],
              fileNamePrefix: 'merchandise',
            ),
          ),
          table: Column(
            children: [
              _customTableHeader(const [
                MapEntry('Product', 3),
                MapEntry('Category', 2),
                MapEntry('Price', 2),
                MapEntry('Stock', 2),
              ]),
              for (var i = 0; i < rows.length; i++)
                _customTableRow(
                  flexes: const [3, 2, 2, 2],
                  isLast: i == rows.length - 1,
                  isEven: i.isEven,
                  onTap: () => _showDetailDialog(
                    title: rows[i]['name'] as String,
                    actionLabel: 'Open in Merchandise Catalog',
                    navigateToTabIndex: 12, // OrgMerchandiseScreen
                    fields: [
                      MapEntry('Category', rows[i]['category'] as String),
                      MapEntry('Price', money(rows[i]['price'] as double)),
                      MapEntry('In Stock', '${rows[i]['stock']}'),
                    ],
                  ),
                  cells: [
                    _cellText(rows[i]['name'] as String, bold: true),
                    _cellBadge(
                      rows[i]['category'] as String,
                      _merchCategoryBadgeColor(rows[i]['category'] as String),
                    ),
                    _cellText(money(rows[i]['price'] as double)),
                    _cellText('${rows[i]['stock']}'),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Shared panel chrome — header, table shell, custom row/header,
  // detail dialog. Mirrors AdminDashboard's equivalents exactly. ──────────
  Widget _panelHeader({
    required String title,
    required String subtitle,
    dynamic Function(String format)? onExport,
    VoidCallback? onBack,
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
                    color: OrgColors.darkGray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Back to Overview',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OrgColors.darkGray,
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
                      color: OrgColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: OrgColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (onExport != null) ...[
              const SizedBox(width: 12),
              AdminExportButton(onSelected: onExport),
            ],
          ],
        ),
      ],
    );
  }

  Widget _customTableHeader(List<MapEntry<String, int>> columns) {
    // Matches every other org table's header treatment (certificates,
    // finance, letter request, proposals, reports): a soft amber tint with
    // a translucent bottom border, instead of this table's own one-off
    // neutral-gray/solid-border variant.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border(
          bottom: BorderSide(color: OrgColors.primaryDark.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.value,
              child: Text(
                c.key.toUpperCase(),
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

  Widget _customTableRow({
    required List<Widget> cells,
    required List<int> flexes,
    required VoidCallback onTap,
    bool isLast = false,
    bool isEven = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        // Matches every other org table's row hover treatment instead of
        // this table's own one-off darker hover/zebra-striped variant.
        hoverColor: const Color(0xFFF8F9FB),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(flex: flexes[i], child: cells[i]),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: OrgColors.surface,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: OrgColors.darkGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cellText(String text, {bool bold = false, Color? color}) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color ?? OrgColors.charcoal,
      ),
    );
  }

  // Merchandise categories are a separate domain from event categories
  // (admin has no merchandise feature to match colors against), so this is
  // its own small fixed palette rather than reusing the event map above.
  static const Map<String, Color> _merchCategoryBadgeColors = {
    'T-Shirts / Uniforms': Color(0xFF6366F1),
    'Lanyards / IDs': Color(0xFF06B6D4),
    'Stickers / Pins': Color(0xFFEC4899),
    'Tumblers / Water Bottles': Color(0xFF14B8A6),
    'Notebooks / Planners': Color(0xFF8B5CF6),
  };

  Color _merchCategoryBadgeColor(String category) {
    return _merchCategoryBadgeColors[category] ?? const Color(0xFF6B7280);
  }

  // [bg] overrides the default alpha-tinted background with a fixed color
  // — used for category badges, which use the same pastel bg / solid fg
  // pair as the calendar's category chips instead of a tint of [color].
  Widget _cellBadge(String text, Color color, {Color? bg}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg ?? color.withAlpha(24),
          borderRadius: BorderRadius.circular(_DS.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
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
          ],
        ),
      ),
    );
  }

  // [badgeColor] renders the value as the same colored pill the table cell
  // uses instead of plain text — without it, Category showed a color-coded
  // badge in the table but flattened to plain black text once you opened
  // the detail view, which read as a missing/broken color.
  // Icon + accent color for each detail-modal field tile's left-side chip.
  // One shared lookup since the same labels (Date, Location, Audience…)
  // repeat across the Events, Proposals and Merchandise detail dialogs.
  static const Map<String, IconData> _detailFieldIcons = {
    'Category': Icons.sell_rounded,
    'Date': Icons.calendar_today_rounded,
    'Event Date': Icons.calendar_today_rounded,
    'Time': Icons.access_time_rounded,
    'Location': Icons.location_on_rounded,
    'Audience': Icons.groups_rounded,
    'Description': Icons.notes_rounded,
    'Submitted': Icons.upload_file_rounded,
    'Price': Icons.payments_rounded,
    'In Stock': Icons.inventory_2_rounded,
  };

  Widget _detailRow(String label, String value) {
    final icon = _detailFieldIcons[label] ?? Icons.info_outline_rounded;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OrgColors.surface,
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: OrgColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: OrgColors.primaryDark,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: OrgColors.textFaint,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: _fullWidthDetailKeys.contains(label)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: OrgColors.charcoal,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fields that carry prose rather than a short value — these get a row to
  // themselves so a description isn't forced to wrap inside a half-width
  // column while the cell beside it sits mostly empty.
  static const _fullWidthDetailKeys = {'Description', 'Remarks', 'Notes'};

  // Groups the flat field list into display rows: a long/prose field takes a
  // whole row, everything else pairs up two-per-row.
  List<List<MapEntry<String, String>>> _pairDetailFields(
    List<MapEntry<String, String>> fields,
  ) {
    final rows = <List<MapEntry<String, String>>>[];
    List<MapEntry<String, String>>? pending;

    for (final f in fields) {
      final isWide =
          _fullWidthDetailKeys.contains(f.key) || f.value.length > 90;
      if (isWide) {
        // Flush a half-filled pair first so field order is never reshuffled.
        if (pending != null) {
          rows.add(pending);
          pending = null;
        }
        rows.add([f]);
      } else if (pending == null) {
        pending = [f];
      } else {
        pending.add(f);
        rows.add(pending);
        pending = null;
      }
    }
    if (pending != null) rows.add(pending);
    return rows;
  }

  void _showDetailDialog({
    required String title,
    required List<MapEntry<String, String>> fields,
    String? actionLabel,
    int? navigateToTabIndex,
  }) {
    // Two-per-row instead of one long vertical stack — at 720px a date, a
    // time range and a venue each fit comfortably in half the width, so
    // stacking them was spending a full row on values a few characters long.
    final rows = _pairDetailFields(fields);

    Widget cellFor(MapEntry<String, String> f) => _detailRow(f.key, f.value);

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_DS.radiusLg),
              boxShadow: _DS.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── HEADER ──
                // Use the Organization portal's deep-orange brand header,
                // equivalent to the Admin modal's dark-navy treatment.
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                  decoration: const BoxDecoration(color: OrgColors.primaryDark),
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
                      Tooltip(
                        message: 'Close',
                        waitDuration: const Duration(milliseconds: 400),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(31),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── BODY ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: cellFor(rows[i].first)),
                              // A lone short field keeps its half-width cell
                              // and an empty gutter, so the left column stays
                              // aligned all the way down.
                              if (rows[i].length > 1) ...[
                                const SizedBox(width: 10),
                                Expanded(child: cellFor(rows[i][1])),
                              ] else if (!_fullWidthDetailKeys.contains(
                                    rows[i].first.key,
                                  ) &&
                                  rows[i].first.value.length <= 90) ...[
                                const SizedBox(width: 10),
                                const Expanded(child: SizedBox.shrink()),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // ── FOOTER ──
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (actionLabel != null &&
                          navigateToTabIndex != null) ...[
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.onNavigateToTab?.call(navigateToTabIndex);
                          },
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                          ),
                          label: Text(
                            actionLabel,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: OrgColors.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OrgColors.primaryDark,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_DS.radiusSm),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
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
      ),
    );
  }

  Widget _tableCardSimple(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_DS.radiusLg),
      border: Border.all(color: OrgColors.border),
      boxShadow: _DS.cardShadow,
    ),
    child: child,
  );

  Widget _tableCard({required Widget header, required Widget table}) =>
      Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusLg),
          border: Border.all(color: OrgColors.border),
          boxShadow: _DS.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.all(20), child: header),
            table,
          ],
        ),
      );

  Future<void> _exportTable({
    required String format,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required String fileNamePrefix,
  }) async {
    try {
      final ts = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String fileName;
      final List<int> bytes;
      final String mimeType;
      if (format == 'excel') {
        bytes = OrgExportExcel.generateStyledTable(
          title: title,
          headers: headers,
          rows: rows,
        );
        fileName = '${fileNamePrefix}_$ts.xlsx';
        mimeType = orgXlsxMimeType;
      } else {
        bytes = await OrgExportPdf.generateTablePdf(
          title: title,
          headers: headers,
          rows: rows,
        );
        fileName = '${fileNamePrefix}_$ts.pdf';
        mimeType = 'application/pdf';
      }
      await OrgExportUtil.saveBytes(bytes, fileName, mimeType: mimeType);
      if (mounted) {
        AppToast.success(context, 'Exported $fileName');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Export failed: $e');
      }
    }
  }
}

// ── Merch sales card (FutureBuilder) ────────────────────────────────────────
// Was "Merch Sales" (summed price*sold) \u2014 merch has no checkout anymore, so
// sold/revenue are permanently frozen at 0 and meaningless. This now counts
// the org's active catalog listings instead.
// Adapter over the shared [StatCard]. Keeps this screen's `count` +
// `loading` call shape while the card itself now lives in one place — and
// renders an em dash rather than a misleading "0" while the stream is
// still connecting.
class _StatCardWidget extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool loading;
  final bool isSelected;
  final VoidCallback? onTap;

  const _StatCardWidget({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.loading,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => StatCard(
    label: label,
    value: loading ? '—' : '$count',
    icon: icon,
    color: color,
    selected: isSelected,
    onTap: onTap,
  );
}

class _MerchSalesStatCard extends StatefulWidget {
  final String orgId;
  final bool isSelected;
  final VoidCallback? onTap;
  const _MerchSalesStatCard({
    required this.orgId,
    this.isSelected = false,
    this.onTap,
  });

  @override
  State<_MerchSalesStatCard> createState() => _MerchSalesStatCardState();
}

class _MerchSalesStatCardState extends State<_MerchSalesStatCard> {
  // Cached once instead of built inline in build() — the sibling stat cards
  // in this row (approved events / pending proposals / upcoming events) tap
  // through a shared setState in the parent, which rebuilds this whole row
  // on every click. An inline `stream:` expression is a *new* Stream object
  // each time, so StreamBuilder tore down and resubscribed a fresh Firestore
  // listener on every single stat-card tap instead of reusing one.
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('products')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isArchived', isEqualTo: false)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (_, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        return StatCard(
          label: 'Merchandise Items',
          value: loading ? '—' : '${snap.data?.docs.length ?? 0}',
          icon: Icons.shopping_bag_rounded,
          color: OrgColors.primaryDark,
          selected: widget.isSelected,
          onTap: widget.onTap,
        );
      },
    );
  }
}

// ── Activity bar chart — monthly proposal counts via fl_chart ────────────────
// A bar per month reads more clearly than a line for discrete counts, and
// fl_chart owns touch/tooltip/scaling, so there's no custom hit-testing math
// left to get wrong.
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
                  color: OrgColors.textFaint,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Default reservedSize (22) is just short of what a 6px top
              // padding plus a fontSize-10 label actually needs — fl_chart
              // clips titles to a fixed box instead of growing it, so that
              // shortfall rendered as a "BOTTOM OVERFLOWED" banner across
              // the whole chart. Same bug, same fix as admin_dashboard.dart's
              // identical chart.
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
                          ? OrgColors.primaryDark
                          : OrgColors.textFaint,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => OrgColors.charcoal,
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
                    ? OrgColors.primaryDark
                    : OrgColors.primaryDark.withAlpha(110),
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

// ─────────────────────────────────────────────────────────────────────────────
// Org Notification Panel
// ─────────────────────────────────────────────────────────────────────────────
class _OrgNotificationPanel extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final void Function(Map<String, dynamic> n) onNotificationTap;
  final GlobalKey bellKey;

  const _OrgNotificationPanel({
    required this.notifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onNotificationTap,
    required this.bellKey,
  });

  @override
  State<_OrgNotificationPanel> createState() => _OrgNotificationPanelState();
}

class _OrgNotificationPanelState extends State<_OrgNotificationPanel> {
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

  // Anchored directly under the actual bell icon (read from its real
  // on-screen position via _bellKey) rather than a guessed fixed inset —
  // the bell has a divider and the org logo/name sitting after it in the
  // top bar, so a hardcoded top-right padding landed the panel well to
  // the side of the bell instead of right under it.
  void _openAllNotifications() {
    final bellBox =
        widget.bellKey.currentContext?.findRenderObject() as RenderBox?;
    final screenWidth = MediaQuery.of(context).size.width;
    double top = 76;
    double right = 28;
    if (bellBox != null) {
      final bellTopLeft = bellBox.localToGlobal(Offset.zero);
      final bellSize = bellBox.size;
      top = bellTopLeft.dy + bellSize.height + 12;
      right = (screenWidth - (bellTopLeft.dx + bellSize.width) - 6).clamp(
        8.0,
        screenWidth - 360,
      );
    }
    Navigator.of(context).pop();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'Notifications',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim, secAnim) {
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: top, right: right),
            child: Material(
              color: Colors.white,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: OrgColors.border, width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 360,
                  minWidth: 360,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: OrgColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'All Notifications',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: OrgColors.charcoal,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: _notifs.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No notifications yet',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: OrgColors.textFaint,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _buildGroupedItems(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
  // row showing the same generic bell — mirrors the admin notification
  // panel's _notifTypeMeta, mapped to the types admin actually sends to
  // orgs (proposal decisions, letter status, and deadline reminders).
  static const Map<String, List<Object>> _notifTypeMeta = {
    'proposal_status': [Icons.description_rounded, Color(0xFF2563EB)],
    'proposal_revision': [Icons.edit_note_rounded, Color(0xFFD97706)],
    'letter_status': [Icons.mail_rounded, Color(0xFF7C3AED)],
    'deadline_reminder': [Icons.alarm_rounded, Color(0xFFDC2626)],
  };

  List<Object> _metaFor(String? type) =>
      _notifTypeMeta[type] ??
      const [Icons.notifications_rounded, OrgColors.primaryDark];

  // Row is a StatefulBuilder so it can track its own hover flag, matching
  // the admin notification panel's hover treatment instead of the flat,
  // static look this had.
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
                    ? OrgColors.lightGray
                    : (isRead ? Colors.white : const Color(0xFFFFF7ED)),
                border: Border(
                  left: BorderSide(
                    color: isRead ? Colors.transparent : OrgColors.primaryDark,
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
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 6, top: 4),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? OrgColors.border
                                    : OrgColors.primaryDark,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                n['title']?.toString() ?? 'Notification',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                  color: isRead
                                      ? OrgColors.darkGray
                                      : OrgColors.charcoal,
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
                                color: OrgColors.textFaint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n['message']?.toString() ?? '',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: OrgColors.darkGray,
                            height: 1.45,
                          ),
                          maxLines: 3,
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
          color: OrgColors.lightGray,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: Text(
            groupKey,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OrgColors.darkGray,
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

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifs.where((n) => n['isRead'] == false).length;

    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: OrgColors.border)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.beVietnamPro(
                    color: OrgColors.charcoal,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (unreadCount > 0)
                  InkWell(
                    onTap: _markAll,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.done_all_rounded,
                            size: 15,
                            color: OrgColors.primaryDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Mark all as read',
                            style: GoogleFonts.beVietnamPro(
                              color: OrgColors.primaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                    decoration: BoxDecoration(
                      color: OrgColors.lightGray,
                      shape: BoxShape.circle,
                      border: Border.all(color: OrgColors.border),
                    ),
                    child: const Icon(
                      Icons.notifications_off_outlined,
                      size: 24,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: OrgColors.textMid,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "You're all caught up!",
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: OrgColors.textFaint,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildGroupedItems(),
                  ),
                ),
              ),
            ),
          // Footer
          if (_notifs.isNotEmpty)
            InkWell(
              onTap: _openAllNotifications,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: OrgColors.border)),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Text(
                  'View all notifications',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: OrgColors.primaryDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MerchRow extends StatelessWidget {
  final String name;
  final int stock;
  final double price;
  const _MerchRow({
    required this.name,
    required this.stock,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OrgColors.charcoal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Stock: $stock',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: OrgColors.textFaint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '\u20B1${price.toStringAsFixed(0)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: OrgColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
