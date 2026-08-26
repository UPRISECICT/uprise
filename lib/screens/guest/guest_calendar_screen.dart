// lib/screens/guest/guest_calendar_screen.dart
//
// GUEST CALENDAR — public event calendar adapted from OrgEventsScheduleScreen.
//
// Shows approved public/CICT-Only events in a monthly calendar grid.
// Tapping a day with events shows a bottom sheet with the event list.
// Tapping an event navigates to GuestEventDetailScreen.
//
// Firestore: collection('events').where('status', '==', 'approved')
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../widgets/common/loading_widget.dart';
import 'guest_auth_service.dart';
import 'guest_events_screen.dart'; // reuses GuestEventDetailScreen + _FirestoreEvent
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

// ─────────────────────────────────────────────────────────────
//  CATEGORY COLOURS  (matches org_events_schedule.dart)
// ─────────────────────────────────────────────────────────────
const Map<String, Color> _catColors = {
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
  'Other': Color(0xFF6B7280),
};

Color _catColor(String cat) => _catColors[cat] ?? const Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────────────────────
const _kPrimary = AppColors.primaryDark;
const _kPrimaryBg = AppColors.primarySoft;
const _kBg = AppColors.background;

// ─────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────
class GuestCalendarScreen extends StatefulWidget {
  /// True when hosted as a sub-tab of the Events screen, which supplies its
  /// own app bar — rendering this screen's would stack two of them.
  final bool embedded;

  const GuestCalendarScreen({super.key, this.embedded = false});

  @override
  State<GuestCalendarScreen> createState() => _GuestCalendarScreenState();
}

class _GuestCalendarScreenState extends State<GuestCalendarScreen> {
  DateTime _currentMonth = DateTime.now();
  StreamSubscription<QuerySnapshot>? _sub;
  final Map<String, FirestoreEvent> _eventMap = {};
  bool _loading = true;
  String _guestClassification = 'Outsider';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final svc = GuestAuthService();
    if (svc.isAuthenticated && svc.docId != null) {
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
    _subscribe();
  }

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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub = FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen(
          (snap) {
            for (final doc in snap.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final aud = (d['audience'] as String?) ?? 'Public';
              if (!_audienceAllowed(aud)) {
                _eventMap.remove(doc.id);
                continue;
              }
              _eventMap[doc.id] = FirestoreEvent.fromDoc(doc);
            }
            final ids = snap.docs.map((d) => d.id).toSet();
            _eventMap.removeWhere((k, _) => !ids.contains(k));
            if (mounted) setState(() => _loading = false);
          },
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  List<FirestoreEvent> _eventsForDay(int day) {
    return _eventMap.values
        .where(
          (e) =>
              e.date.year == _currentMonth.year &&
              e.date.month == _currentMonth.month &&
              e.date.day == day,
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // Build the Map<day, [events]> for the current month
  Map<int, List<FirestoreEvent>> get _byDay {
    final m = <int, List<FirestoreEvent>>{};
    for (final e in _eventMap.values) {
      if (e.date.year == _currentMonth.year &&
          e.date.month == _currentMonth.month) {
        m.putIfAbsent(e.date.day, () => []).add(e);
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: widget.embedded
          ? null
          : const StudentAppBar(title: 'Calendar'),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonLoader(count: 1, height: 340),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Month nav ──────────────────────────────
                  _MonthNav(
                    currentMonth: _currentMonth,
                    onPrev: () => setState(
                      () => _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month - 1,
                      ),
                    ),
                    onNext: () => setState(
                      () => _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month + 1,
                      ),
                    ),
                    onToday: () =>
                        setState(() => _currentMonth = DateTime.now()),
                  ),

                  const SizedBox(height: 16),

                  // ── Calendar grid ──────────────────────────
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
                    child: _CalendarGrid(
                      key: ValueKey(
                        '${_currentMonth.year}-${_currentMonth.month}',
                      ),
                      currentMonth: _currentMonth,
                      byDay: _byDay,
                      onDayTap: (day, events) => _showDaySheet(day, events),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Upcoming events list ───────────────────
                  _UpcomingSection(
                    events:
                        _eventMap.values
                            .where(
                              (e) => e.date.isAfter(
                                DateTime.now().subtract(
                                  const Duration(days: 1),
                                ),
                              ),
                            )
                            .toList()
                          ..sort((a, b) => a.date.compareTo(b.date)),
                    onTap: (e) => _openDetail(e),
                  ),
                ],
              ),
            ),
    );
  }

