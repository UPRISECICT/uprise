import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'guest_auth_service.dart';
import 'guest_access_gateway_screen.dart';
import 'guest_calendar_screen.dart';
import 'guest_registered_events_screen.dart';
import 'package:uprise/models/event_model.dart';
import '../../services/guest_event_registration.dart';
import '../../utils/helpers.dart' show combineDateAndTime;
import '../../widgets/common/error_state.dart';
import '../../widgets/common/event_badges.dart';
import '../../widgets/common/event_browsing.dart';
import '../../widgets/common/event_date_filter.dart';
import '../../widgets/common/event_card.dart';
import '../../widgets/common/info_tile.dart';
import '../../widgets/common/loading_widget.dart' show SkeletonLoader;
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/event_image.dart';
import '../../widgets/student/student_app_bar.dart';
import '../student/student_organization_details_screen.dart';
import 'guest_organizations_screen.dart';

// Shared by both the browse-list filter (which just hides events a guest
// classification isn't allowed to see) and the registration screen (which
// enforces the same rule at the actual write) — a guest reaching the
// registration screen via a direct navigation, bypassing the hidden-from-list
// filter, would otherwise be able to register for a BulSUan-only event
// without ever being BulSUan-classified.
bool classificationAllowsAudience(String audience, String classification) {
  bool singleAllowed(String v) {
    switch (v) {
      case 'BulSUan':
        return classification == 'BulSUan';
      case 'CICT Only':
      case 'Members Only':
        return false;
      default:
        return true;
    }
  }

  final values = audience
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  if (values.isEmpty) return true;
  return values.any(singleAllowed);
}

// ─────────────────────────────────────────────────────────────
// Theme
// ─────────────────────────────────────────────────────────────
const _kPrimary = AppColors.primaryDark;
const _kPrimaryBg = AppColors.primarySoft;
const _kBg = AppColors.background;

// ─────────────────────────────────────────────────────────────
// Firestore event model
// ─────────────────────────────────────────────────────────────
class FirestoreEvent {
  final String id;
  final String title;
  final String description;
  final String category;
  final String audience; // 'Public' | 'CICT Only' | 'Members Only'
  final String orgId;
  final String orgName;
  final String location;
  final String startTime;
  final String endTime;
  final DateTime date;

  /// The event's banner, empty when the org never uploaded one — which is what
  /// [EventImage] wants in order to render its own placeholder. Guest events
  /// used to carry no image field at all, so every guest card fell through to
  /// a coloured initial; they come out of the same `events` documents the
  /// student side reads a banner from, so there was never a reason for that.
  final String imageUrl;

  // enriched after fetch — initialized to empty string to avoid null errors
  String orgLogoUrl = '';

  FirestoreEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.audience,
    required this.orgId,
    required this.orgName,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.date,
    this.imageUrl = '',
  });

  /// Re-wraps an [EventModel] that some other screen already parsed.
  ///
  /// Guest Home fetches its upcoming events as EventModel (it needs
  /// `timeStatus`, which does the startTime/endTime comparison), but the guest
  /// detail screen takes a FirestoreEvent. Converting in memory avoids the
  /// alternative of re-reading the same document by id just to open it.
  factory FirestoreEvent.fromEventModel(EventModel e) => FirestoreEvent(
    id: e.id,
    title: e.title,
    description: e.description,
    category: e.category,
    audience: e.audience,
    orgId: e.orgId,
    orgName: e.orgName,
    location: e.location,
    startTime: e.startTime,
    endTime: e.endTime,
    date: e.date,
    imageUrl: e.imageUrl,
  );

  factory FirestoreEvent.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final dateField = d['date'];
    final DateTime parsedDate = dateField is Timestamp
        ? dateField.toDate()
        : DateTime.now();
    return FirestoreEvent(
      id: doc.id,
      title: d['title'] as String? ?? 'Untitled',
      description: d['description'] as String? ?? '',
      category: d['category'] as String? ?? 'Other',
      audience: d['audience'] as String? ?? 'Public',
      orgId: d['orgId'] as String? ?? '',
      orgName: d['orgName'] as String? ?? 'Organization',
      location: d['location'] as String? ?? 'TBA',
      startTime: d['startTime'] as String? ?? d['time'] as String? ?? '',
      endTime: d['endTime'] as String? ?? '',
      date: parsedDate,
      imageUrl: d['bannerUrl'] as String? ?? '',
    );
  }

  String get dateDisplay => DateFormat('MMM dd, yyyy').format(date);

  String get timeDisplay {
    if (endTime.isNotEmpty) return '$startTime – $endTime';
    return startTime;
  }

  DateTime get fullDateTime => combineDateAndTime(date, startTime);

  /// Falls back to the end of the calendar day when no end time was stated, so
  /// an event without one only counts as over once its whole day has passed.
  DateTime get endDateTime => endTime.trim().isEmpty
      ? DateTime(date.year, date.month, date.day, 23, 59)
      : combineDateAndTime(date, endTime);

  /// Mirrors [EventModel.timeStatus] exactly — same helper, same comparison —
  /// so the Upcoming/Ongoing/Past chips on the guest Discover tab classify an
  /// event the way the student tab classifies the same document.
  EventTimeStatus get timeStatus {
    final now = DateTime.now();
    if (now.isBefore(fullDateTime)) return EventTimeStatus.upcoming;
    if (now.isAfter(endDateTime)) return EventTimeStatus.completed;
    return EventTimeStatus.ongoing;
  }

  bool get isSoon =>
      date.difference(DateTime.now()).inDays <= 7 &&
      date.isAfter(DateTime.now());
}

/// Not-yet-finished events soonest-first, then finished ones
/// most-recently-ended-first. Same ordering as student Discover's
/// `_latestFirst`, so a mixed list reads the same on both sides.
int _latestFirst(FirestoreEvent a, FirestoreEvent b) {
  final aDone = a.timeStatus == EventTimeStatus.completed;
  final bDone = b.timeStatus == EventTimeStatus.completed;
  if (aDone != bDone) return aDone ? 1 : -1;
  return aDone
      ? b.date.compareTo(a.date)
      : a.fullDateTime.compareTo(b.fullDateTime);
}

/// Maps this screen's domain model onto the shared card's data struct — the
/// guest counterpart of student_events_screen.dart's `eventCardData`.
EventCardData guestEventCardData(FirestoreEvent e) => EventCardData(
  title: e.title,
  category: e.category,
  imageUrl: e.imageUrl,
  dateLabel: e.dateDisplay,
  timeLabel: e.timeDisplay,
  location: e.location,
  orgName: e.orgName,
);

// ─────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────
class GuestEventsScreen extends StatefulWidget {
  /// Which sub-tab to open on: Discover(0) / Calendar(1) / My Events(2).
  /// Mirrors the student Events screen so both shells can deep-link the same
  /// way (e.g. Home's "see all registrations").
  final int initialTabIndex;

  /// Bumped by the shell on every deep-link request. Without it, jumping to
  /// the sub-tab that's already selected would look like no change at all and
  /// be ignored — and keying the whole screen off the index instead would
  /// throw away its loaded events on every jump.
  final int jumpToken;

  const GuestEventsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.jumpToken = 0,
  });

  @override
  State<GuestEventsScreen> createState() => _GuestEventsScreenState();
}

