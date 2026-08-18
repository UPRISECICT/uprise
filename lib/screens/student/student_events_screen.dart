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
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import 'student_feedback_screen.dart';
import 'student_certificates_screen.dart';
import 'student_webinar_code_screen.dart';
import 'student_organization_details_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../services/webinar_attendance_service.dart';
import '../../services/certificate_auto_issue_service.dart';

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

  DateTime _selectedDate = DateTime.now();

  // Cached once — this same query used to be created inline in build() in
  // two separate places (the day-count badge and the events list below),
  // so every calendar tap (_selectedDate change via setState) resubscribed
  // both and flashed the loading spinner even though the query result
  // itself doesn't depend on _selectedDate at all (filtering happens
  // client-side after the snapshot arrives).
  late final Stream<QuerySnapshot> _approvedEventsStream = FirebaseFirestore
      .instance
      .collection('events')
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  void _previousMonth() => setState(() {
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1);
  });
  void _nextMonth() => setState(() {
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppColors.primaryDark,
                ),
                onPressed: _previousMonth,
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppColors.primaryDark,
                ),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _CalendarGrid(
            selectedDate: _selectedDate,
            onDateSelected: (date) => setState(() => _selectedDate = date),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Events for ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              StreamBuilder<Set<String>>(
                stream: widget.registeredEventIdsStream,
                builder: (context, regSnap) {
                  final regIds = regSnap.data ?? {};
                  return StreamBuilder<QuerySnapshot>(
                    stream: _approvedEventsStream,
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final count = snap.data!.docs
                          .map((d) => EventModel.fromFirestore(d))
                          .where(
                            (e) =>
                                e.date.year == _selectedDate.year &&
                                e.date.month == _selectedDate.month &&
                                e.date.day == _selectedDate.day,
                          )
                          .length;
                      return Text(
                        '$count events',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: widget.registeredEventIdsStream,
            builder: (context, regSnap) {
              final regIds = regSnap.data ?? {};
              return StreamBuilder<QuerySnapshot>(
                stream: _approvedEventsStream,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryDark,
                      ),
                    );
                  }
                  final todayEvents = snap.data!.docs
                      .map((d) => EventModel.fromFirestore(d))
                      .where(
                        (e) =>
                            e.date.year == _selectedDate.year &&
                            e.date.month == _selectedDate.month &&
                            e.date.day == _selectedDate.day,
                      )
                      .toList();

                  if (todayEvents.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'No events for this day',
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

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: todayEvents.length,
                    itemBuilder: (context, index) {
                      final event = todayEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CompactEventCard(
                          event: event,
                          onTap: () => _openDetail(event),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
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

  // ── Status filter (Upcoming / Ongoing / Past) ──
  _RegStatus _selectedFilter = _RegStatus.upcoming;

  // ── Search + organization filter ──
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedOrgId; // null = All Organizations
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
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime? _combineDateAndTime(DateTime date, String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    final cleaned = timeStr.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(cleaned);
    if (match == null) return null;
    int hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3);
    if (meridiem == 'PM' && hour != 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  _RegStatus _statusFor(EventModel event) {
    final now = DateTime.now();
    final dynamic raw = event;
    String? startTimeStr;
    String? endTimeStr;
    try {
      startTimeStr = raw.startTime as String?;
    } catch (_) {}
    try {
      endTimeStr = raw.endTime as String?;
    } catch (_) {}

    final start = _combineDateAndTime(event.date, startTimeStr) ?? event.date;
    final end =
        _combineDateAndTime(event.date, endTimeStr) ??
        DateTime(event.date.year, event.date.month, event.date.day, 23, 59);

    if (now.isBefore(start)) return _RegStatus.upcoming;
    if (now.isAfter(end)) return _RegStatus.completed;
    return _RegStatus.ongoing;
  }

  String get _emptyStateMessage {
    switch (_selectedFilter) {
      case _RegStatus.upcoming:
        return 'No upcoming events';
      case _RegStatus.ongoing:
        return 'No ongoing events';
      case _RegStatus.completed:
        return 'No past events';
    }
  }

  IconData get _emptyStateIcon {
    switch (_selectedFilter) {
      case _RegStatus.upcoming:
        return Icons.event_available;
      case _RegStatus.ongoing:
        return Icons.event_repeat;
      case _RegStatus.completed:
        return Icons.event_busy;
    }
  }

  // Always-visible 3-way pill selector — replaces the old dropdown so the
  // three event categories read as distinct sections at a glance instead of
  // being hidden behind a menu.
  Widget _buildSegmentedControl() {
    const options = [
      (_RegStatus.upcoming, 'Upcoming'),
      (_RegStatus.ongoing, 'Ongoing'),
      (_RegStatus.completed, 'Past'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((opt) {
          final isActive = _selectedFilter == opt.$1;
          final isOngoingPill = opt.$1 == _RegStatus.ongoing;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primaryDark : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOngoingPill) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white : Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

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

            final allApprovedEvents = snap.data!.docs
                .map((d) => EventModel.fromFirestore(d))
                .toList();

            final query = _searchQuery.trim().toLowerCase();
            final allEvents = allApprovedEvents.where((e) {
              if (_statusFor(e) != _selectedFilter) return false;
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

            // Past events read best most-recent-first; upcoming/ongoing stay
            // in ascending date order (already sorted by the Firestore query).
            if (_selectedFilter == _RegStatus.completed) {
              allEvents.sort((a, b) => b.date.compareTo(a.date));
            }

            final isOngoing = _selectedFilter == _RegStatus.ongoing;

            return Column(
              children: [
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<List<QueryDocumentSnapshot>>(
                          future: _orgsFuture,
                          builder: (context, orgSnap) {
                            final orgs = orgSnap.data ?? const [];
                            return _OrgFilterDropdown(
                              orgs: orgs,
                              selectedOrgId: _selectedOrgId,
                              onChanged: (id) =>
                                  setState(() => _selectedOrgId = id),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(child: _buildSegmentedControl()),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          _compactView
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          color: AppColors.primaryDark,
                        ),
                        tooltip: _compactView
                            ? 'Switch to list view'
                            : 'Switch to grid view',
                        onPressed: () {
                          setState(() => _compactView = !_compactView);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: allEvents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _emptyStateIcon,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _emptyStateMessage,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : (_compactView
                            ? _buildCompactGrid(allEvents, regIds, isOngoing)
                            : _buildDetailedList(allEvents, regIds, isOngoing)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailedList(
    List<EventModel> events,
    Set<String> regIds,
    bool isOngoing,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isRegistered = regIds.contains(event.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _UpcomingEventCard(
            event: event,
            isRegistered: isRegistered,
            showLiveBadge: isOngoing,
            onTap: () => _openDetail(event),
          ),
        );
      },
    );
  }

  Widget _buildCompactGrid(
    List<EventModel> events,
    Set<String> regIds,
    bool isOngoing,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isRegistered = regIds.contains(event.id);
        return _CompactUpcomingCard(
          event: event,
          isRegistered: isRegistered,
          showLiveBadge: isOngoing,
          onTap: () => _openDetail(event),
        );
      },
    );
  }
}

// Organization filter for Discover — same `organizations` collection and
// `status == 'active'` filter every other org picker in the app uses.
class _OrgFilterDropdown extends StatelessWidget {
  final List<QueryDocumentSnapshot> orgs;
  final String? selectedOrgId;
  final ValueChanged<String?> onChanged;

  const _OrgFilterDropdown({
    required this.orgs,
    required this.selectedOrgId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedOrgId,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 20),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          hint: Text(
            'All Organizations',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Organizations'),
            ),
            for (final doc in orgs)
              DropdownMenuItem<String?>(
                value: doc.id,
                child: Text(
                  ((doc.data() as Map<String, dynamic>)['orgName'] ??
                          (doc.data() as Map<String, dynamic>)['name'] ??
                          'Organization')
                      .toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Compact grid card ──
class _CompactUpcomingCard extends StatelessWidget {
  final EventModel event;
  final bool isRegistered;
  final bool showLiveBadge;
  final VoidCallback onTap;

  const _CompactUpcomingCard({
    required this.event,
    required this.isRegistered,
    this.showLiveBadge = false,
    required this.onTap,
  });

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
              color: Colors.black.withOpacity(0.08),
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
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  showLoadingIndicator: true,
                ),
                if (showLiveBadge)
                  const Positioned(top: 6, left: 6, child: _LiveBadge()),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.formattedDate,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.formattedTime,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRegistered
                              ? Colors.green
                              : AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          isRegistered ? 'Registered' : 'View',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
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

enum _ViewFilter { all, active, archived }

enum _RegStatus { upcoming, ongoing, completed }

// Activity status for My Events — distinct from _RegStatus (which is a
// pure time-based upcoming/ongoing/past used by the Discover tab).
enum _MyEventStatus { registered, needsFeedback, completed }

class _MyEventsTabState extends State<MyEventsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Stream<QuerySnapshot>? _registrationsStream;
  _ViewFilter _viewFilter = _ViewFilter.all;

  // Attendance + feedback-submitted event IDs — same two queries the old
  // Evaluations tab used (collectionGroup('attendances') for attendance,
  // both event_feedback and feedback for "already submitted", since the
  // app never finished migrating off the legacy `feedback` collection).
  Future<({Set<String> attended, Set<String> evaluated})>? _statusDataFuture;

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

  DateTime? _combineDateAndTime(DateTime date, String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    final cleaned = timeStr.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(cleaned);
    if (match == null) return null;
    int hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3);
    if (meridiem == 'PM' && hour != 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  _RegStatus _statusFor(EventModel event) {
    final now = DateTime.now();
    final dynamic raw = event;
    String? startTimeStr;
    String? endTimeStr;
    try {
      startTimeStr = raw.startTime as String?;
    } catch (_) {}
    try {
      endTimeStr = raw.endTime as String?;
    } catch (_) {}

    final start = _combineDateAndTime(event.date, startTimeStr) ?? event.date;
    final end =
        _combineDateAndTime(event.date, endTimeStr) ??
        DateTime(event.date.year, event.date.month, event.date.day, 23, 59);

    if (now.isBefore(start)) return _RegStatus.upcoming;
    if (now.isAfter(end)) return _RegStatus.completed;
    return _RegStatus.ongoing;
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

  Future<void> _archiveEvent(EventModel event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Archive Event'),
        content: Text(
          'Are you sure you want to archive "${event.title}"?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docId = '${user.uid}_${event.id}';
      await FirebaseFirestore.instance
          .collection('registrations')
          .doc(docId)
          .update({
            'isArchived': true,
            'archivedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${event.title}" archived'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unarchiveEvent(EventModel event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restore Event'),
        content: Text(
          'Restore "${event.title}" to your registered events?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docId = '${user.uid}_${event.id}';
      await FirebaseFirestore.instance
          .collection('registrations')
          .doc(docId)
          .update({'isArchived': false, 'archivedAt': FieldValue.delete()});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${event.title}" restored'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

        // Filter based on view filter
        final filteredRegistrations = allRegistrationData.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isArchived = data['isArchived'] == true;
          switch (_viewFilter) {
            case _ViewFilter.active:
              return !isArchived;
            case _ViewFilter.archived:
              return isArchived;
            case _ViewFilter.all:
              return true;
          }
        }).toList();

        final eventIds = filteredRegistrations
            .map(
              (d) => (d.data() as Map<String, dynamic>)['eventId'] as String?,
            )
            .whereType<String>()
            .toSet()
            .toList();

        // ⭐ FIX: Build the UI with filter buttons ALWAYS visible
        return Column(
          children: [
            // ─── Filter Segmented Buttons (ALWAYS VISIBLE) ───
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: SegmentedButton<_ViewFilter>(
                segments: const [
                  ButtonSegment(
                    value: _ViewFilter.all,
                    label: Text('All'),
                    icon: Icon(Icons.view_list_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _ViewFilter.active,
                    label: Text('Active'),
                    icon: Icon(Icons.event_note_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _ViewFilter.archived,
                    label: Text('Archived'),
                    icon: Icon(Icons.archive_rounded, size: 16),
                  ),
                ],
                selected: {_viewFilter},
                onSelectionChanged: (Set<_ViewFilter> newSelection) {
                  setState(() {
                    _viewFilter = newSelection.first;
                  });
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primaryDark,
                  selectedForegroundColor: Colors.white,
                  foregroundColor: Colors.grey.shade600,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
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
                      return _buildContent(
                        eventIds,
                        regSnap,
                        attended,
                        evaluated,
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    List<String> eventIds,
    AsyncSnapshot<QuerySnapshot> regSnap,
    Set<String> attended,
    Set<String> evaluated,
  ) {
    if (eventIds.isEmpty) {
      // ⭐ Show empty state with appropriate message based on filter
      String message;
      IconData icon;
      switch (_viewFilter) {
        case _ViewFilter.all:
          message = 'No registered events';
          icon = Icons.event_note_outlined;
          break;
        case _ViewFilter.active:
          message = 'No active events';
          icon = Icons.event_busy_outlined;
          break;
        case _ViewFilter.archived:
          message = 'No archived events';
          icon = Icons.archive_outlined;
          break;
      }

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

    final chunks = <List<String>>[];
    for (var i = 0; i < eventIds.length; i += 30) {
      chunks.add(
        eventIds.sublist(
          i,
          i + 30 > eventIds.length ? eventIds.length : i + 30,
        ),
      );
    }

    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait(
        chunks.map(
          (chunk) => FirebaseFirestore.instance
              .collection('events')
              .where(FieldPath.documentId, whereIn: chunk)
              .get(),
        ),
      ),
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

        final events = evSnap.data!
            .expand((snap) => snap.docs)
            .map((d) => EventModel.fromFirestore(d))
            .toList();

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

            bool isArchived = false;
            if (_viewFilter == _ViewFilter.all) {
              isArchived = (regSnap.data?.docs ?? []).any((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['eventId'] == event.id &&
                    data['isArchived'] == true;
              });
            } else if (_viewFilter == _ViewFilter.archived) {
              isArchived = true;
            }

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
                            color: isArchived ? Colors.grey : style.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isArchived ? 'ARCHIVED' : style.label,
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
                                  backgroundColor: isArchived
                                      ? Colors.grey
                                      : (myStatus ==
                                                _MyEventStatus.needsFeedback
                                            ? style.color
                                            : AppColors.primaryDark),
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
                            const SizedBox(width: 8),
                            if (!isArchived)
                              IconButton(
                                onPressed: () => _archiveEvent(event),
                                icon: Icon(
                                  Icons.archive_outlined,
                                  size: 20,
                                  color: Colors.grey.shade600,
                                ),
                                tooltip: 'Archive',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.grey.shade100,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                onPressed: () => _unarchiveEvent(event),
                                icon: Icon(
                                  Icons.restore_from_trash,
                                  size: 20,
                                  color: Colors.green.shade700,
                                ),
                                tooltip: 'Restore',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.green.shade50,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
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

// ─── CALENDAR GRID ─────────────────────────────────────────────
class _CalendarGrid extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const _CalendarGrid({
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    final firstWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      selectedDate.year,
      selectedDate.month + 1,
      0,
    ).day;

    final eventsStream = FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: eventsStream,
      builder: (context, snap) {
        Set<String> eventDates = {};
        if (snap.hasData) {
          final events = snap.data!.docs
              .map((d) => EventModel.fromFirestore(d))
              .where(
                (e) =>
                    e.date.year == selectedDate.year &&
                    e.date.month == selectedDate.month,
              )
              .toList();

          eventDates = events
              .map(
                (e) =>
                    '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}',
              )
              .toSet();
        }

        List<Widget> dayWidgets = [];
        const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
        for (var day in weekdays) {
          dayWidgets.add(
            Center(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          );
        }

        for (int i = 0; i < firstWeekday; i++) {
          dayWidgets.add(const SizedBox.shrink());
        }

        for (int day = 1; day <= daysInMonth; day++) {
          final currentDate = DateTime(
            selectedDate.year,
            selectedDate.month,
            day,
          );
          final isSelected =
              currentDate.year == selectedDate.year &&
              currentDate.month == selectedDate.month &&
              currentDate.day == selectedDate.day;
          final isToday =
              currentDate.year == DateTime.now().year &&
              currentDate.month == DateTime.now().month &&
              currentDate.day == DateTime.now().day;

          final dateKey =
              '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
          final hasEvent = eventDates.contains(dateKey);

          // ── Dot indicator color logic ──
          // Green  = event is happening today
          // Red    = event date has already passed (finished)
          // Yellow = event is upcoming (in the future)
          Color indicatorColor;
          final todayMidnight = DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          );
          if (hasEvent && isToday) {
            indicatorColor = Colors.green;
          } else if (hasEvent && currentDate.isBefore(todayMidnight)) {
            indicatorColor = Colors.red;
          } else if (hasEvent) {
            indicatorColor = Colors.amber;
          } else {
            indicatorColor = Colors.transparent;
          }

          dayWidgets.add(
            GestureDetector(
              onTap: () => onDateSelected(currentDate),
              child: Container(
                margin: const EdgeInsets.all(2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.primaryDark
                            : isToday
                            ? Colors.grey.shade200
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(
                          day.toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : isToday
                                ? AppColors.primaryDark
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    if (hasEvent)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: indicatorColor,
                        ),
                      )
                    else
                      const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          );
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.1,
          children: dayWidgets,
        );
      },
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

// ─── UPCOMING EVENT CARD ──────────────────────────────────────
class _UpcomingEventCard extends StatelessWidget {
  final EventModel event;
  final bool isRegistered;
  final bool showLiveBadge;
  final VoidCallback onTap;

  const _UpcomingEventCard({
    required this.event,
    required this.isRegistered,
    this.showLiveBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  showLoadingIndicator: true,
                ),
                if (showLiveBadge)
                  const Positioned(top: 10, left: 10, child: _LiveBadge()),
                if (showLiveBadge && isRegistered)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    left: 10,
                    child: _WebinarCodeBanner(eventId: event.id),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CategoryBadge(category: event.displayCategory),
                      const Spacer(),
                      if (isRegistered)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: Colors.green,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Registered',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRegistered
                            ? Colors.green
                            : AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: Text(
                        isRegistered ? 'Registered ✓' : 'View Details',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
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

// ─── LIVE STATUS BADGE ──────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
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
class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  Color get _color {
    switch (category.toLowerCase()) {
      case 'competition':
        return AppColors.primaryDark;
      case 'workshop':
        return const Color(0xFF1565C0);
      case 'seminar':
        return const Color(0xFF6A1B9A);
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── EVENT DETAIL SCREEN ──────────────────────────────────────
// Audience/eligibility — always visible regardless of registration state,
// parsed the same comma-separated way EventModel.audienceAllowsMember
// already does, so the labels shown here always match what's actually
// being enforced.
class _AudienceBadgeRow extends StatelessWidget {
  final String audience;
  const _AudienceBadgeRow({required this.audience});

  @override
  Widget build(BuildContext context) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final labels = values.isEmpty || values.contains('Public')
        ? const ['Public']
        : values;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: label == 'Public'
                  ? Colors.green.withOpacity(0.1)
                  : AppColors.primaryDark.withOpacity(0.08),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: label == 'Public'
                    ? Colors.green.withOpacity(0.3)
                    : AppColors.primaryDark.withOpacity(0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  label == 'Public'
                      ? Icons.public
                      : Icons.verified_user_outlined,
                  size: 12,
                  color: label == 'Public'
                      ? Colors.green.shade700
                      : AppColors.primaryDark,
                ),
                const SizedBox(width: 5),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: label == 'Public'
                        ? Colors.green.shade700
                        : AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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

  bool get _isEventReallyOver {
    try {
      final event = widget.event;
      final dynamic raw = event;
      String? endTimeStr;
      try {
        endTimeStr = raw.endTime as String?;
      } catch (_) {
        endTimeStr = null;
      }

      if (endTimeStr == null || endTimeStr.trim().isEmpty) {
        return widget.isPastEvent;
      }

      final parsedEnd = _combineDateAndTimeString(event.date, endTimeStr);
      if (parsedEnd == null) return widget.isPastEvent;

      return DateTime.now().isAfter(parsedEnd);
    } catch (_) {
      return widget.isPastEvent;
    }
  }

  DateTime? _combineDateAndTimeString(DateTime date, String timeStr) {
    final cleaned = timeStr.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(cleaned);
    if (match == null) return null;

    int hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3);

    if (meridiem == 'PM' && hour != 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

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
    final countSnap = await FirebaseFirestore.instance
        .collection('registrations')
        .where('eventId', isEqualTo: widget.event.id)
        .count()
        .get();
    if (mounted) setState(() => _registeredCount = countSnap.count ?? 0);
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
      final data = {
        'eventId': widget.event.id,
        'eventName': widget.event.title,
        'organization': widget.event.orgName,
        'orgId': widget.event.orgId,
        'rating': _rating,
        'comment': _feedbackCtrl.text.trim(),
        'userId': user.uid,
        'isAnonymous': _isAnonymous,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anonymous Feedback',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAnonymous
                            ? 'The organization won\'t see your name.'
                            : 'The organization can see who submitted this.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _isAnonymous ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _isAnonymous
                        ? AppColors.primaryDark
                        : Colors.grey.shade500,
                  ),
                ),
                Switch(
                  value: _isAnonymous,
                  activeColor: AppColors.primaryDark,
                  onChanged: _feedbackSubmitted
                      ? null
                      : (v) => setState(() => _isAnonymous = v),
                ),
              ],
            ),
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

  // A 'file_upload' question's picked answer. Images are compressed then
  // stored as a base64 data URI directly on the answer (matches how org
  // screens already store product/banner photos inline on a document).
  // Videos go to Firebase Storage instead — even compressed, a video would
  // blow past Firestore's 1 MiB document limit — and the answer stores the
  // resulting download URL, which is also what the org-side answer viewer
  // (showRegistrationAnswers in org_attendance_qr.dart) already renders as
  // a tappable link for any http(s) value.
  Future<void> _pickFileUploadAnswer(
    String id, {
    required bool asVideo,
    VoidCallback? onStateChanged,
  }) async {
    final picker = ImagePicker();
    final XFile? picked = asVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    _fileUploadBusy[id] = true;
    _refreshFieldState(onStateChanged);
    try {
      final bytes = await picked.readAsBytes();
      if (asVideo) {
        final user = FirebaseAuth.instance.currentUser;
        final ext = picked.name.contains('.')
            ? picked.name.split('.').last.toLowerCase()
            : 'mp4';
        final path =
            'registration_uploads/${widget.event.id}/${user?.uid ?? 'anon'}/'
            '${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(bytes, SettableMetadata(contentType: 'video/$ext'));
        final url = await ref.getDownloadURL();
        _fileUploadValues[id] = url;
        _fileUploadNames[id] = picked.name;
      } else {
        final compressed = await _compressPickedImage(bytes);
        _fileUploadValues[id] =
            'data:image/jpeg;base64,${base64Encode(compressed)}';
        _fileUploadNames[id] = picked.name;
      }
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
        if (required && (_fileUploadValues[id] ?? '').isEmpty) {
          return 'Please attach a photo/video for: $label';
        }
        if (_fileUploadBusy[id] == true) {
          return 'Please wait for the upload to finish for: $label';
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
    if (widget.isPastEvent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot register for past events'),
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

        // Optional, org-set — null means unlimited slots.
        final capacity = (evData['capacity'] as num?)?.toInt();
        if (capacity != null) {
          final countSnap = await FirebaseFirestore.instance
              .collection('registrations')
              .where('eventId', isEqualTo: widget.event.id)
              .count()
              .get();
          if ((countSnap.count ?? 0) >= capacity) {
            throw Exception(
              'This event has reached its maximum capacity of $capacity and is no longer accepting registrations.',
            );
          }
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
        final hasValue = (_fileUploadValues[id] ?? '').isNotEmpty;
        final busy = _fileUploadBusy[id] == true;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasValue)
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
                        _fileUploadNames[id] ?? 'File attached',
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
              ),
            if (busy)
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (mediaType == 'image' || mediaType == 'both')
                    OutlinedButton.icon(
                      onPressed: () => _pickFileUploadAnswer(
                        id,
                        asVideo: false,
                        onStateChanged: onStateChanged,
                      ),
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: Text(hasValue ? 'Replace Photo' : 'Choose Photo'),
                    ),
                  if (mediaType == 'video' || mediaType == 'both')
                    OutlinedButton.icon(
                      onPressed: () => _pickFileUploadAnswer(
                        id,
                        asVideo: true,
                        onStateChanged: onStateChanged,
                      ),
                      icon: const Icon(Icons.videocam_outlined, size: 16),
                      label: Text(hasValue ? 'Replace Video' : 'Choose Video'),
                    ),
                ],
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
            EventImage(
              imageUrl: widget.event.imageUrl,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              showLoadingIndicator: true,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryBadge(category: widget.event.displayCategory),
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
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    text: widget.event.formattedDate,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.access_time,
                    text: widget.event.formattedTime,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: widget.event.location,
                  ),
                  const SizedBox(height: 12),
                  _AudienceBadgeRow(audience: widget.event.audience),
                  if (widget.event.capacity != null) ...[
                    const SizedBox(height: 12),
                    _InfoRow(
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
                    else if (!_isEligibleForEvent) ...[
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
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: color ?? Colors.black87,
              fontWeight: color != null ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
