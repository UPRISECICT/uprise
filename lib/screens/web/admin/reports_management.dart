import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:universal_html/html.dart' as html;
import 'package:uprise/screens/web/admin/export_pdf.dart' show AdminExportPdf;
import 'export_util.dart';
import 'export_excel.dart';
import 'package:uprise/widgets/admin_export_button.dart';
import '../../../widgets/student/event_image.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/activity_logger.dart' as activity_log;
import 'dart:convert'; // for base64Decode, utf8
import '../../../utils/platform_file_utils.dart'
    as platform_file_utils; // adjust path if needed
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/stat_cards.dart';
import '../../../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusPill = 100;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Colors
// ─────────────────────────────────────────────────────────────────────────────
class UpriseColors {
  // Kept in sync with the shared brand color in theme/app_theme.dart —
  // this file can't just import that class because primaryLight/success/
  // warning/error here are tuned for this page's badge & tab-indicator
  // tints and mean something different than the shared class's fields
  // of the same name.
  // CICT professional scheme: gray is the primary brand color here too,
  // deepened to slate-800 to match the rest of the admin section.
  static const Color primaryDark = Color(0xFF1E293B);
  static const Color primaryLight = Color(0xFFF1F5F9);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF7F8FA);
  static const Color mediumGray = Color(0xFFE2E6EA);
  static const Color darkGray = Color(0xFF6B7280);
  static const Color charcoal = Color(0xFF1F2937);
  static const Color success = Color(0xFF059669);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color warning = Color(0xFFFB923C);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFEFF6FF);
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Report Model
// ─────────────────────────────────────────────────────────────────────────────
class AdminReport {
  final String id;
  final String orgId;
  final String orgName;
  final String orgAbbrev;
  final String eventTitle;
  final String type;
  final String description;
  final DateTime submittedAt;
  final String? fileBase64;
  final String? fileName;
  final String? fileSize;
  final bool archived;

  AdminReport({
    required this.id,
    required this.orgId,
    required this.orgName,
    this.orgAbbrev = '',
    required this.eventTitle,
    required this.type,
    required this.description,
    required this.submittedAt,
    this.fileBase64,
    this.fileName,
    this.fileSize,
    this.archived = false,
  });

