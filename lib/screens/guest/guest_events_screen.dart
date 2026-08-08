import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'guest_auth_service.dart';

ImageProvider _guestImageProvider(String url) {
  if (url.startsWith('data:image')) {
    return MemoryImage(base64Decode(url.split(',').last));
  }
  return NetworkImage(url);
}

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
const _kPrimary = Color(0xFFBE4700);
const _kPrimaryBg = Color(0xFFF5E3D9);
const _kBg = Color(0xFFF5F5F5);

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
  });

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
    );
  }

  String get dateDisplay => DateFormat('MMM dd, yyyy').format(date);

  String get timeDisplay {
    if (endTime.isNotEmpty) return '$startTime – $endTime';
    return startTime;
  }

  bool get isSoon =>
      date.difference(DateTime.now()).inDays <= 7 &&
      date.isAfter(DateTime.now());
}

// ─────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────
class GuestEventsScreen extends StatefulWidget {
  const GuestEventsScreen({super.key});

  @override
  State<GuestEventsScreen> createState() => _GuestEventsScreenState();
}

class _GuestEventsScreenState extends State<GuestEventsScreen> {
  // Firestore streams (combined: events + event_proposals both approved & public)
  StreamSubscription<QuerySnapshot>? _eventsSubscription;
  StreamSubscription<QuerySnapshot>? _proposalsSubscription;

  final Map<String, FirestoreEvent> _eventMap = {};
  bool _loading = true;
  String? _error;
  String _search = '';
  String _catFilter = 'All';

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