class _GuestEventsScreenState extends State<GuestEventsScreen>
    with SingleTickerProviderStateMixin {
  // Calendar used to be its own bottom-nav tab. It's a sub-tab here so the
  // guest shell matches the student one (Discover / Calendar / My Events).
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 2),
  );

  // Firestore streams (combined: events + event_proposals both approved & public)
  StreamSubscription<QuerySnapshot>? _eventsSubscription;
  StreamSubscription<QuerySnapshot>? _proposalsSubscription;

  final Map<String, FirestoreEvent> _eventMap = {};
  bool _loading = true;
  String? _error;

  // ── Discover filters ──
  // Search text, time status, organization and category all narrow the tab in
  // place (AND-ed together). Mirrors the student Discover tab, with one
  // deliberate difference: a category tile filters here instead of pushing a
  // per-category screen. The student tab has to push one because its results
  // come from a Firestore query it re-subscribes per category; every guest
  // event is already in `_eventMap` and keeps streaming, so a pushed screen
  // would either go stale or need a second subscription for no gain.
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  EventTimeStatus? _activeStatus;
  String? _selectedOrgId; // null = All Organizations
  String? _selectedCategory; // null = show the category tiles
  EventDateFilter? _dateFilter; // null = any date
  bool _compactView = false;

  // Skeleton shown for a beat after each filter change so rapid typing doesn't
  // thrash the list; the timer collapses repeated keystrokes.
  Timer? _searchDebounce;
  bool _showSkeleton = false;

  // Which events this guest already holds a registration for, so their cards
  // read "Registered ✓" the way a student's do. Keyed by email + isGuest,
  // the convention every other guest reader of `registrations` uses — an
  // org-side check-in creates rows with no `userId` on them.
  Stream<Set<String>>? _registeredIdsStream;

  // cache org logos to avoid re-fetching
  final Map<String, String> _orgLogoCache = {};

  // Default to the most restrictive tier — unregistered/visitor guests (no
  // approved external_requests doc yet) never see Bulsuan-only events.
  String _guestClassification = 'Outsider';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant GuestEventsScreen old) {
    super.didUpdateWidget(old);
    // A new token means the shell asked for a sub-tab, even if it's the one
    // already showing. The screen's own state (and its event subscription)
    // survives, so this is just a tab move.
    if (widget.jumpToken != old.jumpToken) {
      _tabController.animateTo(widget.initialTabIndex.clamp(0, 2));
    }
  }

  Future<void> _init() async {
    await _loadGuestClassification();
    if (!mounted) return;
    setState(() => _registeredIdsStream = _buildRegisteredIdsStream());
    _subscribe();
  }

  /// Null for a visitor with no account — StreamBuilder treats a null stream
  /// as "no data", which is exactly right: nothing is registered.
  Stream<Set<String>>? _buildRegisteredIdsStream() {
    final email = (GuestAuthService().email ?? '').toLowerCase();
    if (email.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('registrations')
        .where('email', isEqualTo: email)
        .where('isGuest', isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => (d.data()['eventId'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet(),
        );
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

  // 'Public' is open to everyone; 'BulSUan' only to BulSUan-classified
  // guests; 'CICT Only' and 'Members Only' are never shown to guests at all.
  // An event can now target more than one audience at once (org side stores
  // them comma-joined in the same field, e.g. "CICT Only, BulSUan") — a
  // guest can see it if ANY one of the listed audiences would individually
  // allow them, so checking multiple boxes only ever widens who sees it.
  bool _audienceAllowed(String audience) =>
      classificationAllowsAudience(audience, _guestClassification);

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _proposalsSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _subscribe() {
    // ── 1. 'events' collection ──────────────────────────────
    _eventsSubscription = FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen(
          (snap) async {
            for (final doc in snap.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final audience = (d['audience'] as String?) ?? 'Public';
              // Show only events this guest's classification allows
              if (!_audienceAllowed(audience)) {
                _eventMap.remove(doc.id);
                continue;
              }
              final event = FirestoreEvent.fromDoc(doc);
              await _enrichLogo(event);
              _eventMap[doc.id] = event;
            }
            // Remove docs that disappeared (deleted/status changed)
            final ids = snap.docs.map((d) => d.id).toSet();
            _eventMap.removeWhere(
              (k, _) => !ids.contains(k) && _eventMap[k] != null,
            );
            if (mounted) setState(() => _loading = false);
          },
          onError: (e) {
            if (mounted)
              setState(() {
                _error = e.toString();
                _loading = false;
              });
          },
        );

    // ── 2. 'event_proposals' collection (approved) ─────────
    // Proposals that are approved but haven't been auto-converted to events
    // yet still deserve to be visible.
    _proposalsSubscription = FirebaseFirestore.instance
        .collection('event_proposals')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen(
          (snap) async {
            for (final doc in snap.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final audience = (d['audience'] as String?) ?? 'Public';
              if (!_audienceAllowed(audience)) {
                _eventMap.remove('proposal_${doc.id}');
                continue;
              }
              // Use 'proposal_' prefix to differentiate from events collection
              final dateField = d['date'];
              final DateTime parsedDate = dateField is Timestamp
                  ? dateField.toDate()
                  : DateTime.now();
              final event = FirestoreEvent(
                id: 'proposal_${doc.id}',
                title: d['title'] as String? ?? 'Untitled',
                description: d['description'] as String? ?? '',
                category: d['category'] as String? ?? 'Other',
                audience: audience,
                orgId: d['orgId'] as String? ?? '',
                orgName: d['orgName'] as String? ?? 'Organization',
                location: d['location'] as String? ?? 'TBA',
                startTime: d['time'] as String? ?? '',
                endTime: '',
                date: parsedDate,
                imageUrl: d['bannerUrl'] as String? ?? '',
              );
              await _enrichLogo(event);
              _eventMap['proposal_${doc.id}'] = event;
            }
            final proposalKeys = snap.docs
                .map((d) => 'proposal_${d.id}')
                .toSet();
            _eventMap.removeWhere(
              (k, _) => k.startsWith('proposal_') && !proposalKeys.contains(k),
            );
            if (mounted) setState(() => _loading = false);
          },
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  Future<void> _enrichLogo(FirestoreEvent event) async {
    if (event.orgId.isEmpty) return;
    if (_orgLogoCache.containsKey(event.orgId)) {
      event.orgLogoUrl = _orgLogoCache[event.orgId]!;
      return;
    }
    try {
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(event.orgId)
          .get();
      if (orgDoc.exists) {
        final logo = (orgDoc.data() ?? {})['logoUrl'] as String? ?? '';
        _orgLogoCache[event.orgId] = logo;
        event.orgLogoUrl = logo;
      }
    } catch (_) {}
  }

  bool get _hasInlineFilter =>
      _search.trim().isNotEmpty ||
      _activeStatus != null ||
      _selectedOrgId != null ||
      _selectedCategory != null ||
      _dateFilter != null;

  Future<void> _openDateFilter() async {
    final result = await showEventDateFilterSheet(context, _dateFilter);
    if (result == null || !mounted) return;
    setState(() {
      _dateFilter = result.date;
      _beginResultsTransition();
    });
  }

  void _clearDateFilter() {
    setState(() {
      _dateFilter = null;
      _beginResultsTransition();
    });
  }

  /// Call inside setState after changing any filter.
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

  void _toggleStatus(EventTimeStatus status) {
    setState(() {
      _activeStatus = _activeStatus == status ? null : status;
      _beginResultsTransition();
    });
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _beginResultsTransition();
    });
  }

  void _clearCategory() {
    setState(() {
      _selectedCategory = null;
      _beginResultsTransition();
    });
  }

  List<FirestoreEvent> get _filtered {
    final q = _search.trim().toLowerCase();
    final category = _selectedCategory?.toLowerCase();

    return _eventMap.values.where((e) {
      if (_activeStatus != null && e.timeStatus != _activeStatus) {
        return false;
      }
      if (_selectedOrgId != null && e.orgId != _selectedOrgId) return false;
      if (_dateFilter != null && !_dateFilter!.matches(e.date)) return false;
      if (category != null && e.category.toLowerCase() != category) {
        return false;
      }
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !e.orgName.toLowerCase().contains(q) &&
          !e.location.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()..sort(_latestFirst);
  }

  /// Derived from the events already loaded rather than the `organizations`
  /// collection, so the dropdown can only ever offer an org this guest has at
  /// least one visible event for — and needs no second read.
  List<OrgOption> get _orgOptions {
    final byId = <String, String>{};
    for (final e in _eventMap.values) {
      if (e.orgId.isEmpty) continue;
      byId.putIfAbsent(e.orgId, () => e.orgName);
    }
    return byId.entries
        .map((entry) => OrgOption(id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: StudentAppBar(
        title: 'Events',
        // Same three tabs as student Events, and now the same TabBar styling
        // — the labelStyle override that made guest's labels 13px is gone.
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kPrimary,
          unselectedLabelColor: Colors.black45,
          indicatorColor: _kPrimary,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Discover'),
            Tab(text: 'Calendar'),
            Tab(text: 'My Events'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF81C784)),
            ),
            child: const Text(
              'Open to All',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDiscover(),
          // Both sub-tabs supply their own body but not their own title bar.
          const GuestCalendarScreen(embedded: true),
          const GuestRegisteredEventsScreen(embedded: true),
        ],
      ),
    );
  }

  Widget _buildDiscover() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }
    if (_error != null) {
      return ErrorStateView(
        title: 'Could not load events',
        detail: _error,
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
            _eventMap.clear();
          });
          _subscribe();
        },
      );
    }

    return StreamBuilder<Set<String>>(
      stream: _registeredIdsStream,
      builder: (context, regSnap) {
        final regIds = regSnap.data ?? const <String>{};

        // Everything below the controls swaps in place: category tiles by
        // default, the filtered results as soon as any filter is active.
        final Widget body;
        if (!_hasInlineFilter) {
          body = KeyedSubtree(
            key: const ValueKey('categories'),
            child: CategoryTileGrid(onTap: _selectCategory),
          );
        } else if (_showSkeleton) {
          // Scroll view only so the fixed-height placeholders clip instead of
          // overflowing on short screens.
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
          body = Column(
            key: const ValueKey('results'),
            children: [
              ViewToggleRow(
                compact: _compactView,
                onChanged: (v) => setState(() => _compactView = v),
                leading: _dateFilter == null
                    ? null
                    : EventDateFilterChip(
                        filter: _dateFilter!,
                        onTap: _openDateFilter,
                        onCleared: _clearDateFilter,
                      ),
              ),
              Expanded(
                child: EventResultsList(
                  items: [
                    for (final event in _filtered)
                      EventListItem(
                        data: guestEventCardData(event),
                        isRegistered: regIds.contains(event.id),
                        showLiveBadge:
                            event.timeStatus == EventTimeStatus.ongoing,
                        showSoonBadge: event.isSoon,
                        onTap: () => _openDetail(event),
                      ),
                  ],
                  compact: _compactView,
                  emptyTitle: _emptyStateTitle,
                  emptyMessage: _emptyStateMessage,
                  emptyIcon: _emptyStateIcon,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            const _GuestVisibilityNotice(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: EventSearchField(
                      controller: _searchCtrl,
                      query: _search,
                      hintText: 'Search events, org, location…',
                      onChanged: (v) => setState(() {
                        _search = v;
                        _beginResultsTransition();
                      }),
                      onClear: () => setState(() {
                        _searchCtrl.clear();
                        _search = '';
                        _beginResultsTransition();
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  EventFilterButton(
                    activeCount: _dateFilter != null ? 1 : 0,
                    onTap: _openDateFilter,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OrgFilterDropdown(
                      orgs: _orgOptions,
                      selectedOrgId: _selectedOrgId,
                      onChanged: (id) => setState(() {
                        _selectedOrgId = id;
                        _beginResultsTransition();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChips<EventTimeStatus>(
                    options: const [
                      (EventTimeStatus.upcoming, 'Upcoming'),
                      (EventTimeStatus.ongoing, 'Ongoing'),
                      (EventTimeStatus.completed, 'Past'),
                    ],
                    selected: _activeStatus,
                    onTap: _toggleStatus,
                    dotValue: EventTimeStatus.ongoing,
                  ),
                ],
              ),
            ),
            // The picked category, as the one filter with no control of its
            // own to switch off — the tiles it was chosen from are no longer
            // on screen once results replace them.
            if (_selectedCategory != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: InputChip(
                    label: Text(_selectedCategory!),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                    backgroundColor: _kPrimaryBg,
                    side: BorderSide(color: _kPrimary.withAlpha(77)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    deleteIconColor: _kPrimary,
                    onDeleted: _clearCategory,
                    onPressed: _clearCategory,
                  ),
                ),
              ),
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
  }

  /// Names the narrowest active filter, so the line says which one came up
  /// empty rather than a flat "no events".
  String get _emptyStateTitle {
    final q = _search.trim();
    if (q.isNotEmpty) return 'No events match "$q"';
    final when = _dateFilter == null ? '' : ' ${_dateFilter!.phrase}';
    if (_selectedCategory != null) {
      return 'No events in $_selectedCategory$when';
    }
    switch (_activeStatus) {
      case EventTimeStatus.upcoming:
        return 'No upcoming events$when';
      case EventTimeStatus.ongoing:
        return 'No ongoing events$when';
      case EventTimeStatus.completed:
        return 'No past events$when';
      case null:
        if (_selectedOrgId != null) {
          return 'No events from this organization$when';
        }
        return when.isEmpty ? 'No public events right now' : 'No events$when';
    }
  }

  // The results surface only replaces the category tiles once a filter is on,
  // so an empty list here always has one to clear.
  static const _emptyStateMessage = 'Try clearing your search or filters.';

  IconData get _emptyStateIcon {
    switch (_activeStatus) {
      case EventTimeStatus.upcoming:
        return Icons.event_available;
      case EventTimeStatus.ongoing:
        return Icons.event_repeat;
      case EventTimeStatus.completed:
      case null:
        return Icons.event_busy;
    }
  }

  void _openDetail(FirestoreEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuestEventDetailScreen(event: event)),
    );
  }
}

/// Why a guest's list is shorter than a student's.
///
/// Guest-only, and the reason it sits above the search box rather than inside
/// the results: it explains the whole tab, not the current filter, so it has
/// to stay visible when a filter comes up empty.
class _GuestVisibilityNotice extends StatelessWidget {
  const _GuestVisibilityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kPrimaryBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPrimary.withAlpha(77)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: _kPrimary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Some events are exclusive to CICT students. Sign in to see all events.',
              style: TextStyle(fontSize: 11, color: Color(0xFF7A3300)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Detail Screen
// ─────────────────────────────────────────────────────────────
/// Mirrors the student detail screen (`EventDetailScreen` in
/// student_events_screen.dart) so the same event reads the same way on both
/// sides: StudentAppBar, flat banner, a run of InfoRows, then an inline
/// register block rather than a pinned bottom bar.
///
/// Two things here have no student counterpart and must survive any further
/// alignment work:
///   • the visitor state — a guest with no account gets "Sign in to register",
///     pointing at the guest gateway rather than a student sign-in;
///   • eligibility, which is the guest classification rule
///     ([classificationAllowsAudience]), not the student membership rule.
///
/// There is deliberately no cancel path, matching the student side.
class GuestEventDetailScreen extends StatefulWidget {
  final FirestoreEvent event;
  const GuestEventDetailScreen({super.key, required this.event});

  @override
  State<GuestEventDetailScreen> createState() => _GuestEventDetailScreenState();
}

class _GuestEventDetailScreenState extends State<GuestEventDetailScreen> {
  // null while the approved-guest lookup is still in flight; a visitor
  // resolves to null too and gets the sign-in prompt instead of a button.
  GuestIdentity? _identity;
  bool _resolving = true;
  bool _registered = false;
  bool _busy = false;

  // Capacity lives on events/{id}, not on FirestoreEvent — the guest model is
  // built from list and calendar snapshots that never carried it. One read
  // gets both halves of the "x/y slots filled" line, and `registeredCount` is
  // the same field registerGuestForEvent's capacity gate increments, so the
  // row and the gate can't disagree.
  int? _capacity;
  int? _registeredCount;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _resolve();
    _loadEventStats();
  }

  Future<void> _resolve() async {
    final identity = await resolveGuestIdentity();
    var registered = false;
    if (identity != null) {
      registered = await isGuestRegistered(
        uid: identity.uid,
        eventId: widget.event.id,
      );
    }
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _registered = registered;
      _resolving = false;
    });
  }

  /// Reads capacity and registeredCount off events/{id}.
  ///
  /// Proposal-backed events reach this screen with id `proposal_<docId>` and
  /// have no `events` document at all, so the read is skipped — capacity stays
  /// null, which hides the slots row rather than claiming "0/0 slots filled"
  /// for something that has no capacity concept yet.
  Future<void> _loadEventStats() async {
    if (widget.event.id.startsWith('proposal_')) {
      if (mounted) setState(() => _loadingStats = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .get();
      final data = doc.data();
      if (!mounted) return;
      setState(() {
        _capacity = (data?['capacity'] as num?)?.toInt();
        _registeredCount = (data?['registeredCount'] as num?)?.toInt() ?? 0;
        _loadingStats = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  bool get _isEligible => _identity == null
      ? false
      : classificationAllowsAudience(
          widget.event.audience,
          _identity!.classification,
        );

  bool get _isFull =>
      _capacity != null &&
      _registeredCount != null &&
      _registeredCount! >= _capacity!;

  /// Registration closes the moment an event starts — the same rule, reading
  /// the same `timeStatus`, the student screen uses.
  bool get _registrationOpen =>
      widget.event.timeStatus == EventTimeStatus.upcoming;

  String? get _registrationClosedReason => switch (widget.event.timeStatus) {
    EventTimeStatus.upcoming => null,
    EventTimeStatus.ongoing => 'Registration closed — event has started',
    EventTimeStatus.completed => 'Registration closed — event has ended',
  };

  Future<void> _register() async {
    final identity = _identity;
    if (identity == null || _busy) return;
    setState(() => _busy = true);
    try {
      await registerGuestForEvent(identity: identity, eventId: widget.event.id);
      if (!mounted) return;
      setState(() {
        _registered = true;
        // The transaction already incremented the stored count; mirroring it
        // locally keeps the slots line honest without a second read.
        if (_registeredCount != null) _registeredCount = _registeredCount! + 1;
      });
      _snack('You are registered for this event.', ok: true);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the shared org profile with the *guest* browsing config. Without it
  /// the profile screen falls back to OrgBrowsingConfig.student, which would
  /// hand a guest the member-only broadcast icon and unfiltered CICT-Only
  /// content. Mirrors GuestHomeScreen._openOrg.
  void _openOrg(String orgId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentOrganizationsDetailsScreen(
          orgId: orgId,
          config: guestOrgBrowsingConfig(
            _identity?.classification ?? 'Outsider',
          ),
        ),
      ),
    );
  }

  ButtonStyle _btnStyle() => ElevatedButton.styleFrom(
    backgroundColor: _kPrimary,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  /// Grey, non-pressable button stating why registration is unavailable. Kept
  /// on screen rather than hidden so the reason is visible instead of implied
  /// by a missing button — the same call the student screen makes.
  Widget _disabledButton({
    required IconData icon,
    required String label,
    required double fontSize,
  }) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: 18),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade300,
        disabledBackgroundColor: Colors.grey.shade300,
        disabledForegroundColor: Colors.grey.shade600,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _caption(String text) =>
      Text(text, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600));

  Widget _banner({
    required String text,
    required Color background,
    required Color border,
    required Color foreground,
    required double fontSize,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    ),
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    ),
  );

  /// The inline register block.
  ///
  /// Several states rather than one disabled button, because "you can't
  /// register" has different fixes: wait for the lookup, make a guest account,
  /// be the right audience, arrive before the event starts, or arrive before
  /// the slots run out.
  ///
  /// Two deliberate divergences from the student ordering:
  ///   • the student wraps its whole button group in `!_isFull`, so a past
  ///     *and* full event shows nothing at all; here time is checked before
  ///     capacity, so such an event correctly reads "event has ended";
  ///   • the student hides the registered banner once an event is over,
  ///     because it has MY EVENT and feedback sections below to carry that
  ///     state. This screen has neither, so the banner shows regardless of
  ///     time — otherwise a registered guest opening a finished event would
  ///     see a grey "registration closed" button and no sign they ever
  ///     signed up.
  List<Widget> _buildRegisterSection() {
    if (_resolving || _loadingStats) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }

    if (_registered) {
      return [
        _banner(
          text: '✓ You are registered',
          background: Colors.green.shade50,
          border: Colors.green.shade200,
          foreground: Colors.green,
          fontSize: 16,
        ),
      ];
    }

    if (!_registrationOpen) {
      return [
        _disabledButton(
          icon: Icons.timer_off_outlined,
          label: _registrationClosedReason ?? 'Registration closed',
          fontSize: 14.5,
        ),
        const SizedBox(height: 6),
        _caption(
          'Registration closes when an event begins. You can still view the '
          'details here.',
        ),
      ];
    }

    // Guest-only: a visitor has no account to register with. The fix is a
    // guest account, so this points at the gateway, not a student sign-in.
    if (_identity == null) {
      return [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GuestAccessGatewayScreen(),
              ),
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text(
              'Sign in to register',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: _btnStyle(),
          ),
        ),
        const SizedBox(height: 6),
        _caption('Registering needs an approved guest account.'),
      ];
    }

    if (!_isEligible) {
      return [
        _disabledButton(
          icon: Icons.lock_outline,
          label: 'Restricted Event',
          fontSize: 16,
        ),
        const SizedBox(height: 6),
        _caption('This event is limited to a different audience.'),
      ];
    }

    if (_isFull) {
      return [
        _banner(
          text: 'Event Full — no more slots available',
          background: Colors.red.shade50,
          border: Colors.red.shade200,
          foreground: Colors.red.shade700,
          fontSize: 15,
        ),
      ];
    }

    return [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _register,
          style: _btnStyle(),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Register Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    ];
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? const Color(0xFF059669) : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final hasOrg = event.orgId.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const StudentAppBar(title: 'Event Details'),
      // The register block scrolls with the content now that the pinned bar is
      // gone, so it needs the bottom inset the bar's own SafeArea used to give.
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EventImage(
                imageUrl: event.imageUrl,
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
                    CategoryBadge(category: event.category),
                    const SizedBox(height: 12),
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: hasOrg ? () => _openOrg(event.orgId) : null,
                      child: Text(
                        'Hosted by ${event.orgName}',
                        style: TextStyle(
                          fontSize: 14,
                          color: hasOrg ? AppColors.primaryDark : Colors.grey,
                          fontWeight: hasOrg
                              ? FontWeight.w600
                              : FontWeight.normal,
                          decoration: hasOrg
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    InfoRow(
                      icon: Icons.calendar_today_outlined,
                      text: event.dateDisplay,
                    ),
                    // timeDisplay is empty rather than a dash when the event
                    // carries no start time, so the row is dropped entirely.
                    if (event.startTime.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InfoRow(icon: Icons.access_time, text: event.timeDisplay),
                    ],
                    const SizedBox(height: 12),
                    InfoRow(
                      icon: Icons.location_on_outlined,
                      text: event.location,
                    ),
                    const SizedBox(height: 12),
                    AudienceBadgeRow(audience: event.audience),
                    if (_capacity != null) ...[
                      const SizedBox(height: 12),
                      InfoRow(
                        icon: Icons.groups_outlined,
                        text: _registeredCount == null
                            ? '$_capacity slots'
                            : '$_registeredCount/$_capacity slots filled',
                        color: _isFull ? Colors.red.shade600 : null,
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'About the Event',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.description.isNotEmpty
                          ? event.description
                          : 'No description provided.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._buildRegisterSection(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
