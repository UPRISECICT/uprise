// ignore_for_file: unused_element_parameter
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../admin/export_util.dart';
import '../admin/export_pdf.dart';
import '../../../theme/org_theme.dart';

// ==================== CATEGORY COLORS ====================
Map<String, Color> _categoryColors = {
  'Workshop': const Color(0xFF8B5CF6),
  'Seminar': const Color(0xFF3B82F6),
  'Competition': const Color(0xFFEF4444),
  'General Assembly': const Color(0xFFF97316),
  'Social': const Color(0xFFEC4899),
  'Outreach': const Color(0xFF10B981),
  'Sports': const Color(0xFF14B8A6),
  'Academic': const Color(0xFF6366F1),
  'Technical': const Color(0xFF06B6D4),
  'Cultural': const Color(0xFFD946EF),
  'Other': const Color(0xFF6B7280),
};

Color _getCategoryColor(String category) {
  return _categoryColors[category] ?? const Color(0xFF6B7280);
}

// ==================== DESIGN TOKENS ====================
class _DS {
  static const double radiusSm = 8;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class CategoryColors {
  // Pastel bg / solid fg pair per category, derived from the same canonical
  // hue each category uses in `_categoryColors` above (Tailwind -100/-700
  // of that hue) — kept in sync with admin/event_calendar.dart's
  // CategoryColors value-for-value. This used to only cover 6 of the 11
  // categories, with hues picked independently of `_categoryColors` (e.g.
  // Academic was green here but indigo everywhere else it's badged), so a
  // category didn't reliably read as the same color across the page.
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
  // Dot color is just the canonical single hue for the category, so the
  // small dot always matches whatever accent color the rest of the page
  // uses for that category.
  static Color getDot(String cat) => _getCategoryColor(cat);
}

// ==================== HELPER WIDGETS ====================
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: UpriseColors.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: UpriseColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

Widget _categoryChip(String category) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: CategoryColors.getBg(category),
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      category.toUpperCase(),
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: CategoryColors.getFg(category),
        letterSpacing: 0.8,
      ),
    ),
  );
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'approved':
      return const Color(0xFF059669);
    case 'pending':
      return const Color(0xFFFB923C);
    case 'rejected':
      return const Color(0xFFDC2626);
    case 'archived':
      return const Color(0xFF6B7280);
    default:
      return UpriseColors.primaryDark;
  }
}

// ==================== EVENT MODEL ====================
class EventModel {
  final String id;
  final String orgId;
  final String orgName;
  final String createdFromProposalId;
  final String title;
  final String description;
  final String location;
  final String startTime;
  final String endTime;
  final String category;
  final String guestSpeaker;
  final String audience;
  final List<String> resources;
  final List<String> labPreparation;
  final List<String> tags;
  final DateTime date;
  final String status;
  final String bannerUrl;

  EventModel({
    required this.id,
    required this.orgId,
    this.orgName = '',
    this.createdFromProposalId = '',
    required this.title,
    required this.description,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.category,
    required this.guestSpeaker,
    this.audience = '',
    required this.resources,
    required this.labPreparation,
    required this.tags,
    required this.date,
    required this.status,
    this.bannerUrl = '',
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    List<String> toList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return EventModel(
      id: doc.id,
      orgId: (d['orgId'] ?? '').toString(),
      orgName: (d['orgName'] ?? '').toString(),
      createdFromProposalId: (d['createdFromProposalId'] ?? '').toString(),
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      location: d['location'] ?? '',
      startTime: d['startTime'] ?? '',
      endTime: d['endTime'] ?? '',
      category: d['category'] ?? 'Other',
      guestSpeaker: d['guestSpeaker'] ?? '',
      audience: (d['audience'] ?? '').toString(),
      resources: toList(d['resources']),
      labPreparation: toList(d['labPreparation']),
      tags: toList(d['tags']),
      date: d['date'] is Timestamp
          ? (d['date'] as Timestamp).toDate()
          : DateTime.tryParse(d['date']?.toString() ?? '') ?? DateTime.now(),
      status: (d['status'] ?? 'pending').toString().toLowerCase(),
      bannerUrl: (d['bannerUrl'] ?? '').toString(),
    );
  }
}

// ==================== MAIN SCREEN ====================
class OrgEventsScheduleScreen extends StatefulWidget {
  final String orgId;
  const OrgEventsScheduleScreen({super.key, required this.orgId});