  Future<void> _init() async {
    await _loadGuestClassification();
    _subscribe();
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

  List<FirestoreEvent> get _filtered {
    var list = _eventMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (_catFilter != 'All') {
      list = list
          .where((e) => e.category.toLowerCase() == _catFilter.toLowerCase())
          .toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (e) =>
                e.title.toLowerCase().contains(q) ||
                e.orgName.toLowerCase().contains(q) ||
                e.location.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  List<String> get _categories {
    final cats = _eventMap.values.map((e) => e.category).toSet().toList()
      ..sort();
    return ['All', ...cats];
  }

  @override
  Widget build(BuildContext context) {
    final events = _filtered;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Public Events',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFF0F0F0)),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
          ? _ErrorView(
              error: _error!,
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                  _eventMap.clear();
                });
                _subscribe();
              },
            )
          : Column(
              children: [
                _SearchAndFilter(
                  search: _search,
                  onSearch: (v) => setState(() => _search = v),
                  categories: _categories,
                  selected: _catFilter,
                  onCategory: (c) => setState(() => _catFilter = c),
                ),
                Expanded(
                  child: events.isEmpty
                      ? _EmptyEvents(
                          isFiltering:
                              _search.isNotEmpty || _catFilter != 'All',
                        )
                      : _EventList(
                          events: events,
                          onTap: (e) => _openDetail(e),
                        ),
                ),
              ],
            ),
    );
  }

  void _openDetail(FirestoreEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuestEventDetailScreen(event: event)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Search + Filter bar
// ─────────────────────────────────────────────────────────────
class _SearchAndFilter extends StatefulWidget {
  final String search;
  final ValueChanged<String> onSearch;
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onCategory;

  const _SearchAndFilter({
    required this.search,
    required this.onSearch,
    required this.categories,
    required this.selected,
    required this.onCategory,
  });

  @override
  State<_SearchAndFilter> createState() => _SearchAndFilterState();
}

class _SearchAndFilterState extends State<_SearchAndFilter> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.search,
  );

  @override
  void didUpdateWidget(_SearchAndFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync when the search text changed from outside this field
    // (e.g. the clear button) — not on every keystroke, which would fight
    // the user's cursor position.
    if (widget.search != _ctrl.text) {
      _ctrl.value = _ctrl.value.copyWith(
        text: widget.search,
        selection: TextSelection.collapsed(offset: widget.search.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _ctrl,
            onChanged: widget.onSearch,
            decoration: InputDecoration(
              hintText: 'Search events, org, location…',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Colors.black38,
              ),
              suffixIcon: widget.search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => widget.onSearch(''),
                    )
                  : null,
              filled: true,
              fillColor: _kBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Category chips
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.categories.length,
              itemBuilder: (_, i) {
                final cat = widget.categories[i];
                final sel = cat == widget.selected;
                return GestureDetector(
                  onTap: () => widget.onCategory(cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel ? _kPrimary : Colors.black12,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Event list
// ─────────────────────────────────────────────────────────────
class _EventList extends StatelessWidget {
  final List<FirestoreEvent> events;
  final void Function(FirestoreEvent) onTap;
  const _EventList({required this.events, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final featured = events.first;
    final rest = events.sublist(1);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kPrimaryBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kPrimary.withOpacity(0.3)),
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
        ),

        // Featured
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: _FeaturedCard(event: featured, onTap: () => onTap(featured)),
        ),

        // Rest
        ...rest.map(
          (e) => Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _CompactCard(event: e, onTap: () => onTap(e)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Featured card
// ─────────────────────────────────────────────────────────────
class _FeaturedCard extends StatelessWidget {
  final FirestoreEvent event;
  final VoidCallback onTap;
  const _FeaturedCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Banner or gradient placeholder
            _EventBanner(orgName: event.orgName, height: 220),

            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                    stops: [0.3, 1.0],
                  ),
                ),
              ),
            ),

            // Content
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CategoryBadge(category: event.category),
                        if (event.isSoon) ...[
                          const SizedBox(width: 6),
                          _SoonBadge(),
                        ],
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
                        fontSize: 22,
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
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.dateDisplay,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: _kPrimary.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Compact card
// ─────────────────────────────────────────────────────────────
class _CompactCard extends StatelessWidget {
  final FirestoreEvent event;
  final VoidCallback onTap;
  const _CompactCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            _EventBanner(orgName: event.orgName, height: 120),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xDD000000), Color(0x55000000)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      _CategoryBadge(category: event.category),
                      if (event.isSoon) ...[
                        const SizedBox(width: 6),
                        _SoonBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 10,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.dateDisplay,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.business_outlined,
                        size: 10,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.orgName,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white60,
                          ),
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
  }
}

// ─────────────────────────────────────────────────────────────
// Banner widget — uses org logo or fallback gradient
// ─────────────────────────────────────────────────────────────
class _EventBanner extends StatelessWidget {
  final String orgName;
  final double height;
  const _EventBanner({required this.orgName, required this.height});

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
            color: Colors.white.withOpacity(0.15),
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
  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      backgroundColor: _kBg,
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
                        color: Colors.white.withOpacity(0.92),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
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
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _EventBanner(orgName: event.orgName, height: 250),
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
                                _CategoryBadge(category: event.category),
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
                                ? _guestImageProvider(event.orgLogoUrl)
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

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  Color get _color {
    switch (category.toLowerCase()) {
      case 'competition':
        return const Color(0xFFBE4700);
      case 'workshop':
        return const Color(0xFF1565C0);
      case 'seminar':
        return const Color(0xFF6A1B9A);
      case 'hackathon':
        return const Color(0xFFD32F2F);
      case 'sports':
        return const Color(0xFF1B5E20);
      default:
        return const Color(0xFF37474F);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        category.toUpperCase(),
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

class _SoonBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEB3B),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'SOON',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
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
            color: iconColor.withOpacity(0.1),
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

class _EmptyEvents extends StatelessWidget {
  final bool isFiltering;
  const _EmptyEvents({this.isFiltering = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: _kPrimaryBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy_outlined,
              size: 48,
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isFiltering
                ? 'No events match your filter'
                : 'No public events right now',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltering
                ? 'Try clearing your search or filter.'
                : 'Check back soon for upcoming events.',
            style: const TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load events',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
