// lib/screens/student/student_events_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:uprise/models/event_model.dart';
import '../../widgets/student/event_image.dart';
import '../../utils/feedback_helper.dart';
import '../../widgets/common/review_identity.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/common/loading_widget.dart' show SkeletonLoader;
import '../../widgets/common/calendar_month.dart';
import '../../widgets/common/event_badges.dart';
import '../../widgets/common/event_browsing.dart';
import '../../widgets/common/event_card.dart';
import '../../widgets/common/info_tile.dart';
import '../../widgets/student/student_app_bar.dart';
import 'student_certificates_screen.dart';
import 'student_webinar_code_screen.dart';
import 'student_organization_details_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../services/webinar_attendance_service.dart';
import '../../services/certificate_auto_issue_service.dart';

/// Maps this screen's domain model onto the shared card's data struct.
///
/// [EventCardData] deliberately knows nothing about [EventModel] — see
/// widgets/common/event_card.dart — so the mapping lives here instead.
/// `displayCategory` rather than `category`, so an event filed under "Other"
/// shows its custom label; `feedCategoryColor` then falls through to its
/// default grey for that label, which is the right colour for "Other" anyway.
EventCardData eventCardData(EventModel e) => EventCardData(
  title: e.title,
  category: e.displayCategory,
  imageUrl: e.imageUrl,
  dateLabel: e.formattedDate,
  timeLabel: e.formattedTime,
  location: e.location,
);

/// Maps `organizations` docs onto the shared dropdown's option struct.
///
/// `orgName` is the field the org portal writes; `name` is what the older
/// records carry, and both org pickers in the app already fall back that way.
List<OrgOption> orgOptions(List<QueryDocumentSnapshot> docs) => [
  for (final doc in docs)
    OrgOption(
      id: doc.id,
      name:
          ((doc.data() as Map<String, dynamic>)['orgName'] ??
                  (doc.data() as Map<String, dynamic>)['name'] ??
                  'Organization')
              .toString(),
    ),
];

// ─── MAIN SCREEN ──────────────────────────────────────────────
class StudentEventsScreen extends StatefulWidget {
  final int initialTabIndex;
  // Bumped by the caller on every explicit "jump to sub-tab" request (e.g.
  // Profile's "See All Registrations"). Comparing this instead of
  // initialTabIndex directly means a second jump to the *same* sub-tab
  // still animates there even if the student manually swiped elsewhere in
  // between — comparing initialTabIndex alone would see no change and
  // silently no-op.
  final int jumpToken;
  const StudentEventsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.jumpToken = 0,
  });

  @override
  State<StudentEventsScreen> createState() => _StudentEventsScreenState();
}