  void _showDaySheet(int day, List<FirestoreEvent> events) {
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
                        color: _kPrimaryBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_rounded,
                        color: _kPrimary,
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
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            '${events.length} event${events.length == 1 ? '' : 's'}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: Colors.grey,
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
                  itemBuilder: (_, i) => _DayEventTile(
                    event: events[i],
                    onTap: () {
                      Navigator.pop(context);
                      _openDetail(events[i]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(FirestoreEvent event) {
    // Convert to FirestoreEvent for the detail screen
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuestEventDetailScreen(event: event)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MONTH NAV BAR
// ─────────────────────────────────────────────────────────────
class _MonthNav extends StatelessWidget {
  final DateTime currentMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const _MonthNav({
    required this.currentMonth,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Today button
        GestureDetector(
          onTap: onToday,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.today_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  'Today',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Month navigator
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E6EA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(currentMonth),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 40,
        child: Icon(icon, size: 20, color: Colors.black45),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CALENDAR GRID  (7-column grid matching org_events_schedule)
// ─────────────────────────────────────────────────────────────
class _CalendarGrid extends StatelessWidget {
  final DateTime currentMonth;
  final Map<int, List<FirestoreEvent>> byDay;
  final void Function(int, List<FirestoreEvent>) onDayTap;

  const _CalendarGrid({
    super.key,
    required this.currentMonth,
    required this.byDay,
    required this.onDayTap,
  });

  int get _daysInMonth =>
      DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
  int get _startWeekday =>
      DateTime(currentMonth.year, currentMonth.month, 1).weekday % 7;
  int get _totalRows => ((_startWeekday + _daysInMonth) / 7).ceil();

  @override
  Widget build(BuildContext context) {
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Weekday header
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppColors.primarySoft)),
            ),
            child: Row(
              children: weekdays
                  .map(
                    (d) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Day cells
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 100,
            ),
            itemCount: _totalRows * 7,
            itemBuilder: (_, index) {
              final dayNum = index - _startWeekday + 1;
              if (dayNum < 1 || dayNum > _daysInMonth) {
                return _emptyCell(index);
              }
              final events = byDay[dayNum] ?? [];
              return _DayCell(
                day: dayNum,
                events: events,
                currentMonth: currentMonth,
                totalRows: _totalRows,
                startWeekday: _startWeekday,
                daysInMonth: _daysInMonth,
                onTap: events.isEmpty ? null : () => onDayTap(dayNum, events),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyCell(int index) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        border: Border(
          right: (index % 7) < 6
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
          bottom: index < (_totalRows - 1) * 7
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DAY CELL
// ─────────────────────────────────────────────────────────────
class _DayCell extends StatelessWidget {
  final int day;
  final List<FirestoreEvent> events;
  final DateTime currentMonth;
  final int totalRows;
  final int startWeekday;
  final int daysInMonth;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.events,
    required this.currentMonth,
    required this.totalRows,
    required this.startWeekday,
    required this.daysInMonth,
    required this.onTap,
  });

  bool get isToday =>
      day == DateTime.now().day &&
      currentMonth.year == DateTime.now().year &&
      currentMonth.month == DateTime.now().month;

  int get cellIndex => startWeekday + day - 1;
  int get colIndex => cellIndex % 7;
  bool get isLastRow => cellIndex >= (totalRows - 1) * 7;

  @override
  Widget build(BuildContext context) {
    final display = events.take(3).toList();
    final extra = events.length - display.length;

    return InkWell(
      onTap: onTap,
      hoverColor: _kPrimary.withAlpha(10),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? _kPrimary.withAlpha(18) : null,
          border: Border(
            right: colIndex < 6
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
            bottom: !isLastRow
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kPrimary,
                          boxShadow: [
                            BoxShadow(
                              color: _kPrimary.withAlpha(89),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                      color: isToday ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (events.length > 1)
                  Text(
                    '${events.length}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            ...display.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _catColor(e.category).withAlpha(31),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: _catColor(e.category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.title,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: _catColor(e.category),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (extra > 0)
              Text(
                '+$extra more',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DAY EVENT TILE  (bottom sheet item)
// ─────────────────────────────────────────────────────────────
class _DayEventTile extends StatelessWidget {
  final FirestoreEvent event;
  final VoidCallback onTap;
  const _DayEventTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _catColor(event.category);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_outlined,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.startTime.isNotEmpty ? event.startTime : 'TBA',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      event.category,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  UPCOMING EVENTS SECTION
// ─────────────────────────────────────────────────────────────
class _UpcomingSection extends StatelessWidget {
  final List<FirestoreEvent> events;
  final void Function(FirestoreEvent) onTap;

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
                color: _kPrimaryBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 26,
                color: _kPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No events this month',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check back later or browse another month above.',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
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
        Text(
          'Upcoming Events',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...upcoming.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DayEventTile(event: e, onTap: () => onTap(e)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CAL EVENT MODEL
// ─────────────────────────────────────────────────────────────