  factory AdminReport.fromFirestore(
    DocumentSnapshot doc,
    Map<String, String> orgMap, [
    Map<String, String> orgAbbrevMap = const {},
  ]) {
    final data = doc.data() as Map<String, dynamic>;
    final orgId = data['orgId']?.toString() ?? '';
    return AdminReport(
      id: doc.id,
      orgId: orgId,
      orgName: orgMap[orgId] ?? 'Unknown',
      orgAbbrev: orgAbbrevMap[orgId] ?? '',
      eventTitle: data['title']?.toString() ?? 'Untitled',
      type: data['type']?.toString() ?? 'financial',
      description: data['description']?.toString() ?? '',
      submittedAt:
          (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fileBase64: data['fileBase64'] as String?,
      fileName: data['fileName'] as String?,
      fileSize: data['fileSize'] as String?,
      archived: data['archived'] as bool? ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
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

Widget _statusBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'submitted': _BadgeStyle(
      UpriseColors.successBg,
      UpriseColors.success,
      'SUBMITTED',
    ),
    'on time': _BadgeStyle(
      UpriseColors.successBg,
      UpriseColors.success,
      'ON TIME',
    ),
    'late': _BadgeStyle(UpriseColors.warningBg, UpriseColors.warning, 'LATE'),
    'pending': _BadgeStyle(
      UpriseColors.warningBg,
      UpriseColors.warning,
      'PENDING',
    ),
    'overdue': _BadgeStyle(UpriseColors.errorBg, UpriseColors.error, 'OVERDUE'),
    'approved': _BadgeStyle(
      UpriseColors.successBg,
      UpriseColors.success,
      'APPROVED',
    ),
    'no events': _BadgeStyle(
      const Color(0xFFF3F4F6),
      const Color(0xFF6B7280),
      'NO EVENTS',
    ),
  };
  final s =
      styles[status.toLowerCase()] ??
      _BadgeStyle(
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        status.toUpperCase(),
      );
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: BoxDecoration(
      color: s.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      s.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: s.fg,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Models for Events
// ─────────────────────────────────────────────────────────────────────────────
class EventReport {
  final String id, title, orgId, orgName, type, status;
  final String orgAbbrev;
  final DateTime date;
  final String description;
  final String location;
  final String eventImageUrl;
  final double totalIncome, totalExpenses;
  final int registrants, attendees;
  final String submittedBy, reportPeriod;
  final DateTime? submittedDate;
  // Written onto every event doc by org_event_proposals.dart when a
  // proposal is approved, but never read here until now — the detail view
  // showed four fields while these sat unused in a document it was already
  // fetching in full.
  final String startTime, endTime;
  final int? capacity;
  final String audience, schoolYear, semester;
  final bool issuesCertificate;
  final List<Map<String, dynamic>> incomeBreakdown,
      expenseBreakdown,
      attachments;
  final List<String> financialNotes, recommendations;

  EventReport({
    required this.id,
    required this.title,
    required this.orgId,
    required this.orgName,
    this.orgAbbrev = '',
    required this.type,
    required this.date,
    required this.status,
    this.totalIncome = 0,
    this.totalExpenses = 0,
    this.registrants = 0,
    this.attendees = 0,
    this.submittedBy = '',
    this.reportPeriod = '',
    this.submittedDate,
    this.description = '',
    this.location = '',
    this.eventImageUrl = '',
    this.startTime = '',
    this.endTime = '',
    this.capacity,
    this.audience = '',
    this.schoolYear = '',
    this.semester = '',
    this.issuesCertificate = false,
    this.incomeBreakdown = const [],
    this.expenseBreakdown = const [],
    this.attachments = const [],
    this.financialNotes = const [],
    this.recommendations = const [],
  });

  double get netAmount => totalIncome - totalExpenses;

  int get attendanceRatio =>
      registrants > 0 ? ((attendees / registrants) * 100).round() : 0;

  factory EventReport.fromFirestore(
    DocumentSnapshot doc,
    String orgName,
    int registrants,
    int attendees, [
    String orgAbbrev = '',
  ]) {
    final d = doc.data() as Map<String, dynamic>;
    return EventReport(
      id: doc.id,
      title: d['title']?.toString() ?? 'Untitled',
      orgId: d['orgId']?.toString() ?? '',
      orgName: orgName,
      orgAbbrev: orgAbbrev,
      type: (d['category'] as String? ?? d['type'] as String? ?? 'Others')
          .toString(),
      date: (d['date'] as Timestamp).toDate(),
      status: d['status']?.toString() ?? 'approved',
      description: d['description']?.toString() ?? '',
      location: d['location']?.toString() ?? '',
      eventImageUrl:
          (d['bannerUrl'] as String?)?.toString() ??
          (d['imageUrl'] as String?)?.toString() ??
          '',
      startTime: d['startTime']?.toString() ?? '',
      endTime: d['endTime']?.toString() ?? '',
      capacity: (d['capacity'] as num?)?.toInt(),
      audience: d['audience']?.toString() ?? '',
      schoolYear: d['schoolYear']?.toString() ?? '',
      semester: d['semester']?.toString() ?? '',
      issuesCertificate: d['issuesCertificate'] == true,
      totalIncome: (d['totalIncome'] as num?)?.toDouble() ?? 0,
      totalExpenses: (d['totalExpenses'] as num?)?.toDouble() ?? 0,
      registrants: registrants,
      attendees: attendees,
      submittedBy:
          d['submittedBy']?.toString() ??
          d['submittedByEmail']?.toString() ??
          d['publishedBy']?.toString() ??
          '',
      submittedDate: (d['submittedDate'] as Timestamp?)?.toDate(),
      reportPeriod: d['reportPeriod']?.toString() ?? '',
      incomeBreakdown: List<Map<String, dynamic>>.from(
        d['incomeBreakdown'] ?? [],
      ),
      expenseBreakdown: List<Map<String, dynamic>>.from(
        d['expenseBreakdown'] ?? [],
      ),
      financialNotes: List<String>.from(d['financialNotes'] ?? []),
      recommendations: List<String>.from(d['recommendations'] ?? []),
      attachments: List<Map<String, dynamic>>.from(d['attachments'] ?? []),
    );
  }
}

class OrgSubmission {
  final String orgId, orgName;
  final String orgAbbrev;
  final DateTime? submittedAt;
  // The org side stores the uploaded file as base64 directly on the
  // Firestore doc (fileBase64/fileName) — no Firebase Storage, no URL.
  final String? fileBase64, fileName, submissionId;
  final String? eventId, eventTitle;
  final DateTime? eventDate;
  // Admin override for this specific org's deadline, if they ever edited it.
  // Falls back to the automatic 7-day rule when null.
  final DateTime? deadlineOverride;
  // 'event' (default) | 'semester' | 'year' — a submission can instead
  // cover a whole semester/school year with no single event behind it.
  final String scope;
  final String? schoolYear, semester;

  OrgSubmission({
    required this.orgId,
    required this.orgName,
    this.orgAbbrev = '',
    this.submittedAt,
    this.fileBase64,
    this.fileName,
    this.submissionId,
    this.eventId,
    this.eventTitle,
    this.eventDate,
    this.deadlineOverride,
    this.scope = 'event',
    this.schoolYear,
    this.semester,
  });

  bool get isPeriodScope => scope == 'semester' || scope == 'year';

  // What to show as the "event" column for this row — an actual event
  // title for event-scoped submissions, or a school year/semester label
  // for period-scoped ones.
  String get displayTitle {
    if (!isPeriodScope) return eventTitle ?? '—';
    return scope == 'semester'
        ? '${schoolYear ?? '—'} — ${semester ?? '—'}'
        : '${schoolYear ?? '—'} (Whole Year)';
  }

  // Previously required eventDate too, which excluded submissions whose
  // source event was deleted after the report was uploaded (eventDate is
  // only ever populated by joining against the live `events` collection —
  // an orphaned submission has no event to join against, but the title
  // baked into the report doc itself is still real, submitted evidence).
  bool get hasApprovedEvent => isPeriodScope || eventTitle != null;

  // Submission deadline rule: automatically 1 week AFTER the event date,
  // unless an admin has set a per-org override for this report type.
  DateTime? get eventDeadline =>
      deadlineOverride ?? eventDate?.add(const Duration(days: 7));

  bool get isLate =>
      submittedAt != null &&
      eventDeadline != null &&
      submittedAt!.isAfter(eventDeadline!);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class ReportsManagement extends StatefulWidget {
  const ReportsManagement({super.key});
  @override
  State<ReportsManagement> createState() => _ReportsManagementState();
}

class _ReportsManagementState extends State<ReportsManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _getOrgLogo(String orgId) {
    // Find the organization with this ID
    final org = _organizations.firstWhere(
      (o) => o['id'] == orgId,
      orElse: () => <String, dynamic>{},
    );
    // Return its logo URL (or null if not found)
    return org['logoUrl'] as String?;
  }

  final TextEditingController _eventSearchController = TextEditingController();
  final TextEditingController _reportSearchController = TextEditingController();
  final TextEditingController _submissionSearchController =
      TextEditingController();

  // Event Summary tab's own filters.
  String _filterOrg = 'All Organizations';
  String _filterType = 'All Types';
  String _filterRange = 'All Time';
  String _filterAcademicYear = 'All Years';
  String _filterSemester = 'All Semesters';
  // 'Active' | 'Archived' — previously a dead field with no UI (always
  // 'All', so the events query never actually filtered by status and
  // archived events would silently reappear on next load). Now drives a
  // real toggle, same as every other admin page's Active/Archived filter.
  String _filterStatus = 'Active';

  // Financial/Accomplishment Reports and Submission Tracker each used to
  // read the SAME _filterOrg/_filterAcademicYear/_filterSemester fields
  // above as Event Summary — since all 4 tabs stay mounted at once inside
  // the TabBarView, changing the org filter in any one tab silently
  // changed what the other three showed too. Each tab now gets its own.
  String _filterOrgSubmissions = 'All Organizations';

  String _filterOrgFinancial = 'All Organizations';
  String _filterAcademicYearFinancial = 'All Years';
  String _filterSemesterFinancial = 'All Semesters';
  String _filterStatusFinancial = 'Active';

  String _filterOrgAccomplishment = 'All Organizations';
  String _filterAcademicYearAccomplishment = 'All Years';
  String _filterSemesterAccomplishment = 'All Semesters';
  String _filterStatusAccomplishment = 'Active';

  String _submissionStatusFilter = 'All';
  // Which of the two submission types the tracker card is currently
  // showing — split into a toggle instead of stacking both full tables at
  // once, which was the "dizzying wall of tables" the redesign fixed.
  String _submissionTypeView = 'Financial';
  final String _reportView = 'By Event';

  static const List<String> _academicYears = [
    'All Years',
    '2025-2026',
    '2024-2025',
    '2023-2024',
  ];
  static const List<String> _semesters = [
    'All Semesters',
    '1st Semester',
    '2nd Semester',
    'Summer',
  ];
  static const List<String> _activeArchivedOptions = ['Active', 'Archived'];

  List<EventReport> _events = [];
  List<Map<String, dynamic>> _organizations = [];
  bool _loadingEvents = true;
  bool _loadingEventCounts = false;

  // Admin reports for financial and accomplishment
  List<AdminReport> _financialReports = [];
  List<AdminReport> _accomplishmentReports = [];
  bool _loadingFinancial = true;
  bool _loadingAccomplishment = true;

  // Keep these for submission tracker tab
  List<OrgSubmission> _financialSubs = [];
  List<OrgSubmission> _accomplishmentSubs = [];
  bool _loadingFinancialSubs = true;
  bool _loadingAccomplishmentSubs = true;

  EventReport? _detailEvent;
  int _currentPage = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(
      () => setState(() {
        _detailEvent = null;
        _currentPage = 1;
      }),
    );
    // Pre-warms the PDF font/logo fetch (network font + letterhead images)
    // so it's already cached by the time an admin clicks Export — otherwise
    // that cost is paid on the first click and the button appears to
    // freeze. Same pattern as student_accounts.dart/adviser_roles.dart.
    AdminExportPdf.warmUp();
    _loadOrganizations();
    _loadSubmissionData();
    _loadFinancialReports();
    _loadAccomplishmentReports();
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSearchController.dispose();
    _reportSearchController.dispose();
    _submissionSearchController.dispose();
    super.dispose();
  }

  // ── Date range helper ─────────────────────────────────────────────

  (DateTime?, DateTime?) _computeDateRange() =>
      _computeDateRangeFor(_filterAcademicYear, _filterSemester, _filterRange);

  // Parameterized so Event Summary, Financial Reports, and Accomplishment
  // Reports can each pass their own independent academic year/semester
  // filter values instead of all reading the same shared fields.
  (DateTime?, DateTime?) _computeDateRangeFor(
    String academicYear,
    String semester,
    String range,
  ) {
    final now = DateTime.now();
    int startYear;
    int endYear;

    if (academicYear == 'All Years') {
      if (semester == 'All Semesters' && range == 'All Time') {
        return (null, null);
      }
    }

    if (academicYear != 'All Years') {
      final parts = academicYear.split('-');
      startYear = int.tryParse(parts[0]) ?? now.year;
      endYear = int.tryParse(parts[1]) ?? now.year + 1;
    } else {
      // Use current academic year based on month
      startYear = now.month >= 8 ? now.year : now.year - 1;
      endYear = startYear + 1;
    }

    switch (semester) {
      case '1st Semester':
        return (
          DateTime(startYear, 8, 1),
          DateTime(startYear + 1, 1, 31, 23, 59),
        );
      case '2nd Semester':
        return (
          DateTime(startYear + 1, 2, 1),
          DateTime(startYear + 1, 6, 30, 23, 59),
        );
      case 'Summer':
        return (
          DateTime(startYear + 1, 6, 1),
          DateTime(startYear + 1, 8, 31, 23, 59),
        );
      default: // All Semesters within academic year
        if (academicYear != 'All Years') {
          return (DateTime(startYear, 8, 1), DateTime(endYear, 7, 31, 23, 59));
        }
    }

    // Fall back to range
    switch (range) {
      case 'Last 30 Days':
        return (now.subtract(const Duration(days: 30)), now);
      case 'Last 90 Days':
        return (now.subtract(const Duration(days: 90)), now);
      case 'This Year':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59));
      default:
        return (null, null);
    }
  }

  // ── Firebase loaders ──────────────────────────────────────────────

  Future<void> _loadOrganizations() async {
    final snap = await FirebaseFirestore.instance
        .collection('organizations')
        .get();
    if (!mounted) return;
    setState(() {
      _organizations = snap.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'id': doc.id,
          'name': data['name']?.toString() ?? 'Unknown',
          'shortName': data['shortName']?.toString() ?? '',
          'logoUrl': data['logoUrl'] as String?,
        };
      }).toList();
    });
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _loadingEvents = true);
    try {
      Query query = FirebaseFirestore.instance.collection('events');
      // Always applied now — this used to only filter when _filterStatus
      // wasn't the default 'All', but there was no UI that ever set it to
      // anything else, so the query silently fetched every status
      // (approved/pending/rejected/archived) mixed together, and an
      // "archived" event would just reappear here on the next reload.
      query = query.where(
        'status',
        isEqualTo: _filterStatus == 'Archived' ? 'archived' : 'approved',
      );
      if (_filterType != 'All Types') {
        query = query.where('type', isEqualTo: _filterType);
      }
      if (_filterOrg != 'All Organizations') {
        final org = _organizations.firstWhere(
          (o) => o['name'] == _filterOrg,
          orElse: () => <String, dynamic>{'id': '', 'name': ''},
        );
        if ((org['id'] as String).isNotEmpty) {
          query = query.where('orgId', isEqualTo: org['id']);
        }
      }
      final (rangeStart, rangeEnd) = _computeDateRange();
      if (rangeStart != null) {
        query = query.where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        );
      }
      if (rangeEnd != null) {
        query = query.where(
          'date',
          isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd),
        );
      }
      final eventsSnap = await query.get();
      final orgMap = {
        for (var o in _organizations) o['id'] as String: o['name'] as String,
      };
      final orgAbbrevMap = {
        for (var o in _organizations)
          o['id'] as String: (o['shortName'] as String? ?? ''),
      };
      // Registrant/attendee counts are no longer fetched here — this used
      // to run one extra Firestore round-trip PER event, sequentially,
      // every time any filter changed (the cause of the page-wide lag).
      // Those counts are now fetched on-demand for just the one event
      // being viewed, in _buildDetailView's attendance section instead.
      final List<EventReport> loaded = [
        for (final doc in eventsSnap.docs)
          EventReport.fromFirestore(
            doc,
            orgMap[(doc.data() as Map<String, dynamic>)['orgId']?.toString() ??
                    ''] ??
                (doc.data() as Map<String, dynamic>)['orgName']?.toString() ??
                'Unknown',
            0,
            0,
            orgAbbrevMap[(doc.data() as Map<String, dynamic>)['orgId']
                        ?.toString() ??
                    ''] ??
                '',
          ),
      ];
      // The query above has no .orderBy — Firestore then returns docs in
      // arbitrary (roughly insertion) order, not by date, which is what
      // made this table look shuffled. Sorted client-side instead of
      // adding .orderBy('date') to the query itself, since that would need
      // a new composite index alongside the existing status/type/orgId/date
      // filters — this app has been bitten before by a query silently
      // returning empty when one isn't provisioned.
      loaded.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() => _events = loaded);
    } catch (e) {
      debugPrint('Error loading events: $e');
    } finally {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  // Registrants come from the `registrations` collection; attendees come
  // from the actual attendance subcollection events/{id}/attendances
  // (only ever written with status 'present' or 'late' — see
  // org_attendance_qr.dart — so a doc existing there means the student
  // showed up). `registrations.attended` is NOT used: nothing in the app
  // ever writes that field, so it would always read as 0.
  Future<(int, int)> _loadEventAttendanceStats(String eventId) async {
    final regSnap = await FirebaseFirestore.instance
        .collection('registrations')
        .where('eventId', isEqualTo: eventId)
        .get();
    final attSnap = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('attendances')
        .get();
    return (regSnap.docs.length, attSnap.docs.length);
  }

  EventReport _eventWithCounts(EventReport e, int registrants, int attendees) {
    return EventReport(
      id: e.id,
      title: e.title,
      orgId: e.orgId,
      orgName: e.orgName,
      orgAbbrev: e.orgAbbrev,
      type: e.type,
      date: e.date,
      status: e.status,
      totalIncome: e.totalIncome,
      totalExpenses: e.totalExpenses,
      registrants: registrants,
      attendees: attendees,
      submittedBy: e.submittedBy,
      reportPeriod: e.reportPeriod,
      submittedDate: e.submittedDate,
      eventImageUrl: e.eventImageUrl,
      // description and location were already being dropped here, so an
      // event silently lost both the moment its page's attendance counts
      // came back. Everything the model carries is copied now.
      description: e.description,
      location: e.location,
      startTime: e.startTime,
      endTime: e.endTime,
      capacity: e.capacity,
      audience: e.audience,
      schoolYear: e.schoolYear,
      semester: e.semester,
      issuesCertificate: e.issuesCertificate,
      incomeBreakdown: e.incomeBreakdown,
      expenseBreakdown: e.expenseBreakdown,
      attachments: e.attachments,
      financialNotes: e.financialNotes,
      recommendations: e.recommendations,
    );
  }

  Future<void> _fetchAttendanceCountsForPage(
    List<EventReport> pageItems,
  ) async {
    if (_loadingEventCounts) return;
    if (!mounted) return;
    setState(() => _loadingEventCounts = true);
    try {
      final futures = <Future<void>>[];
      for (final e in pageItems) {
        // Skip if we already have counts (and not both zero)
        if (e.registrants != 0 || e.attendees != 0) continue;
        futures.add(
          Future(() async {
            try {
              final stats = await _loadEventAttendanceStats(e.id);
              final regs = stats.$1;
              final atts = stats.$2;
              if (!mounted) return;
              setState(() {
                final idx = _events.indexWhere((ev) => ev.id == e.id);
                if (idx >= 0) _events[idx] = _eventWithCounts(e, regs, atts);
              });
            } catch (ex) {
              debugPrint('Error fetching attendance for ${e.id}: $ex');
            }
          }),
        );
      }
      await Future.wait(futures);
    } finally {
      if (mounted) setState(() => _loadingEventCounts = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadEventAttendeesList(
    String eventId,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .collection('attendances')
          .orderBy('timestamp')
          .get();
      return snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        m['id'] = d.id;
        m['timestamp'] = (m['timestamp'] as Timestamp?)?.toDate();
        return m;
      }).toList();
    } catch (e) {
      debugPrint('Error loading attendees: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadEventFeedbacks(String eventId) async {
    final db = FirebaseFirestore.instance;
    final results = <Map<String, dynamic>>[];
    try {
      // Primary 'feedback' collection (used by org analytics)
      final fb1 = await db
          .collection('feedback')
          .where('eventId', isEqualTo: eventId)
          .get();
      for (final d in fb1.docs) {
        final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        m['id'] = d.id;
        m['source'] = 'feedback';
        results.add(m);
      }
    } catch (_) {}
    try {
      // Secondary 'event_feedback' (used elsewhere)
      final fb2 = await db
          .collection('event_feedback')
          .where('eventId', isEqualTo: eventId)
          .get();
      for (final d in fb2.docs) {
        final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        m['id'] = d.id;
        m['source'] = 'event_feedback';
        results.add(m);
      }
    } catch (_) {}
    // Normalize timestamp fields
    for (final r in results) {
      if (r['timestamp'] is Timestamp)
        r['timestamp'] = (r['timestamp'] as Timestamp).toDate();
      if (r['createdAt'] is Timestamp)
        r['createdAt'] = (r['createdAt'] as Timestamp).toDate();
    }
    // Sort by timestamp/createdAt desc
    results.sort((a, b) {
      final da = (a['timestamp'] ?? a['createdAt']) as DateTime?;
      final dbt = (b['timestamp'] ?? b['createdAt']) as DateTime?;
      if (da == null && dbt == null) return 0;
      if (da == null) return 1;
      if (dbt == null) return -1;
      return dbt.compareTo(da);
    });

    // Neither `feedback` nor `event_feedback` stores a display name — only
    // the submitter's auth uid (`userId`) — so without this lookup the
    // admin sees a raw uid like "B3TguKrHcAUtkNLQvN3i4DBmdbn1" instead of
    // the student's name. Resolve all of them in one batched query instead
    // of one read per feedback.
    final userIds = results
        .map((r) => r['userId']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (userIds.isNotEmpty) {
      try {
        final names = <String, String>{};
        for (var i = 0; i < userIds.length; i += 30) {
          final chunk = userIds.sublist(
            i,
            i + 30 > userIds.length ? userIds.length : i + 30,
          );
          final snap = await db
              .collection('students')
              .where('uid', whereIn: chunk)
              .get();
          for (final d in snap.docs) {
            final data = d.data();
            final uid = data['uid']?.toString();
            final name = data['fullName']?.toString();
            if (uid != null && name != null && name.isNotEmpty) {
              names[uid] = name;
            }
          }
        }
        for (final r in results) {
          final uid = r['userId']?.toString();
          if (uid != null && names.containsKey(uid)) {
            r['authorName'] = names[uid];
          }
        }
      } catch (_) {}
    }
    return results;
  }

  Stream<
    (
      double totalIncome,
      double totalExpenses,
      double netAmount,
      List<Map<String, dynamic>> incomeBreakdown,
      List<Map<String, dynamic>> expenseBreakdown,
      int transactionCount,
    )
  >
  _eventTransactionSummaryStream(
    String orgId,
    String eventId,
    String eventTitle,
  ) {
    final title = eventTitle.trim().toLowerCase();
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map((snap) {
          // `eventId` isn't reliably set on every transaction — org_finance.dart
          // only writes it when the org explicitly picks an event, and older
          // entries predate the field. Event name is the more dependable join
          // key (same fallback the org-side Event Analytics screen uses), so
          // match on either.
          final docs = snap.docs.where((d) {
            final data = d.data();
            final matchesId = (data['eventId']?.toString() ?? '') == eventId;
            final matchesTitle =
                (data['eventName']?.toString() ?? '').trim().toLowerCase() ==
                title;
            return matchesId || matchesTitle;
          }).toList();
          return _computeTransactionSummaryFromDocs(docs);
        });
  }

  (
    double totalIncome,
    double totalExpenses,
    double netAmount,
    List<Map<String, dynamic>> incomeBreakdown,
    List<Map<String, dynamic>> expenseBreakdown,
    int transactionCount,
  )
  _computeTransactionSummaryFromDocs(List<QueryDocumentSnapshot> docs) {
    double totalIncome = 0;
    double totalExpenses = 0;
    final incomeBuckets = <String, double>{};
    final expenseBuckets = <String, double>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = (data['type'] as String?)?.toLowerCase() ?? 'income';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      if (amount == 0) continue;
      final segment = (data['segment'] as String?)?.trim() ?? '';
      final category = (data['category'] as String?)?.trim() ?? '';
      final bucketName = segment.isNotEmpty
          ? segment
          : category.isNotEmpty
          ? category
          : 'Other';
      if (type == 'expense' || type == 'outflow' || type == 'cost') {
        totalExpenses += amount;
        expenseBuckets[bucketName] = (expenseBuckets[bucketName] ?? 0) + amount;
      } else {
        totalIncome += amount;
        incomeBuckets[bucketName] = (incomeBuckets[bucketName] ?? 0) + amount;
      }
    }

    List<Map<String, dynamic>> toList(Map<String, double> buckets) {
      final list = buckets.entries
          .map((e) => {'name': e.key, 'amount': e.value})
          .toList();
      list.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
      );
      return list;
    }

    return (
      totalIncome,
      totalExpenses,
      totalIncome - totalExpenses,
      toList(incomeBuckets),
      toList(expenseBuckets),
      docs.length,
    );
  }

  bool _loadingEventDetail = false;

  Future<void> _openEventDetail(EventReport event) async {
    // Toggle off if already viewing the same event
    if (_detailEvent?.id == event.id) {
      setState(() => _detailEvent = null);
      return;
    }

    if (!mounted) return;
    setState(() => _loadingEventDetail = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .get();
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event not found'),
            backgroundColor: UpriseColors.error,
          ),
        );
        return;
      }

      // Resolve org name from cached organizations list, fallback to event.orgName
      final data = doc.data() as Map<String, dynamic>;
      final orgId = data['orgId']?.toString() ?? event.orgId;
      final org = _organizations.firstWhere(
        (o) => o['id'] == orgId,
        orElse: () => <String, dynamic>{'name': event.orgName},
      );
      final orgName = org['name'] as String? ?? event.orgName;
      // fromFirestore takes orgAbbrev as a 5th positional arg; omitting it
      // meant the detail view silently lost the abbreviation the table row
      // had already resolved.
      final orgAbbrev = org['shortName'] as String? ?? event.orgAbbrev;

      final stats = await _loadEventAttendanceStats(event.id);
      final registrants = stats.$1;
      final attendees = stats.$2;

      final populated = EventReport.fromFirestore(
        doc,
        orgName,
        registrants,
        attendees,
        orgAbbrev,
      );
      if (!mounted) return;
      setState(() => _detailEvent = populated);
    } catch (e) {
      debugPrint('Error loading event details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load event details: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEventDetail = false);
    }
  }

  // ── Load Financial Reports ──────────────────────────────────
  Future<void> _loadFinancialReports() async {
    if (!mounted) return;
    setState(() => _loadingFinancial = true);
    try {
      // Query WITHOUT the 'archived' filter
      final reportsSnap = await FirebaseFirestore.instance
          .collection('reports')
          .where('type', isEqualTo: 'financial')
          .get();

      final orgsSnap = await FirebaseFirestore.instance
          .collection('organizations')
          .get();
      final orgMap = {
        for (var doc in orgsSnap.docs)
          doc.id: doc.data()['name']?.toString() ?? 'Unknown',
      };
      final orgAbbrevMap = {
        for (var doc in orgsSnap.docs)
          doc.id: doc.data()['shortName']?.toString() ?? '',
      };

      final allReports = reportsSnap.docs
          .map((doc) => AdminReport.fromFirestore(doc, orgMap, orgAbbrevMap))
          .toList();

      // Kept unfiltered — the Active/Archived toggle filters client-side
      // in _applyReportFilters, so archived reports stay in this list and
      // can be browsed/restored instead of vanishing outright.
      if (!mounted) return;
      setState(() {
        _financialReports = allReports;
        _loadingFinancial = false;
      });
    } catch (e) {
      debugPrint('Error loading financial reports: $e');
      if (mounted) {
        setState(() => _loadingFinancial = false);
        // Show a snackbar to let you know something went wrong
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load financial reports: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    }
  }

  // ── Load Accomplishment Reports ─────────────────────────────
  Future<void> _loadAccomplishmentReports() async {
    if (!mounted) return;
    setState(() => _loadingAccomplishment = true);
    try {
      // Query WITHOUT the 'archived' filter
      final reportsSnap = await FirebaseFirestore.instance
          .collection('reports')
          .where('type', isEqualTo: 'accomplishment')
          .get();

      final orgsSnap = await FirebaseFirestore.instance
          .collection('organizations')
          .get();
      final orgMap = {
        for (var doc in orgsSnap.docs)
          doc.id: doc.data()['name']?.toString() ?? 'Unknown',
      };
      final orgAbbrevMap = {
        for (var doc in orgsSnap.docs)
          doc.id: doc.data()['shortName']?.toString() ?? '',
      };

      final allReports = reportsSnap.docs
          .map((doc) => AdminReport.fromFirestore(doc, orgMap, orgAbbrevMap))
          .toList();

      // Kept unfiltered — the Active/Archived toggle filters client-side
      // in _applyReportFilters, so archived reports stay in this list and
      // can be browsed/restored instead of vanishing outright.
      if (!mounted) return;
      setState(() {
        _accomplishmentReports = allReports;
        _loadingAccomplishment = false;
      });
    } catch (e) {
      debugPrint('Error loading accomplishment reports: $e');
      if (mounted) {
        setState(() => _loadingAccomplishment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load accomplishment reports: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    }
  }

  // ── Archive Report ────────────────────────────────────────────────
  Future<void> _archiveReport(AdminReport report) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        title: 'Archive Report',
        message:
            'Are you sure you want to archive "${report.eventTitle}" from ${report.orgName}?',
        confirmLabel: 'Archive',
        destructive: false,
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(report.id)
          .update({'archived': true});

      await activity_log.ActivityLogger.log(
        action: 'archive_report',
        module: 'Reports',
        details: {
          'reportId': report.id,
          'orgId': report.orgId,
          'eventTitle': report.eventTitle,
        },
      );

      _setReportArchived(report, true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report archived successfully'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error archiving report: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  Future<void> _restoreReport(AdminReport report) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        title: 'Restore Report',
        message:
            'Restore "${report.eventTitle}" from ${report.orgName}? It will show up as active again.',
        confirmLabel: 'Restore',
        destructive: false,
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(report.id)
          .update({'archived': false});

      await activity_log.ActivityLogger.log(
        action: 'restore_report',
        module: 'Reports',
        details: {
          'reportId': report.id,
          'orgId': report.orgId,
          'eventTitle': report.eventTitle,
        },
      );

      _setReportArchived(report, false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report restored successfully'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error restoring report: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  // The Financial/Accomplishment lists now hold BOTH active and archived
  // reports (the Active/Archived toggle filters client-side), so
  // archiving/restoring updates the item in place instead of removing it
  // from the list outright.
  void _setReportArchived(AdminReport report, bool archived) {
    AdminReport copy(AdminReport r) => AdminReport(
      id: r.id,
      orgId: r.orgId,
      orgName: r.orgName,
      orgAbbrev: r.orgAbbrev,
      eventTitle: r.eventTitle,
      type: r.type,
      description: r.description,
      submittedAt: r.submittedAt,
      fileBase64: r.fileBase64,
      fileName: r.fileName,
      fileSize: r.fileSize,
      archived: archived,
    );
    setState(() {
      final list = report.type == 'financial'
          ? _financialReports
          : _accomplishmentReports;
      final idx = list.indexWhere((r) => r.id == report.id);
      if (idx >= 0) list[idx] = copy(report);
    });
  }

  // ── Archive Event (Event Summary tab) ───────────────────────────────
  // Events use a `status` field (approved/pending/rejected/archived) —
  // same convention org_events_schedule.dart writes — not the boolean
  // `archived` field reports/proposals use, so this is its own function
  // rather than reusing _archiveReport.
  Future<void> _archiveEvent(EventReport event) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        title: 'Archive Event',
        message:
            'Archive "${event.title}" from ${event.orgName}? It will no longer show up as an active event.',
        confirmLabel: 'Archive',
        destructive: false,
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({'status': 'archived'});

      await activity_log.ActivityLogger.log(
        action: 'archive_event',
        module: 'Reports',
        details: {
          'eventId': event.id,
          'orgId': event.orgId,
          'title': event.title,
        },
      );

      setState(() {
        _events.removeWhere((e) => e.id == event.id);
        if (_detailEvent?.id == event.id) _detailEvent = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Event archived successfully'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error archiving event: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  Future<void> _restoreEvent(EventReport event) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        title: 'Restore Event',
        message:
            'Restore "${event.title}" from ${event.orgName}? It will show up as an active event again.',
        confirmLabel: 'Restore',
        destructive: false,
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({'status': 'approved'});

      await activity_log.ActivityLogger.log(
        action: 'restore_event',
        module: 'Reports',
        details: {
          'eventId': event.id,
          'orgId': event.orgId,
          'title': event.title,
        },
      );

      setState(() {
        _events.removeWhere((e) => e.id == event.id);
        if (_detailEvent?.id == event.id) _detailEvent = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Event restored successfully'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error restoring event: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  // ── View Report Modal ─────────────────────────────────────────────
  void _viewReport(AdminReport report) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _ViewAdminReportModal(report: report),
    );
  }

  // Reports are only due once an event has actually happened. Returns
  // EVERY finished approved event per org (not just the most recent one)
  // — an org that held 3 events has 3 separate report obligations, each
  // tracked as its own row, not collapsed into one.
  Future<Map<String, List<Map<String, dynamic>>>>
  _loadFinishedEventsByOrg() async {
    final now = DateTime.now();
    final eventsSnap = await FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .get();

    final Map<String, List<Map<String, dynamic>>> eventsByOrg = {};
    for (final doc in eventsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final orgId = data['orgId']?.toString();
      final date = (data['date'] as Timestamp?)?.toDate();
      if (orgId == null ||
          orgId.isEmpty ||
          date == null ||
          !date.isBefore(now)) {
        continue;
      }
      eventsByOrg.putIfAbsent(orgId, () => []).add({
        'eventId': doc.id,
        'eventTitle': data['title']?.toString() ?? 'Untitled Event',
        'eventDate': date,
      });
    }
    for (final list in eventsByOrg.values) {
      list.sort(
        (a, b) =>
            (b['eventDate'] as DateTime).compareTo(a['eventDate'] as DateTime),
      );
    }
    return eventsByOrg;
  }

  Future<void> _loadSubmissionData() async {
    await Future.wait([
      _loadFinancialSubmissions(),
      _loadAccomplishmentSubmissions(),
    ]);
  }

  // Per-(org, event, type) deadline overrides an admin has set. Mapped by
  // the doc's own orgId+eventId fields (not by parsing the doc ID), so
  // this stays backward-compatible with override docs saved under the
  // old org+type-only ID scheme — they already had `eventId` populated.
  Future<Map<String, DateTime>> _loadDeadlineOverrides(String type) async {
    final snap = await FirebaseFirestore.instance
        .collection('report_deadline_overrides')
        .where('type', isEqualTo: type)
        .get();
    final map = <String, DateTime>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final orgId = data['orgId']?.toString();
      final eventId = data['eventId']?.toString();
      final deadline = (data['deadline'] as Timestamp?)?.toDate();
      if (orgId != null &&
          eventId != null &&
          eventId.isNotEmpty &&
          deadline != null) {
        map['${orgId}_$eventId'] = deadline;
      }
    }
    return map;
  }

  Future<void> _saveDeadlineOverride(
    OrgSubmission sub,
    String type,
    DateTime? deadline,
  ) async {
    // Keyed per event (not just per org+type) so different events for the
    // same org don't stomp on each other's custom deadline.
    final docId = '${sub.orgId}_${sub.eventId}_$type';
    final ref = FirebaseFirestore.instance
        .collection('report_deadline_overrides')
        .doc(docId);
    if (deadline == null) {
      await ref.delete();
    } else {
      await ref.set({
        'orgId': sub.orgId,
        'type': type,
        'deadline': Timestamp.fromDate(deadline),
        'eventId': sub.eventId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await activity_log.ActivityLogger.log(
      action: deadline == null
          ? 'Cleared $type report deadline override for ${sub.orgName}'
          : 'Set $type report deadline for ${sub.orgName} to ${DateFormat('yyyy-MM-dd').format(deadline)}',
      module: 'Reports',
      severity: 'info',
      details: {'orgId': sub.orgId, 'type': type},
    );
    if (type == 'financial') {
      await _loadFinancialSubmissions();
    } else {
      await _loadAccomplishmentSubmissions();
    }
  }

  Future<void> _showEditDeadlineDialog(OrgSubmission sub, String type) async {
    DateTime? picked = sub.deadlineOverride;
    final autoDeadline = sub.eventDate?.add(const Duration(days: 7));
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.event_available_rounded,
                        color: UpriseColors.primaryDark,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit ${type == 'financial' ? 'Financial' : 'Accomplishment'} Deadline',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            sub.eventTitle != null
                                ? '${sub.orgName} — ${sub.eventTitle}'
                                : sub.orgName,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (autoDeadline != null)
                  Text(
                    'Default (7 days after event): ${DateFormat('MMM dd, yyyy').format(autoDeadline)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF9AA5B4),
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(_DS.radiusSm),
                    border: Border.all(color: const Color(0xFFE2E6EA)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          picked != null
                              ? DateFormat('MMMM dd, yyyy').format(picked!)
                              : 'Using default',
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: UpriseColors.primaryDark,
                        ),
                        tooltip: 'Choose Date',
                        onPressed: () async {
                          final result = await showDatePicker(
                            context: ctx,
                            initialDate:
                                picked ?? autoDeadline ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                            // Material 3's default seed skews purple/indigo
                            // unless the scheme is seeded from the brand
                            // color — same fix as event_calendar.dart's
                            // month picker.
                            builder: (context, child) {
                              final baseTheme = Theme.of(context);
                              final scheme =
                                  ColorScheme.fromSeed(
                                    seedColor: UpriseColors.primaryDark,
                                    brightness: Brightness.light,
                                  ).copyWith(
                                    primary: UpriseColors.primaryDark,
                                    onPrimary: Colors.white,
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
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (result != null) setDlg(() => picked = result);
                        },
                      ),
                      if (picked != null)
                        IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 18,
                            color: Color(0xFF9AA5B4),
                          ),
                          tooltip: 'Reset to default',
                          onPressed: () => setDlg(() => picked = null),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
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
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _saveDeadlineOverride(sub, type, picked);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UpriseColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Save',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Keep these for submission tracker tab
  // Builds one OrgSubmission per (org, finished event) pair — the real
  // source of truth for an actual submission is the `reports` collection
  // (one doc per org+event+type, written by org_reports.dart's _submit()),
  // NOT the old financial_submissions/accomplishment_submissions
  // collections, which only ever held a single doc per ORG (keyed by
  // orgId alone) that got silently overwritten by every new upload
  // regardless of which event it was actually for.
  Future<List<OrgSubmission>> _loadSubmissionRows(String type) async {
    final orgsSnap = await FirebaseFirestore.instance
        .collection('organizations')
        .get();
    final allOrgs = orgsSnap.docs
        .map(
          (doc) => {
            'id': doc.id,
            'name': doc.data()['name']?.toString() ?? 'Unknown',
            'shortName': doc.data()['shortName']?.toString() ?? '',
          },
        )
        .toList();
    final eventsByOrg = await _loadFinishedEventsByOrg();
    final overrides = await _loadDeadlineOverrides(type);

    final reportsSnap = await FirebaseFirestore.instance
        .collection('reports')
        .where('type', isEqualTo: type)
        .get();
    final subsMap = <String, Map<String, dynamic>>{};
    final periodDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in reportsSnap.docs) {
      final data = doc.data();
      final scope = (data['scope'] ?? 'event').toString();
      if (scope != 'event') {
        periodDocs.add(doc);
        continue;
      }
      final orgId = data['orgId']?.toString() ?? '';
      final eventId = data['eventId']?.toString() ?? '';
      if (orgId.isEmpty || eventId.isEmpty) continue;
      subsMap['${orgId}_$eventId'] = {
        'orgId': orgId,
        'eventId': eventId,
        // The event's title at submission time — org_reports.dart bakes this
        // in directly rather than joining against `events` on read, so it
        // survives even if the event doc is later deleted.
        'title': data['title']?.toString() ?? 'Untitled Event',
        'submittedAt': (data['submittedAt'] as Timestamp?)?.toDate(),
        'fileBase64': data['fileBase64'],
        'fileName': data['fileName'],
        'submissionId': doc.id,
      };
    }

    final orgNames = {for (final org in allOrgs) org['id']!: org['name']!};
    final orgAbbrevs = {
      for (final org in allOrgs) org['id']!: org['shortName'] ?? '',
    };

    final rows = <OrgSubmission>[];
    final usedKeys = <String>{};
    for (final org in allOrgs) {
      final orgId = org['id']!;
      final events = eventsByOrg[orgId];
      if (events == null) continue;
      for (final ev in events) {
        final eventId = ev['eventId'] as String;
        final key = '${orgId}_$eventId';
        final sub = subsMap[key];
        usedKeys.add(key);
        rows.add(
          OrgSubmission(
            orgId: orgId,
            orgName: org['name']!,
            orgAbbrev: org['shortName'] ?? '',
            submittedAt: sub?['submittedAt'] as DateTime?,
            fileBase64: sub?['fileBase64'] as String?,
            fileName: sub?['fileName'] as String?,
            submissionId: sub?['submissionId'] as String?,
            eventId: eventId,
            eventTitle: ev['eventTitle'] as String,
            eventDate: ev['eventDate'] as DateTime,
            deadlineOverride: overrides[key],
          ),
        );
      }
    }

    // A submission's event can be deleted after the report was uploaded
    // (event_proposals/events are independent of the reports doc, and
    // nothing stops an org or admin from removing an old event) — without
    // this, that submission's key never matched anything in the loop above
    // and just silently vanished, even though the org genuinely submitted
    // it. Surfaced here using the title/eventId baked into the report doc
    // itself, with no event date/deadline since the source event is gone.
    for (final key in subsMap.keys) {
      if (usedKeys.contains(key)) continue;
      final sub = subsMap[key]!;
      final orgId = sub['orgId'] as String;
      rows.add(
        OrgSubmission(
          orgId: orgId,
          orgName: orgNames[orgId] ?? 'Unknown',
          orgAbbrev: orgAbbrevs[orgId] ?? '',
          submittedAt: sub['submittedAt'] as DateTime?,
          fileBase64: sub['fileBase64'] as String?,
          fileName: sub['fileName'] as String?,
          submissionId: sub['submissionId'] as String?,
          eventId: sub['eventId'] as String?,
          eventTitle: sub['title'] as String?,
        ),
      );
    }

    // Semester/whole-year submissions only ever appear here if an org
    // actually uploaded one — unlike events, there's no fixed date to
    // proactively chase a "pending" placeholder for every period.
    for (final doc in periodDocs) {
      final data = doc.data();
      final orgId = data['orgId']?.toString() ?? '';
      if (orgId.isEmpty) continue;
      rows.add(
        OrgSubmission(
          orgId: orgId,
          orgName: orgNames[orgId] ?? 'Unknown',
          orgAbbrev: orgAbbrevs[orgId] ?? '',
          submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
          fileBase64: data['fileBase64'],
          fileName: data['fileName'],
          submissionId: doc.id,
          scope: (data['scope'] ?? 'event').toString(),
          schoolYear: data['schoolYear']?.toString(),
          semester: data['semester']?.toString(),
        ),
      );
    }
    return rows;
  }

  Future<void> _loadFinancialSubmissions() async {
    if (!mounted) return;
    setState(() => _loadingFinancialSubs = true);
    try {
      final rows = await _loadSubmissionRows('financial');
      if (!mounted) return;
      setState(() => _financialSubs = rows);
    } catch (e) {
      debugPrint('Error loading financial submissions: $e');
    } finally {
      if (mounted) setState(() => _loadingFinancialSubs = false);
    }
  }

  Future<void> _loadAccomplishmentSubmissions() async {
    if (!mounted) return;
    setState(() => _loadingAccomplishmentSubs = true);
    try {
      final rows = await _loadSubmissionRows('accomplishment');
      if (!mounted) return;
      setState(() => _accomplishmentSubs = rows);
    } catch (e) {
      debugPrint('Error loading accomplishment submissions: $e');
    } finally {
      if (mounted) setState(() => _loadingAccomplishmentSubs = false);
    }
  }

  // ── Export / PDF ──────────────────────────────────────────────────

  Future<void> _logGeneratedReport(
    String fileName,
    String format,
    String type,
  ) async {
    await FirebaseFirestore.instance.collection('generated_reports').add({
      'fileName': fileName,
      'dateRange': _filterRange,
      'academicYear': _filterAcademicYear,
      'semester': _filterSemester,
      'organization': _filterOrg,
      'eventType': _filterType,
      'status': _filterStatus,
      'reportView': _reportView,
      'generatedAt': FieldValue.serverTimestamp(),
      'format': format,
      'reportType': type,
    });
    await activity_log.ActivityLogger.log(
      action: 'Generated $type report in $format format',
      module: 'Reports',
      severity: 'info',
      details: {
        'fileName': fileName,
        'filters':
            'Org: $_filterOrg, Type: $_filterType, AY: $_filterAcademicYear, Sem: $_filterSemester, Status: $_filterStatus',
      },
    );
  }

  // The Event Summary tab only ever renders the non-financial column
  // layout (Event/Org/Type/Date/Registrants/Attendees/Ratio — see
  // _buildEventSummaryResults' showFinancial: false), so its export must
  // match those columns, not an Income/Expenses/Net shape nobody sees on
  // screen. Exports `_filteredEvents` (search term included) instead of
  // the raw `_events` list, so what gets downloaded matches what's
  // currently visible.
  List<List<String>> _eventSummaryRows() => _filteredEvents
      .map(
        (e) => [
          e.title,
          e.orgName,
          e.type,
          DateFormat('yyyy-MM-dd').format(e.date),
          '${e.registrants}',
          '${e.attendees}',
          '${e.attendanceRatio}%',
        ],
      )
      .toList();

  static const _eventSummaryHeaders = [
    'Event Name',
    'Organization',
    'Type',
    'Date',
    'Registrants',
    'Attendees',
    'Ratio',
  ];

  Future<void> _exportEventSummaryCsv() async {
    if (_filteredEvents.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final bytes = AdminExportExcel.generateStyledTable(
      title: 'Event Summary',
      headers: _eventSummaryHeaders,
      rows: _eventSummaryRows(),
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'event_summary_$ts.xlsx';
    await AdminExportUtil.saveBytes(bytes, fileName, mimeType: xlsxMimeType);
    await _logGeneratedReport(fileName, 'Excel', 'Event Summary');
  }

  Future<void> _exportEventSummaryPdf() async {
    if (_filteredEvents.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'event_summary_$ts.pdf';

    final pdfBytes = await AdminExportPdf.generateTablePdf(
      title: 'UPRISE Event Summary Report',
      headers: _eventSummaryHeaders,
      rows: _eventSummaryRows(),
      subtitle:
          'Organization: $_filterOrg  |  Event Type: $_filterType  |  Status: $_filterStatus',
    );

    await AdminExportUtil.saveBytes(
      pdfBytes,
      fileName,
      mimeType: 'application/pdf',
    );
    await _logGeneratedReport(fileName, 'PDF', 'Event Summary');
  }

  // Per-event "Download PDF" button on the detail view — previously wired
  // to _generatePDFReport, which ignored the event being viewed entirely
  // and re-exported the WHOLE events list as a financial-shaped PDF. This
  // generates a one-row report for just this event instead.
  Future<void> _downloadEventPdf(EventReport event) async {
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final safeTitle = event.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final fileName = 'event_report_${safeTitle}_$ts.pdf';

    final pdfBytes = await AdminExportPdf.generateTablePdf(
      title: 'UPRISE Event Report — ${event.title}',
      headers: _eventSummaryHeaders,
      rows: [
        [
          event.title,
          event.orgName,
          event.type,
          DateFormat('yyyy-MM-dd').format(event.date),
          '${event.registrants}',
          '${event.attendees}',
          '${event.attendanceRatio}%',
        ],
      ],
    );

    await AdminExportUtil.saveBytes(
      pdfBytes,
      fileName,
      mimeType: 'application/pdf',
    );
    await _logGeneratedReport(fileName, 'PDF', 'Event Summary');
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Stack(
        children: [
          _detailEvent != null
              ? _buildDetailView(_detailEvent!)
              : _buildMainView(),
          if (_loadingEventDetail)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // Page-level overview, visible regardless of which tab is active — same
  // pattern as the stats row on event_proposals.dart / external_account.dart.
  Widget _buildPageStatsRow() {
    final trackedFin = _financialSubs.where((s) => s.hasApprovedEvent).toList();
    final trackedAcc = _accomplishmentSubs
        .where((s) => s.hasApprovedEvent)
        .toList();
    final overdue =
        trackedFin
            .where(
              (s) =>
                  s.submittedAt == null &&
                  s.eventDeadline != null &&
                  DateTime.now().isAfter(s.eventDeadline!),
            )
            .length +
        trackedAcc
            .where(
              (s) =>
                  s.submittedAt == null &&
                  s.eventDeadline != null &&
                  DateTime.now().isAfter(s.eventDeadline!),
            )
            .length;
    final cards = [
      StatCard(
        label: 'Total Events',
        value: '${_events.length}',
        icon: Icons.event_note_rounded,
        color: UpriseColors.primaryDark,
        onTap: () => _tabController.animateTo(0),
      ),
      StatCard(
        label: 'Financial Reports',
        value: '${_financialReports.where((r) => !r.archived).length}',
        icon: Icons.payments_rounded,
        color: UpriseColors.success,
        onTap: () => _tabController.animateTo(2),
      ),
      StatCard(
        label: 'Accomplishment Reports',
        value: '${_accomplishmentReports.where((r) => !r.archived).length}',
        icon: Icons.assignment_rounded,
        color: UpriseColors.info,
        onTap: () => _tabController.animateTo(1),
      ),
      StatCard(
        label: 'Overdue (Not Submitted)',
        value: '$overdue',
        icon: Icons.error_outline_rounded,
        color: UpriseColors.error,
        onTap: () {
          setState(() => _submissionStatusFilter = 'Overdue');
          _tabController.animateTo(3);
        },
      ),
    ];

    final width = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: StatCardsRow(cards: cards, isMobile: width < 720),
    );
  }

  Widget _buildMainView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageStatsRow(),
        const SizedBox(height: 16),
        _buildTabBar(),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildEventSummaryTab(),
              _buildReportTab(
                'Accomplishment',
                _accomplishmentReports,
                _loadingAccomplishment,
              ),
              _buildReportTab(
                'Financial',
                _financialReports,
                _loadingFinancial,
              ),
              _buildSubmissionTrackerTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab Bar ───────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusMd),
          border: Border.all(color: const Color(0xFFE8ECF0)),
          boxShadow: _DS.cardShadow,
        ),
        child: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Event Summary'),
            Tab(text: 'Accomplishment Reports'),
            Tab(text: 'Financial Reports'),
            Tab(text: 'Submission Tracker'),
          ],
          labelColor: UpriseColors.primaryDark,
          unselectedLabelColor: const Color(0xFF64748B),
          indicator: BoxDecoration(
            color: UpriseColors.primaryLight,
            borderRadius: BorderRadius.circular(_DS.radiusMd - 2),
            border: Border.all(color: UpriseColors.primaryDark.withAlpha(76)),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 13),
          isScrollable: false,
          padding: const EdgeInsets.all(4),
        ),
      ),
    );
  }

  // ── Report Tab (Accomplishment / Financial) ──────────────────────
  // Pure viewing of whatever orgs have uploaded — filters apply live, no
  // "generate" step needed since the data already exists.
  Widget _buildReportTab(
    String reportType,
    List<AdminReport> reports,
    bool loading,
  ) {
    final filtered = _applyReportFilters(reports, reportType);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReportFilterRow(reportType, filtered),
          const SizedBox(height: 16),
          _buildReportTable(reportType, filtered, loading),
        ],
      ),
    );
  }

  List<AdminReport> _applyReportFilters(
    List<AdminReport> reports,
    String reportType,
  ) {
    final isFinancial = reportType == 'Financial';
    final org = isFinancial ? _filterOrgFinancial : _filterOrgAccomplishment;
    final academicYear = isFinancial
        ? _filterAcademicYearFinancial
        : _filterAcademicYearAccomplishment;
    final semester = isFinancial
        ? _filterSemesterFinancial
        : _filterSemesterAccomplishment;
    final status = isFinancial
        ? _filterStatusFinancial
        : _filterStatusAccomplishment;

    var filtered = reports.where((r) => r.archived == (status == 'Archived'));
    final term = _reportSearchController.text.trim().toLowerCase();
    if (term.isNotEmpty) {
      filtered = filtered.where(
        (r) =>
            r.orgName.toLowerCase().contains(term) ||
            r.eventTitle.toLowerCase().contains(term),
      );
    }
    if (org != 'All Organizations') {
      filtered = filtered.where((r) => r.orgName == org);
    }
    final (start, end) = _computeDateRangeFor(
      academicYear,
      semester,
      'All Time',
    );
    if (start != null) {
      filtered = filtered.where((r) => !r.submittedAt.isBefore(start));
    }
    if (end != null) {
      filtered = filtered.where((r) => !r.submittedAt.isAfter(end));
    }
    return filtered.toList();
  }

  // Same bare search-field-plus-dropdowns layout as the other admin
  // tables — no card wrapper, no section label.
  Widget _buildReportFilterRow(
    String reportType,
    List<AdminReport> filteredReports,
  ) {
    final orgNames = [
      'All Organizations',
      ..._organizations.map((o) => o['name'] as String),
    ];

    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _reportSearchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by event or organization…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final isFinancial = reportType == 'Financial';
    final currentOrg = isFinancial
        ? _filterOrgFinancial
        : _filterOrgAccomplishment;
    final currentAcademicYear = isFinancial
        ? _filterAcademicYearFinancial
        : _filterAcademicYearAccomplishment;
    final currentSemester = isFinancial
        ? _filterSemesterFinancial
        : _filterSemesterAccomplishment;
    final currentStatus = isFinancial
        ? _filterStatusFinancial
        : _filterStatusAccomplishment;

    final filters = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterDropdown(
          value: currentOrg,
          items: orgNames,
          hint: 'Organization',
          icon: Icons.business_rounded,
          onChanged: (v) => setState(() {
            if (isFinancial) {
              _filterOrgFinancial = v!;
            } else {
              _filterOrgAccomplishment = v!;
            }
          }),
        ),
        _FilterDropdown(
          value: currentAcademicYear,
          items: _academicYears,
          hint: 'Academic Year',
          icon: Icons.school_rounded,
          onChanged: (v) => setState(() {
            if (isFinancial) {
              _filterAcademicYearFinancial = v!;
            } else {
              _filterAcademicYearAccomplishment = v!;
            }
          }),
        ),
        _FilterDropdown(
          value: currentSemester,
          items: _semesters,
          hint: 'Semester',
          icon: Icons.calendar_view_month_rounded,
          onChanged: (v) => setState(() {
            if (isFinancial) {
              _filterSemesterFinancial = v!;
            } else {
              _filterSemesterAccomplishment = v!;
            }
          }),
        ),
        _FilterDropdown(
          value: currentStatus,
          items: _activeArchivedOptions,
          hint: 'Status',
          icon: Icons.visibility_outlined,
          onChanged: (v) => setState(() {
            if (isFinancial) {
              _filterStatusFinancial = v!;
            } else {
              _filterStatusAccomplishment = v!;
            }
          }),
        ),
        _ExportButton(
          onExportCsv: () =>
              _exportAdminReportsCsv(reportType, filteredReports),
          onExportPdf: () =>
              _exportAdminReportsPdf(reportType, filteredReports),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchField, const SizedBox(height: 10), filters],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 10),
            filters,
          ],
        );
      },
    );
  }

  Future<void> _exportAdminReportsCsv(
    String reportType,
    List<AdminReport> reports,
  ) async {
    if (reports.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final rows = reports
        .map(
          (r) => [
            r.orgName,
            r.eventTitle,
            r.type,
            r.description,
            DateFormat('yyyy-MM-dd').format(r.submittedAt),
          ],
        )
        .toList();
    final bytes = AdminExportExcel.generateStyledTable(
      title: '$reportType Reports',
      headers: const [
        'Organization',
        'Event',
        'Type',
        'Description',
        'Date Submitted',
      ],
      rows: rows,
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = '${reportType.toLowerCase()}_reports_$ts.xlsx';
    await AdminExportUtil.saveBytes(bytes, fileName, mimeType: xlsxMimeType);
    await _logGeneratedReport(fileName, 'Excel', reportType);
  }

  Future<void> _exportAdminReportsPdf(
    String reportType,
    List<AdminReport> reports,
  ) async {
    if (reports.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final rows = reports
        .map(
          (r) => [
            r.orgName,
            r.eventTitle,
            r.type,
            r.description,
            DateFormat('yyyy-MM-dd').format(r.submittedAt),
          ],
        )
        .toList();
    final pdfBytes = await AdminExportPdf.generateTablePdf(
      title: '$reportType Reports',
      headers: const [
        'Organization',
        'Event',
        'Type',
        'Description',
        'Date Submitted',
      ],
      rows: rows,
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = '${reportType.toLowerCase()}_reports_$ts.pdf';
    await AdminExportUtil.saveBytes(
      pdfBytes,
      fileName,
      mimeType: 'application/pdf',
    );
    await _logGeneratedReport(fileName, 'PDF', reportType);
  }

  // ── Report Table ─────────────────────────────────────────────────
  Widget _buildReportTable(
    String reportType,
    List<AdminReport> reports,
    bool loading,
  ) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final sorted = List<AdminReport>.from(reports)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
                Expanded(flex: 3, child: _headerCell('EVENT')),
                Expanded(flex: 2, child: _headerCell('TYPE')),
                Expanded(flex: 3, child: _headerCell('DESCRIPTION')),
                Expanded(flex: 2, child: _headerCell('DATE SUBMITTED')),
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _headerCell('ACTIONS'),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          if (sorted.isEmpty)
            _buildEmptyState()
          else
            ...sorted.asMap().entries.map((entry) {
              final i = entry.key;
              final report = entry.value;
              final isLast = i == sorted.length - 1;
              return InkWell(
                hoverColor: const Color(0xFFF8F9FB),
                onTap: () => _viewReport(report),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            _OrgAvatar(
                              name: report.orgName,
                              imageUrl: _getOrgLogo(report.orgId),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Tooltip(
                                message: report.orgName,
                                child: Text(
                                  report.orgAbbrev.isNotEmpty
                                      ? report.orgAbbrev
                                      : report.orgName,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A202C),
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          report.eventTitle,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1A202C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: report.type == 'financial'
                                  ? const Color(0xFFECFDF5)
                                  : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              report.type == 'financial'
                                  ? 'Financial'
                                  : 'Accomplishment',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: report.type == 'financial'
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          report.description,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          DateFormat('MMM dd, yyyy').format(report.submittedAt),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ActionIconButton(
                              icon: Icons.visibility_outlined,
                              tooltip: 'View Report',
                              color: const Color(0xFF3B82F6),
                              onTap: () => _viewReport(report),
                            ),
                            const SizedBox(width: 4),
                            if (report.archived)
                              _ActionIconButton(
                                icon: Icons.restore_rounded,
                                tooltip: 'Restore Report',
                                color: const Color(0xFF059669),
                                onTap: () => _restoreReport(report),
                              )
                            else
                              _ActionIconButton(
                                icon: Icons.archive_outlined,
                                tooltip: 'Archive Report',
                                color: const Color(0xFF6B7280),
                                onTap: () => _archiveReport(report),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // Footer — export now lives in the toolbar at the top, next to
          // the filters, same as every other tab.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
              color: Color(0xFFF8F9FB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Text(
              'Showing ${sorted.length} reports',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Event Summary Tab ─────────────────────────────────────────────
  Widget _buildEventSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEventSummaryToolbar(),
          const SizedBox(height: 16),
          _loadingEvents
              ? const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _buildEventSummaryResults(),
        ],
      ),
    );
  }

  List<EventReport> get _filteredEvents {
    final term = _eventSearchController.text.trim().toLowerCase();
    if (term.isEmpty) return _events;
    return _events
        .where(
          (e) =>
              e.title.toLowerCase().contains(term) ||
              e.orgName.toLowerCase().contains(term),
        )
        .toList();
  }

  // Live analytics, filtered as you go — same idea as the org-side Event
  // Analytics screen, but aggregated across every organization instead of
  // just one. No "generate" step: each filter re-queries immediately. Same
  // bare search-field-plus-dropdowns layout as the other admin tables
  // (no card wrapper, no section label).
  Widget _buildEventSummaryToolbar() {
    final orgNames = [
      'All Organizations',
      ..._organizations.map((o) => o['name'] as String),
    ];

    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _eventSearchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by event or organization…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final filters = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterDropdown(
          value: _filterOrg,
          items: orgNames,
          hint: 'Organization',
          icon: Icons.business_rounded,
          onChanged: (v) {
            setState(() => _filterOrg = v!);
            _loadEvents();
          },
        ),
        _FilterDropdown(
          value: _filterType,
          items: const [
            'All Types',
            'Seminar',
            'Workshop',
            'Exhibition',
            'Social',
            'Cultural',
            'Competition',
          ],
          hint: 'Event Type',
          icon: Icons.category_rounded,
          onChanged: (v) {
            setState(() => _filterType = v!);
            _loadEvents();
          },
        ),
        _FilterDropdown(
          value: _filterAcademicYear,
          items: _academicYears,
          hint: 'Academic Year',
          icon: Icons.school_rounded,
          onChanged: (v) {
            setState(() => _filterAcademicYear = v!);
            _loadEvents();
          },
        ),
        _FilterDropdown(
          value: _filterSemester,
          items: _semesters,
          hint: 'Semester',
          icon: Icons.calendar_view_month_rounded,
          onChanged: (v) {
            setState(() => _filterSemester = v!);
            _loadEvents();
          },
        ),
        _FilterDropdown(
          value: _filterStatus,
          items: _activeArchivedOptions,
          hint: 'Status',
          icon: Icons.visibility_outlined,
          onChanged: (v) {
            setState(() => _filterStatus = v!);
            _loadEvents();
          },
        ),
        _ExportButton(
          onExportCsv: _exportEventSummaryCsv,
          onExportPdf: _exportEventSummaryPdf,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchField, const SizedBox(height: 10), filters],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 10),
            filters,
          ],
        );
      },
    );
  }

  // Toolbar + table only — matches the layout every other tab on this page
  // uses (_buildReportTab, _buildSubmissionTrackerTab). The per-event Type
  // and attendance Ratio are already visible per-row in the table itself,
  // so a separate aggregate chart above it was just duplicate noise.
  Widget _buildEventSummaryResults() {
    return _buildEventsTable(
      _filteredEvents,
      showFinancial: false,
      showCountdown: false,
    );
  }

  // ── Events Table ──────────────────────────────────────────────────
  // Plain Column of mapped rows, no ListView/Expanded — same structural
  // pattern as _buildReportTable/_buildSubmissionTable elsewhere in this
  // file, so it doesn't need a height-bounded ancestor (that mismatch was
  // the cause of the bottom overflow).
  Widget _buildEventsTable(
    List<EventReport> events, {
    required bool showFinancial,
    required bool showCountdown,
  }) {
    if (_loadingEvents) return const Center(child: CircularProgressIndicator());
    final totalPages = events.isEmpty ? 1 : (events.length / _pageSize).ceil();
    final safePage = _currentPage.clamp(1, totalPages);
    final start = (safePage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, events.length);
    final pageItems = events.isEmpty
        ? <EventReport>[]
        : events.sublist(start, end);

    // Ensure attendance counts are populated for visible page items.
    if (!_loadingEventCounts) {
      final needsCounts = pageItems.any(
        (e) => e.registrants == 0 && e.attendees == 0,
      );
      if (needsCounts) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchAttendanceCountsForPage(pageItems);
        });
      }
    }

    // No horizontal margin here — the parent SingleChildScrollView
    // (_buildEventSummaryTab) already applies 28px side padding, so this
    // table lines up flush with the toolbar above it instead of being
    // indented an extra 28px on top of that.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        children: [
          _buildTableHeader(
            showFinancial: showFinancial,
            showCountdown: showCountdown,
          ),
          if (events.isEmpty)
            _buildEmptyState()
          else
            ...pageItems.asMap().entries.map(
              (entry) => _buildEventRow(
                event: entry.value,
                isLast: entry.key == pageItems.length - 1,
                showFinancial: showFinancial,
                showCountdown: showCountdown,
              ),
            ),
          _buildTableFooter(events.length, totalPages, start, end),
        ],
      ),
    );
  }

  Widget _buildTableHeader({
    required bool showFinancial,
    required bool showCountdown,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: showFinancial
            ? [
                Expanded(flex: 3, child: _headerCell('EVENT NAME')),
                Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
                Expanded(flex: 2, child: _headerCell('INCOME')),
                Expanded(flex: 2, child: _headerCell('EXPENSES')),
                Expanded(flex: 2, child: _headerCell('NET AMOUNT')),
                if (showCountdown)
                  Expanded(flex: 2, child: _headerCell('DAYS TO EVENT')),
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _headerCell('ACTIONS'),
                  ),
                ),
              ]
            : [
                Expanded(flex: 4, child: _headerCell('EVENT NAME')),
                Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
                Expanded(flex: 2, child: _headerCell('TYPE')),
                Expanded(flex: 2, child: _headerCell('DATE')),
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _headerCell('ACTIONS'),
                  ),
                ),
              ],
      ),
    );
  }

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildEventRow({
    required EventReport event,
    required bool isLast,
    required bool showFinancial,
    required bool showCountdown,
  }) {
    final now = DateTime.now();
    final daysUntil = event.date.difference(now).inDays;
    final String countdownText = daysUntil < 0
        ? 'Passed'
        : daysUntil == 0
        ? 'Today'
        : '$daysUntil days';
    final Color countdownColor = daysUntil < 0
        ? const Color(0xFF9AA5B4)
        : daysUntil == 0
        ? UpriseColors.success
        : daysUntil <= 7
        ? UpriseColors.warning
        : UpriseColors.primaryDark;

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _openEventDetail(event),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: showFinancial
              ? [
                  Expanded(
                    flex: 3,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: EventImage(
                            imageUrl: event.eventImageUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            showLoadingIndicator: false,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            event.title,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A202C),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Tooltip(
                      message: event.orgName,
                      child: Text(
                        event.orgAbbrev.isNotEmpty
                            ? event.orgAbbrev
                            : event.orgName,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₱${_fmt(event.totalIncome)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: UpriseColors.success,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₱${_fmt(event.totalExpenses)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: UpriseColors.error,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₱${_fmt(event.netAmount)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: event.netAmount >= 0
                            ? UpriseColors.success
                            : UpriseColors.error,
                      ),
                    ),
                  ),
                  if (showCountdown)
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: countdownColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            countdownText,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: countdownColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ActionIconButton(
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Report',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _openEventDetail(event),
                      ),
                    ),
                  ),
                ]
              : [
                  Expanded(
                    flex: 4,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: EventImage(
                            imageUrl: event.eventImageUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            showLoadingIndicator: false,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            event.title,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A202C),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Tooltip(
                      message: event.orgName,
                      child: Text(
                        event.orgAbbrev.isNotEmpty
                            ? event.orgAbbrev
                            : event.orgName,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _EventCategoryChip(type: event.type),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      DateFormat('MMM dd, yyyy').format(event.date),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _ActionIconButton(
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Report',
                          color: const Color(0xFF3B82F6),
                          onTap: () => _openEventDetail(event),
                        ),
                        const SizedBox(width: 4),
                        if (event.status == 'archived')
                          _ActionIconButton(
                            icon: Icons.restore_rounded,
                            tooltip: 'Restore Event',
                            color: const Color(0xFF059669),
                            onTap: () => _restoreEvent(event),
                          )
                        else
                          _ActionIconButton(
                            icon: Icons.archive_outlined,
                            tooltip: 'Archive Event',
                            color: const Color(0xFF6B7280),
                            onTap: () => _archiveEvent(event),
                          ),
                      ],
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              size: 40,
              color: Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No reports found',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableFooter(int total, int totalPages, int start, int end) {
    const int maxVisible = 5;
    int firstPage = (_currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    if (lastPage - firstPage + 1 < maxVisible && firstPage > 1) {
      firstPage = (lastPage - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total events',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left_rounded,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (p) => _PageNumButton(
                  page: p,
                  isActive: p == _currentPage,
                  onTap: () => setState(() => _currentPage = p),
                ),
              ),
              if (lastPage < totalPages) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '…',
                    style: GoogleFonts.beVietnamPro(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ),
                _PageNumButton(
                  page: totalPages,
                  isActive: _currentPage == totalPages,
                  onTap: () => setState(() => _currentPage = totalPages),
                ),
              ],
              const SizedBox(width: 4),
              _PageButton(
                icon: Icons.chevron_right_rounded,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Submission Tracker Tab ─────────────────────────────────────────
  // Redesigned around one enclosing card instead of two full-width tables
  // floating loose on the page, with a Financial/Accomplishment toggle so
  // only one dense table is ever on screen at a time, plus a quick-count
  // strip for at-a-glance status instead of having to scan every row.
  Widget _buildSubmissionTrackerTab() {
    final isFinancial = _submissionTypeView == 'Financial';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8ECF0)),
          boxShadow: _DS.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSubmissionTrackerToolbar(),
            const SizedBox(height: 16),
            _buildSubmissionTypeToggle(),
            const SizedBox(height: 16),
            _buildSubmissionQuickCounts(
              isFinancial ? _financialSubs : _accomplishmentSubs,
            ),
            // Only surfaced while looking at the Overdue filter — sending
            // reminders to orgs that aren't actually overdue doesn't make
            // sense, so this stays out of the way otherwise.
            if (_submissionStatusFilter == 'Overdue') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () => _sendReminderToAllOverdue(
                    isFinancial ? _financialSubs : _accomplishmentSubs,
                    isFinancial ? 'financial' : 'accomplishment',
                  ),
                  icon: const Icon(
                    Icons.notifications_active_outlined,
                    size: 16,
                  ),
                  label: Text(
                    'Send Reminder to All',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UpriseColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            isFinancial
                ? _buildSubmissionTable(
                    'Financial',
                    _financialSubs,
                    _loadingFinancialSubs,
                  )
                : _buildSubmissionTable(
                    'Accomplishment',
                    _accomplishmentSubs,
                    _loadingAccomplishmentSubs,
                  ),
          ],
        ),
      ),
    );
  }

  // Financial/Accomplishment segmented toggle — replaces stacking both
  // full tables on screen simultaneously.
  Widget _buildSubmissionTypeToggle() {
    Widget seg(String label, IconData icon, int count) {
      final selected = _submissionTypeView == label;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _submissionTypeView = label),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? UpriseColors.primaryDark : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Text(
                  '$label ($count)',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg(
            'Financial',
            Icons.payments_rounded,
            _financialSubs.where((s) => s.hasApprovedEvent).length,
          ),
          const SizedBox(width: 4),
          seg(
            'Accomplishment',
            Icons.assignment_rounded,
            _accomplishmentSubs.where((s) => s.hasApprovedEvent).length,
          ),
        ],
      ),
    );
  }

  (int submitted, int pending, int late, int overdue) _submissionCounts(
    List<OrgSubmission> subs,
  ) {
    final tracked = subs.where((s) => s.hasApprovedEvent);
    int submitted = 0, pending = 0, late = 0, overdue = 0;
    for (final s in tracked) {
      final isSubmitted = s.submittedAt != null;
      final deadline = s.eventDeadline;
      final isOverdue =
          !isSubmitted && deadline != null && DateTime.now().isAfter(deadline);
      final isLate =
          isSubmitted && deadline != null && s.submittedAt!.isAfter(deadline);
      if (isLate) {
        late++;
      } else if (isSubmitted) {
        submitted++;
      } else if (isOverdue) {
        overdue++;
      } else {
        pending++;
      }
    }
    return (submitted, pending, late, overdue);
  }

  // Clickable quick-count chips double as status-filter shortcuts — tapping
  // one sets the same _submissionStatusFilter the dropdown above controls,
  // tapping the active one again clears it.
  Widget _buildSubmissionQuickCounts(List<OrgSubmission> subs) {
    final (submitted, pending, late, overdue) = _submissionCounts(subs);
    void toggle(String status) => setState(
      () => _submissionStatusFilter = _submissionStatusFilter == status
          ? 'All'
          : status,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _quickCountChip(
          'On time',
          submitted,
          UpriseColors.success,
          selected: _submissionStatusFilter == 'Submitted',
          onTap: () => toggle('Submitted'),
        ),
        _quickCountChip(
          'Pending',
          pending,
          UpriseColors.info,
          selected: _submissionStatusFilter == 'Pending',
          onTap: () => toggle('Pending'),
        ),
        _quickCountChip(
          'Late',
          late,
          UpriseColors.warning,
          selected: _submissionStatusFilter == 'Late',
          onTap: () => toggle('Late'),
        ),
        _quickCountChip(
          'Overdue',
          overdue,
          UpriseColors.error,
          selected: _submissionStatusFilter == 'Overdue',
          onTap: () => toggle('Overdue'),
        ),
      ],
    );
  }

  Widget _quickCountChip(
    String label,
    int count,
    Color color, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(28) : const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? color : const Color(0xFFE2E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A202C),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Single search + filter + export toolbar shared by BOTH tables below —
  // replaces what used to be two separate, control-less tables each with
  // their own footer export button. Same bare search-field-plus-dropdowns
  // layout as the other admin toolbars in this file.
  Widget _buildSubmissionTrackerToolbar() {
    final orgNames = [
      'All Organizations',
      ..._organizations.map((o) => o['name'] as String),
    ];

    final searchField = SizedBox(
      height: 40,
      child: TextField(
        controller: _submissionSearchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by organization or event…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final filters = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterDropdown(
          value: _filterOrgSubmissions,
          items: orgNames,
          hint: 'Organization',
          icon: Icons.business_rounded,
          onChanged: (v) => setState(() => _filterOrgSubmissions = v!),
        ),
        _FilterDropdown(
          value: _submissionStatusFilter,
          items: const ['All', 'Pending', 'Submitted', 'Late', 'Overdue'],
          hint: 'Status',
          icon: Icons.flag_outlined,
          onChanged: (v) => setState(() => _submissionStatusFilter = v!),
        ),
        _ExportButton(
          onExportCsv: _exportSubmissionTrackerCsv,
          onExportPdf: _exportSubmissionTrackerPdf,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchField, const SizedBox(height: 10), filters],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 10),
            filters,
          ],
        );
      },
    );
  }

  // Shared by both tables and the combined export, so what you export
  // always matches what you're currently looking at.
  List<OrgSubmission> _filterSubmissionRows(List<OrgSubmission> subs) {
    final term = _submissionSearchController.text.trim().toLowerCase();
    var filtered = subs.where((s) => s.hasApprovedEvent).toList();
    if (term.isNotEmpty) {
      filtered = filtered
          .where(
            (s) =>
                s.orgName.toLowerCase().contains(term) ||
                s.displayTitle.toLowerCase().contains(term),
          )
          .toList();
    }
    if (_filterOrgSubmissions != 'All Organizations') {
      filtered = filtered
          .where((s) => s.orgName == _filterOrgSubmissions)
          .toList();
    }
    if (_submissionStatusFilter != 'All') {
      filtered = filtered.where((s) {
        final isSubmitted = s.submittedAt != null;
        final deadline = s.eventDeadline;
        final isOverdue =
            !isSubmitted &&
            deadline != null &&
            DateTime.now().isAfter(deadline);
        final isLate =
            isSubmitted && deadline != null && s.submittedAt!.isAfter(deadline);
        switch (_submissionStatusFilter) {
          case 'Submitted':
            return isSubmitted && !isLate;
          case 'Late':
            return isLate;
          case 'Overdue':
            return isOverdue;
          case 'Pending':
            return !isSubmitted && !isOverdue;
        }
        return true;
      }).toList();
    }
    return filtered;
  }

  Future<void> _exportSubmissionTrackerCsv() async {
    final finRows = _filterSubmissionRows(_financialSubs);
    final accRows = _filterSubmissionRows(_accomplishmentSubs);
    if (finRows.isEmpty && accRows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final rows = <List<String>>[];
    for (final entry in [('Financial', finRows), ('Accomplishment', accRows)]) {
      for (final s in entry.$2) {
        rows.add(_submissionExportRow(entry.$1, s));
      }
    }
    final bytes = AdminExportExcel.generateStyledTable(
      title: 'Submission Tracker',
      headers: const [
        'Type',
        'Organization',
        'Event / Period',
        'Event Date',
        'Deadline',
        'Submitted On',
        'Status',
      ],
      rows: rows,
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'submission_tracker_$ts.xlsx';
    await AdminExportUtil.saveBytes(bytes, fileName, mimeType: xlsxMimeType);
    await _logGeneratedReport(fileName, 'Excel', 'Submission Tracker');
  }

  Future<void> _exportSubmissionTrackerPdf() async {
    final finRows = _filterSubmissionRows(_financialSubs);
    final accRows = _filterSubmissionRows(_accomplishmentSubs);
    if (finRows.isEmpty && accRows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final rows = <List<String>>[];
    for (final entry in [('Financial', finRows), ('Accomplishment', accRows)]) {
      for (final s in entry.$2) {
        rows.add(_submissionExportRow(entry.$1, s));
      }
    }
    final pdfBytes = await AdminExportPdf.generateTablePdf(
      title: 'Submission Tracker Report',
      headers: const [
        'Type',
        'Organization',
        'Event / Period',
        'Event Date',
        'Deadline',
        'Submitted On',
        'Status',
      ],
      rows: rows,
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'submission_tracker_$ts.pdf';
    await AdminExportUtil.saveBytes(
      pdfBytes,
      fileName,
      mimeType: 'application/pdf',
    );
    await _logGeneratedReport(fileName, 'PDF', 'Submission Tracker');
  }

  List<String> _submissionExportRow(String type, OrgSubmission s) {
    final isSubmitted = s.submittedAt != null;
    final deadline = s.eventDeadline;
    final isOverdue =
        !isSubmitted && deadline != null && DateTime.now().isAfter(deadline);
    final status = isSubmitted
        ? (s.isLate ? 'Late' : 'On Time')
        : (isOverdue ? 'Overdue' : 'Pending');
    return [
      type,
      s.orgName,
      s.displayTitle,
      s.eventDate != null ? DateFormat('yyyy-MM-dd').format(s.eventDate!) : '',
      deadline != null ? DateFormat('yyyy-MM-dd').format(deadline) : '',
      isSubmitted ? DateFormat('yyyy-MM-dd').format(s.submittedAt!) : '',
      status,
    ];
  }

  // ── Submission Table ──────────────────────────────────────────────
  Widget _buildSubmissionTable(
    String title,
    List<OrgSubmission> submissions,
    bool loading,
  ) {
    if (loading)
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );

    final type = title.toLowerCase();

    // Search/org/status filters come from the shared toolbar above both
    // tables. Deadline is per (org, event): their own override if set,
    // else 7 days after that specific event.
    final sorted = _filterSubmissionRows(submissions)
      ..sort((a, b) {
        final now = DateTime.now();
        final aS = a.submittedAt != null;
        final bS = b.submittedAt != null;
        final aDeadline = a.eventDeadline;
        final bDeadline = b.eventDeadline;
        final aO = aDeadline != null && !aS && now.isAfter(aDeadline);
        final bO = bDeadline != null && !bS && now.isAfter(bDeadline);
        if (aO && !bO) return -1;
        if (!aO && bO) return 1;
        if (aS && !bS) return 1;
        if (!aS && bS) return -1;
        return 0;
      });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Color(0xFFFB923C))),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: _headerCell('ORGANIZATION')),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _headerCell('EVENT / PERIOD'),
                  ),
                ),
                Expanded(flex: 2, child: _headerCell('EVENT DATE')),
                Expanded(flex: 2, child: _headerCell('DEADLINE')),
                Expanded(flex: 2, child: _headerCell('SUBMITTED ON')),
                Expanded(flex: 2, child: _headerCell('STATUS')),
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _headerCell('ACTIONS'),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          if (sorted.isEmpty)
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No matching submissions.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            )
          else
            ...sorted.asMap().entries.map((entry) {
              final i = entry.key;
              final sub = entry.value;
              final isSubmitted = sub.submittedAt != null;
              // Precedence: this org's own override beats the automatic
              // 7-days-after-event rule. Period-scoped (semester/whole-year)
              // submissions have no deadline concept at all — they only ever
              // appear in this list once actually uploaded.
              final rowDeadline = sub.eventDeadline;
              final isOverdue =
                  !isSubmitted &&
                  rowDeadline != null &&
                  DateTime.now().isAfter(rowDeadline);
              final isLate =
                  isSubmitted &&
                  rowDeadline != null &&
                  sub.submittedAt!.isAfter(rowDeadline);
              final daysLeft = (!isSubmitted && rowDeadline != null)
                  ? rowDeadline.difference(DateTime.now()).inDays
                  : 0;
              final isLast = i == sorted.length - 1;
              return InkWell(
                hoverColor: const Color(0xFFF8F9FB),
                onTap: isSubmitted ? () => _viewSubmission(sub, title) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                  ),
                  child: Row(
                    children: [
                      // ---- NEW: Organization column ----
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            _OrgAvatar(name: sub.orgName),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Tooltip(
                                message: sub.orgName,
                                child: Text(
                                  sub.orgAbbrev.isNotEmpty
                                      ? sub.orgAbbrev
                                      : sub.orgName,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A202C),
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ---- NEW: Event column ----
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            sub.displayTitle,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: UpriseColors.primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      // ---- Keep the remaining columns, but adjust their flex to match the new header ----
                      // Event Date
                      Expanded(
                        flex: 2,
                        child: Text(
                          sub.eventDate != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(sub.eventDate!)
                              : '—',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      // Deadline
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                rowDeadline != null
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(rowDeadline)
                                    : '—',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (sub.deadlineOverride != null) ...[
                              const SizedBox(width: 4),
                              const Tooltip(
                                message: 'Custom deadline set by admin',
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 12,
                                  color: UpriseColors.primaryDark,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Submitted On
                      Expanded(
                        flex: 2,
                        child: Text(
                          isSubmitted
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(sub.submittedAt!)
                              : '—',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: isSubmitted
                                ? const Color(0xFF374151)
                                : const Color(0xFF9AA5B4),
                          ),
                        ),
                      ),
                      // Status
                      Expanded(
                        flex: 2,
                        child: isSubmitted
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: _statusBadge(
                                  isLate ? 'late' : 'on time',
                                ),
                              )
                            : isOverdue
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: _statusBadge('overdue'),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _statusBadge('pending'),
                                  const SizedBox(width: 6),
                                  Text(
                                    daysLeft > 0 ? '$daysLeft d left' : 'today',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 10,
                                      color: UpriseColors.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      // Actions
                      Expanded(
                        flex: 1,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isSubmitted)
                              _ActionIconButton(
                                icon: Icons.visibility_outlined,
                                tooltip: 'View Report',
                                color: const Color(0xFF3B82F6),
                                onTap: () => _viewSubmission(sub, title),
                              )
                            else
                              _ActionIconButton(
                                icon: Icons.send_outlined,
                                tooltip: 'Send Reminder',
                                color: const Color(0xFF7C3AED),
                                onTap: () => _sendReminder(sub, title),
                              ),
                            if (!sub.isPeriodScope) ...[
                              const SizedBox(width: 4),
                              _ActionIconButton(
                                icon: Icons.edit_calendar_outlined,
                                tooltip: 'Edit Deadline',
                                color: UpriseColors.primaryDark,
                                onTap: () => _showEditDeadlineDialog(sub, type),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // Footer — count only now; export moved to the shared toolbar
          // above both tables instead of a separate button per table.
          // Explicit width: the table sits in a plain Column (default
          // center cross-axis alignment, loose constraints), so without
          // this the Container just shrink-wraps its Text instead of
          // spanning the table — the "floating pill" look this fixes.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
              color: Color(0xFFF8F9FB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Text(
              'Showing ${sorted.length} submission${sorted.length == 1 ? '' : 's'}',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detail View ───────────────────────────────────────────────────
  Widget _buildDetailView(EventReport event) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        children: [
          // Detail header
          Container(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _detailEvent = null),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Back to Reports List',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryDark.withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: UpriseColors.primaryDark,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A202C),
                            ),
                          ),
                          Text(
                            '${event.orgName} • ${event.type} • ${DateFormat('MMM dd, yyyy').format(event.date)}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _archiveEvent(event),
                          icon: const Icon(Icons.archive_outlined, size: 15),
                          label: Text(
                            'Archive',
                            style: GoogleFonts.beVietnamPro(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE2E6EA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(_DS.radiusSm),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () => _downloadEventPdf(event),
                          icon: const Icon(Icons.download_rounded, size: 15),
                          label: Text(
                            'Download PDF',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UpriseColors.primaryDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(_DS.radiusSm),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Detail body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              // One container for the whole report. This used to be seven
              // separately bordered and shadowed cards stacked down the
              // page — the properties box, an attendance stat row, a
              // participants card, a feedback card, a financial stat row
              // with two breakdown cards, and attachments — all repeating
              // the same chrome. They are sections of one box now,
              // separated by hairlines instead of gaps.
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                // Sections pair up two-across when there is room for them.
                // The switch reads LayoutBuilder's real content width rather
                // than MediaQuery's screen width, because the admin shell
                // swaps its 256px sidebar for a drawer at 900px: a 900px
                // screen leaves *less* room in here than an 899px one, so a
                // screen-width threshold would flip the layout the wrong way
                // around exactly that point.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 780;

                    // Registration & attendance — fetched on-demand for just
                    // this one event (cheap: two queries) rather than eagerly
                    // for every event in the list, which used to be the cause
                    // of the page-wide lag. Attendees comes from the real
                    // attendance subcollection (events/{id}/attendances),
                    // not the `registrations.attended` field, which nothing
                    // in the app ever actually writes to.
                    final attendanceBlock = Padding(
                      // 14 at the top rather than 18 so the first stat lines
                      // up with the properties grid's first _metaCell row
                      // across the divider.
                      padding: twoCol
                          ? const EdgeInsets.fromLTRB(18, 14, 18, 18)
                          : const EdgeInsets.all(18),
                      child: FutureBuilder<(int, int)>(
                        future: _loadEventAttendanceStats(event.id),
                        builder: (context, snapshot) {
                          final registrants = snapshot.data?.$1 ?? 0;
                          final attendees = snapshot.data?.$2 ?? 0;
                          final ratio = registrants > 0
                              ? ((attendees / registrants) * 100).round()
                              : 0;
                          final loading =
                              snapshot.connectionState ==
                              ConnectionState.waiting;
                          // There is no separate loading branch here and
                          // never was — `loading` just swaps the value for a
                          // dash, so both layouts below take the same
                          // arguments.
                          final rateColor = ratio >= 50
                              ? UpriseColors.success
                              : UpriseColors.warning;
                          final rateBg = ratio >= 50
                              ? UpriseColors.successBg
                              : UpriseColors.warningBg;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel(
                                'Attendance',
                                icon: Icons.how_to_reg_rounded,
                              ),
                              if (twoCol) ...[
                                // Narrow column: one stat per line.
                                _compactStatRow(
                                  'Registrants',
                                  loading ? '—' : '$registrants',
                                  UpriseColors.info,
                                  UpriseColors.infoBg,
                                  Icons.people_outline_rounded,
                                ),
                                _compactStatRow(
                                  'Attendees',
                                  loading ? '—' : '$attendees',
                                  UpriseColors.primaryDark,
                                  UpriseColors.primaryLight,
                                  Icons.check_circle_outline_rounded,
                                ),
                                _compactStatRow(
                                  'Attendance Rate',
                                  loading ? '—' : '$ratio%',
                                  rateColor,
                                  rateBg,
                                  Icons.donut_large_rounded,
                                ),
                              ] else
                                // Full width: the three cards across, as they
                                // sat before the two-column split.
                                Row(
                                  children: [
                                    _detailStatCard(
                                      'Registrants',
                                      loading ? '—' : '$registrants',
                                      UpriseColors.info,
                                      UpriseColors.infoBg,
                                      Icons.people_outline_rounded,
                                    ),
                                    const SizedBox(width: 14),
                                    _detailStatCard(
                                      'Attendees',
                                      loading ? '—' : '$attendees',
                                      UpriseColors.primaryDark,
                                      UpriseColors.primaryLight,
                                      Icons.check_circle_outline_rounded,
                                    ),
                                    const SizedBox(width: 14),
                                    _detailStatCard(
                                      'Attendance Rate',
                                      loading ? '—' : '$ratio%',
                                      rateColor,
                                      rateBg,
                                      Icons.donut_large_rounded,
                                    ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                    );

                    // Participants (attendees list)
                    final participantsBlock = Padding(
                      padding: const EdgeInsets.all(18),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _loadEventAttendeesList(event.id),
                        builder: (context, snap) {
                          final loadingA =
                              snap.connectionState == ConnectionState.waiting;
                          final attendeesList = snap.data ?? [];
                          // Flat: this is a section of the detail view's one
                          // container now, not a card of its own.
                          return SizedBox(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel(
                                  'Participants',
                                  icon: Icons.people_outline_rounded,
                                ),
                                const SizedBox(height: 8),
                                if (loadingA)
                                  const Center(
                                    child: SizedBox(
                                      height: 36,
                                      width: 36,
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (attendeesList.isEmpty)
                                  Text(
                                    'No attendees recorded.',
                                    style: GoogleFonts.beVietnamPro(
                                      color: const Color(0xFF64748B),
                                    ),
                                  )
                                else ...[
                                  ...attendeesList
                                      .take(5)
                                      .map(
                                        (a) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: _attendeeTile(a),
                                        ),
                                      ),
                                  if (attendeesList.length > 5) ...[
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () =>
                                            _showAllParticipantsDialog(
                                              event.title,
                                              attendeesList,
                                            ),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              UpriseColors.primaryDark,
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'View all ${attendeesList.length} participants',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    );

                    // Evaluation / Feedback
                    final feedbackBlock = Padding(
                      padding: const EdgeInsets.all(18),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _loadEventFeedbacks(event.id),
                        builder: (context, snap) {
                          final loadingF =
                              snap.connectionState == ConnectionState.waiting;
                          final feedbacks = snap.data ?? [];
                          final total = feedbacks.length;
                          final avg = total == 0
                              ? 0.0
                              : (feedbacks.fold<double>(
                                      0.0,
                                      (s, f) =>
                                          s +
                                          ((f['rating'] as num?)?.toDouble() ??
                                              0),
                                    ) /
                                    total);
                          final starCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
                          for (final f in feedbacks) {
                            final r = (f['rating'] as num?)?.toInt() ?? 0;
                            if (starCounts.containsKey(r))
                              starCounts[r] = starCounts[r]! + 1;
                          }
                          // Flat: this is a section of the detail view's one
                          // container now, not a card of its own.
                          return SizedBox(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel(
                                  'Evaluation & Feedback',
                                  icon: Icons.reviews_rounded,
                                ),
                                const SizedBox(height: 8),
                                if (loadingF)
                                  const Center(
                                    child: SizedBox(
                                      height: 36,
                                      width: 36,
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (feedbacks.isEmpty)
                                  Text(
                                    'No feedback recorded.',
                                    style: GoogleFonts.beVietnamPro(
                                      color: const Color(0xFF64748B),
                                    ),
                                  )
                                else ...[
                                  Row(
                                    children: [
                                      Text(
                                        'Average Rating',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        avg.toStringAsFixed(1),
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: UpriseColors.primaryDark,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '· $total feedbacks',
                                        style: GoogleFonts.beVietnamPro(
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...[5, 4, 3, 2, 1]
                                      .map(
                                        (star) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                child: Text(
                                                  '$star',
                                                  textAlign: TextAlign.right,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: const Color(
                                                          0xFF374151,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.star,
                                                size: 14,
                                                color: UpriseColors.primaryDark,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: LinearProgressIndicator(
                                                  value: total == 0
                                                      ? 0
                                                      : (starCounts[star]! /
                                                            total),
                                                  backgroundColor: const Color(
                                                    0xFFE8ECF0,
                                                  ),
                                                  color:
                                                      UpriseColors.primaryDark,
                                                  minHeight: 8,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 20,
                                                child: Text(
                                                  '${starCounts[star]}',
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        color: const Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  const SizedBox(height: 12),
                                  // Recent comments
                                  Column(
                                    children: feedbacks
                                        .take(3)
                                        .map(
                                          (f) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: _feedbackTile(f),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  if (feedbacks.length > 3) ...[
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () => _showAllFeedbackDialog(
                                          event.title,
                                          feedbacks,
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              UpriseColors.primaryDark,
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'View all ${feedbacks.length} feedback',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    );

                    // stretch, not the default center: _boxDivider is a
                    // height-1 Container with no width of its own, so a
                    // centering Column would render it as nothing.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Attendance beside the properties grid. IntrinsicHeight
                        // is load-bearing, not decoration: this sits in a
                        // SingleChildScrollView, so a stretch Row would
                        // otherwise be handed an infinite height to stretch to.
                        // _buildEventPropertiesSection already uses the same
                        // pairing for its own meta rows.
                        if (twoCol)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 1, child: attendanceBlock),
                                _vBoxDivider(),
                                Expanded(
                                  flex: 2,
                                  child: _buildEventPropertiesSection(event),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          _buildEventPropertiesSection(event),
                          _boxDivider(),
                          attendanceBlock,
                        ],
                        _boxDivider(),
                        // Participants beside evaluation & feedback. Both
                        // FutureBuilders are still siblings built in the same
                        // frame, so they still fetch in parallel.
                        if (twoCol)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: participantsBlock),
                                _vBoxDivider(),
                                Expanded(child: feedbackBlock),
                              ],
                            ),
                          )
                        else ...[
                          participantsBlock,
                          _boxDivider(),
                          feedbackBlock,
                        ],
                        _boxDivider(),
                        // The standalone "Event Summary" card that used to sit
                        // here held only event.description, which the info box at
                        // the top of this page now carries alongside the rest of
                        // the event's own properties.
                        // Financial stats — live totals computed from transactions.
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child:
                              StreamBuilder<
                                (
                                  double totalIncome,
                                  double totalExpenses,
                                  double netAmount,
                                  List<Map<String, dynamic>> incomeBreakdown,
                                  List<Map<String, dynamic>> expenseBreakdown,
                                  int transactionCount,
                                )
                              >(
                                stream: _eventTransactionSummaryStream(
                                  event.orgId,
                                  event.id,
                                  event.title,
                                ),
                                builder: (context, snapshot) {
                                  final loading =
                                      snapshot.connectionState ==
                                      ConnectionState.waiting;
                                  final totalIncome =
                                      snapshot.data?.$1 ?? event.totalIncome;
                                  final totalExpenses =
                                      snapshot.data?.$2 ?? event.totalExpenses;
                                  final netAmount =
                                      snapshot.data?.$3 ??
                                      (totalIncome - totalExpenses);
                                  final incomeBreakdown =
                                      snapshot.data?.$4 ??
                                      event.incomeBreakdown;
                                  final expenseBreakdown =
                                      snapshot.data?.$5 ??
                                      event.expenseBreakdown;
                                  final transactionCount =
                                      snapshot.data?.$6 ?? 0;
                                  final maxInc = incomeBreakdown.isEmpty
                                      ? 1.0
                                      : incomeBreakdown
                                            .map(
                                              (i) =>
                                                  (i['amount'] as num?)
                                                      ?.toDouble() ??
                                                  0.0,
                                            )
                                            .reduce((a, b) => a > b ? a : b);
                                  final maxExp = expenseBreakdown.isEmpty
                                      ? 1.0
                                      : expenseBreakdown
                                            .map(
                                              (i) =>
                                                  (i['amount'] as num?)
                                                      ?.toDouble() ??
                                                  0.0,
                                            )
                                            .reduce((a, b) => a > b ? a : b);

                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          _detailStatCard(
                                            'Total Income',
                                            loading
                                                ? '—'
                                                : '₱${_fmt(totalIncome)}',
                                            UpriseColors.success,
                                            UpriseColors.successBg,
                                            Icons.trending_up_rounded,
                                          ),
                                          const SizedBox(width: 14),
                                          _detailStatCard(
                                            'Total Expenses',
                                            loading
                                                ? '—'
                                                : '₱${_fmt(totalExpenses)}',
                                            UpriseColors.error,
                                            UpriseColors.errorBg,
                                            Icons.trending_down_rounded,
                                          ),
                                          const SizedBox(width: 14),
                                          _detailStatCard(
                                            'Net Amount',
                                            loading
                                                ? '—'
                                                : '₱${_fmt(netAmount)}',
                                            netAmount >= 0
                                                ? UpriseColors.success
                                                : UpriseColors.error,
                                            netAmount >= 0
                                                ? UpriseColors.successBg
                                                : UpriseColors.errorBg,
                                            Icons
                                                .account_balance_wallet_rounded,
                                          ),
                                          const SizedBox(width: 14),
                                          _detailStatCard(
                                            'Transactions',
                                            loading ? '—' : '$transactionCount',
                                            UpriseColors.primaryDark,
                                            UpriseColors.primaryLight,
                                            Icons.receipt_long_rounded,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // Breakdowns
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _breakdownCard(
                                              'Income Breakdown',
                                              incomeBreakdown,
                                              maxInc,
                                              UpriseColors.success,
                                              Icons.trending_up_rounded,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: _breakdownCard(
                                              'Expense Breakdown',
                                              expenseBreakdown,
                                              maxExp,
                                              UpriseColors.error,
                                              Icons.trending_down_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                        ),
                        if (event.attachments.isNotEmpty) ...[
                          _boxDivider(),
                          _attachmentsCard(event.attachments),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendeeTile(Map<String, dynamic> a) {
    final name = a['studentName'] ?? a['studentId'] ?? 'Unknown';
    final email = a['studentEmail'] ?? '';
    final status = a['status'] ?? '';
    final ts = a['timestamp'] is DateTime ? a['timestamp'] as DateTime : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${email.isNotEmpty ? '$email · ' : ''}${status.toString().toUpperCase()}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        Text(
          ts != null ? DateFormat('MMM dd, HH:mm').format(ts) : '',
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _feedbackTile(Map<String, dynamic> f) {
    final author = f['authorName'] ?? f['userName'] ?? 'Anonymous';
    final rating = (f['rating'] as num?)?.toInt() ?? 0;
    final comment = f['comment']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              author,
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '· $rating★',
              style: GoogleFonts.beVietnamPro(
                color: const Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            comment,
            style: GoogleFonts.beVietnamPro(color: const Color(0xFF374151)),
          ),
        ],
      ],
    );
  }

  // Shared "View all" modal shell for Participants/Feedback — a scrollable
  // list under a gradient header, matching the rest of the app's dialogs,
  // so browsing 50 attendees doesn't mean scrolling the whole detail page.
  void _showListModal({
    required String title,
    required String subtitle,
    required IconData icon,
    required int count,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 520,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFAF5),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      UpriseColors.primaryDark,
                      UpriseColors.primaryDark.withAlpha(225),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 18),
                    ),

                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$title ($count)',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withAlpha(220),
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
                  padding: const EdgeInsets.all(20),
                  shrinkWrap: true,
                  itemCount: count,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 20, color: Color(0xFFF1F5F9)),
                  itemBuilder: itemBuilder,
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
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

  void _showAllParticipantsDialog(
    String eventTitle,
    List<Map<String, dynamic>> attendeesList,
  ) {
    _showListModal(
      title: 'Participants',
      subtitle: eventTitle,
      icon: Icons.people_outline_rounded,
      count: attendeesList.length,
      itemBuilder: (context, i) => _attendeeTile(attendeesList[i]),
    );
  }

  void _showAllFeedbackDialog(
    String eventTitle,
    List<Map<String, dynamic>> feedbacks,
  ) {
    _showListModal(
      title: 'Feedback',
      subtitle: eventTitle,
      icon: Icons.reviews_rounded,
      count: feedbacks.length,
      itemBuilder: (context, i) => _feedbackTile(feedbacks[i]),
    );
  }

  Widget _detailStatCard(
    String label,
    String value,
    Color color,
    Color bgColor,
    IconData icon,
  ) {
    // Flat: every call site now lives inside the detail view's single
    // container, so a border and shadow here would just draw a card inside
    // a card. Still an Expanded — both call sites place it directly in a
    // Row and rely on it dividing the width.
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
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

  // The narrow-column twin of _detailStatCard. _detailStatCard is sized for a
  // Row — it returns an Expanded and puts the value under the label — which
  // leaves it far too tall and wide once the attendance stats stack down a
  // one-third column beside the properties grid. Same icon chip, same colors,
  // just slimmer: label and value on one line, and no Expanded, because this
  // goes in a Column.
  Widget _compactStatRow(
    String label,
    String value,
    Color color,
    Color bgColor,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Single income/expense row (name, amount, progress bar) — pulled out of
  // _breakdownCard so it can be reused both in the capped inline preview
  // and in the "View all" modal below.
  Widget _breakdownItemTile(
    Map<String, dynamic> item,
    double maxVal,
    Color color,
  ) {
    final amt = (item['amount'] as num?)?.toDouble() ?? 0;
    final ratio = maxVal > 0 ? amt / maxVal : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                item['name']?.toString() ?? '',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₱${_fmt(amt)}',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio.toDouble(),
            backgroundColor: const Color(0xFFE8ECF0),
            color: color,
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  // Capped at 5 rows + a "View all" link into the shared scrollable modal —
  // previously rendered every income/expense entry inline with no limit,
  // which made this card (and the page under it) grow as long as however
  // many transactions the event had.
  Widget _breakdownCard(
    String title,
    List<Map<String, dynamic>> items,
    double maxVal,
    Color color,
    IconData icon,
  ) {
    // Flat — see _detailStatCard. This sits inside the detail view's one
    // container now, so it only needs its padding.
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(title, icon: icon),
          if (items.isEmpty)
            Text(
              'No breakdown data.',
              style: GoogleFonts.beVietnamPro(
                color: const Color(0xFF64748B),
                fontSize: 13,
              ),
            )
          else ...[
            ...items
                .take(5)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _breakdownItemTile(item, maxVal, color),
                  ),
                ),
            if (items.length > 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showListModal(
                    title: title,
                    subtitle: '${items.length} entries',
                    icon: icon,
                    count: items.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _breakdownItemTile(items[i], maxVal, color),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: UpriseColors.primaryDark,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'View all ${items.length} entries',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _notesCard(String title, List<String> notes, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(title, icon: icon),
          if (notes.isEmpty)
            Text(
              'No entries recorded.',
              style: GoogleFonts.beVietnamPro(
                color: const Color(0xFF64748B),
                fontSize: 13,
              ),
            )
          else
            ...notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 42,
                      margin: const EdgeInsets.only(right: 10, top: 2),
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryDark.withAlpha(76),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        note,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF374151),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attachmentsCard(List<Map<String, dynamic>> attachments) {
    // Flat — see _detailStatCard. Pads itself since it is placed straight
    // into the container's Column rather than through a Padding wrapper.
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Attachments', icon: Icons.attach_file_rounded),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: attachments.map((att) {
              final name = att['name']?.toString() ?? 'File';
              final size = att['size']?.toString() ?? '';
              final fileUrl = att['fileUrl']?.toString() ?? '';
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening: $fileUrl'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_DS.radiusSm),
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E6EA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: UpriseColors.infoBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.insert_drive_file_outlined,
                            color: UpriseColors.info,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              size,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.download_outlined,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// One label-over-value cell of the event info box.
  ///
  /// [child] renders a widget instead of the plain value text — used for the
  /// category chip and the report-status badges so they match how the same
  /// facts are drawn elsewhere on the page.
  ///
  /// The value now wraps to two lines. It was capped at one with an
  /// ellipsis, which truncated most real venue names ("BulSU Gymnasium,
  /// Malolos Campus") down to something unreadable in a cell this narrow.
  Widget _metaCell(
    String key,
    String value, {
    bool last = false,
    bool lastRow = false,
    Widget? child,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : const BorderSide(color: Color(0xFFE8ECF0)),
            bottom: lastRow
                ? BorderSide.none
                : const BorderSide(color: Color(0xFFE8ECF0)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key,
              style: GoogleFonts.beVietnamPro(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            if (child != null)
              Align(alignment: Alignment.centerLeft, child: child)
            else
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A202C),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Report status for one event, resolved from the submission rows that
  /// `_loadSubmissionData()` already loaded in initState — no extra query.
  /// Returns a key `_statusBadge` understands.
  String _reportStatusFor(List<OrgSubmission> subs, EventReport event) {
    final match = subs.where((s) => s.eventId == event.id).toList();
    if (match.isEmpty) return 'pending';
    final sub = match.first;
    if (sub.submittedAt == null) {
      final deadline = sub.eventDeadline;
      final overdue = deadline != null && DateTime.now().isAfter(deadline);
      return overdue ? 'overdue' : 'pending';
    }
    return sub.isLate ? 'late' : 'on time';
  }

  /// The event's own properties — the first section of the detail view's
  /// single container. Carries everything the event document knows about
  /// itself, including the description that used to have a card of its own
  /// further down the page.
  Widget _buildEventPropertiesSection(EventReport event) {
    String orDash(String v) => v.trim().isEmpty ? '—' : v.trim();

    final timeRange = (event.startTime.isEmpty && event.endTime.isEmpty)
        ? '—'
        : '${orDash(event.startTime)} – ${orDash(event.endTime)}';
    final term = [
      if (event.schoolYear.isNotEmpty) event.schoolYear,
      if (event.semester.isNotEmpty) event.semester,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metaCell('ORGANIZATION', orDash(event.orgName)),
              _metaCell(
                'EVENT TYPE',
                event.type,
                child: _EventCategoryChip(type: event.type),
              ),
              _metaCell(
                'STATUS',
                event.status == 'archived' ? 'Archived' : 'Approved',
                last: true,
              ),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metaCell('DATE', DateFormat('MMM dd, yyyy').format(event.date)),
              _metaCell('TIME', timeRange),
              _metaCell('LOCATION', orDash(event.location), last: true),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metaCell('AUDIENCE', orDash(event.audience)),
              _metaCell(
                'CAPACITY',
                event.capacity == null ? 'Unlimited' : '${event.capacity}',
              ),
              _metaCell('TERM', orDash(term), last: true),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metaCell(
                'CERTIFICATES',
                event.issuesCertificate ? 'Issued' : 'Not issued',
                lastRow: true,
              ),
              _metaCell(
                'FINANCIAL REPORT',
                '',
                lastRow: true,
                child: _statusBadge(_reportStatusFor(_financialSubs, event)),
              ),
              _metaCell(
                'ACCOMPLISHMENT REPORT',
                '',
                last: true,
                lastRow: true,
                child: _statusBadge(
                  _reportStatusFor(_accomplishmentSubs, event),
                ),
              ),
            ],
          ),
        ),
        // Description lives here rather than in a card of its own further
        // down — it is a property of the event like everything above it.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DESCRIPTION',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                event.description.trim().isEmpty
                    ? 'No summary provided.'
                    : event.description.trim(),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  height: 1.55,
                  color: event.description.trim().isEmpty
                      ? const Color(0xFF9AA5B4)
                      : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Hairline between sections of the detail container.
  Widget _boxDivider() => Container(height: 1, color: const Color(0xFFE8ECF0));

  /// Hairline between two side-by-side columns of one detail section.
  /// Mirrors _boxDivider(); has no height of its own, so the parent Row must
  /// use CrossAxisAlignment.stretch inside an IntrinsicHeight.
  Widget _vBoxDivider() => Container(width: 1, color: const Color(0xFFE8ECF0));

  // ── Dialogs ───────────────────────────────────────────────────────
  void _viewSubmission(OrgSubmission sub, String reportType) {
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
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      UpriseColors.primaryDark,
                      UpriseColors.primaryDark.withAlpha(225),
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
                        Icons.assignment_turned_in_rounded,
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
                            '$reportType Report',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            sub.orgName,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withAlpha(179),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _credentialRow(
                        label: sub.isPeriodScope ? 'For Period' : 'For Event',
                        value: sub.isPeriodScope
                            ? sub.displayTitle
                            : (sub.eventDate != null
                                  ? '${sub.eventTitle} (${DateFormat('MMM dd, yyyy').format(sub.eventDate!)})'
                                  : (sub.eventTitle ?? '—')),
                        icon: sub.isPeriodScope
                            ? Icons.school_outlined
                            : Icons.event_rounded,
                      ),
                      const SizedBox(height: 12),
                      _credentialRow(
                        label: 'Submitted On',
                        value: DateFormat(
                          'MMMM dd, yyyy HH:mm',
                        ).format(sub.submittedAt!),
                        icon: Icons.calendar_today_rounded,
                      ),
                      const SizedBox(height: 12),
                      _credentialRow(
                        label: 'File',
                        value:
                            sub.fileBase64 != null && sub.fileBase64!.isNotEmpty
                            ? (sub.fileName ?? 'Attached file')
                            : 'No file attached.',
                        icon: Icons.attach_file_rounded,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (sub.fileBase64 != null &&
                        sub.fileBase64!.isNotEmpty) ...[
                      ElevatedButton.icon(
                        onPressed: () => _openSubmissionFile(
                          sub.fileBase64!,
                          sub.fileName ?? 'document',
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: Text(
                          'Open File',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UpriseColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _downloadSubmissionFile(
                          sub.fileBase64!,
                          sub.fileName ?? 'document',
                        ),
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: Text(
                          'Download File',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UpriseColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
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

  Widget _credentialRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: UpriseColors.primaryDark.withAlpha(150),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: SelectableText(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A202C),
            ),
          ),
        ),
      ],
    );
  }

  // The file lives as base64 directly on the Firestore doc (no Storage, no
  // URL) — build a data: URI on demand from it, mirroring _openAttachment's
  // pattern on _ViewAdminReportModal for the same fileBase64/fileName shape.
  void _openSubmissionFile(String fileBase64, String fileName) {
    try {
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final mime = _ViewAdminReportModal._mimeFromExt(ext);
      final anchor = html.AnchorElement(href: 'data:$mime;base64,$fileBase64')
        ..target = '_blank';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Opening file in a new tab...'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  void _downloadSubmissionFile(String fileBase64, String fileName) {
    try {
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final mime = _ViewAdminReportModal._mimeFromExt(ext);
      final anchor = html.AnchorElement(href: 'data:$mime;base64,$fileBase64')
        ..target = '_blank'
        ..download = fileName;
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Download started...'),
          backgroundColor: UpriseColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not download file: $e'),
          backgroundColor: UpriseColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
    }
  }

  // Actually sends a push/in-app notification to every member of the org
  // (previously this just showed a "Reminder sent" snackbar with nothing
  // behind it — no notification, no Firestore write, nothing — so orgs
  // never actually heard about it). Returns true on success so callers
  // sending to several orgs at once can tally results.
  Future<bool> _sendReminder(
    OrgSubmission sub,
    String reportType, {
    bool showSnack = true,
  }) async {
    if (!sub.hasApprovedEvent) {
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No approved event found for ${sub.orgName}. Reminder not sent.',
            ),
            backgroundColor: UpriseColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_DS.radiusSm),
            ),
          ),
        );
      }
      return false;
    }

    final eventLabel = sub.eventTitle != null ? ' (${sub.eventTitle})' : '';
    final when = sub.eventDate != null
        ? ' on ${DateFormat('MMM dd, yyyy').format(sub.eventDate!)}'
        : '';
    try {
      await NotificationService.sendToOrgMembers(
        orgId: sub.orgId,
        title:
            '${reportType[0].toUpperCase()}${reportType.substring(1)} report overdue',
        body:
            'Your $reportType report for "${sub.displayTitle}" is overdue. '
            'Please submit it as soon as possible.',
        type: 'deadline_reminder',
        data: {'orgId': sub.orgId, 'reportType': reportType},
      );
      await activity_log.ActivityLogger.log(
        action: 'Sent $reportType report reminder to ${sub.orgName}$eventLabel',
        module: 'Reports',
        severity: 'info',
        orgId: sub.orgId,
      );
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reminder sent to ${sub.orgName}$eventLabel for $reportType report$when',
            ),
            backgroundColor: UpriseColors.primaryDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_DS.radiusSm),
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reminder to ${sub.orgName}: $e'),
            backgroundColor: UpriseColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_DS.radiusSm),
            ),
          ),
        );
      }
      return false;
    }
  }

  // Sends a reminder to every org currently shown as overdue for this
  // report type (respects the active search/org filter), in one click
  // instead of clicking "Send Reminder" per row.
  Future<void> _sendReminderToAllOverdue(
    List<OrgSubmission> submissions,
    String reportType,
  ) async {
    final now = DateTime.now();
    final overdue = _filterSubmissionRows(submissions).where((s) {
      final deadline = s.eventDeadline;
      return s.submittedAt == null && deadline != null && now.isAfter(deadline);
    }).toList();

    if (overdue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No overdue submissions to remind right now.'),
          backgroundColor: UpriseColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _ConfirmDialog(
        title: 'Send Reminder to All',
        message:
            'Send an overdue-report reminder to ${overdue.length} '
            'organization${overdue.length == 1 ? '' : 's'}?',
        confirmLabel: 'Send',
      ),
    );
    if (confirmed != true) return;

    int sent = 0;
    for (final sub in overdue) {
      final ok = await _sendReminder(sub, reportType, showSnack: false);
      if (ok) sent++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent == overdue.length
              ? 'Reminder sent to $sent organization${sent == 1 ? '' : 's'}.'
              : 'Sent $sent of ${overdue.length} reminders — some failed.',
        ),
        backgroundColor: sent == overdue.length
            ? UpriseColors.primaryDark
            : UpriseColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────
  String _fmt(double value) => NumberFormat('#,##0.00', 'en_PH').format(value);
  String _fmtK(double value) {
    if (value.abs() >= 1000000)
      return '${NumberFormat('#,##0.0', 'en_PH').format(value / 1000000)}M';
    if (value.abs() >= 1000)
      return '${NumberFormat('#,##0.0', 'en_PH').format(value / 1000)}K';
    return NumberFormat('#,##0.00', 'en_PH').format(value);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View Admin Report Modal
// ─────────────────────────────────────────────────────────────────────────────
class _ViewAdminReportModal extends StatelessWidget {
  final AdminReport report;
  const _ViewAdminReportModal({required this.report});

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFinancial = report.type == 'financial';
    final hasFile = report.fileBase64 != null && report.fileBase64!.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 500,
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
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    UpriseColors.primaryDark,
                    UpriseColors.primaryDark.withAlpha(225),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha(70)),
                    ),
                    child: const Icon(
                      Icons.article_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Details',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          report.orgName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: Colors.white.withAlpha(179),
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
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event Title
                    Text(
                      report.eventTitle,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _detailItem(
                            'Organization',
                            report.orgName,
                            Icons.business_rounded,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _detailItem(
                            'Type',
                            isFinancial
                                ? 'Financial Report'
                                : 'Accomplishment Report',
                            Icons.label_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _detailItem(
                            'Date Submitted',
                            DateFormat(
                              'MMM dd, yyyy',
                            ).format(report.submittedAt),
                            Icons.calendar_today_outlined,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _detailItem(
                            'Event',
                            report.eventTitle,
                            Icons.event_rounded,
                          ),
                        ),
                      ],
                    ),
                    if (report.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _detailItem(
                        'Description',
                        report.description,
                        Icons.notes_rounded,
                      ),
                    ],
                    // File Attachment
                    if (hasFile) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: UpriseColors.primaryDark.withAlpha(26),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.insert_drive_file_rounded,
                                size: 20,
                                color: UpriseColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    report.fileName ?? 'Attached File',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (report.fileSize != null)
                                    Text(
                                      report.fileSize!,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _openAttachment(context),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 15,
                              ),
                              label: const Text('Open'),
                              style: TextButton.styleFrom(
                                foregroundColor: UpriseColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
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
    );
  }

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
            Icon(
              icon,
              size: 13,
              color: UpriseColors.primaryDark.withAlpha(150),
            ),
            const SizedBox(width: 5),
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

  Future<void> _openAttachment(BuildContext context) async {
    final b64 = report.fileBase64;
    if (b64 == null || b64.isEmpty) return;
    try {
      final bytes = base64Decode(b64);
      final name = report.fileName ?? 'document';
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFromExt(ext);

      if (mime.startsWith('image/')) {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    name,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                ),
                Flexible(child: Image.memory(bytes)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (mime == 'text/plain') {
        final text = utf8.decode(bytes);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              name,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A202C),
              ),
            ),
            content: SingleChildScrollView(
              child: SelectableText(
                text,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF374151),
                  side: const BorderSide(color: Color(0xFFE2E6EA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                ),
              ),
            ],
          ),
        );
      } else {
        // Use platform_file_utils if available, otherwise fallback
        try {
          await platform_file_utils.saveBytesToTempAndOpen(
            bytes,
            name,
            mimeType: mime,
          );
        } catch (e) {
          // Fallback: download via HTML
          final anchor = html.AnchorElement(href: 'data:$mime;base64,$b64')
            ..download = name
            ..target = '_blank';
          html.document.body?.append(anchor);
          anchor.click();
          anchor.remove();
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening attachment: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Container(
      width: 420,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: destructive
                      ? const Color(0xFFFEF2F2)
                      : UpriseColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  destructive
                      ? Icons.delete_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: destructive
                      ? const Color(0xFFDC2626)
                      : UpriseColors.primaryDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: const Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2E6EA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF374151),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: destructive
                      ? const Color(0xFFDC2626)
                      : UpriseColors.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String hint;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnchoredMenuTrigger<String>(
      items: items,
      labelOf: (s) => s,
      selectedValue: value,
      onSelected: onChanged,
      trigger: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final VoidCallback onExportCsv, onExportPdf;
  const _ExportButton({required this.onExportCsv, required this.onExportPdf});

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      onSelected: (choice) {
        if (choice == 'excel') onExportCsv();
        if (choice == 'pdf') onExportPdf();
      },
    );
  }
}

// Shared event-category styling — used by both the icon badge next to the
// event title and the category chip in the TYPE column, so they always
// agree with each other.
_IconStyle _eventTypeStyle(String type) {
  const styles = {
    'Seminar': _IconStyle(
      Color(0xFFEFF6FF),
      Color(0xFF2563EB),
      Icons.mic_rounded,
    ),
    'Workshop': _IconStyle(
      Color(0xFFFFF7ED),
      Color(0xFFEA580C),
      Icons.build_rounded,
    ),
    'Exhibition': _IconStyle(
      Color(0xFFF5F3FF),
      Color(0xFF7C3AED),
      Icons.museum_rounded,
    ),
    'Social': _IconStyle(
      Color(0xFFFCE7F3),
      Color(0xFFDB2777),
      Icons.people_rounded,
    ),
    'Cultural': _IconStyle(
      Color(0xFFF0FDF4),
      Color(0xFF16A34A),
      Icons.celebration_rounded,
    ),
    'Competition': _IconStyle(
      Color(0xFFFEFCE8),
      Color(0xFFCA8A04),
      Icons.emoji_events_rounded,
    ),
  };
  return styles[type] ??
      const _IconStyle(
        Color(0xFFF3F4F6),
        Color(0xFF6B7280),
        Icons.event_rounded,
      );
}

class _EventIcon extends StatelessWidget {
  final String type;
  const _EventIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final s = _eventTypeStyle(type);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(s.icon, color: s.fg, size: 15),
    );
  }
}

// Category chip for the TYPE column — shrink-wraps to its text (via the
// Align wrapper at the call site) instead of stretching the whole column,
// matching the category-chip convention used on the other admin pages.
class _EventCategoryChip extends StatelessWidget {
  final String type;
  const _EventCategoryChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final s = _eventTypeStyle(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type,
        maxLines: 1,
        softWrap: false,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.fg,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _IconStyle {
  final Color bg, fg;
  final IconData icon;
  const _IconStyle(this.bg, this.fg, this.icon);
}

class _OrgAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  const _OrgAvatar({required this.name, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(imageUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    // fallback: initials
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: UpriseColors.primaryDark.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: UpriseColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = onTap == null
        ? const Color(0xFFD1D5DB)
        : (color ?? const Color(0xFF64748B));
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: effectiveColor.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: effectiveColor),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.chevron_left_rounded
          ? 'Previous Page'
          : 'Next Page',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}

class _PageNumButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;
  const _PageNumButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? UpriseColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$page',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
