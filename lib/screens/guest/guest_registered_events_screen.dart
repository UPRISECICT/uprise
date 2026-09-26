// lib/screens/guest/guest_registered_events_screen.dart
//
// GUEST REGISTERED EVENTS — Only meaningful for authenticated guests.
//
// Loads this guest's `registrations` (keyed by email + isGuest==true, same
// convention as guest_events_screen.dart / guest_feedback_screen.dart),
// joins the matching `events` docs, and splits them into Upcoming / Past.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'guest_auth_service.dart';
import '../../widgets/common/event_date_filter.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;

class _RegisteredEvent {
  final String eventId;
  final String title;
  final String orgName;
  final String location;
  final DateTime date;
  final String status;
  _RegisteredEvent({
    required this.eventId,
    required this.title,
    required this.orgName,
    required this.location,
    required this.date,
    required this.status,
  });
}

class GuestRegisteredEventsScreen extends StatefulWidget {
  /// True when hosted as a sub-tab of the Events screen. The Upcoming/Past
  /// TabBar is still needed, so only the title row collapses.
  final bool embedded;

  const GuestRegisteredEventsScreen({super.key, this.embedded = false});

  @override
  State<GuestRegisteredEventsScreen> createState() => _GuestRegisteredEventsScreenState();
}

class _GuestRegisteredEventsScreenState extends State<GuestRegisteredEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  final List<_RegisteredEvent> _events = [];
  EventDateFilter? _dateFilter; // null = any date

  Future<void> _openDateFilter() async {
    final result = await showEventDateFilterSheet(context, _dateFilter);
    if (result == null || !mounted) return;
    setState(() => _dateFilter = result.date);
  }

  bool _matchesDate(_RegisteredEvent e) =>
      _dateFilter == null || _dateFilter!.matches(e.date);

  /// Empty-state line, naming the date filter when one is narrowing the list.
  String _emptyText(String base) => _dateFilter == null
      ? 'No $base registrations.'
      : 'No $base registrations ${_dateFilter!.phrase}.';

  String get _email => (GuestAuthService().email ?? '').toLowerCase();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_email.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }
    try {
      final regSnap = await FirebaseFirestore.instance
          .collection('registrations')
          .where('email', isEqualTo: _email)
          .where('isGuest', isEqualTo: true)
          .get();

      final eventIds = regSnap.docs
          .map((d) => (d.data())['eventId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final list = <_RegisteredEvent>[];
      if (eventIds.isNotEmpty) {
        final eventDocs = await Future.wait(eventIds.map(
            (id) => FirebaseFirestore.instance.collection('events').doc(id).get()));
        for (final doc in eventDocs) {
          if (!doc.exists) continue;
          final d = doc.data() as Map<String, dynamic>;
          list.add(_RegisteredEvent(
            eventId: doc.id,
            title: d['title'] as String? ?? 'Untitled',
            orgName: d['orgName'] as String? ?? '',
            location: d['location'] as String? ?? 'TBA',
            date: d['date'] is Timestamp ? (d['date'] as Timestamp).toDate() : DateTime.now(),
            status: d['status'] as String? ?? 'approved',
          ));
        }
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      if (mounted) setState(() { _events..clear()..addAll(list); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<_RegisteredEvent> get _upcoming =>
      _events.where((e) => !e.date.isBefore(DateTime.now()) && _matchesDate(e)).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  List<_RegisteredEvent> get _past =>
      _events.where((e) => e.date.isBefore(DateTime.now()) && _matchesDate(e)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: StudentAppBar(
        title: 'Registered Events',
        // Hosted as the Events screen's "My Events" sub-tab, the parent
        // already shows a title — only the TabBar below is needed.
        showTitleBar: !widget.embedded,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kOrange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _kOrange,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'Upcoming (${_upcoming.length})'),
            Tab(text: 'Past (${_past.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)))
              : Column(
                  children: [
                    _buildDateFilterRow(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_upcoming, _emptyText('upcoming')),
                          _buildList(_past, _emptyText('past')),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Active date filter (or "All dates") on the left, the filter button on
  /// the right — the same button the Discover tab has beside its search box.
  Widget _buildDateFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _dateFilter == null
                  ? Text(
                      'All dates',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    )
                  : EventDateFilterChip(
                      filter: _dateFilter!,
                      onTap: _openDateFilter,
                      onCleared: () => setState(() => _dateFilter = null),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          EventFilterButton(
            activeCount: _dateFilter != null ? 1 : 0,
            onTap: _openDateFilter,
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<_RegisteredEvent> items, String emptyText) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_busy_outlined, size: 48, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 14),
            Text(emptyText, textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF0F0F0)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 48, height: 54,
                decoration: BoxDecoration(color: _kOrangeLight, borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(DateFormat('MMM').format(items[i].date).toUpperCase(),
                      style: GoogleFonts.beVietnamPro(fontSize: 9, fontWeight: FontWeight.w700, color: _kOrange)),
                  Text(DateFormat('dd').format(items[i].date),
                      style: GoogleFonts.beVietnamPro(fontSize: 22, fontWeight: FontWeight.w900, color: _kOrange)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(items[i].orgName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text(items[i].location, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey))),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