  @override
  State<OrgEventsScheduleScreen> createState() =>
      _OrgEventsScheduleScreenState();
}

class _OrgEventsScheduleScreenState extends State<OrgEventsScheduleScreen> {
  DateTime _currentMonth = DateTime.now();
  List<EventModel> _cachedEvents = [];

  bool _showOrgEventsOnly = true;

  late final Stream<QuerySnapshot> _orgEventsStream = FirebaseFirestore.instance
      .collection('events')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .snapshots();

  late final Stream<QuerySnapshot> _allEventsStream = FirebaseFirestore.instance
      .collection('events')
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  late final Stream<QuerySnapshot> _orgPendingStream = FirebaseFirestore
      .instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'pending')
      .snapshots();

  late final Stream<QuerySnapshot> _allPendingStream = FirebaseFirestore
      .instance
      .collection('event_proposals')
      .where('status', isEqualTo: 'pending')
      .snapshots();

  Stream<QuerySnapshot> get _activePendingStream =>
      _showOrgEventsOnly ? _orgPendingStream : _allPendingStream;

  Stream<QuerySnapshot> get _activeStream =>
      _showOrgEventsOnly ? _orgEventsStream : _allEventsStream;

  @override
  void initState() {
    super.initState();
    _restoreAutoArchivedEvents();
  }