class _StudentEventsScreenState extends State<StudentEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Stream of registered event IDs (shared across tabs)
  late final Stream<Set<String>> _registeredEventIdsStream = () {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream<Set<String>>.value(<String>{});
    return FirebaseFirestore.instance
        .collection('registrations')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d['eventId'] as String).toSet());
  }();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void didUpdateWidget(covariant StudentEventsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Now that student_home_screen.dart keeps this screen alive in an
    // IndexedStack instead of recreating it per tab switch, initialIndex
    // alone (read only in initState) would no longer respond to a fresh
    // "jump to sub-tab N" request — e.g. Profile's "See All Registrations"
    // passing eventsSubTab: 1 — since the widget is only ever constructed
    // once now.
    if (widget.jumpToken != oldWidget.jumpToken) {
      _tabController.animateTo(widget.initialTabIndex.clamp(0, 2));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openCertificates() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentCertificatesScreen()),
    );
  }

  void _openWebinarCode() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentWebinarCodeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Events',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openWebinarCode,
            icon: Icon(
              Icons.qr_code_scanner_rounded,
              color: AppColors.primaryDark,
              size: 26,
            ),
            tooltip: 'Enter Webinar Code',
          ),
          IconButton(
            onPressed: _openCertificates,
            icon: Icon(
              Icons.workspace_premium,
              color: AppColors.primaryDark,
              size: 28,
            ),
            tooltip: 'Certificates',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryDark,
          labelColor: AppColors.primaryDark,
          unselectedLabelColor: Colors.black45,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Discover'),
            Tab(text: 'Calendar'),
            Tab(text: 'My Events'),
          ],
        ),
      ),
      // Discover | Calendar | My Events — Registered and Evaluations used
      // to be separate tabs; they're merged into My Events now (a single
      // registered event naturally carries a Registered -> Needs Feedback
      // -> Completed status instead of living in two different tabs
      // depending on where it is in that lifecycle).
      body: TabBarView(
        controller: _tabController,
        children: [
          UpcomingTab(registeredEventIdsStream: _registeredEventIdsStream),
          CalendarTab(registeredEventIdsStream: _registeredEventIdsStream),
          MyEventsTab(registeredEventIdsStream: _registeredEventIdsStream),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  TAB 1: CALENDAR
// ═══════════════════════════════════════════════════════════════
class CalendarTab extends StatefulWidget {
  final Stream<Set<String>> registeredEventIdsStream;
  const CalendarTab({required this.registeredEventIdsStream, super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _currentMonth = DateTime.now();

  late final Stream<QuerySnapshot> _approvedEventsStream = FirebaseFirestore
      .instance
      .collection('events')
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  void _previousMonth() => setState(() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
  });
  void _nextMonth() => setState(() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
  });
  void _goToday() => setState(() {
    _currentMonth = DateTime.now();
  });

  void _openDetail(EventModel event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          onRegistered: () => setState(() {}),
          isPastEvent: event.isPast,
        ),
      ),
    );
  }

  void _showDaySheet(int day, List<EventModel> events) {
    final label = DateFormat(
      'EEEE, MMMM d, yyyy',
    ).format(DateTime(_currentMonth.year, _currentMonth.month, day));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_rounded,
                        color: AppColors.primaryDark,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            '${events.length} event${events.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Events
              Expanded(
                child: ListView.separated(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _openDetail(events[i]);
                    },
                    child: _CompactEventCard(
                      event: events[i],
                      onTap: () {
                        Navigator.pop(context);
                        _openDetail(events[i]);
                      },
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _approvedEventsStream,
      builder: (context, snap) {
        Map<int, List<EventModel>> byDay = {};
        if (snap.hasData) {
          final events = snap.data!.docs
              .map((d) => EventModel.fromFirestore(d))
              .where(
                (e) =>
                    e.date.year == _currentMonth.year &&
                    e.date.month == _currentMonth.month,
              )
              .toList();
          for (final e in events) {
            byDay.putIfAbsent(e.date.day, () => []).add(e);
          }
        }

        final upcomingEvents = snap.hasData
            ? (snap.data!.docs
                  .map((d) => EventModel.fromFirestore(d))
                  .where(
                    (e) => e.date.isAfter(
                      DateTime.now().subtract(const Duration(days: 1)),
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date)))
            : <EventModel>[];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month nav
              MonthNav(
                currentMonth: _currentMonth,
                onPrev: _previousMonth,
                onNext: _nextMonth,
                onToday: _goToday,
              ),
              const SizedBox(height: 16),
              // Calendar grid
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.03),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: MonthCalendarGrid<EventModel>(
                  key: ValueKey('${_currentMonth.year}-${_currentMonth.month}'),
                  currentMonth: _currentMonth,
                  byDay: byDay,
                  titleOf: (e) => e.title,
                  categoryOf: (e) => e.category,
                  onDayTap: (day, events) => _showDaySheet(day, events),
                ),
              ),
              const SizedBox(height: 20),
              // Upcoming events
              _UpcomingSection(events: upcomingEvents, onTap: _openDetail),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  TAB 2: UPCOMING
// ═══════════════════════════════════════════════════════════════
class UpcomingTab extends StatefulWidget {
  final Stream<Set<String>> registeredEventIdsStream;
  const UpcomingTab({required this.registeredEventIdsStream, super.key});

  @override
  State<UpcomingTab> createState() => _UpcomingTabState();
}

class _UpcomingTabState extends State<UpcomingTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _compactView = false;

  // ── Inline landing filters ──
  // Status chip, search text and org all filter the landing page in place
  // (AND-ed together); none of them navigate. null status = no chip active.
  _RegStatus? _activeStatus;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedOrgId; // null = All Organizations

  // Skeleton shown for a beat after each filter change so rapid typing
  // doesn't thrash the list; the timer collapses repeated keystrokes.
  Timer? _searchDebounce;
  bool _showSkeleton = false;

  bool get _hasInlineFilter =>
      _searchQuery.trim().isNotEmpty ||
      _activeStatus != null ||
      _selectedOrgId != null;

  // Call inside setState after changing any inline filter.
  void _beginResultsTransition() {
    _searchDebounce?.cancel();
    if (!_hasInlineFilter) {
      _showSkeleton = false;
      return;
    }
    _showSkeleton = true;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _showSkeleton = false);
    });
  }

  void _toggleStatus(_RegStatus status) {
    setState(() {
      _activeStatus = _activeStatus == status ? null : status;
      _beginResultsTransition();
    });
  }

  void _openCategory(String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryEventsScreen(
          category: category,
          initialCompactView: _compactView,
          onCompactViewChanged: (v) => setState(() => _compactView = v),
        ),
      ),
    );
  }

  late final Future<List<QueryDocumentSnapshot>> _orgsFuture = FirebaseFirestore
      .instance
      .collection('organizations')
      .where('status', isEqualTo: 'active')
      .get()
      .then((s) => s.docs);

  // Cached once — this was being created inline in build() before, so
  // every keystroke in the search box (_searchQuery is a setState field)
  // resubscribed the whole events query and flashed the loading spinner
  // on every character typed. Filtering by search/org/status all happens
  // client-side after the snapshot arrives, so the query itself never
  // needs to change.
  late final Stream<QuerySnapshot> _approvedEventsStream = FirebaseFirestore
      .instance
      .collection('events')
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  _RegStatus _statusFor(EventModel event) {
    switch (event.timeStatus) {
      case EventTimeStatus.upcoming:
        return _RegStatus.upcoming;
      case EventTimeStatus.ongoing:
        return _RegStatus.ongoing;
      case EventTimeStatus.completed:
        return _RegStatus.completed;
    }
  }

  String get _emptyStateMessage {
    final q = _searchQuery.trim();
    if (q.isNotEmpty) return 'No events match "$q"';
    switch (_activeStatus) {
      case _RegStatus.upcoming:
        return 'No upcoming events';
      case _RegStatus.ongoing:
        return 'No ongoing events';
      case _RegStatus.completed:
        return 'No past events';
      case null:
        return 'No events found';
    }
  }

  IconData get _emptyStateIcon {
    switch (_activeStatus) {
      case _RegStatus.upcoming:
        return Icons.event_available;
      case _RegStatus.ongoing:
        return Icons.event_repeat;
      case _RegStatus.completed:
      case null:
        return Icons.event_busy;
    }
  }

  // Compact single-select filter chips — tapping one filters the landing
  // page in place, tapping the active one clears it back to the tile grid.
  Widget _buildStatusChips() {
    return FilterChips<_RegStatus>(
      options: const [
        (_RegStatus.upcoming, 'Upcoming'),
        (_RegStatus.ongoing, 'Ongoing'),
        (_RegStatus.completed, 'Past'),
      ],
      selected: _activeStatus,
      onTap: _toggleStatus,
      dotValue: _RegStatus.ongoing,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<Set<String>>(
      stream: widget.registeredEventIdsStream,
      builder: (context, regSnap) {
        final regIds = regSnap.data ?? {};
        return StreamBuilder<QuerySnapshot>(
          stream: _approvedEventsStream,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryDark),
              );
            }

            final orgDropdownAndChips = Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: FutureBuilder<List<QueryDocumentSnapshot>>(
                      future: _orgsFuture,
                      builder: (context, orgSnap) {
                        final orgs = orgSnap.data ?? const [];
                        return OrgFilterDropdown(
                          orgs: orgOptions(orgs),
                          selectedOrgId: _selectedOrgId,
                          onChanged: (id) => setState(() {
                            _selectedOrgId = id;
                            _beginResultsTransition();
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChips(),
                ],
              ),
            );

            final searchBar = Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: EventSearchField(
                controller: _searchCtrl,
                query: _searchQuery,
                hintText: 'Search events or organizations',
                onChanged: (v) => setState(() {
                  _searchQuery = v;
                  _beginResultsTransition();
                }),
                onClear: () => setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _beginResultsTransition();
                }),
              ),
            );

            // Everything below the controls swaps in place: category tiles
            // by default, the filtered results as soon as any of search /
            // status chip / org is active. Only a tile leaves this page.
            final Widget body;
            if (!_hasInlineFilter) {
              body = KeyedSubtree(
                key: const ValueKey('categories'),
                child: CategoryTileGrid(onTap: _openCategory),
              );
            } else if (_showSkeleton) {
              // Scroll view only so the fixed-height placeholders clip
              // instead of overflowing on short screens.
              body = SingleChildScrollView(
                key: const ValueKey('skeleton'),
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: SkeletonLoader(
                  count: _compactView ? 5 : 4,
                  height: _compactView ? 110 : 190,
                  borderRadius: 16,
                ),
              );
            } else {
              final query = _searchQuery.trim().toLowerCase();
              final events =
                  snap.data!.docs.map((d) => EventModel.fromFirestore(d)).where(
                    (e) {
                      if (_activeStatus != null &&
                          _statusFor(e) != _activeStatus) {
                        return false;
                      }
                      if (_selectedOrgId != null && e.orgId != _selectedOrgId) {
                        return false;
                      }
                      if (query.isNotEmpty &&
                          !e.title.toLowerCase().contains(query) &&
                          !e.orgName.toLowerCase().contains(query)) {
                        return false;
                      }
                      return true;
                    },
                  ).toList()..sort(_latestFirst);

              body = Column(
                key: const ValueKey('results'),
                children: [
                  ViewToggleRow(
                    compact: _compactView,
                    onChanged: (v) => setState(() => _compactView = v),
                  ),
                  Expanded(
                    child: EventResultsList(
                      items: [
                        for (final event in events)
                          studentEventListItem(
                            context,
                            event,
                            isRegistered: regIds.contains(event.id),
                            onRegistered: () => setState(() {}),
                          ),
                      ],
                      compact: _compactView,
                      emptyTitle: _emptyStateMessage,
                      emptyIcon: _emptyStateIcon,
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                searchBar,
                orgDropdownAndChips,
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: body,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Not-yet-completed events soonest-first, then completed events
// most-recently-ended-first — generalizes the old "Past sorts descending,
// everything else ascending" special case to a mixed (any-status) list.
int _latestFirst(EventModel a, EventModel b) {
  final aDone = a.timeStatus == EventTimeStatus.completed;
  final bDone = b.timeStatus == EventTimeStatus.completed;
  if (aDone != bDone) return aDone ? 1 : -1;
  return aDone
      ? b.date.compareTo(a.date)
      : a.fullDateTime.compareTo(b.fullDateTime);
}

/// One row of the shared [EventResultsList], as the student sees it: opens the
/// student detail screen, and hangs the rotating webinar code off the banner
/// for a live event this student holds a registration for.
///
/// Used by both the Discover landing page and the per-category screen, so the
/// two keep showing the same card with the same affordances.
EventListItem studentEventListItem(
  BuildContext context,
  EventModel event, {
  required bool isRegistered,
  required VoidCallback onRegistered,
}) {
  final isLive = event.timeStatus == EventTimeStatus.ongoing;
  return EventListItem(
    data: eventCardData(event),
    isRegistered: isRegistered,
    showLiveBadge: isLive,
    bannerOverlay: isLive && isRegistered
        ? _WebinarCodeBanner(eventId: event.id)
        : null,
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          onRegistered: onRegistered,
          isPastEvent: event.isPast,
        ),
      ),
    ),
  );
}

// Per-category results, pushed from a Discover tile — the only thing on the
// Discover landing page that navigates. Its search box and date/sort filters
// are its own; nothing is inherited from the landing page's filters except
// the grid/list preference, which is mirrored back out.
class _CategoryEventsScreen extends StatefulWidget {
  final String category;
  final bool initialCompactView;
  final ValueChanged<bool> onCompactViewChanged;

  const _CategoryEventsScreen({
    required this.category,
    required this.initialCompactView,
    required this.onCompactViewChanged,
  });

  @override
  State<_CategoryEventsScreen> createState() => _CategoryEventsScreenState();
}

class _CategoryEventsScreenState extends State<_CategoryEventsScreen> {
  // These used to be handed down from the landing page, which left this screen
  // stuck on its spinner forever. Firestore's snapshots() is a BROADCAST
  // stream, and a broadcast stream does not replay its latest event to a
  // subscriber that arrives late. The landing page is kept alive by
  // AutomaticKeepAliveClientMixin, so it still holds its subscription and had
  // already consumed the snapshot long before the user tapped a category tile
  // — this screen's StreamBuilder then sat waiting for an event that would
  // only arrive if something in `events` happened to change, and the
  // `!snap.hasData` guard below renders a CircularProgressIndicator until then.
  //
  // The three tabs get away with sharing the parent's stream because they all
  // subscribe at startup, before the first snapshot is delivered.
  //
  // Owning the subscriptions here is also the pattern every other screen in
  // this file already uses.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('events')
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  late final Stream<Set<String>> _registeredEventIdsStream = () {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream<Set<String>>.value(<String>{});
    return FirebaseFirestore.instance
        .collection('registrations')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d['eventId'] as String).toSet());
  }();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late bool _compactView = widget.initialCompactView;

  _DateBucket? _dateBucket;
  DateTime? _customDate;
  _SortBy _sortBy = _SortBy.latest;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setCompactView(bool v) {
    setState(() => _compactView = v);
    widget.onCompactViewChanged(v);
  }

  bool _matchesDateBucket(EventModel e) {
    final bucket = _dateBucket;
    if (bucket == null) return true;
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    switch (bucket) {
      case _DateBucket.today:
        return sameDay(e.date, now);
      case _DateBucket.thisWeek:
        final startOfWeek = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return !e.date.isBefore(startOfWeek) && e.date.isBefore(endOfWeek);
      case _DateBucket.thisMonth:
        return e.date.year == now.year && e.date.month == now.month;
      case _DateBucket.custom:
        return _customDate != null && sameDay(e.date, _customDate!);
    }
  }

  void _sortEvents(List<EventModel> events) {
    switch (_sortBy) {
      case _SortBy.latest:
        events.sort(_latestFirst);
        break;
      case _SortBy.mostPopular:
        events.sort((a, b) {
          final byCount = b.registeredCount.compareTo(a.registeredCount);
          return byCount != 0 ? byCount : _latestFirst(a, b);
        });
        break;
    }
  }

  // Selections stay pending inside the sheet — nothing reaches the results
  // list until "Filter" is tapped, so dismissing the sheet discards them.
  Future<void> _showFilterSheet() async {
    var pendingBucket = _dateBucket;
    var pendingCustom = _customDate;
    var pendingSort = _sortBy;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Widget optionRow({
              required String label,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: selected
                            ? AppColors.primaryDark
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? Colors.black87 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            void pickBucket(_DateBucket bucket) {
              setSheetState(() {
                pendingBucket = pendingBucket == bucket ? null : bucket;
                if (pendingBucket != _DateBucket.custom) pendingCustom = null;
              });
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Text(
                      'Date and Time',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  optionRow(
                    label: 'Today',
                    selected: pendingBucket == _DateBucket.today,
                    onTap: () => pickBucket(_DateBucket.today),
                  ),
                  optionRow(
                    label: 'This Week',
                    selected: pendingBucket == _DateBucket.thisWeek,
                    onTap: () => pickBucket(_DateBucket.thisWeek),
                  ),
                  optionRow(
                    label: 'This Month',
                    selected: pendingBucket == _DateBucket.thisMonth,
                    onTap: () => pickBucket(_DateBucket.thisMonth),
                  ),
                  optionRow(
                    label:
                        pendingBucket == _DateBucket.custom &&
                            pendingCustom != null
                        ? 'Pick a Date — ${DateFormat('MMM d, yyyy').format(pendingCustom!)}'
                        : 'Pick a Date (Custom)',
                    selected: pendingBucket == _DateBucket.custom,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: pendingCustom ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 2),
                        ),
                      );
                      if (picked == null) return;
                      setSheetState(() {
                        pendingBucket = _DateBucket.custom;
                        pendingCustom = picked;
                      });
                    },
                  ),
                  const Divider(height: 24),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'Sort By',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  optionRow(
                    label: 'Latest',
                    selected: pendingSort == _SortBy.latest,
                    onTap: () =>
                        setSheetState(() => pendingSort = _SortBy.latest),
                  ),
                  optionRow(
                    label: 'Most Popular (Most registered event)',
                    selected: pendingSort == _SortBy.mostPopular,
                    onTap: () =>
                        setSheetState(() => pendingSort = _SortBy.mostPopular),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Filter',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied != true || !mounted) return;
    setState(() {
      _dateBucket = pendingBucket;
      _customDate = pendingCustom;
      _sortBy = pendingSort;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeFilterCount =
        (_dateBucket != null ? 1 : 0) + (_sortBy != _SortBy.latest ? 1 : 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          widget.category,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<Set<String>>(
        stream: _registeredEventIdsStream,
        builder: (context, regSnap) {
          final regIds = regSnap.data ?? <String>{};
          return StreamBuilder<QuerySnapshot>(
            stream: _eventsStream,
            builder: (context, snap) {
              // Errors used to fall into the spinner branch below, so a failed
              // query was indistinguishable from one still loading — which is
              // what made the stale-stream bug above look like a hang.
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Failed to load events',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryDark,
                  ),
                );
              }

              final query = _searchQuery.trim().toLowerCase();
              final events = snap.data!.docs
                  .map((d) => EventModel.fromFirestore(d))
                  .where((e) {
                    if (e.category != widget.category) return false;
                    if (query.isNotEmpty &&
                        !e.title.toLowerCase().contains(query) &&
                        !e.orgName.toLowerCase().contains(query)) {
                      return false;
                    }
                    return _matchesDateBucket(e);
                  })
                  .toList();
              _sortEvents(events);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: EventSearchField(
                            controller: _searchCtrl,
                            query: _searchQuery,
                            hintText: 'Search in ${widget.category}',
                            onChanged: (v) => setState(() => _searchQuery = v),
                            onClear: () => setState(() {
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Badge(
                          isLabelVisible: activeFilterCount > 0,
                          label: Text('$activeFilterCount'),
                          child: Material(
                            color: AppColors.primaryDark,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _showFilterSheet,
                              child: const Padding(
                                padding: EdgeInsets.all(11),
                                child: Icon(
                                  Icons.tune_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ViewToggleRow(
                    compact: _compactView,
                    onChanged: _setCompactView,
                  ),
                  Expanded(
                    child: EventResultsList(
                      items: [
                        for (final event in events)
                          studentEventListItem(
                            context,
                            event,
                            isRegistered: regIds.contains(event.id),
                            onRegistered: () => setState(() {}),
                          ),
                      ],
                      compact: _compactView,
                      emptyTitle: query.isNotEmpty
                          ? 'No events match "${_searchQuery.trim()}"'
                          : 'No events in ${widget.category}',
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  TAB 3: REGISTERED EVENTS - FIXED
// ═══════════════════════════════════════════════════════════════
// The student's personal event activity center — merges what used to be
// two separate tabs (Registered, Evaluations). A registered event now
// naturally shows one of: Registered (upcoming or past-but-not-attended),
// Needs Feedback (attended, not yet evaluated), or Completed (evaluated),
// instead of living in two different tabs depending on where it is in
// that lifecycle. Uses the exact same attendance/feedback queries the old
// Evaluations tab used.
class MyEventsTab extends StatefulWidget {
  final Stream<Set<String>> registeredEventIdsStream;
  const MyEventsTab({required this.registeredEventIdsStream, super.key});

  @override
  State<MyEventsTab> createState() => _MyEventsTabState();
}

enum _ViewFilter { all, active, attended }

enum _RegStatus { upcoming, ongoing, completed }

enum _DateBucket { today, thisWeek, thisMonth, custom }

enum _SortBy { latest, mostPopular }

// Activity status for My Events — distinct from _RegStatus (which is a
// pure time-based upcoming/ongoing/past used by the Discover tab).
enum _MyEventStatus { registered, needsFeedback, completed }

class _MyEventsTabState extends State<MyEventsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Stream<QuerySnapshot>? _registrationsStream;
  _ViewFilter _viewFilter = _ViewFilter.all;

  // Inline filters ported from Discover — search box and org picker.
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedOrgId;

  late final Future<List<QueryDocumentSnapshot>> _orgsFuture = FirebaseFirestore
      .instance
      .collection('organizations')
      .where('status', isEqualTo: 'active')
      .get()
      .then((s) => s.docs);

  // Attendance + feedback-submitted event IDs — same two queries the old
  // Evaluations tab used (collectionGroup('attendances') for attendance,
  // both event_feedback and feedback for "already submitted", since the
  // app never finished migrating off the legacy `feedback` collection).
  Future<({Set<String> attended, Set<String> evaluated})>? _statusDataFuture;

  // The events fetch is memoised on the registered event IDs so typing in the
  // search box filters the already-loaded list instead of re-running the
  // Firestore gets (and flashing the spinner) on every keystroke.
  Set<String>? _cachedEventIds;
  Future<List<QuerySnapshot>>? _eventsFuture;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _registrationsStream = FirebaseFirestore.instance
          .collection('registrations')
          .where('userId', isEqualTo: user.uid)
          .snapshots();
      _statusDataFuture = _loadStatusData(user.uid);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasInlineFilter =>
      _searchQuery.trim().isNotEmpty || _selectedOrgId != null;

  Future<({Set<String> attended, Set<String> evaluated})> _loadStatusData(
    String uid,
  ) async {
    final attendanceSnap = await FirebaseFirestore.instance
        .collectionGroup('attendances')
        .where('studentId', isEqualTo: uid)
        .get();
    final attended = <String>{};
    for (final doc in attendanceSnap.docs) {
      final status = doc.data()['status']?.toString() ?? '';
      if (status != 'present' && status != 'late') continue;
      final eventRef = doc.reference.parent.parent;
      if (eventRef != null) attended.add(eventRef.id);
    }

    final evaluated = <String>{};
    final fb1 = await FirebaseFirestore.instance
        .collection('event_feedback')
        .where('userId', isEqualTo: uid)
        .get();
    for (final doc in fb1.docs) {
      final eid = doc.data()['eventId']?.toString();
      if (eid != null && eid.isNotEmpty) evaluated.add(eid);
    }
    final fb2 = await FirebaseFirestore.instance
        .collection('feedback')
        .where('userId', isEqualTo: uid)
        .get();
    for (final doc in fb2.docs) {
      final eid = doc.data()['eventId']?.toString();
      if (eid != null && eid.isNotEmpty) evaluated.add(eid);
    }
    return (attended: attended, evaluated: evaluated);
  }

  _MyEventStatus _myEventStatusFor(
    EventModel event,
    _RegStatus timeStatus,
    Set<String> attended,
    Set<String> evaluated,
  ) {
    if (timeStatus != _RegStatus.completed) return _MyEventStatus.registered;
    if (!attended.contains(event.id)) return _MyEventStatus.registered;
    if (evaluated.contains(event.id)) return _MyEventStatus.completed;
    return _MyEventStatus.needsFeedback;
  }

  ({String label, Color color}) _myStatusStyle(_MyEventStatus status) {
    switch (status) {
      case _MyEventStatus.registered:
        return (label: 'REGISTERED', color: const Color(0xFF2563EB));
      case _MyEventStatus.needsFeedback:
        return (label: 'NEEDS FEEDBACK', color: const Color(0xFFD97706));
      case _MyEventStatus.completed:
        return (label: 'COMPLETED', color: const Color(0xFF059669));
    }
  }

  _RegStatus _statusFor(EventModel event) {
    switch (event.timeStatus) {
      case EventTimeStatus.upcoming:
        return _RegStatus.upcoming;
      case EventTimeStatus.ongoing:
        return _RegStatus.ongoing;
      case EventTimeStatus.completed:
        return _RegStatus.completed;
    }
  }

  void _openDetail(EventModel event, bool isPast) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          onRegistered: () => setState(() {}),
          isPastEvent: isPast,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_registrationsStream == null) {
      return const Center(
        child: Text(
          'Please log in to see your registered events.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _registrationsStream,
      builder: (context, regSnap) {
        if (regSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryDark),
          );
        }
        if (regSnap.hasError) {
          return Center(
            child: Text(
              'Failed to load registrations',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        // Get all event IDs from registrations
        final allRegistrationData = regSnap.data?.docs ?? [];

        final eventIds = allRegistrationData
            .map(
              (d) => (d.data() as Map<String, dynamic>)['eventId'] as String?,
            )
            .whereType<String>()
            .toSet()
            .toList();

        // ⭐ FIX: Build the UI with filter buttons ALWAYS visible
        return Column(
          children: [
            // ─── Search ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search events or organizations',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                          }),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // ─── Organization filter + view chips ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: FutureBuilder<List<QueryDocumentSnapshot>>(
                      future: _orgsFuture,
                      builder: (context, orgSnap) {
                        final orgs = orgSnap.data ?? const [];
                        return OrgFilterDropdown(
                          orgs: orgOptions(orgs),
                          selectedOrgId: _selectedOrgId,
                          onChanged: (id) =>
                              setState(() => _selectedOrgId = id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChips<_ViewFilter>(
                    options: const [
                      (_ViewFilter.all, 'All'),
                      (_ViewFilter.active, 'Active'),
                      (_ViewFilter.attended, 'Attended'),
                    ],
                    selected: _viewFilter,
                    // Single-select: tapping the active chip keeps it, since
                    // `all` is already the cleared state.
                    onTap: (v) => setState(() => _viewFilter = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // ─── Content Area ───
            Expanded(
              child:
                  FutureBuilder<
                    ({Set<String> attended, Set<String> evaluated})
                  >(
                    future: _statusDataFuture,
                    builder: (context, statusSnap) {
                      final attended = statusSnap.data?.attended ?? const {};
                      final evaluated = statusSnap.data?.evaluated ?? const {};
                      return _buildContent(eventIds, attended, evaluated);
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    List<String> eventIds,
    Set<String> attended,
    Set<String> evaluated,
  ) {
    if (eventIds.isEmpty) {
      return _emptyState('No registered events', Icons.event_note_outlined);
    }

    // Only re-fetch when the set of registered events actually changes —
    // otherwise every keystroke in the search box would re-run these gets.
    final idSet = eventIds.toSet();
    final cached = _cachedEventIds;
    if (_eventsFuture == null ||
        cached == null ||
        cached.length != idSet.length ||
        !cached.containsAll(idSet)) {
      final chunks = <List<String>>[];
      for (var i = 0; i < eventIds.length; i += 30) {
        chunks.add(
          eventIds.sublist(
            i,
            i + 30 > eventIds.length ? eventIds.length : i + 30,
          ),
        );
      }
      _cachedEventIds = idSet;
      _eventsFuture = Future.wait(
        chunks.map(
          (chunk) => FirebaseFirestore.instance
              .collection('events')
              .where(FieldPath.documentId, whereIn: chunk)
              .get(),
        ),
      );
    }

    return FutureBuilder<List<QuerySnapshot>>(
      future: _eventsFuture,
      builder: (context, evSnap) {
        if (evSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryDark),
          );
        }
        if (evSnap.hasError || !evSnap.hasData) {
          return Center(
            child: Text(
              'Failed to load events',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        var events = evSnap.data!
            .expand((snap) => snap.docs)
            .map((d) => EventModel.fromFirestore(d))
            .toList();

        switch (_viewFilter) {
          case _ViewFilter.active:
            events = events
                .where((e) => _statusFor(e) != _RegStatus.completed)
                .toList();
            break;
          case _ViewFilter.attended:
            events = events.where((e) => attended.contains(e.id)).toList();
            break;
          case _ViewFilter.all:
            break;
        }

        // Inline filters (search / org) narrow within the selected chip —
        // same predicate shape the Discover tab uses.
        final query = _searchQuery.trim().toLowerCase();
        events = events.where((e) {
          if (_selectedOrgId != null && e.orgId != _selectedOrgId) {
            return false;
          }
          if (query.isNotEmpty &&
              !e.title.toLowerCase().contains(query) &&
              !e.orgName.toLowerCase().contains(query)) {
            return false;
          }
          return true;
        }).toList();

        if (events.isEmpty) {
          if (_hasInlineFilter) {
            return _emptyState(
              query.isNotEmpty
                  ? 'No events match "${_searchQuery.trim()}"'
                  : 'No events match your filters',
              Icons.search_off,
            );
          }
          switch (_viewFilter) {
            case _ViewFilter.active:
              return _emptyState('No active events', Icons.event_busy_outlined);
            case _ViewFilter.attended:
              return _emptyState(
                'No attended events yet',
                Icons.task_alt_outlined,
              );
            case _ViewFilter.all:
              return _emptyState(
                'No registered events',
                Icons.event_note_outlined,
              );
          }
        }

        // Needs Feedback first (most actionable), then Registered (soonest
        // first), then Completed (most recently finished first).
        events.sort((a, b) {
          final sa = _myEventStatusFor(a, _statusFor(a), attended, evaluated);
          final sb = _myEventStatusFor(b, _statusFor(b), attended, evaluated);
          if (sa != sb) {
            const order = {
              _MyEventStatus.needsFeedback: 0,
              _MyEventStatus.registered: 1,
              _MyEventStatus.completed: 2,
            };
            return order[sa]!.compareTo(order[sb]!);
          }
          return sa == _MyEventStatus.completed
              ? b.date.compareTo(a.date)
              : a.date.compareTo(b.date);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 100,
          ),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final myStatus = _myEventStatusFor(
              event,
              _statusFor(event),
              attended,
              evaluated,
            );
            final style = _myStatusStyle(myStatus);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      EventImage(
                        imageUrl: event.imageUrl,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        showLoadingIndicator: true,
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: style.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            style.label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.orgName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              event.formattedDate,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.formattedTime,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.location,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _openDetail(
                                  event,
                                  _statusFor(event) == _RegStatus.completed,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      myStatus == _MyEventStatus.needsFeedback
                                      ? style.color
                                      : AppColors.primaryDark,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  myStatus == _MyEventStatus.needsFeedback
                                      ? 'Give Feedback'
                                      : 'View',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
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
            );
          },
        );
      },
    );
  }
}

// Evaluations used to be a separate tab (EvaluationsTab/_EvaluationCard) —
// merged into MyEventsTab below, which now computes the same
// attended-but-not-evaluated status per event instead of keeping a
// separate queue screen.

// ─── UPCOMING EVENTS SECTION ───────────────────────────────────
class _UpcomingSection extends StatelessWidget {
  final List<EventModel> events;
  final void Function(EventModel) onTap;

  const _UpcomingSection({required this.events, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDEDEF)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 26,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No events this month',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check back later or browse another month above.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final upcoming = events.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upcoming Events',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...upcoming.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CompactEventCard(event: e, onTap: () => onTap(e)),
          ),
        ),
      ],
    );
  }
}

// ─── COMPACT EVENT CARD ────────────────────────────────────────
class _CompactEventCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _CompactEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: EventImage(
                  imageUrl: event.imageUrl,
                  height: 70,
                  width: 70,
                  fit: BoxFit.cover,
                  showLoadingIndicator: false,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.formattedTime,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  backgroundColor: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LIVE WEBINAR CODE BANNER (registered students, ongoing events) ────────
// Streams the org-side rotating code (webinar_attendance_service.dart) so a
// registered student sees the current code — and a one-tap check-in/out
// button — right on the event card instead of hunting for a separate entry
// screen and retyping a code they can already see.
class _WebinarCodeBanner extends StatelessWidget {
  final String eventId;
  const _WebinarCodeBanner({required this.eventId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WebinarAttendanceService.sessionStream(eventId),
      builder: (context, sessionSnap) {
        final session = sessionSnap.data?.data();
        if (session == null || session['isActive'] != true) {
          return const SizedBox.shrink();
        }
        final phase = (session['phase'] as String?) ?? 'checkin';
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: WebinarAttendanceService.codeStream(eventId, phase),
          builder: (context, codeSnap) {
            final codeData = codeSnap.data?.data();
            final code = codeData?['code'] as String?;
            final expiresAt = (codeData?['expiresAt'] as Timestamp?)?.toDate();
            if (code == null || code.isEmpty || expiresAt == null) {
              return const SizedBox.shrink();
            }
            return _WebinarCodeCard(
              eventId: eventId,
              phase: phase,
              code: code,
              expiresAt: expiresAt,
            );
          },
        );
      },
    );
  }
}

class _WebinarCodeCard extends StatefulWidget {
  final String eventId;
  final String phase;
  final String code;
  final DateTime expiresAt;

  const _WebinarCodeCard({
    required this.eventId,
    required this.phase,
    required this.code,
    required this.expiresAt,
  });

  @override
  State<_WebinarCodeCard> createState() => _WebinarCodeCardState();
}

class _WebinarCodeCardState extends State<_WebinarCodeCard> {
  Timer? _tick;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Just to keep the countdown text fresh — the code value itself updates
    // via the Firestore stream in the parent, not this timer.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _checkIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _submitting) return;
    setState(() => _submitting = true);
    final result = await WebinarAttendanceService.submitCode(
      eventDocId: widget.eventId,
      studentUid: user.uid,
      submittedCode: widget.code,
      type: widget.phase,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final isCheckout = widget.phase == 'checkout';
    String message;
    switch (result) {
      case 'success':
        message = isCheckout
            ? 'Checked out successfully!'
            : 'Attendance recorded!';
        break;
      case 'duplicate':
        message = isCheckout ? 'Already checked out.' : 'Already checked in.';
        break;
      case 'expired':
        message = 'That code just expired — wait for the next one.';
        break;
      case 'not_checked_in':
        message = 'Check in first before checking out.';
        break;
      case 'not_registered':
        message = 'You need to register for this event before checking in.';
        break;
      case 'session_inactive':
        message = 'Attendance is not open right now.';
        break;
      default:
        message = 'Something went wrong. Please try again.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: result == 'success'
            ? Colors.green.shade700
            : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return const SizedBox.shrink();
    final seconds = remaining.inSeconds.clamp(0, 999);
    final isCheckout = widget.phase == 'checkout';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.74),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_tethering_rounded,
            color: Colors.greenAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCheckout
                      ? 'CHECK-OUT CODE · ${seconds}s'
                      : 'CHECK-IN CODE · ${seconds}s',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  widget.code,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _submitting ? null : _checkIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isCheckout ? 'Check Out' : 'Check In',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CATEGORY BADGE ────────────────────────────────────────────
class EventDetailScreen extends StatefulWidget {
  final EventModel event;
  final VoidCallback onRegistered;
  final bool isPastEvent;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.onRegistered,
    required this.isPastEvent,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _isLoading = false;
  bool _loadingForm = true;
  bool _isRegistered = false;
  Map<String, dynamic>? _formDef;

  // The signed-in student's own users/{uid} doc — fetched once so the
  // Register button can be disabled up-front for audience-restricted
  // events (CICT Only / Members Only / BulSUan) the student doesn't
  // qualify for, instead of only rejecting the write server-side after
  // they've already filled out the whole form.
  Map<String, dynamic>? _userData;
  // students/{uid}.course — needed for the "CICT Only" audience check
  // (course isn't on the users doc, only on the students one).
  String? _studentCourse;
  bool _loadingUserData = true;
  bool get _isEligibleForEvent => EventModel.audienceAllowsMember(
    audience: widget.event.audience,
    eventOrgId: widget.event.orgId,
    userData: _userData,
    course: _studentCourse,
  );
  final Map<String, TextEditingController> _fieldControllers = {};
  final Map<String, String?> _singleChoice = {};
  final Map<String, Set<String>> _multiChoice = {};
  // 'file_upload' question answers — images are compressed and stored as a
  // base64 data URI directly on the value (same convention org screens
  // already use for product/banner photos); videos go to Firebase Storage
  // instead since they'd blow past Firestore's 1 MiB document limit even
  // compressed, so the value is a download URL for those.
  final Map<String, String> _fileUploadValues = {};
  final Map<String, String> _fileUploadNames = {};
  final Map<String, bool> _fileUploadBusy = {};

  // Whether this student has actually been marked present/late for this
  // event (via QR/manual check-in) — separate from _isRegistered, since
  // registering for an event doesn't mean you showed up to it.
  bool _hasAttended = false;

  // Only tracked when the event has a capacity set — unlimited events skip
  // this query entirely since there's nothing to compare against.
  int? _registeredCount;
  bool get _isFull =>
      widget.event.capacity != null &&
      _registeredCount != null &&
      _registeredCount! >= widget.event.capacity!;

  int _rating = 0;
  final TextEditingController _feedbackCtrl = TextEditingController();
  String? _existingFeedbackDocId;
  bool _feedbackSubmitted = false;
  bool _isAnonymous = false;
  bool _checkingFeedback = true;
  bool _submittingFeedback = false;

  bool get _isEventReallyOver =>
      widget.event.timeStatus == EventTimeStatus.completed;

  /// Registration closes the moment an event starts — you can't sign up for
  /// something already underway. Reads the same `timeStatus` that drives the
  /// LIVE badge on the event cards, so the two can't disagree about whether an
  /// event has begun.
  bool get _registrationOpen =>
      widget.event.timeStatus == EventTimeStatus.upcoming;

  /// Why the Register button is disabled, or null while it's usable.
  String? get _registrationClosedReason => switch (widget.event.timeStatus) {
    EventTimeStatus.upcoming => null,
    EventTimeStatus.ongoing => 'Registration closed — event has started',
    EventTimeStatus.completed => 'Registration closed — event has ended',
  };

  // Certificate status for the My Event section — same `certificates`
  // collection and `recipientUid` field the Certificates screen already
  // queries, just scoped to this one event via `eventId`.
  late final Future<QuerySnapshot<Map<String, dynamic>>> _certFuture =
      _loadCertStatus();

  Future<QuerySnapshot<Map<String, dynamic>>> _loadCertStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FirebaseFirestore.instance
        .collection('certificates')
        .where('recipientUid', isEqualTo: uid)
        .where('eventId', isEqualTo: widget.event.id)
        .get();
  }

  @override
  void initState() {
    super.initState();
    _loadRegistrationForm();
    _checkRegistrationStatus();
    _checkAttendanceStatus();
    _loadUserData();
    if (widget.event.capacity != null) _loadRegisteredCount();
    if (_isEventReallyOver) {
      _checkFeedbackStatus();
    } else {
      _checkingFeedback = false;
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingUserData = false);
      return;
    }
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('students').doc(user.uid).get(),
      ]);
      if (mounted) {
        setState(() {
          _userData = results[0].data();
          _studentCourse = (results[1].data()?['course'] as String?);
          _loadingUserData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUserData = false);
    }
  }

  Future<void> _loadRegisteredCount() async {
    // Reads the same `registeredCount` field the registration transaction
    // maintains, instead of a separate `.count()` query — one doc read,
    // and it can never disagree with the number the capacity gate itself
    // is enforcing.
    final evDoc = await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.event.id)
        .get();
    if (mounted) {
      setState(
        () => _registeredCount =
            (evDoc.data()?['registeredCount'] as num?)?.toInt() ?? 0,
      );
    }
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkRegistrationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('registrations')
        .where('userId', isEqualTo: user.uid)
        .where('eventId', isEqualTo: widget.event.id)
        .get();
    if (mounted) {
      setState(() => _isRegistered = snap.docs.isNotEmpty);
    }
  }

  // Attendance is per-event-per-student, keyed by uid, under
  // events/{eventId}/attendances/{uid} — written by org_attendance_qr.dart
  // on QR scan or manual check-in. Only 'present' or 'late' count as
  // actually attended; a doc simply existing isn't enough on its own since
  // nothing else writes to this subcollection with another status today,
  // but checking the value explicitly keeps this correct if that changes.
  DateTime? _attendanceTimestamp;
  String? _attendanceStatusRaw;

  Future<void> _checkAttendanceStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('attendances')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final status = data?['status']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _hasAttended = status == 'present' || status == 'late';
          _attendanceStatusRaw = status.isEmpty ? null : status;
          _attendanceTimestamp = (data?['timestamp'] as Timestamp?)?.toDate();
        });
      }
    } catch (_) {
      // Leave _hasAttended false — the feedback section just stays hidden.
    }
  }

  // Reads from `event_feedback` (not the unrelated `feedback` collection
  // this used to write to) — org_certificates.dart's auto-certificate gate
  // and manual "Generate & Distribute" both check event_feedback for
  // `userId`, so feedback submitted here now actually counts toward the
  // student's certificate eligibility instead of going nowhere.
  Future<void> _checkFeedbackStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _checkingFeedback = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('event_feedback')
          .where('eventId', isEqualTo: widget.event.id)
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (mounted) {
        setState(() {
          if (snap.docs.isNotEmpty) {
            final doc = snap.docs.first;
            final d = doc.data();
            _existingFeedbackDocId = doc.id;
            _feedbackSubmitted = true;
            _rating = (d['rating'] ?? 0) as int;
            _feedbackCtrl.text = (d['comment'] ?? '').toString();
            _isAnonymous = d['isAnonymous'] == true;
          }
          _checkingFeedback = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingFeedback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load feedback status: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to submit feedback'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _submittingFeedback = true);
    try {
      // authorName only when the reviewer opted in to attribution — an
      // anonymous review stores no name at all, so there is nothing for a
      // display bug to leak later. FieldValue.delete() on the anonymous path
      // clears a name left behind by an earlier attributed submission, since
      // this write merges into an existing doc.
      final authorName = _isAnonymous
          ? ''
          : await FeedbackHelper.currentStudentReviewerName();

      final data = {
        'eventId': widget.event.id,
        'eventName': widget.event.title,
        'organization': widget.event.orgName,
        'orgId': widget.event.orgId,
        'rating': _rating,
        'comment': _feedbackCtrl.text.trim(),
        'userId': user.uid,
        'isAnonymous': _isAnonymous,
        'authorName': authorName.isNotEmpty ? authorName : FieldValue.delete(),
        'submittedAt': FieldValue.serverTimestamp(),
      };
      final feedbackCol = FirebaseFirestore.instance.collection(
        'event_feedback',
      );
      if (_existingFeedbackDocId != null) {
        await feedbackCol
            .doc(_existingFeedbackDocId)
            .set(data, SetOptions(merge: true));
      } else {
        final ref = await feedbackCol.add(data);
        _existingFeedbackDocId = ref.id;
      }

      // If the org already distributed certificates for this event before
      // this feedback came in, issue this student's certificate right now
      // instead of leaving them waiting for the org to re-run it.
      await CertificateAutoIssueService.tryIssueForFeedback(
        eventDocId: widget.event.id,
        recipientKey: user.uid,
        isGuest: false,
      );

      if (mounted) {
        setState(() {
          _feedbackSubmitted = true;
          _submittingFeedback = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
        // Return to previous screen
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submittingFeedback = false);
        final msg = e.toString().toLowerCase().contains('permission')
            ? 'Failed to submit: missing Firestore permission for "event_feedback" collection. Check your security rules.'
            : 'Failed to submit feedback: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Widget _buildStarSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = starIndex <= _rating;
        return GestureDetector(
          onTap: _feedbackSubmitted
              ? null
              : () => setState(() => _rating = starIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: 36,
              color: filled ? const Color(0xFFFBBF24) : Colors.grey.shade400,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMyEventSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDark.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_available_rounded,
                size: 16,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Text(
                'MY EVENT',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildAttendanceStatusRow(),
          const SizedBox(height: 12),
          _buildCertificateStatusRow(),
        ],
      ),
    );
  }

  Widget _myEventStatusRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // Digital ID QR scanning (org_attendance_qr.dart) stays the primary
  // attendance path and isn't touched here — this only surfaces the
  // status that path already writes, plus the existing alternate
  // "enter a code" path (StudentWebinarCodeScreen) for when scanning
  // isn't available.
  Widget _buildAttendanceStatusRow() {
    if (_hasAttended) {
      final ts = _attendanceTimestamp;
      final late = _attendanceStatusRaw == 'late';
      final value = ts != null
          ? '${late ? 'Late' : 'Present'} — ${DateFormat('MMM dd, yyyy • h:mm a').format(ts)}'
          : (late ? 'Marked late' : 'Attendance Recorded');
      return _myEventStatusRow(
        icon: Icons.verified_rounded,
        iconColor: Colors.green.shade600,
        label: 'Attendance',
        value: value,
      );
    }
    if (_isEventReallyOver) {
      return _myEventStatusRow(
        icon: Icons.cancel_outlined,
        iconColor: Colors.grey,
        label: 'Attendance',
        value: 'Not recorded',
      );
    }
    return _myEventStatusRow(
      icon: Icons.schedule_rounded,
      iconColor: Colors.orange.shade700,
      label: 'Attendance',
      value: 'Not yet recorded',
      trailing: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudentWebinarCodeScreen()),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Enter Code',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildCertificateStatusRow() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _certFuture,
      builder: (context, snap) {
        final hasCert = (snap.data?.docs.length ?? 0) > 0;
        if (!hasCert) {
          return _myEventStatusRow(
            icon: Icons.workspace_premium_outlined,
            iconColor: Colors.grey,
            label: 'Certificate',
            value: 'Not yet available',
          );
        }
        return _myEventStatusRow(
          icon: Icons.workspace_premium_rounded,
          iconColor: const Color(0xFFD97706),
          label: 'Certificate',
          value: 'Available',
          trailing: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const StudentCertificatesScreen(),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'View',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedbackSection() {
    if (_checkingFeedback) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _feedbackSubmitted ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _feedbackSubmitted
              ? Colors.green.shade200
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _feedbackSubmitted
                    ? Icons.check_circle_rounded
                    : Icons.rate_review_rounded,
                color: _feedbackSubmitted
                    ? Colors.green
                    : AppColors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _feedbackSubmitted ? 'Feedback Submitted' : 'Rate this event',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _feedbackSubmitted
                      ? Colors.green.shade700
                      : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStarSelector(),
          const SizedBox(height: 14),
          TextField(
            controller: _feedbackCtrl,
            readOnly: _feedbackSubmitted,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Share your thoughts about this event (optional)',
              hintStyle: const TextStyle(fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.primaryDark,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The treatment this block used to spell out inline is now the
          // shared AnonymityToggle, so all four submit paths present the
          // identical control.
          AnonymityToggle(
            value: _isAnonymous,
            onChanged: _feedbackSubmitted
                ? null
                : (v) => setState(() => _isAnonymous = v),
          ),
          if (!_feedbackSubmitted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submittingFeedback ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _submittingFeedback
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Submit Feedback',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadRegistrationForm() async {
    final proposalId = widget.event.createdFromProposalId ?? '';
    if (proposalId.isEmpty) {
      if (mounted) setState(() => _loadingForm = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('registration_forms')
          .doc(proposalId)
          .get();

      if (doc.exists) {
        final d = doc.data()!;
        final fields = (d['fields'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (d['isPublished'] == true && fields.isNotEmpty) {
          for (final f in fields) {
            final id = f['id'] as String;
            final type = (f['type'] ?? 'short_text') as String;
            if (type == 'multiple_choice' || type == 'dropdown') {
              _singleChoice[id] = null;
            } else if (type == 'checkboxes') {
              _multiChoice[id] = {};
            } else {
              _fieldControllers[id] = TextEditingController();
            }
          }
          _formDef = {...d, 'fields': fields};
        }
      }
    } catch (_) {
      // fall through
    }
    if (mounted) setState(() => _loadingForm = false);
  }

  void _refreshFieldState(VoidCallback? onStateChanged) {
    if (onStateChanged != null) {
      onStateChanged();
    } else if (mounted) {
      setState(() {});
    }
  }

  // Same compression settings org_merchandise.dart already uses for its own
  // photo uploads (1280px max dimension, quality 72) — kept consistent so a
  // registration-form photo answer stays comfortably under Firestore's
  // 1 MiB document limit once base64-encoded, same as everywhere else in
  // the app that stores an image inline on a document.
  Future<Uint8List> _compressPickedImage(Uint8List bytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 72,
        format: CompressFormat.jpeg,
      );
      return compressed.length < bytes.length ? compressed : bytes;
    } catch (_) {
      return bytes;
    }
  }

  // A 'file_upload' question's picked photo answer. Compressed then stored
  // as a base64 data URI directly on the answer (matches how org screens
  // already store product/banner photos inline on a document).
  //
  // Video used to go through Firebase Storage (putData + getDownloadURL),
  // but that requires the project to be on the Blaze billing plan just to
  // provision the default bucket — on Spark it fails every attempt with
  // firebase_storage/object-not-found, no matter how the upload code is
  // written. Video answers are now a pasted link (Drive/YouTube/etc, see
  // the 'file_upload' case in _buildFieldWidget) instead of a device
  // upload, so this only ever handles the image path now.
  Future<void> _pickFileUploadAnswer(
    String id, {
    VoidCallback? onStateChanged,
  }) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    _fileUploadBusy[id] = true;
    _refreshFieldState(onStateChanged);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = await _compressPickedImage(bytes);
      _fileUploadValues[id] =
          'data:image/jpeg;base64,${base64Encode(compressed)}';
      _fileUploadNames[id] = picked.name;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _fileUploadBusy[id] = false;
      _refreshFieldState(onStateChanged);
    }
  }

  static final RegExp _formEmailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateDynamicFields() {
    if (_formDef == null) return null;
    final fields = (_formDef!['fields'] as List).cast<Map<String, dynamic>>();
    for (final f in fields) {
      final id = f['id'] as String;
      final type = (f['type'] ?? 'short_text') as String;
      final label = (f['label'] ?? 'This question').toString();
      final required = f['required'] == true;

      if (type == 'multiple_choice' || type == 'dropdown') {
        if (required && _singleChoice[id] == null) {
          return 'Please answer: $label';
        }
        continue;
      }
      if (type == 'checkboxes') {
        if (required && (_multiChoice[id] ?? {}).isEmpty) {
          return 'Please answer: $label';
        }
        continue;
      }
      if (type == 'file_upload') {
        final val = (_fileUploadValues[id] ?? '').trim();
        if (required && val.isEmpty) {
          return 'Please attach a photo or paste a video link for: $label';
        }
        if (_fileUploadBusy[id] == true) {
          return 'Please wait for the upload to finish for: $label';
        }
        if (val.isNotEmpty &&
            !val.startsWith('data:image/') &&
            !val.startsWith('http://') &&
            !val.startsWith('https://')) {
          return 'Please paste a valid link (starting with http:// or https://) for: $label';
        }
        continue;
      }

      final text = (_fieldControllers[id]?.text ?? '').trim();
      if (required && text.isEmpty) return 'Please answer: $label';
      // Optional and left blank — nothing to validate.
      if (text.isEmpty) continue;

      // The number/date keyboards only hint the on-screen keys shown — they
      // don't stop a user from pasting or switching to a text keyboard, so
      // the actual value still needs checking here.
      if (type == 'email' && !_formEmailPattern.hasMatch(text)) {
        return 'Please enter a valid email for: $label';
      }
      if (type == 'number' && double.tryParse(text) == null) {
        return 'Please enter a valid number for: $label';
      }
    }
    return null;
  }

  Map<String, dynamic> _collectFormResponses() {
    if (_formDef == null) return {};
    final fields = (_formDef!['fields'] as List).cast<Map<String, dynamic>>();
    final out = <String, dynamic>{};
    for (final f in fields) {
      final id = f['id'] as String;
      final type = (f['type'] ?? 'short_text') as String;
      final label = f['label'] ?? '';
      if (type == 'multiple_choice' || type == 'dropdown') {
        out[id] = {'label': label, 'value': _singleChoice[id]};
      } else if (type == 'checkboxes') {
        out[id] = {'label': label, 'value': (_multiChoice[id] ?? {}).toList()};
      } else if (type == 'file_upload') {
        out[id] = {'label': label, 'value': _fileUploadValues[id] ?? ''};
      } else {
        out[id] = {
          'label': label,
          'value': _fieldControllers[id]?.text.trim() ?? '',
        };
      }
    }
    return out;
  }

  Future<void> _registerForEvent() async {
    // Late joiners to an ongoing event used to be allowed here; they no longer
    // are — registration closes at the start time. Re-checked at submit rather
    // than trusting the disabled button, since a detail screen left open
    // across the start time would otherwise still be able to submit.
    if (!_registrationOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _registrationClosedReason ?? 'Registration is closed',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final formError = _validateDynamicFields();
    if (formError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formError), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login to register')));
      setState(() => _isLoading = false);
      return;
    }
    try {
      final formResponses = _collectFormResponses();
      final regRef = FirebaseFirestore.instance
          .collection('registrations')
          .doc('${user.uid}_${widget.event.id}');
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final regDoc = await tx.get(regRef);
        if (regDoc.exists)
          throw Exception('You are already registered for this event');
        final evRef = FirebaseFirestore.instance
            .collection('events')
            .doc(widget.event.id);
        final evDoc = await tx.get(evRef);
        if (!evDoc.exists) throw Exception('Event not found');
        final evData = evDoc.data() as Map<String, dynamic>;

        // Optional, org-set — null means unlimited slots. Read from the
        // event doc itself (already fetched via tx.get() above) rather than
        // a separate `.count()` query — a `.count()` aggregation can't be
        // read transactionally, so two students registering for the last
        // slot at the same instant could both pass that check and both
        // commit. `registeredCount` is incremented in the same transaction
        // as the registration write below, so Firestore's normal
        // optimistic-concurrency retry (triggered by evDoc having been
        // read via tx.get()) now actually protects this check. A missing
        // field reads as 0 and self-initializes from here on.
        final capacity = (evData['capacity'] as num?)?.toInt();
        final registeredCount =
            (evData['registeredCount'] as num?)?.toInt() ?? 0;
        if (capacity != null && registeredCount >= capacity) {
          throw Exception(
            'This event has reached its maximum capacity of $capacity and is no longer accepting registrations.',
          );
        }

        final userDoc = await tx.get(
          FirebaseFirestore.instance.collection('users').doc(user.uid),
        );
        final studentDoc = await tx.get(
          FirebaseFirestore.instance.collection('students').doc(user.uid),
        );
        final eligible = EventModel.audienceAllowsMember(
          audience: (evData['audience'] ?? 'Public').toString(),
          eventOrgId: (evData['orgId'] ?? '').toString(),
          userData: userDoc.data(),
          course: studentDoc.data()?['course'] as String?,
        );
        if (!eligible) {
          // Deliberately generic — doesn't reveal which specific condition
          // (CICT status, org membership, BulSU account) the student failed.
          throw Exception(
            'You\'re not eligible to register for this event based on its '
            'audience restrictions.',
          );
        }

        tx.set(regRef, {
          'userId': user.uid,
          'eventId': widget.event.id,
          'registeredAt': FieldValue.serverTimestamp(),
          'status': 'registered',
          if (formResponses.isNotEmpty) 'formResponses': formResponses,
        });
        tx.update(evRef, {'registeredCount': FieldValue.increment(1)});
      });
      setState(() {
        _isRegistered = true;
        if (_registeredCount != null) _registeredCount = _registeredCount! + 1;
      });
      widget.onRegistered();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully registered for event!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.5),
    ),
  );

  Widget _buildDynamicField(
    Map<String, dynamic> field, {
    VoidCallback? onStateChanged,
  }) {
    final id = field['id'] as String;
    final type = (field['type'] ?? 'short_text') as String;
    final label = (field['label'] ?? '').toString();
    final desc = (field['description'] ?? '').toString();
    final required = field['required'] == true;
    final options =
        (field['options'] as List?)?.map((o) => o.toString()).toList() ?? [];

    Widget input;
    switch (type) {
      case 'paragraph':
        input = TextField(
          controller: _fieldControllers[id],
          maxLines: 4,
          decoration: _fieldDecoration('Your answer'),
        );
        break;
      case 'email':
        input = TextField(
          controller: _fieldControllers[id],
          keyboardType: TextInputType.emailAddress,
          decoration: _fieldDecoration('someone@email.com'),
        );
        break;
      case 'number':
        input = TextField(
          controller: _fieldControllers[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // keyboardType only hints which on-screen keyboard shows — it
          // doesn't block pasted or IME-typed text, so letters were still
          // getting through and saved as-is. This actually restricts it.
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: _fieldDecoration('0'),
        );
        break;
      case 'date':
        input = TextField(
          controller: _fieldControllers[id],
          readOnly: true,
          decoration: _fieldDecoration('Select date').copyWith(
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              _fieldControllers[id]!.text = DateFormat(
                'MMM dd, yyyy',
              ).format(picked);
              if (onStateChanged != null) onStateChanged();
            }
          },
        );
        break;
      case 'multiple_choice':
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: options
              .map(
                (o) => RadioListTile<String>(
                  value: o,
                  groupValue: _singleChoice[id],
                  title: Text(o, style: const TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    _singleChoice[id] = v;
                    if (onStateChanged != null) {
                      onStateChanged();
                    } else {
                      setState(() {});
                    }
                  },
                ),
              )
              .toList(),
        );
        break;
      case 'dropdown':
        input = DropdownButtonFormField<String>(
          initialValue: _singleChoice[id],
          decoration: _fieldDecoration('Select an option'),
          items: options
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: const TextStyle(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: (v) {
            _singleChoice[id] = v;
            if (onStateChanged != null) {
              onStateChanged();
            } else {
              setState(() {});
            }
          },
        );
        break;
      case 'checkboxes':
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: options
              .map(
                (o) => CheckboxListTile(
                  value: _multiChoice[id]?.contains(o) ?? false,
                  title: Text(o, style: const TextStyle(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    _multiChoice.putIfAbsent(id, () => {});
                    if (v == true) {
                      _multiChoice[id]!.add(o);
                    } else {
                      _multiChoice[id]!.remove(o);
                    }
                    if (onStateChanged != null) {
                      onStateChanged();
                    } else {
                      setState(() {});
                    }
                  },
                ),
              )
              .toList(),
        );
        break;
      case 'file_upload':
        final mediaType = (field['mediaType'] as String?) ?? 'both';
        final allowsImage = mediaType == 'image' || mediaType == 'both';
        final allowsVideo = mediaType == 'video' || mediaType == 'both';
        final hasPhoto = (_fileUploadValues[id] ?? '').startsWith(
          'data:image/',
        );
        final videoLinkText = _fieldControllers[id]?.text.trim() ?? '';
        final hasVideoLink = videoLinkText.isNotEmpty;
        final busy = _fileUploadBusy[id] == true;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allowsImage && !hasVideoLink) ...[
              if (hasPhoto)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fileUploadNames[id] ?? 'Photo attached',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _fileUploadValues.remove(id);
                          _fileUploadNames.remove(id);
                          if (onStateChanged != null) {
                            onStateChanged();
                          } else {
                            setState(() {});
                          }
                        },
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                )
              else if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _pickFileUploadAnswer(
                    id,
                    onStateChanged: onStateChanged,
                  ),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('Choose Photo'),
                ),
            ],
            if (allowsImage && allowsVideo && !hasPhoto && !hasVideoLink)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'or paste a video link',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            if (allowsVideo && !hasPhoto)
              TextField(
                controller: _fieldControllers[id],
                keyboardType: TextInputType.url,
                decoration: _fieldDecoration('Paste a Google Drive/YouTube link').copyWith(
                  prefixIcon: const Icon(Icons.link_rounded, size: 18),
                ),
                onChanged: (v) {
                  _fileUploadValues[id] = v.trim();
                  _fileUploadNames[id] = 'Video link';
                  if (onStateChanged != null) {
                    onStateChanged();
                  } else {
                    setState(() {});
                  }
                },
              ),
          ],
        );
        break;
      default:
        input = TextField(
          controller: _fieldControllers[id],
          decoration: _fieldDecoration('Your answer'),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                desc,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            )
          else
            const SizedBox(height: 6),
          input,
        ],
      ),
    );
  }

  List<Widget> _buildDialogFields(VoidCallback setDialogState) {
    if (_formDef == null) return [];
    final fields = (_formDef!['fields'] as List).cast<Map<String, dynamic>>();
    final title = (_formDef!['title'] ?? 'Registration Form').toString();
    final desc = (_formDef!['description'] ?? '').toString();

    return [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      if (desc.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            desc,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      const SizedBox(height: 16),
      ...fields.map(
        (f) => _buildDynamicField(f, onStateChanged: setDialogState),
      ),
    ];
  }

  void _showRegistrationDialog() {
    if (_formDef == null) {
      _registerForEvent();
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.edit_note, color: AppColors.primaryDark),
                  const SizedBox(width: 10),
                  const Text('Register for Event'),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: (MediaQuery.of(ctx).size.width * 0.9).clamp(0, 450),
                  // No maxHeight here — a Column can't shrink its children
                  // to fit a box that's smaller than their natural size, so
                  // constraining height on this inner box (instead of just
                  // letting the SingleChildScrollView above handle overflow)
                  // was what caused forms with several fields to overflow.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildDialogFields(() => setDialogState(() {})),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final formError = _validateDynamicFields();
                          if (formError != null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(formError),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _registerForEvent();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit Registration'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const StudentAppBar(title: 'Event Details'),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // expandable only here, not on the list cards: a card's whole
            // surface already navigates to this screen, so a tap handler on
            // its banner would swallow that instead of opening the event.
            EventImage(
              imageUrl: widget.event.imageUrl,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              showLoadingIndicator: true,
              expandable: true,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryBadge(category: widget.event.displayCategory),
                  const SizedBox(height: 12),
                  Text(
                    widget.event.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Organizer information — tappable through to the same
                  // public org profile the Organizations tab already uses,
                  // instead of just being static text.
                  InkWell(
                    onTap: widget.event.orgId.isEmpty
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentOrganizationsDetailsScreen(
                                orgId: widget.event.orgId,
                              ),
                            ),
                          ),
                    child: Text(
                      'Hosted by ${widget.event.orgName}',
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.event.orgId.isEmpty
                            ? Colors.grey
                            : AppColors.primaryDark,
                        fontWeight: widget.event.orgId.isEmpty
                            ? FontWeight.normal
                            : FontWeight.w600,
                        decoration: widget.event.orgId.isEmpty
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  InfoRow(
                    icon: Icons.calendar_today_outlined,
                    text: widget.event.formattedDate,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: Icons.access_time,
                    text: widget.event.formattedTime,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: Icons.location_on_outlined,
                    text: widget.event.location,
                  ),
                  const SizedBox(height: 12),
                  AudienceBadgeRow(audience: widget.event.audience),
                  if (widget.event.capacity != null) ...[
                    const SizedBox(height: 12),
                    InfoRow(
                      icon: Icons.groups_outlined,
                      text: _registeredCount == null
                          ? '${widget.event.capacity} slots'
                          : '$_registeredCount/${widget.event.capacity} slots filled',
                      color: _isFull ? Colors.red.shade600 : null,
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'About the Event',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.event.description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!_isEventReallyOver && !_isRegistered && !_isFull) ...[
                    if (_loadingForm || _loadingUserData)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    // Time closes registration before eligibility does: once
                    // the event is underway there's nothing to sign up for,
                    // eligible or not. Kept visible but disabled so the reason
                    // is on screen rather than implied by a missing button.
                    else if (!_registrationOpen) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.timer_off_outlined, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          label: Text(
                            _registrationClosedReason ?? 'Registration closed',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Registration closes when an event begins. You can '
                        'still view the details here.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ] else if (!_isEligibleForEvent) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.lock_outline, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          label: const Text(
                            'Restricted Event',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Deliberately generic — doesn't reveal which specific
                      // condition (CICT status, org membership, BulSU
                      // account) this student failed.
                      Text(
                        'You\'re not eligible to register for this event '
                        'based on its audience restrictions.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _showRegistrationDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Register Now',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],

                  if (_isFull && !_isRegistered && !_isEventReallyOver)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Center(
                        child: Text(
                          'Event Full — no more slots available',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),

                  if (_isRegistered && !_isEventReallyOver)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Center(
                        child: Text(
                          '✓ You are registered',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),

                  // MY EVENT — attendance + certificate status, grouped
                  // together the way the redesign calls for, both read
                  // from data this screen already fetches/queries
                  // (events/{id}/attendances and certificates), no new
                  // collections.
                  if (_isRegistered) _buildMyEventSection(),

                  // Feedback only for students who registered AND were
                  // actually marked present/late — a past event you never
                  // attended shouldn't offer a feedback form, since
                  // org_certificates.dart's certificate gate reads this
                  // exact combination (attendance + event_feedback).
                  if (_isEventReallyOver && _isRegistered && _hasAttended)
                    _buildFeedbackSection()
                  else if (_isEventReallyOver && _isRegistered)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Feedback is only available for events you attended. No attendance was recorded for you at this event.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── INFO ROW ──────────────────────────────────────────────────
