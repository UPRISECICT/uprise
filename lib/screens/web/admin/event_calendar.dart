import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import 'package:intl/intl.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'export_excel.dart';
import '../../../theme/admin_theme.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../widgets/app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Category Colors - matching the submission form categories
// ─────────────────────────────────────────────────────────────────────────────
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

// ─── Category chip colors (matching org version) ────────────────
// Pastel bg / solid fg pair per category, derived from the same canonical
// hue each category uses in `_categoryColors` above (Tailwind -100/-700 of
// that hue) — kept in sync with org_events_schedule.dart's CategoryColors
// value-for-value. Previously this only covered 6 of the 11 categories and
// gave Sports and Workshop the exact same foreground color, making them
// indistinguishable on the calendar.
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
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusLg = 16;
  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AdminColors.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

// Glass-style outlined chip for dialog headers — used instead of solid
// filled pills, which read as a generic dashboard-template look.
Widget _outlinedChip(String label, {bool dim = false, Color? accent}) {
  if (accent != null) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: Colors.white.withAlpha(dim ? 90 : 150)),
    ),
    child: Text(
      label,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white.withAlpha(dim ? 200 : 255),
        letterSpacing: 0.6,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Event model
// ─────────────────────────────────────────────────────────────────────────────
class _Event {
  final String id,
      title,
      time,
      category,
      organization,
      orgId,
      createdFromProposalId;
  final String location, description, guestSpeaker, audience, status;
  final String schoolYear, semester;
  final List<String> tags;
  final DateTime date;

  _Event({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.category,
    required this.organization,
    this.orgId = '',
    this.createdFromProposalId = '',
    this.location = '',
    this.description = '',
    this.guestSpeaker = '',
    this.audience = '',
    this.status = 'approved',
    this.schoolYear = '',
    this.semester = '',
    this.tags = const [],
  });
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
      return AdminColors.primaryDark;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class EventCalendar extends StatefulWidget {
  const EventCalendar({super.key});

  @override
  _EventCalendarState createState() => _EventCalendarState();
}

class _EventCalendarState extends State<EventCalendar> {
  DateTime _currentMonth = DateTime.now();

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Jump to month',
      builder: (context, child) {
        final baseTheme = Theme.of(context);
        // Material3's default seed color skews purple/indigo, which is why
        // just overriding primary/secondary still left the calendar panel
        // and header looking lavender-tinted — seeding the whole scheme
        // from the brand color instead gives every derived surface tone a
        // warm, on-brand cast rather than patching a couple of properties.
        final scheme =
            ColorScheme.fromSeed(
              seedColor: AdminColors.primaryDark,
              brightness: Brightness.light,
            ).copyWith(
              primary: AdminColors.primaryDark,
              onPrimary: Colors.white,
              secondary: AdminColors.accent,
              surface: Colors.white,
              onSurface: const Color(0xFF1A202C),
              surfaceTint: Colors.transparent,
            );
        return Theme(
          data: baseTheme.copyWith(
            colorScheme: scheme,
            dialogTheme: baseTheme.dialogTheme.copyWith(
              backgroundColor: Colors.white,
            ),
            textTheme: GoogleFonts.beVietnamProTextTheme(baseTheme.textTheme),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AdminColors.primaryDark,
                textStyle: GoogleFonts.beVietnamPro(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _currentMonth = DateTime(picked.year, picked.month));
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreAutoArchivedEvents();
    _autoFixDuplicatesOnLoad();
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

  Future<void> _autoFixDuplicatesOnLoad() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('events').get();
      final groups =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final doc in snap.docs) {
        final proposalId = (doc.data()['createdFromProposalId'] ?? '')
            .toString();
        if (proposalId.isEmpty) continue;
        groups.putIfAbsent(proposalId, () => []).add(doc);
      }
      final duplicateGroups = groups.entries
          .where((e) => e.value.length > 1)
          .toList();
      if (duplicateGroups.isEmpty) return;
      await _mergeDuplicates(duplicateGroups);
    } catch (_) {
      // Silent
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 720 ? 16.0 : (width < 1200 ? 22.0 : 28.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(horizontalPadding),
            const SizedBox(height: 16),
            _buildCalendarStream(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _eventMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar ──────────────────────────────────────────────────────
  Widget _buildToolbar(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canUseRow = constraints.maxWidth > 800;

          final todayButton = InkWell(
            onTap: () => setState(() => _currentMonth = DateTime.now()),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AdminColors.primaryDark,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AdminColors.primaryDark.withAlpha(70),
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

          final dateControl = Container(
            height: 40,
            constraints: const BoxConstraints(minWidth: 200),
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
                  onTap: () => setState(() {
                    _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month - 1,
                    );
                  }),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _pickMonth(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(_currentMonth),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A202C),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18,
                          color: Color(0xFF9AA5B4),
                        ),
                      ],
                    ),
                  ),
                ),
                _NavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => setState(() {
                    _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month + 1,
                    );
                  }),
                ),
              ],
            ),
          );

          if (canUseRow) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                todayButton,
                const SizedBox(width: 10),
                dateControl,
                const Spacer(),
                _ExportEventsButton(),
              ],
            );
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [todayButton, dateControl, _ExportEventsButton()],
          );
        },
      ),
    );
  }

  // ── Duplicate cleanup ─────────────────────────────────────────────
  Future<void> _mergeDuplicates(
    List<MapEntry<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>>
    duplicateGroups,
  ) async {
    int deleted = 0;
    final firestore = FirebaseFirestore.instance;
    for (final entry in duplicateGroups) {
      final proposalId = entry.key;
      final docs = entry.value;

      String? keepId;
      try {
        final propSnap = await firestore
            .collection('event_proposals')
            .doc(proposalId)
            .get();
        final publishedEventId = (propSnap.data()?['publishedEventId'] ?? '')
            .toString();
        if (docs.any((d) => d.id == publishedEventId))
          keepId = publishedEventId;
      } catch (_) {}

      if (keepId == null) {
        final sorted =
            List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
              ..sort((a, b) {
                final ta = a.data()['createdAt'];
                final tb = b.data()['createdAt'];
                if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
                return 0;
              });
        keepId = sorted.first.id;
      }

      final batch = firestore.batch();
      for (final doc in docs) {
        if (doc.id == keepId) continue;
        batch.delete(doc.reference);
        deleted++;
      }
      batch.update(firestore.collection('event_proposals').doc(proposalId), {
        'publishedEventId': keepId,
      });
      await batch.commit();
    }

    await activity_log.ActivityLogger.log(
      action: 'Merged duplicate events',
      module: 'Event Management',
      severity: 'warning',
      details: {'groups': duplicateGroups.length, 'deleted': deleted},
    );

    if (mounted) {
      AppToast.success(
        context,
        'Cleaned up $deleted duplicate event${deleted == 1 ? '' : 's'}.',
      );
    }
  }

  // ── Calendar stream ──────────────────────────────────────────────
  Widget _buildCalendarStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('status', isEqualTo: 'approved')
          .orderBy('date')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final approvedEvents = snapshot.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return _Event(
            id: doc.id,
            title: d['title'] ?? 'Untitled',
            date: (d['date'] as Timestamp).toDate(),
            time: d['startTime'] ?? d['time'] ?? 'TBD',
            category: d['category'] ?? 'Other',
            organization: d['orgName'] ?? 'Unknown',
            orgId: (d['orgId'] ?? '').toString(),
            createdFromProposalId: (d['createdFromProposalId'] ?? '')
                .toString(),
            location: d['location'] ?? '',
            description: d['description'] ?? '',
            guestSpeaker: d['guestSpeaker'] ?? '',
            audience: (d['audience'] ?? '').toString(),
            status: (d['status'] ?? 'approved').toString(),
            schoolYear: (d['schoolYear'] ?? '').toString(),
            semester: (d['semester'] ?? '').toString(),
            tags: List<String>.from(d['tags'] ?? []),
          );
        }).toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('event_proposals')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, pendingSnap) {
            final pendingEvents = (pendingSnap.data?.docs ?? []).map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return _Event(
                id: doc.id,
                title: d['title'] ?? 'Untitled',
                date: (d['date'] as Timestamp).toDate(),
                time: d['startTime'] ?? d['time'] ?? 'TBD',
                category: d['category'] ?? 'Other',
                organization: d['orgName'] ?? 'Unknown',
                orgId: (d['orgId'] ?? '').toString(),
                location: d['location'] ?? '',
                description: d['description'] ?? '',
                guestSpeaker: d['guestSpeaker'] ?? '',
                audience: (d['audience'] ?? '').toString(),
                status: 'pending',
                schoolYear: (d['schoolYear'] ?? '').toString(),
                semester: (d['semester'] ?? '').toString(),
                tags: List<String>.from(d['tags'] ?? []),
              );
            }).toList();
            final events = [...approvedEvents, ...pendingEvents];
            return _buildCalendarGrid(events);
          },
        );
      },
    );
  }

  // ── Calendar grid ─────────────────────────────────────────────────
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

  Widget _buildCalendarGrid(List<_Event> events) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final totalRows = _totalRows;

    final Map<int, List<_Event>> byDay = {};
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
                bottom: BorderSide(color: AdminColors.primaryLight),
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
              mainAxisExtent: 140,
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

  Widget _buildDayCell(int day, List<_Event> events, int totalRows) {
    final isToday =
        day == DateTime.now().day &&
        _currentMonth.year == DateTime.now().year &&
        _currentMonth.month == DateTime.now().month;

    final sorted = List<_Event>.from(events)
      ..sort((a, b) => a.time.compareTo(b.time));
    final display = sorted.take(2).toList(); // show only 2 events + "more"
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
      onTap: events.isEmpty ? null : () => _showDayEventsSheet(day, sorted),
      hoverColor: AdminColors.primaryDark.withAlpha(8),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? AdminColors.primaryDark.withAlpha(10) : null,
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
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Day number ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: AdminColors.primaryDark,
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.primaryDark.withAlpha(60),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${events.length}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // ── Event chips ──────────────────────────────────────────
            ...display.map((e) {
              final isPending = e.status.toLowerCase() == 'pending';
              final chipColor = isPending
                  ? _statusColor(e.status)
                  : _getCategoryColor(e.category);
              // Pending chips stay status-colored (alpha-tinted); category
              // chips use the same pastel bg / solid fg pair as the org
              // calendar's chips, instead of an alpha-tint of the raw hue.
              final chipBg = isPending
                  ? chipColor.withAlpha(20)
                  : CategoryColors.getBg(e.category);
              final chipFg = isPending
                  ? chipColor
                  : CategoryColors.getFg(e.category);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(4),
                    border: isPending
                        ? Border.all(color: chipColor.withAlpha(140), width: 1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      if (isPending)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 9,
                            color: chipFg,
                          ),
                        )
                      else
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: chipFg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          e.title,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: chipFg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (extra > 0)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '+$extra more',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF9AA5B4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Day events dialog ──────────────────────────────────────────
  Future<void> _showDayEventsSheet(int day, List<_Event> events) async {
    final dateLabel = DateFormat(
      'EEEE, MMMM d, yyyy',
    ).format(DateTime(_currentMonth.year, _currentMonth.month, day));

    final resolvedTimes = <String, String>{};
    await Future.wait(
      events.map((e) async {
        if (e.createdFromProposalId.isEmpty) {
          resolvedTimes[e.id] = e.time;
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
              : e.time;
        } catch (_) {
          resolvedTimes[e.id] = e.time;
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
          decoration: const BoxDecoration(
            color: Color(0xFFFFFAF5),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AdminColors.primaryDark,
                      AdminColors.primaryDark.withAlpha(225),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withAlpha(70)),
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
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
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
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
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

  // ─── EVENT DETAIL DIALOG ─────────────────────────────────────────
  Future<void> _showEventDetailDialog(_Event event) async {
    // Fetch latest data from proposal (if available)
    var time = event.time;
    var guestSpeaker = event.guestSpeaker;

    if (event.createdFromProposalId.isNotEmpty) {
      try {
        final propDoc = await FirebaseFirestore.instance
            .collection('event_proposals')
            .doc(event.createdFromProposalId)
            .get();
        if (propDoc.exists) {
          final pd = propDoc.data()!;
          final start = (pd['startTime'] ?? '').toString();
          final end = (pd['endTime'] ?? '').toString();
          time = start.isNotEmpty
              ? (end.isNotEmpty ? '$start - $end' : start)
              : '';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 620,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── HEADER ──────────────────────────────────────────────
              // A restrained, flat brand header keeps the modal aligned with
              // the UPRISE admin portal instead of competing with the data.
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(26, 22, 18, 20),
                  decoration: const BoxDecoration(
                    color: AdminColors.primaryDark,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(55)),
                        ),
                        child: const Icon(
                          Icons.event_rounded,
                          color: Colors.white,
                          size: 21,
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
                                _outlinedChip(event.category.toUpperCase()),
                                if (event.organization.isNotEmpty &&
                                    event.organization != 'Unknown')
                                  _outlinedChip(event.organization, dim: true),
                                if (event.status.toLowerCase() != 'approved')
                                  _outlinedChip(
                                    event.status.toUpperCase(),
                                    accent: _statusColor(event.status),
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
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
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
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children:
                              [
                                    _detailCard(
                                      'Date',
                                      DateFormat(
                                        'MMM d, yyyy',
                                      ).format(event.date),
                                      Icons.calendar_today_rounded,
                                    ),
                                    _detailCard(
                                      'Time',
                                      time.isNotEmpty && time != 'TBD'
                                          ? time
                                          : 'TBD',
                                      Icons.access_time_rounded,
                                    ),
                                    _detailCard(
                                      'Location',
                                      event.location.isNotEmpty
                                          ? event.location
                                          : 'TBD',
                                      Icons.location_on_outlined,
                                    ),
                                    _detailCard(
                                      'Audience',
                                      event.audience.isNotEmpty
                                          ? event.audience
                                          : 'Public',
                                      Icons.group_outlined,
                                    ),
                                    if (event.schoolYear.isNotEmpty)
                                      _detailCard(
                                        'School Year',
                                        event.schoolYear,
                                        Icons.school_outlined,
                                      ),
                                    if (event.semester.isNotEmpty)
                                      _detailCard(
                                        'Semester',
                                        event.semester,
                                        Icons.date_range_outlined,
                                      ),
                                  ]
                                  .map(
                                    (card) => SizedBox(
                                      width: constraints.maxWidth < 480
                                          ? constraints.maxWidth
                                          : (constraints.maxWidth - 12) / 2,
                                      child: card,
                                    ),
                                  )
                                  .toList(),
                        ),
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
                            border: Border.all(color: const Color(0xFFE8ECF0)),
                          ),
                          child: Text(
                            event.description,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
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

  // ─── NEW DETAIL CARD helper (used in the dialog) ──────────────────
  Widget _detailCard(String label, String value, IconData icon) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AdminColors.primaryDark,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: Colors.white),
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

  // ─── Existing helper for detail rows (kept for other uses) ───────
  Widget _detailItem(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AdminColors.primaryDark.withAlpha(150)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: valueColor ?? const Color(0xFF1A202C),
          ),
        ),
      ],
    );
  }

  String _formatTime(String time) {
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final suffix = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $suffix';
    } catch (_) {
      return time;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.chevron_left_rounded
          ? 'Previous Month'
          : 'Next Month',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 20, color: AdminColors.primaryDark),
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final _Event event;
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
    final rawTime = displayTime ?? event.time;
    final timeLabel = (rawTime.isEmpty || rawTime == 'TBD')
        ? 'TBD'
        : _fmtTime(rawTime);

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
                        event.organization,
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
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 11,
                      color: Color(0xFF9AA5B4),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      timeLabel,
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

  String _fmtTime(String time) {
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final suffix = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $suffix';
    } catch (_) {
      return time;
    }
  }
}

class _ExportEventsButton extends StatelessWidget {
  const _ExportEventsButton();

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) => _doExport(context, choice),
    );
  }

  Future<void> _doExport(BuildContext context, String format) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('events')
          .where('status', isEqualTo: 'approved')
          .orderBy('date')
          .get();
      var docs = snap.docs;

      if (docs.isEmpty) {
        AppToast.info(context, 'No data to export.');
        return;
      }

      final now = DateTime.now().toString().substring(0, 10);

      if (format == 'excel') {
        final rows = docs.map((doc) {
          final d = doc.data();
          final date = (d['date'] as Timestamp).toDate();
          return [
            (d['title'] ?? '').toString(),
            (d['orgName'] ?? '').toString(),
            (d['category'] ?? 'Other').toString(),
            DateFormat('yyyy-MM-dd').format(date),
            (d['time'] ?? '').toString(),
          ];
        }).toList();
        final bytes = AdminExportExcel.generateStyledTable(
          title: 'Event Calendar',
          headers: const ['Title', 'Organization', 'Category', 'Date', 'Time'],
          rows: rows,
        );
        final fileName = 'events_$now.xlsx';
        await AdminExportUtil.saveBytes(
          bytes,
          fileName,
          mimeType: xlsxMimeType,
        );
      } else if (format == 'pdf') {
        final rows = docs.map((doc) {
          final d = doc.data();
          final date = (d['date'] as Timestamp).toDate();
          return [
            d['title'] ?? '',
            d['orgName'] ?? '',
            d['category'] ?? 'Other',
            DateFormat('yyyy-MM-dd').format(date),
            d['time'] ?? '',
          ].map((value) => value.toString()).toList();
        }).toList();

        final pdfBytes = await AdminExportPdf.generateTablePdf(
          title: 'Event Calendar Report',
          headers: const ['Title', 'Organization', 'Category', 'Date', 'Time'],
          rows: rows,
        );

        await AdminExportUtil.saveBytes(
          pdfBytes,
          'events_$now.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        throw UnsupportedError('Unsupported export format: $format');
      }
    } catch (e) {
      AppToast.error(context, 'Export failed: $e');
    }
  }
}