  Future<void> _restoreAutoArchivedEvents() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('status', isEqualTo: 'archived')
          .get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'status': 'approved'});
      }
      await batch.commit();
    } catch (_) {
      // Silent
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;
    final horizontalPadding = isMobile ? 16.0 : (isTablet ? 22.0 : 28.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(isMobile, isTablet, horizontalPadding),
            const SizedBox(height: 16),
            _buildCalendarStream(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet, double horizontalPadding) {
    final fieldWidth = isMobile ? double.infinity : (isTablet ? 200.0 : 200.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canUseRow = constraints.maxWidth > 800;
          final dateControl = Container(
            height: 40,
            constraints: BoxConstraints(minWidth: fieldWidth),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E6EA)),
              boxShadow: _DS.cardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => setState(
                    () => _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month - 1,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    DateFormat('MMMM yyyy').format(_currentMonth),
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                ),
                _NavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => setState(
                    () => _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month + 1,
                    ),
                  ),
                ),
              ],
            ),
          );

          final todayButton = InkWell(
            onTap: () => setState(() => _currentMonth = DateTime.now()),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: UpriseColors.primaryDark,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: UpriseColors.primaryDark.withAlpha(70),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.today_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 7),
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
          );

          final toggleContainer = Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E6EA)),
              boxShadow: _DS.cardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTab(
                  label: 'Org Events',
                  active: _showOrgEventsOnly,
                  onTap: () => setState(() {
                    _showOrgEventsOnly = true;
                  }),
                ),
                _ToggleTab(
                  label: 'All Events',
                  active: !_showOrgEventsOnly,
                  onTap: () => setState(() {
                    _showOrgEventsOnly = false;
                  }),
                ),
              ],
            ),
          );

          final controls = [todayButton, dateControl, toggleContainer];

          if (canUseRow) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                todayButton,
                const SizedBox(width: 10),
                dateControl,
                const Spacer(),
                toggleContainer,
              ],
            );
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls,
          );
        },
      ),
    );
  }

  Widget _buildCalendarStream() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('cal_${_showOrgEventsOnly}_${widget.orgId}'),
      stream: _activeStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final approvedEvents = (snapshot.data?.docs ?? [])
            .map((doc) => EventModel.fromFirestore(doc))
            .toList();
        approvedEvents.sort((a, b) => a.date.compareTo(b.date));

        return StreamBuilder<QuerySnapshot>(
          key: ValueKey('pending_${_showOrgEventsOnly}_${widget.orgId}'),
          stream: _activePendingStream,
          builder: (context, pendingSnap) {
            final pendingEvents = (pendingSnap.data?.docs ?? [])
                .map((doc) => EventModel.fromFirestore(doc))
                .toList();
            final merged = [...approvedEvents, ...pendingEvents]
              ..sort((a, b) => a.date.compareTo(b.date));
            _cachedEvents = merged;
            return _buildCalendarGrid(merged);
          },
        );
      },
    );
  }

  int get _totalRows {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    return ((startWeekday + daysInMonth) / 7).ceil();
  }

  Widget _buildCalendarGrid(List<EventModel> events) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final totalRows = _totalRows;

    final Map<int, List<EventModel>> byDay = {};
    for (final e in events) {
      if (e.date.year == _currentMonth.year &&
          e.date.month == _currentMonth.month) {
        byDay.putIfAbsent(e.date.day, () => []).add(e);
      }
    }

    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    final horizontalPadding = MediaQuery.of(context).size.width < 720
        ? 16.0
        : 28.0;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: UpriseColors.primaryLight),
              ),
            ),
            child: Row(
              children: weekdays
                  .map(
                    (d) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 120,
            ),
            itemCount: totalRows * 7,
            itemBuilder: (_, index) {
              final dayNum = index - startWeekday + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return _buildEmptyCell(
                  isLastRow: index >= (totalRows - 1) * 7,
                  colIndex: index % 7,
                  isBottomRight: index == totalRows * 7 - 1,
                  isBottomLeft: index == (totalRows - 1) * 7,
                );
              }
              return _buildDayCell(dayNum, byDay[dayNum] ?? [], totalRows);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCell({
    bool isLastRow = false,
    int colIndex = 0,
    bool isBottomRight = false,
    bool isBottomLeft = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        border: Border(
          right: colIndex < 6
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
          bottom: !isLastRow
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
        ),
        borderRadius: isBottomLeft
            ? const BorderRadius.only(bottomLeft: Radius.circular(14))
            : isBottomRight
            ? const BorderRadius.only(bottomRight: Radius.circular(14))
            : null,
      ),
    );
  }

  Widget _buildDayCell(int day, List<EventModel> events, int totalRows) {
    final isToday =
        day == DateTime.now().day &&
        _currentMonth.year == DateTime.now().year &&
        _currentMonth.month == DateTime.now().month;

    final sorted = List<EventModel>.from(events)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final display = sorted.take(3).toList();
    final extra = sorted.length - display.length;

    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startWeekday = firstDay.weekday % 7;
    final cellIndex = startWeekday + day - 1;
    final colIndex = cellIndex % 7;
    final isLastRow = cellIndex >= (totalRows - 1) * 7;
    final isBottomLeft = isLastRow && colIndex == 0;
    final isBottomRight =
        cellIndex == totalRows * 7 - 1 ||
        (isLastRow &&
            day ==
                DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day);

    return InkWell(
      onTap: () => _showDayEventsSheet(day, sorted),
      hoverColor: UpriseColors.primaryDark.withAlpha(8),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? UpriseColors.primaryDark.withAlpha(10) : null,
          border: Border(
            right: colIndex < 6
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
            bottom: !isLastRow
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
          ),
          borderRadius: isBottomLeft
              ? const BorderRadius.only(bottomLeft: Radius.circular(14))
              : isBottomRight
              ? const BorderRadius.only(bottomRight: Radius.circular(14))
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: UpriseColors.primaryDark,
                          boxShadow: [
                            BoxShadow(
                              color: UpriseColors.primaryDark.withAlpha(70),
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
                      color: isToday ? Colors.white : const Color(0xFF1A202C),
                    ),
                  ),
                ),
                if (events.length > 1)
                  Text(
                    '${events.length}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            ...display.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(e.category).withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(e.category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.title,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _getCategoryColor(e.category),
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
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '+$extra more',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10,
                    color: const Color(0xFF9AA5B4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Day events dialog ──────────────────────────────────────────
  Future<void> _showDayEventsSheet(int day, List<EventModel> events) async {
    final dateLabel = DateFormat(
      'EEEE, MMMM d, yyyy',
    ).format(DateTime(_currentMonth.year, _currentMonth.month, day));

    final resolvedTimes = <String, String>{};
    await Future.wait(
      events.map((e) async {
        if (e.createdFromProposalId.isEmpty) {
          resolvedTimes[e.id] = e.startTime;
          return;
        }
        try {
          final propDoc = await FirebaseFirestore.instance
              .collection('event_proposals')
              .doc(e.createdFromProposalId)
              .get();
          final pd = propDoc.data();
          resolvedTimes[e.id] = pd != null
              ? (pd['startTime'] ?? '').toString()
              : e.startTime;
        } catch (_) {
          resolvedTimes[e.id] = e.startTime;
        }
      }),
    );

    if (!mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 460,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
                  decoration: const BoxDecoration(
                    color: UpriseColors.primaryDark,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(20),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(38),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.event_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateLabel,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${events.length} event${events.length == 1 ? '' : 's'}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    color: Colors.white.withAlpha(204),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.event_busy_rounded,
                                  size: 26,
                                  color: Color(0xFF9AA5B4),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No events this day',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(20),
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _EventListTile(
                          event: events[i],
                          displayTime: resolvedTimes[events[i].id],
                          onTap: () {
                            Navigator.pop(ctx);
                            _showEventDetailDialog(events[i]);
                          },
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                  color: Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF374151),
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

  // ─── NEW PROFESSIONAL EVENT DETAIL DIALOG ──────────────────────
  Future<void> _showEventDetailDialog(EventModel event) async {
    // Fetch latest data from proposal (if available)
    var startTime = event.startTime;
    var endTime = event.endTime;
    var guestSpeaker = event.guestSpeaker;

    if (event.createdFromProposalId.isNotEmpty) {
      try {
        final propDoc = await FirebaseFirestore.instance
            .collection('event_proposals')
            .doc(event.createdFromProposalId)
            .get();
        if (propDoc.exists) {
          final pd = propDoc.data()!;
          startTime = (pd['startTime'] ?? '').toString();
          endTime = (pd['endTime'] ?? '').toString();
          guestSpeaker = (pd['guestSpeaker'] ?? '').toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final catColor = _getCategoryColor(event.category);

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 620,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── HEADER ──────────────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(26, 24, 18, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        UpriseColors.primaryDark,
                        catColor.withAlpha(230),
                      ],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        right: -30,
                        top: -40,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(18),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 40,
                        bottom: -50,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(14),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(35),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withAlpha(90),
                              ),
                            ),
                            child: const Icon(
                              Icons.event_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _categoryChip(event.category),
                                    if (event.orgName.isNotEmpty &&
                                        event.orgName != 'Unknown')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withAlpha(150),
                                          ),
                                        ),
                                        child: Text(
                                          event.orgName.toUpperCase(),
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withAlpha(255),
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                    if (event.status.toLowerCase() !=
                                        'approved')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(event.status),
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                        ),
                                        child: Text(
                                          event.status.toUpperCase(),
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  event.title,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ─── BODY ────────────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Key details as tidy cards ──────────────────
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _detailCard(
                            'Date',
                            DateFormat('MMM d, yyyy').format(event.date),
                            Icons.calendar_today_rounded,
                            accent: catColor,
                          ),
                          _detailCard(
                            'Time',
                            startTime.isNotEmpty
                                ? (endTime.isNotEmpty
                                      ? '$startTime - $endTime'
                                      : startTime)
                                : 'TBD',
                            Icons.access_time_rounded,
                            accent: catColor,
                          ),
                          _detailCard(
                            'Location',
                            event.location.isNotEmpty ? event.location : 'TBD',
                            Icons.location_on_outlined,
                            accent: catColor,
                          ),
                          _detailCard(
                            'Audience',
                            event.audience.isNotEmpty
                                ? event.audience
                                : 'Public',
                            Icons.group_outlined,
                            accent: catColor,
                          ),
                          if (event.orgName.isNotEmpty)
                            _detailCard(
                              'Organization',
                              event.orgName,
                              Icons.business_center,
                              accent: catColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // ── Description ──────────────────────────────────
                      if (event.description.isNotEmpty) ...[
                        _sectionLabel(
                          'Description',
                          icon: Icons.description_outlined,
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(color: catColor, width: 3),
                            ),
                          ),
                          child: Text(
                            event.description,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              color: const Color(0xFF374151),
                              height: 1.65,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],

                      // ── Guest Speaker ────────────────────────────────
                      if (guestSpeaker.isNotEmpty) ...[
                        _sectionLabel(
                          'Guest Speaker',
                          icon: Icons.person_outline_rounded,
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: catColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: catColor.withAlpha(45)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: catColor.withAlpha(30),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: catColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  guestSpeaker,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A202C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],

                      // ── Resources ────────────────────────────────────
                      if (event.resources.isNotEmpty) ...[
                        _sectionLabel('Resources', icon: Icons.folder_outlined),
                        _buildBulletList(event.resources),
                        const SizedBox(height: 22),
                      ],

                      // ── Lab Preparation ──────────────────────────────
                      if (event.labPreparation.isNotEmpty) ...[
                        _sectionLabel(
                          'Lab Preparation',
                          icon: Icons.build_circle_outlined,
                        ),
                        _buildBulletList(event.labPreparation),
                        const SizedBox(height: 22),
                      ],

                      // ── Tags ─────────────────────────────────────────
                      if (event.tags.isNotEmpty) ...[
                        _sectionLabel('Tags', icon: Icons.local_offer_outlined),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: event.tags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withAlpha(15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: catColor.withAlpha(60),
                                ),
                              ),
                              child: Text(
                                tag,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: catColor,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),

              // ─── FOOTER ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
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

  // ─── DETAIL CARD helper (used in the dialog) ─────────────────────
  Widget _detailCard(
    String label,
    String value,
    IconData icon, {
    Color? accent,
  }) {
    final c = accent ?? UpriseColors.primaryDark;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withAlpha(35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.withAlpha(35),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A202C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── BULLET LIST helper ──────────────────────────────────────────
  Widget _buildBulletList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.circle, size: 5, color: Color(0xFF9AA5B4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  // ─── Export (kept but unused; you can remove if not needed) ──────
  Future<void> _exportEvents(String format) async {
    if (_cachedEvents.isEmpty) return;
    String csvEscape(String value) => '"${value.replaceAll('"', '""')}"';
    final rows = _cachedEvents
        .map(
          (event) => [
            event.title,
            event.category,
            event.status.toUpperCase(),
            DateFormat('yyyy-MM-dd').format(event.date),
            '${event.startTime} - ${event.endTime}',
            event.location,
          ],
        )
        .toList();
    final headers = ['Title', 'Category', 'Status', 'Date', 'Time', 'Location'];

    if (format == 'csv') {
      final csv = StringBuffer();
      csv.writeln(headers.map(csvEscape).join(','));
      for (final row in rows) {
        csv.writeln(row.map(csvEscape).join(','));
      }
      await AdminExportUtil.saveText(
        csv.toString(),
        '${_showOrgEventsOnly ? 'org' : 'cict'}_events_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
        mimeType: 'text/csv',
      );
      return;
    }

    final bytes = await AdminExportPdf.generateTablePdf(
      title: _showOrgEventsOnly ? 'Organization Events' : 'CICT Events',
      headers: headers,
      rows: rows,
      subtitle: _showOrgEventsOnly
          ? 'Organization event schedule export'
          : 'CICT event schedule export',
    );
    await AdminExportUtil.saveBytes(
      bytes,
      '${_showOrgEventsOnly ? 'org' : 'cict'}_events_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
    );
  }
}

// ==================== REUSABLE WIDGETS ====================
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, size: 20, color: UpriseColors.primaryDark),
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? UpriseColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final EventModel event;
  final String? displayTime;
  final VoidCallback onTap;
  const _EventListTile({
    required this.event,
    this.displayTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(event.category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: categoryColor.withAlpha(15),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: categoryColor.withAlpha(13),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: categoryColor.withAlpha(51)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: categoryColor,
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
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.category,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: categoryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        event.location,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _categoryChip(event.category),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 11,
                      color: Color(0xFF9AA5B4),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      displayTime ?? event.startTime,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}
