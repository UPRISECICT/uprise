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
import '../../widgets/common/event_card.dart';
import '../../widgets/common/image_viewer.dart';
import '../../widgets/common/loading_widget.dart' show SkeletonLoader;
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/event_image.dart';
import '../../widgets/student/student_app_bar.dart';

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
      _selectedCategory != null;

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
    if (_selectedCategory != null) return 'No events in $_selectedCategory';
    switch (_activeStatus) {
      case EventTimeStatus.upcoming:
        return 'No upcoming events';
      case EventTimeStatus.ongoing:
        return 'No ongoing events';
      case EventTimeStatus.completed:
        return 'No past events';
      case null:
        return _selectedOrgId != null
            ? 'No events from this organization'
            : 'No public events right now';
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
// Banner widget — uses org logo or fallback gradient
// ─────────────────────────────────────────────────────────────
/// The detail screen's hero. Renders the event's real banner when it has one,
/// falling back to the org-coloured initial.
///
/// It used to render *only* the coloured initial and never read the banner at
/// all — the same gap the note on [FirestoreEvent.imageUrl] describes for the
/// cards, left behind here. EventImage does the decoding (including the
/// authenticated Firebase Storage fetch) and makes the hero tappable.
class _EventBanner extends StatelessWidget {
  final String orgName;
  final String imageUrl;
  final double height;
  const _EventBanner({
    required this.orgName,
    this.imageUrl = '',
    required this.height,
  });

  Color _bgColor() {
    final hash = orgName.hashCode.abs();
    const colors = [
      Color(0xFF1A237E),
      Color(0xFF4A148C),
      Color(0xFF880E4F),
      Color(0xFF1B5E20),
      Color(0xFF0D47A1),
      Color(0xFF37474F),
      Color(0xFF4E342E),
      Color(0xFF263238),
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return EventImage(
        imageUrl: imageUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        showLoadingIndicator: true,
        expandable: true,
      );
    }
    return Container(
      height: height,
      width: double.infinity,
      color: _bgColor(),
      child: Center(
        child: Text(
          orgName.isNotEmpty ? orgName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: height * 0.35,
            fontWeight: FontWeight.w900,
            color: Colors.white.withAlpha(38),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Detail Screen
// ─────────────────────────────────────────────────────────────
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

  @override
  void initState() {
    super.initState();
    _resolve();
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

  /// The event is over once its end time (or, lacking one, the end of its
  /// calendar day) has passed — `date` alone is day-granular. Reads the same
  /// classification the Discover chips filter on, rather than a second
  /// hand-rolled end-time comparison beside it.
  bool get _isPast => widget.event.timeStatus == EventTimeStatus.completed;

  bool get _isEligible => _identity == null
      ? false
      : classificationAllowsAudience(
          widget.event.audience,
          _identity!.classification,
        );

  Future<void> _register() async {
    final identity = _identity;
    if (identity == null || _busy) return;
    setState(() => _busy = true);
    try {
      await registerGuestForEvent(identity: identity, eventId: widget.event.id);
      if (!mounted) return;
      setState(() => _registered = true);
      _snack('You\'re registered for this event.', ok: true);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final identity = _identity;
    if (identity == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel registration?'),
        content: const Text(
          'Your slot will be released and someone else can take it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await cancelGuestRegistration(
        uid: identity.uid,
        eventId: widget.event.id,
      );
      if (!mounted) return;
      setState(() => _registered = false);
      _snack('Registration cancelled.', ok: true);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The bottom action bar.
  ///
  /// Four distinct states rather than one disabled button, because "you can't
  /// register" has four different fixes: finish loading, make an account, be
  /// the right audience, or nothing (it already happened).
  Widget? _buildRegisterBar() {
    if (_resolving) return null;
    if (_isPast) {
      return _bar(
        child: const Text(
          'This event has ended',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.grey,
          ),
        ),
      );
    }

    // Visitor — the fix is a guest account, not a CICT student sign-in, so
    // this points at the gateway rather than the student prompt sheet.
    if (_identity == null) {
      return _bar(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GuestAccessGatewayScreen(),
              ),
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Sign in to register'),
            style: _btnStyle(),
          ),
        ),
      );
    }

    if (!_isEligible) {
      return _bar(
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'This event is limited to a different audience.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return _bar(
      child: SizedBox(
        width: double.infinity,
        child: _registered
            ? OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle, size: 18),
                label: Text(_busy ? 'Working…' : 'Registered · Tap to cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF059669)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : ElevatedButton.icon(
                onPressed: _busy ? null : _register,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.how_to_reg_outlined, size: 18),
                label: Text(_busy ? 'Registering…' : 'Register for this event'),
                style: _btnStyle(),
              ),
      ),
    );
  }

  Widget _bar({required Widget child}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 12)],
    ),
    child: SafeArea(top: false, child: child),
  );

  ButtonStyle _btnStyle() => ElevatedButton.styleFrom(
    backgroundColor: _kPrimary,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

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

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _buildRegisterBar(),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(235),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(26),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                title: const Text(
                  'Event Details',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  // Tap-to-expand hangs off the whole Stack, not the banner
                  // alone: the scrim and title block layered over it are
                  // Containers with a BoxDecoration, and BoxDecoration.hitTest
                  // returns true for a plain rectangle, so as siblings painted
                  // above the banner they swallowed the tap. An ancestor still
                  // receives what a child absorbs.
                  background: expandableImage(
                    context: context,
                    source: event.imageUrl,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _EventBanner(
                          orgName: event.orgName,
                          imageUrl: event.imageUrl,
                          height: 250,
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x44000000), Color(0xCC000000)],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  CategoryBadge(category: event.category),
                                  if (event.audience
                                      .split(',')
                                      .map((s) => s.trim())
                                      .contains('CICT Only')) ...[
                                    const SizedBox(width: 6),
                                    _AudienceBadge(audience: event.audience),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                event.orgName.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white60,
                                  letterSpacing: 1.4,
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

              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Organizer row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: event.orgLogoUrl.isNotEmpty
                                ? AppImage.provider(event.orgLogoUrl)
                                : null,
                            child: event.orgLogoUrl.isEmpty
                                ? Text(
                                    event.orgName.isNotEmpty
                                        ? event.orgName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimary,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.orgName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const Text(
                                  'ORGANIZATION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 1, color: Color(0xFFF0F0F0)),
                      const SizedBox(height: 16),

                      // Info tiles
                      _InfoTile(
                        icon: Icons.calendar_today_outlined,
                        iconColor: _kPrimary,
                        label: 'Date',
                        value: event.dateDisplay,
                      ),
                      if (event.startTime.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _InfoTile(
                          icon: Icons.access_time_outlined,
                          iconColor: const Color(0xFF1565C0),
                          label: 'Time',
                          value: event.timeDisplay,
                        ),
                      ],
                      const SizedBox(height: 10),
                      _InfoTile(
                        icon: Icons.location_on_outlined,
                        iconColor: const Color(0xFF2E7D32),
                        label: 'Location',
                        value: event.location,
                      ),
                      const SizedBox(height: 10),
                      _InfoTile(
                        icon: Icons.people_outline,
                        iconColor: const Color(0xFF6A1B9A),
                        label: 'Audience',
                        value: event.audience.isNotEmpty
                            ? event.audience
                            : 'Public',
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 1, color: Color(0xFFF0F0F0)),
                      const SizedBox(height: 16),

                      const Text(
                        'ABOUT THIS EVENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF888888),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        event.description.isNotEmpty
                            ? event.description
                            : 'No description provided.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.65,
                        ),
                      ),

                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFF0F0F0)),
                      const SizedBox(height: 16),

                      const Text(
                        'LOCATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF888888),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _LocationCard(location: event.location),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudienceBadge extends StatelessWidget {
  final String audience;
  const _AudienceBadge({required this.audience});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        audience.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  final String location;
  const _LocationCard({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kPrimaryBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: _kPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                location,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
