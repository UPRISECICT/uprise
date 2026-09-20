// lib/screens/web/org/org_event_analytics.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../theme/org_theme.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/stat_cards.dart';
import '../../../widgets/app_toast.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'package:fl_chart/fl_chart.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _DS {
  // Card radius matches StatCardTokens.radius (12) so the KPI cards and the
  // chart cards below them read as one family rather than two.
  static const double radiusMd = 12;

  // One 4px spacing scale for the whole screen. The gaps between sections
  // were 14/14/20 and the paddings 20/18/16/14 - close enough to look
  // accidental rather than deliberate.
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;

  // Matches the single flat drop shadow every other org screen's cards
  // use (dashboard, calendar, certificates, finance, merchandise, etc.)
  // instead of a two-layer "clay" shadow unique to this screen.
  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // Soft fade-out divider — replaces flat 1px gray Divider lines, which
  // read as harsh/out-of-place against the soft-shadowed clay cards.
  static Widget fadeDivider({double height = 1}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, _C.border, Colors.transparent],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }

  // The one card surface for every section on this screen. Each section used
  // to build its own BoxDecoration and they had drifted apart - two used a
  // half-alpha border, one a full one - and the page then wrapped the lot in
  // a *fourth* card, so white cards sat on a white card and the shadows
  // cancelled instead of separating anything.
  static BoxDecoration card() => BoxDecoration(
    color: _C.white,
    borderRadius: BorderRadius.circular(radiusMd),
    border: Border.all(color: _C.border),
    boxShadow: cardShadow,
  );
}

// ── Color aliases ────────────────────────────────────────────────────────────
class _C {
  // The four loose KPI accents that used to live here - amber, green, red
  // and blue - are gone. They tinted the four summary cards in four hues
  // for four things that are not four categories of anything, which is
  // decoration, not encoding. The cards now take chartBrand like the rest
  // of the page, and the only non-brand hues left in this file are the
  // three status steps below, which each carry a meaning.

  // Matches the 0xFFFBFCFE Scaffold background every other org screen uses.
  static const Color surface = Color(0xFFFBFCFE);
  // Matches StatCardTokens.border so the KPI cards and the chart cards
  // underneath share one edge colour (was 0xFFE2E8F0, a half-step off).
  static const Color border = Color(0xFFE8ECF0);
  static const Color muted = Color(0xFF64748B);
  static const Color charcoal = Color(0xFF0F172A);
  static const Color white = Color(0xFFFFFFFF);

  // -- Chart tokens ---------------------------------------------------------
  //
  // Every bar chart here plots ONE measure across events, so it is a single
  // series and takes a single hue. Colouring a bar by its own value (which
  // the rating chart used to do) re-encodes what the bar's height already
  // says and spends the colour channel for nothing.
  //
  // The brand primary is the hue for the count charts (registrations,
  // attendance, ratings by event). The two money tabs deliberately break
  // from it - income and expense read faster in the conventional green/red -
  // and they borrow the status steps below rather than introducing a second
  // green and a second red, so one green means "good" everywhere here.
  static const Color chartBrand = UpriseColors.primaryDark;

  // Recessive hairline grid - one step off the card surface.
  static const Color grid = Color(0xFFF1F5F9);

  // Star ratings are an ORDINAL scale, so they take a one-hue ramp with
  // monotone lightness (5 = darkest) rather than the green->amber->red
  // rainbow this used to draw. Validated as an ordinal ramp against the
  // white card: monotone L, every adjacent gap >= 0.06, light end 2.18:1,
  // hue spread 9 degrees.
  static const Color rating5 = Color(0xFF7A2E00);
  static const Color rating4 = Color(0xFFA83E00);
  static const Color rating3 = Color(0xFFC85A1C);
  static const Color rating2 = Color(0xFFDE7D45);
  static const Color rating1 = Color(0xFFEA9E70);

  // Attendance IS a status scale (good / warning / critical), so it keeps
  // reserved status steps instead of the ordinal ramp. A darker amber was
  // tried for "Late" and rejected: it collapses to deltaE 1.7 against the
  // green under deuteranopia, where this lighter step holds 11.3. It sits
  // below 3:1 on white by design - the legend label + count beside every
  // wedge is the required relief, so the colour never carries meaning alone.
  static const Color statusGood = Color(0xFF0CA30C);
  static const Color statusWarning = Color(0xFFFAB219);
  static const Color statusCritical = Color(0xFFD03B3B);

  // Neutral chip behind the donut legend percentages. The percentage used to
  // be set in the slice's own colour on a 10%-alpha wash of it, which put
  // the lightest steps (status warning, rating1) at ~1.8:1 as *text*. The
  // coloured dot beside the label already carries identity, so the number
  // goes back to ink.
  static const Color chipBg = Color(0xFFF3F5F7);
}

// ── Data model ───────────────────────────────────────────────────────────────
class _AnalyticsData {
  final List<Map<String, dynamic>> feedbacks;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> registrations;
  final List<Map<String, dynamic>> attendances;

  final Map<String, String> _eventTitleCache = {};

  _AnalyticsData({
    required this.feedbacks,
    this.transactions = const [],
    this.registrations = const [],
    this.attendances = const [],
    required this.events,
  });

  int get totalFeedbacks => feedbacks.length;

  int get totalRegistrations => registrations.length;

  Map<String, int> get registrationCountByEvent {
    final Map<String, int> c = {};
    for (final r in registrations) {
      final id = r['eventId'] as String? ?? '';
      if (id.isEmpty) continue;
      c[id] = (c[id] ?? 0) + 1;
    }
    return c;
  }

  Map<String, int> get attendanceDocCountByEvent {
    final Map<String, int> c = {};
    for (final a in attendances) {
      final id = a['eventId'] as String? ?? '';
      if (id.isEmpty) continue;
      c[id] = (c[id] ?? 0) + 1;
    }
    return c;
  }

  Map<String, int> get presentOrLateCountByEvent {
    final Map<String, int> c = {};
    for (final a in attendances) {
      final id = a['eventId'] as String? ?? '';
      if (id.isEmpty) continue;
      final status = a['status'] as String?;
      if (status != 'present' && status != 'late') continue;
      c[id] = (c[id] ?? 0) + 1;
    }
    return c;
  }

  // Per event, "slots" = max(registered, attendance docs) — mirrors the
  // Registration/Attendance tab math in org_events_schedule.dart, since an
  // event can have walk-in attendance docs with no matching registration
  // (or vice versa). Overall rate is attended slots / total slots.
  double get attendanceRate {
    final regByEvent = registrationCountByEvent;
    final attDocsByEvent = attendanceDocCountByEvent;
    final attendedByEvent = presentOrLateCountByEvent;
    final eventIds = {...regByEvent.keys, ...attDocsByEvent.keys};
    if (eventIds.isEmpty) return 0;

    int totalSlots = 0;
    int totalAttended = 0;
    for (final id in eventIds) {
      final slots = math.max(regByEvent[id] ?? 0, attDocsByEvent[id] ?? 0);
      totalSlots += slots;
      totalAttended += attendedByEvent[id] ?? 0;
    }
    if (totalSlots == 0) return 0;
    return totalAttended / totalSlots * 100;
  }

  // Org-wide Present/Late/Absent split — same "slots" math as
  // attendanceRate above, just broken out by status instead of collapsed
  // into a single attended/not-attended rate.
  Map<String, int> get attendanceStatusBreakdown {
    final regByEvent = registrationCountByEvent;
    final attDocsByEvent = attendanceDocCountByEvent;
    final eventIds = {...regByEvent.keys, ...attDocsByEvent.keys};

    int totalSlots = 0;
    for (final id in eventIds) {
      totalSlots += math.max(regByEvent[id] ?? 0, attDocsByEvent[id] ?? 0);
    }

    final present = attendances.where((a) => a['status'] == 'present').length;
    final late = attendances.where((a) => a['status'] == 'late').length;
    final absent = (totalSlots - present - late).clamp(0, totalSlots);

    return {'present': present, 'late': late, 'absent': absent};
  }

  // Registered vs. attended per event, keyed by event id (chart widgets
  // resolve the display title via eventDisplayTitle(), same as avgByEvent).
  Map<String, ({int registered, int attended})>
  get registrationVsAttendanceByEvent {
    final regByEvent = registrationCountByEvent;
    final attendedByEvent = presentOrLateCountByEvent;
    final eventIds = {...regByEvent.keys, ...attendanceDocCountByEvent.keys};
    final out = <String, ({int registered, int attended})>{};
    for (final id in eventIds) {
      out[id] = (
        registered: regByEvent[id] ?? 0,
        attended: attendedByEvent[id] ?? 0,
      );
    }
    return out;
  }

  double get avgRating {
    if (feedbacks.isEmpty) return 0;
    final sum = feedbacks.fold<int>(
      0,
      (s, f) => s + (f['rating'] as int? ?? 0),
    );
    return sum / feedbacks.length;
  }

  Map<String, double> get avgByEvent {
    final Map<String, List<int>> byEvent = {};
    for (final f in feedbacks) {
      final id = f['eventId'] as String? ?? '';
      byEvent.putIfAbsent(id, () => []).add(f['rating'] as int? ?? 0);
    }
    return byEvent.map(
      (k, v) => MapEntry(k, v.reduce((a, b) => a + b) / v.length),
    );
  }

  Map<int, int> get starCounts {
    final Map<int, int> c = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final f in feedbacks) {
      final r = f['rating'] as int? ?? 0;
      if (c.containsKey(r)) c[r] = c[r]! + 1;
    }
    return c;
  }

  Map<String, int> get feedbackCountByEvent {
    final Map<String, int> c = {};
    for (final f in feedbacks) {
      final id = f['eventId'] as String? ?? '';
      c[id] = (c[id] ?? 0) + 1;
    }
    return c;
  }

  String eventTitle(String eventId) {
    if (_eventTitleCache.containsKey(eventId)) {
      return _eventTitleCache[eventId]!;
    }

    String result = eventId;

    for (final event in events) {
      final id = event['id'] as String? ?? '';
      if (id == eventId) {
        final title = event['title'] as String? ?? '';
        if (title.isNotEmpty) {
          _eventTitleCache[eventId] = title;
          return title;
        }
      }
    }

    for (final event in events) {
      final evEventId = event['eventId'] as String? ?? '';
      if (evEventId == eventId) {
        final title = event['title'] as String? ?? '';
        if (title.isNotEmpty) {
          _eventTitleCache[eventId] = title;
          return title;
        }
      }
    }

    for (final event in events) {
      final title = event['title'] as String? ?? '';
      if (title == eventId) {
        _eventTitleCache[eventId] = title;
        return title;
      }
    }

    for (final event in events) {
      final title = event['title'] as String? ?? '';
      if (title.isNotEmpty && eventId.isNotEmpty) {
        if (title.contains(eventId) || eventId.contains(title)) {
          _eventTitleCache[eventId] = title;
          return title;
        }
      }
    }

    _eventTitleCache[eventId] = result;
    return result;
  }

  String eventDisplayTitle(String eventId) {
    if (eventId.isEmpty) return 'Unknown event';
    final title = eventTitle(eventId);
    if (title == eventId) return 'Deleted / unlinked event';
    return title;
  }

  // Per-event income/expense rollup, keyed by event TITLE — transactions
  // only reliably denormalize `eventName` (not a matching `eventId`), so
  // title is the one identity finance data can safely resolve an event by.
  Map<String, ({double income, double expense})> get financeByEventTitle {
    final Map<String, ({double income, double expense})> out = {};
    for (final t in transactions) {
      if (t['isArchived'] == true) continue;
      final name = (t['eventName'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final amount = (t['amount'] as num?)?.toDouble() ?? 0;
      final isIncome = (t['type'] as String? ?? 'income') == 'income';
      final current = out[name] ?? (income: 0.0, expense: 0.0);
      out[name] = (
        income: current.income + (isIncome ? amount : 0),
        expense: current.expense + (isIncome ? 0 : amount),
      );
    }
    return out;
  }

  ({double income, double expense})? financeForEvent(String eventTitle) =>
      financeByEventTitle[eventTitle];
}

// ════════════════════════════════════════════════════════════════════════════
// Screen
// ════════════════════════════════════════════════════════════════════════════
class OrgEventAnalyticsScreen extends StatefulWidget {
  final String orgId;
  const OrgEventAnalyticsScreen({super.key, required this.orgId});

  @override
  State<OrgEventAnalyticsScreen> createState() =>
      _OrgEventAnalyticsScreenState();
}

class _OrgEventAnalyticsScreenState extends State<OrgEventAnalyticsScreen> {
  late Future<_AnalyticsData> _dataFuture;

  // Every collection _loadAll() reads is watched, so the page keeps itself
  // current and there is no Refresh button to press. It used to watch only
  // the two feedback collections, which made the "Live sync" chip a
  // half-truth: ratings updated on their own, but a new event, a new
  // registration, an attendance check-in or a finance entry sat stale until
  // someone refreshed by hand.
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _subscriptions = [];

  // One re-fetch per burst of writes - see _scheduleReload().
  Timer? _reloadDebounce;

  // Each KPI card jumps to the chart section with more detail on that
  // metric instead of just sitting there as a static number.
  final _distributionKey = GlobalKey();
  final _ratingKey = GlobalKey();
  final _regAttendanceKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadAll();
    _listenForUpdates();
    activity_log.ActivityLogger.log(
      action: 'view_analytics',
      module: 'event_analytics',
      details: {'orgId': widget.orgId},
    );
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<_AnalyticsData> _loadAll() async {
    final db = FirebaseFirestore.instance;

    try {
      final eventsSnapshot = await db
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      final events = eventsSnapshot.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': data['title'] as String? ?? 'Untitled Event',
          'eventId': data['eventId'] as String? ?? d.id,
          'date': data['date'],
          'bannerUrl': data['bannerUrl'] as String? ?? '',
        };
      }).toList();

      // Every event this org owns, under either id shape events get looked
      // up by elsewhere in this file (doc id, or the event's own denormalized
      // 'eventId' field).
      final orgEventIds = <String>{
        for (final e in events) e['id'] as String,
        for (final e in events)
          if ((e['eventId'] as String).isNotEmpty) e['eventId'] as String,
      };

      // Feedback is split across two collections from an incomplete
      // migration — three mobile screens submit event feedback, and only
      // some were ever switched to the newer 'event_feedback'. The one most
      // students actually complete in practice (via the "rate this event"
      // notification) still writes to the older 'feedback' collection,
      // which — live-data-checked — currently holds real submissions while
      // 'event_feedback' holds none. Neither carries an orgId field, so
      // scope by event membership instead: every event here is already
      // known to belong to this org.
      final feedbackSnapshots = await Future.wait([
        db.collection('feedback').get(),
        db.collection('event_feedback').get(),
      ]);

      final transactionsSnapshot = await db
          .collection('transactions')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      // Neither 'registrations' nor the 'attendances' subcollection group
      // carries an orgId field, so — same as feedback above — fetch broadly
      // and scope client-side by membership in this org's own event ids.
      // collectionGroup('attendances') is an existing pattern used across
      // student/guest screens for the same events/{id}/attendances data.
      final registrationsSnapshot = await db.collection('registrations').get();
      final attendancesSnapshot = await db.collectionGroup('attendances').get();

      final feedbacks = feedbackSnapshots
          .expand((snap) => snap.docs)
          .map(
            (d) => {
              ...d.data(),
              'id': d.id,
              'eventId': d.data()['eventId'] as String? ?? '',
            },
          )
          .where((f) => orgEventIds.contains(f['eventId']))
          .toList();

      final transactions = transactionsSnapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

      final registrations = registrationsSnapshot.docs
          .map(
            (d) => {
              ...d.data(),
              'id': d.id,
              'eventId': d.data()['eventId'] as String? ?? '',
            },
          )
          .where((r) => orgEventIds.contains(r['eventId']))
          .toList();

      final attendances = attendancesSnapshot.docs
          .map(
            (d) => {
              ...d.data(),
              'id': d.id,
              // The attendance doc's own parent is the event doc:
              // events/{eventId}/attendances/{attendanceDocId}.
              'eventId': d.reference.parent.parent?.id ?? '',
            },
          )
          .where((a) => orgEventIds.contains(a['eventId']))
          .toList();

      return _AnalyticsData(
        feedbacks: feedbacks,
        events: events,
        transactions: transactions,
        registrations: registrations,
        attendances: attendances,
      );
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      rethrow;
    }
  }

  void _listenForUpdates() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    final db = FirebaseFirestore.instance;

    // These mirror the reads in _loadAll() one for one, including the three
    // unscoped ones: neither 'registrations', the attendances group, nor
    // either feedback collection carries an orgId to filter by, so they are
    // watched whole and _loadAll() does the event-membership scoping
    // client-side. A change anywhere in them costs one re-fetch, which is
    // why the debounce below exists.
    final sources = <Query<Map<String, dynamic>>>[
      db.collection('events').where('orgId', isEqualTo: widget.orgId),
      db.collection('transactions').where('orgId', isEqualTo: widget.orgId),
      db.collection('feedback'),
      db.collection('event_feedback'),
      db.collection('registrations'),
      db.collectionGroup('attendances'),
    ];

    for (final source in sources) {
      var isFirstSnapshot = true;
      _subscriptions.add(
        source.snapshots().listen(
          (_) {
            // Each listener fires once on attach with data the initial
            // _loadAll() has already fetched; only later changes are worth
            // re-fetching for.
            if (isFirstSnapshot) {
              isFirstSnapshot = false;
              return;
            }
            _scheduleReload();
          },
          onError: (Object error) {
            debugPrint('Analytics listener error: $error');
          },
        ),
      );
    }
  }

  // One re-fetch per burst. A single _loadAll() is six queries, and one user
  // action often writes to several of the watched collections at once -
  // publishing an event, or a check-in that writes an attendance and a
  // registration - so without this each of those would trigger its own full
  // reload.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _dataFuture = _loadAll();
      });
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    if (color == UpriseColors.error) {
      AppToast.error(context, msg);
    } else if (color == UpriseColors.success) {
      AppToast.success(context, msg);
    } else if (color == UpriseColors.warning) {
      AppToast.warning(context, msg);
    } else {
      AppToast.info(context, msg);
    }
  }

  // Every screen with an AdminExportButton emits 'excel'/'pdf' from its
  // dropdown (see admin_export_button.dart's _items) — matches that
  // exactly rather than checking for 'csv', which the button never
  // actually sends.
  Future<void> _exportAnalytics(String format) async {
    final data = await _dataFuture;
    final byEvent = data.registrationVsAttendanceByEvent;
    final avgByEvent = data.avgByEvent;
    final feedbackCountByEvent = data.feedbackCountByEvent;
    final eventIds = {...byEvent.keys, ...avgByEvent.keys};

    if (eventIds.isEmpty) {
      _showSnack('No analytics data to export', UpriseColors.warning);
      return;
    }

    const headers = [
      'Event',
      'Registered',
      'Attended',
      'Avg. Rating',
      'Feedback Count',
      'Income',
      'Expense',
    ];
    final rows = eventIds.map((id) {
      final title = data.eventDisplayTitle(id);
      final counts = byEvent[id];
      final avg = avgByEvent[id];
      final finance = data.financeForEvent(title);
      return [
        title,
        '${counts?.registered ?? 0}',
        '${counts?.attended ?? 0}',
        avg == null ? '—' : avg.toStringAsFixed(1),
        '${feedbackCountByEvent[id] ?? 0}',
        (finance?.income ?? 0).toStringAsFixed(2),
        (finance?.expense ?? 0).toStringAsFixed(2),
      ];
    }).toList();

    final now = DateFormat('yyyyMMdd').format(DateTime.now());
    try {
      if (format == 'excel') {
        final csv = [headers, ...rows]
            .map(
              (row) => row.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
            )
            .join('\n');
        await OrgExportUtil.saveText(
          csv,
          'event_analytics_$now.csv',
          mimeType: 'text/csv',
        );
      } else if (format == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Event Analytics',
          headers: headers,
          rows: rows,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'event_analytics_$now.pdf',
          mimeType: 'application/pdf',
        );
      }
      if (mounted) _showSnack('Exported analytics', UpriseColors.success);
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e', UpriseColors.error);
    }
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AnalyticsData>(
      future: _dataFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: UpriseColors.primaryDark),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: _C.statusCritical,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load analytics',
                  style: GoogleFonts.beVietnamPro(),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          );
        }

        final data = snap.data!;

        return Scaffold(
          backgroundColor: _C.surface,
          body: Builder(
            builder: (context) {
              final width = MediaQuery.of(context).size.width;
              final isMobile = width < 720;
              final isTablet = width >= 720 && width < 1200;
              final horizontalPadding = isMobile
                  ? 16.0
                  : (isTablet ? 22.0 : 28.0);

              // The cards and the section cards sit straight on the tinted
              // page surface. They used to be wrapped in one big white card,
              // which put white cards on a white card: the section shadows
              // had nothing to fall on, so the groups stopped reading as
              // separate and the whole tab flattened into one slab.
              //
              // The four KPI cards come first, before the heading. They are
              // the answer the page exists to give - four numbers, readable
              // without scrolling - and each one is a shortcut into the
              // chart that explains it. The heading below them introduces
              // those charts rather than the page, which the app bar
              // already names.
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isMobile ? _DS.s5 : _DS.s6,
                  horizontalPadding,
                  _DS.s7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KpiStatsRow(
                      data: data,
                      onTapEvents: () => _scrollToSection(_distributionKey),
                      onTapRegistrations: () =>
                          _scrollToSection(_regAttendanceKey),
                      onTapAttendance: () =>
                          _scrollToSection(_regAttendanceKey),
                      onTapRating: () => _scrollToSection(_ratingKey),
                    ),
                    SizedBox(height: isMobile ? _DS.s6 : _DS.s7),
                    _buildHeader(isMobile: isMobile),
                    SizedBox(height: isMobile ? _DS.s4 : _DS.s5),
                    _buildAnalyticsTab(data),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // The heading that introduces the charts, sitting under the KPI cards.
  // This screen used to switch between an Analytics tab and an Events tab;
  // the Events tab (per-event registrants/attendance/feedback/finance) has
  // moved to Events & Schedules' own Event Overview, so there's nothing
  // left to switch between. What was left behind was a card title bar that
  // still read as a tab strip.
  //
  // It is sized as a section heading, not a page title: the app bar above
  // already says "Analytics", and a second 22px "Analytics" under the cards
  // would be the same word twice at the same weight.
  Widget _buildHeader({required bool isMobile}) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Analytics',
              style: GoogleFonts.beVietnamPro(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w700,
                color: _C.charcoal,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: _DS.s3),
            const _LiveSyncPill(),
          ],
        ),
        const SizedBox(height: _DS.s1),
        Text(
          'Registrations, attendance, ratings and event finance across your '
          'organization.',
          style: GoogleFonts.beVietnamPro(fontSize: 12.5, color: _C.muted),
        ),
      ],
    );

    // Export is the only action left. The Refresh button next to it is
    // gone: every collection this page reads is now watched (see
    // _listenForUpdates), so there is nothing a manual refresh would fetch
    // that has not already arrived. _refresh() itself stays for the Retry
    // in the error state, where there is no live data yet to wait on.
    final actions = AdminExportButton(onSelected: _exportAnalytics);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: _DS.s3),
          actions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        actions,
      ],
    );
  }

  // ── Analytics tab ──────────────────────────────────────────────────────────
  // Pure aggregate/graph view.
  Widget _buildAnalyticsTab(_AnalyticsData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _distributionKey,
          child: _DistributionCard(data: data),
        ),
        const SizedBox(height: _DS.s4),
        KeyedSubtree(
          key: _ratingKey,
          child: _RatingByEventChart(data: data),
        ),
        const SizedBox(height: _DS.s4),
        KeyedSubtree(
          key: _regAttendanceKey,
          child: _PerformanceOverviewChart(data: data),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Supporting widgets
// ════════════════════════════════════════════════════════════════════════════

// The live-sync indicator. Was a bare 7px green dot plus green 11px text
// floating in the title bar; as a contained chip it reads as a status badge
// instead of stray decoration, and the label stops wearing a status colour
// as text at 3.3:1.
class _LiveSyncPill extends StatelessWidget {
  const _LiveSyncPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _DS.s2, vertical: 3),
      decoration: BoxDecoration(
        color: _C.statusGood.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _C.statusGood,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live sync',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _C.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

// One header for every section card. The three cards each built their own -
// different icon tints (blue / amber / none at all) and different paddings -
// which is what made them look like three components borrowed from three
// different screens.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  const _CardHeader({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_DS.s4, _DS.s4, _DS.s4, _DS.s3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _C.chartBrand.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _C.chartBrand),
          ),
          const SizedBox(width: _DS.s3),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _C.charcoal,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: _C.muted),
            ),
        ],
      ),
    );
  }
}

// A small lift on hover. The KPI cards have always been tappable - each
// jumps to the chart that explains its number - but nothing said so except
// the cursor. This wraps the shared StatCard rather than changing it, since
// twenty other screens use that widget and most of their cards are not
// tappable at all.
class _HoverLift extends StatefulWidget {
  final Widget child;
  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: Offset(0, _hovered ? -0.02 : 0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// Top-of-tab KPI row — quick-glance org-wide totals that don't need a
// chart of their own (event count, registrations, attendance rate, avg
// rating), each already computed by _AnalyticsData from the same
// events/registrations/attendances/feedback data the charts below use.
class _KpiStatsRow extends StatelessWidget {
  final _AnalyticsData data;
  final VoidCallback? onTapEvents;
  final VoidCallback? onTapRegistrations;
  final VoidCallback? onTapAttendance;
  final VoidCallback? onTapRating;
  const _KpiStatsRow({
    required this.data,
    this.onTapEvents,
    this.onTapRegistrations,
    this.onTapAttendance,
    this.onTapRating,
  });

  @override
  Widget build(BuildContext context) {
    // One hue across the row. These were blue / amber / green / a colour
    // that changed with the rating - four hues for four cards that are not
    // four categories, so the colour channel was spent on nothing the icon
    // and the label did not already say, and the strip read as four widgets
    // borrowed from four different screens. Brand orange makes them one
    // group, and it leaves green and red free to keep meaning "good" and
    // "bad" in the charts below.
    //
    // Not four steps of orange either: an ordinal ramp on nominal cards
    // would imply the leftmost matters most.
    final stats = [
      (
        'Total Events',
        '${data.events.length}',
        Icons.event_outlined,
        onTapEvents,
      ),
      (
        'Registrations',
        '${data.totalRegistrations}',
        Icons.how_to_reg_outlined,
        onTapRegistrations,
      ),
      (
        'Attendance Rate',
        '${data.attendanceRate.toStringAsFixed(0)}%',
        Icons.fact_check_outlined,
        onTapAttendance,
      ),
      (
        'Avg. Rating',
        data.totalFeedbacks == 0 ? '—' : data.avgRating.toStringAsFixed(1),
        Icons.star_outline_rounded,
        onTapRating,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        final cardWidth = isNarrow
            ? (constraints.maxWidth - _DS.s3) / 2
            : (constraints.maxWidth - _DS.s3 * 3) / 4;
        return Wrap(
          spacing: _DS.s3,
          runSpacing: _DS.s3,
          children: [
            for (final s in stats)
              SizedBox(
                width: cardWidth,
                child: _kpiCard(s.$1, s.$2, s.$3, s.$4),
              ),
          ],
        );
      },
    );
  }

  // Uses the shared Organization/Admin summary-card layout while retaining
  // the existing tap action for each metric.
  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    VoidCallback? onTap,
  ) {
    return _HoverLift(
      child: StatCard(
        label: label,
        value: value,
        icon: icon,
        color: _C.chartBrand,
        onTap: onTap,
      ),
    );
  }
}

// A real bar chart (fl_chart) instead of a stacked list of labeled progress
// bars — the numbers were all there before, but a chart reads at a glance
// where a list has to be read line by line. Capped to the top N so bars
// (and their labels) stay legible regardless of how many events an org
// has — the Events tab already lists every event individually if a full
// breakdown is needed.
class _RatingByEventChart extends StatelessWidget {
  final _AnalyticsData data;
  const _RatingByEventChart({required this.data});

  static const int _maxBars = 8;

  @override
  Widget build(BuildContext context) {
    final sorted = data.avgByEvent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = sorted.take(_maxBars).toList();

    return Container(
      decoration: _DS.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: Icons.bar_chart_rounded,
            title: 'Average rating by event',
            trailing: sorted.length > shown.length
                ? 'Top ${shown.length} of ${sorted.length}'
                : null,
          ),
          _DS.fadeDivider(),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No feedback data yet',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: _C.muted,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 20, 8),
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    maxY: 5,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: _C.grid, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              color: _C.muted,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= shown.length) {
                              return const SizedBox.shrink();
                            }
                            final title = data.eventDisplayTitle(shown[i].key);
                            final short = title.length > 10
                                ? '${title.substring(0, 9)}…'
                                : title;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                short,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10,
                                  color: _C.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => _C.charcoal,
                        getTooltipItem: (group, _, rod, __) {
                          final title = data.eventDisplayTitle(
                            shown[group.x].key,
                          );
                          return BarTooltipItem(
                            '$title\n',
                            GoogleFonts.beVietnamPro(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                            children: [
                              TextSpan(
                                text: '${rod.toY.toStringAsFixed(1)} ★ average',
                                style: GoogleFonts.beVietnamPro(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    barGroups: List.generate(shown.length, (i) {
                      final score = shown[i].value;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: score,
                            // One hue for every bar. This used to call
                            // _ratingColor(score), which painted each bar by
                            // its own value - the bar's height already says
                            // that, so the colour channel was spent saying it
                            // twice and the chart came out a green/amber/red
                            // rainbow of nominal event names.
                            color: _C.chartBrand,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Single "Performance Overview" card with a tab per metric instead of three
// full-size stacked bar charts (Registrations/Attendance were previously one
// grouped chart, Income/Expense another) — switching tabs keeps the same
// data on screen at a fraction of the vertical space.
class _PerformanceOverviewChart extends StatelessWidget {
  final _AnalyticsData data;
  const _PerformanceOverviewChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final byEvent = data.registrationVsAttendanceByEvent;
    final regEntries =
        byEvent.entries
            .map(
              (e) => MapEntry(
                data.eventDisplayTitle(e.key),
                e.value.registered.toDouble(),
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final attEntries =
        byEvent.entries
            .map(
              (e) => MapEntry(
                data.eventDisplayTitle(e.key),
                e.value.attended.toDouble(),
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final finance = data.financeByEventTitle;
    final incomeEntries =
        finance.entries.map((e) => MapEntry(e.key, e.value.income)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final expenseEntries =
        finance.entries.map((e) => MapEntry(e.key, e.value.expense)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      decoration: _DS.card(),
      clipBehavior: Clip.antiAlias,
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CardHeader(
              icon: Icons.insights_rounded,
              title: 'Performance overview',
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _C.border)),
              ),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                labelColor: UpriseColors.primaryDark,
                unselectedLabelColor: _C.muted,
                indicatorColor: UpriseColors.primaryDark,
                labelStyle: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 13),
                tabs: const [
                  Tab(text: 'Registrations'),
                  Tab(text: 'Attendance'),
                  Tab(text: 'Income'),
                  Tab(text: 'Expenses'),
                ],
              ),
            ),
            SizedBox(
              height: 272,
              child: TabBarView(
                children: [
                  _SingleSeriesBarChart(
                    entries: regEntries,
                    color: _C.chartBrand,
                    moneyFormat: false,
                    emptyMessage:
                        'No registration records yet — they will show up '
                        'here once students register for an event.',
                  ),
                  _SingleSeriesBarChart(
                    entries: attEntries,
                    color: _C.chartBrand,
                    moneyFormat: false,
                    emptyMessage:
                        'No attendance records yet — they will show up '
                        'here once students check in to an event.',
                  ),
                  _SingleSeriesBarChart(
                    entries: incomeEntries,
                    // Money in. statusGood rather than the _C.green KPI
                    // accent: that one measures 2.54:1 on the white card,
                    // under the 3:1 floor for a chart mark.
                    color: _C.statusGood,
                    moneyFormat: true,
                    emptyMessage:
                        'No income records tied to an event yet — '
                        'transactions in Finance whose event name matches '
                        'an event here will show up as a chart.',
                  ),
                  _SingleSeriesBarChart(
                    entries: expenseEntries,
                    // Money out, matching the Absent wedge's red.
                    color: _C.statusCritical,
                    moneyFormat: true,
                    emptyMessage:
                        'No expense records tied to an event yet — '
                        'transactions in Finance whose event name matches '
                        'an event here will show up as a chart.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// Shared single-series bar chart body for each Performance Overview tab —
// same fl_chart scaffolding (grid, axes, tooltip, truncated event labels)
// the old grouped charts used, just one color/series per tab instead of two.
class _SingleSeriesBarChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final Color color;
  final bool moneyFormat;
  final String emptyMessage;

  const _SingleSeriesBarChart({
    required this.entries,
    required this.color,
    required this.moneyFormat,
    required this.emptyMessage,
  });

  static const int _maxBars = 8;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.bar_chart_rounded, size: 18, color: _C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                emptyMessage,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: _C.muted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final shown = entries.take(_maxBars).toList();
    final maxValue = shown.fold<double>(0, (m, e) => math.max(m, e.value));
    final chartMaxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final money = NumberFormat('#,###.00');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entries.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Top ${shown.length} of ${entries.length}',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: _C.muted),
              ),
            ),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMaxY / 4,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: _C.grid, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: moneyFormat ? 44 : 30,
                      interval: chartMaxY / 4,
                      getTitlesWidget: (v, _) => Text(
                        moneyFormat
                            ? '₱${NumberFormat.compact().format(v)}'
                            : NumberFormat.compact().format(v),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 9,
                          color: _C.muted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= shown.length) {
                          return const SizedBox.shrink();
                        }
                        final title = shown[i].key;
                        final short = title.length > 10
                            ? '${title.substring(0, 9)}…'
                            : title;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            short,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              color: _C.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _C.charcoal,
                    getTooltipItem: (group, _, rod, __) {
                      final title = shown[group.x].key;
                      final value = moneyFormat
                          ? '₱${money.format(rod.toY)}'
                          : rod.toY.toInt().toString();
                      return BarTooltipItem(
                        '$title\n',
                        GoogleFonts.beVietnamPro(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        children: [
                          TextSpan(
                            text: value,
                            style: GoogleFonts.beVietnamPro(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                barGroups: List.generate(shown.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: shown[i].value,
                        color: color,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final _AnalyticsData data;
  const _DistributionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final counts = data.starCounts;
    final totalRatings = data.totalFeedbacks;
    // An ordinal one-hue ramp, darkest at 5. This was a green/emerald/amber/
    // orange/red rainbow, which reads as five unrelated categories rather
    // than one ordered scale and re-uses the status hues for non-status data.
    final ratingSlices = [
      _DonutSlice('5 stars', counts[5]!, _C.rating5),
      _DonutSlice('4 stars', counts[4]!, _C.rating4),
      _DonutSlice('3 stars', counts[3]!, _C.rating3),
      _DonutSlice('2 stars', counts[2]!, _C.rating2),
      _DonutSlice('1 star', counts[1]!, _C.rating1),
    ];

    final att = data.attendanceStatusBreakdown;
    final attendanceSlices = [
      _DonutSlice('Present', att['present']!, _C.statusGood),
      _DonutSlice('Late', att['late']!, _C.statusWarning),
      _DonutSlice('Absent', att['absent']!, _C.statusCritical),
    ];
    final attTotal = attendanceSlices.fold<int>(0, (s, e) => s + e.count);

    return Container(
      decoration: _DS.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.insert_chart_outlined,
            title: 'Rating & attendance breakdown',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_DS.s4, 0, _DS.s4, _DS.s4),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _DonutSection(
                      label: 'By rating',
                      slices: ratingSlices,
                      centerBig: totalRatings == 0
                          ? '—'
                          : data.avgRating.toStringAsFixed(1),
                      centerSmall: 'average',
                      emptyText: 'No feedback yet',
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: _DS.s5),
                    color: _C.border,
                  ),
                  Expanded(
                    child: _DonutSection(
                      label: 'By attendance',
                      slices: attendanceSlices,
                      centerBig: attTotal == 0
                          ? '—'
                          : '${data.attendanceRate.toStringAsFixed(0)}%',
                      centerSmall: 'attended',
                      emptyText: 'No attendance yet',
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
}

// One donut + its own legend, with hover: hovering a wedge or a legend row
// highlights the other and pops a small info chip above the donut showing
// that slice's exact label/percentage/count — the counts underneath were
// already there, this just surfaces them without a click.
class _DonutSection extends StatefulWidget {
  final String label;
  final List<_DonutSlice> slices;
  final String centerBig;
  final String centerSmall;
  final String emptyText;
  const _DonutSection({
    required this.label,
    required this.slices,
    required this.centerBig,
    required this.centerSmall,
    required this.emptyText,
  });

  @override
  State<_DonutSection> createState() => _DonutSectionState();
}

class _DonutSectionState extends State<_DonutSection> {
  static const double _size = 140;
  static const double _ringWidth = 24;
  int? _hovered;

  int get _total => widget.slices.fold(0, (s, e) => s + e.count);

  void _setHover(int? idx) {
    if (idx != _hovered) setState(() => _hovered = idx);
  }

  // Maps a pointer position over the donut to the slice under it, using
  // the exact same start-angle/sweep math the painter below uses to draw
  // the wedges, so the hit area lines up with what's actually rendered.
  int? _hitTest(Offset local) {
    final total = _total;
    if (total == 0) return null;
    const center = Offset(_size / 2, _size / 2);
    final dx = local.dx - center.dx, dy = local.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final r = _size / 2 - 14;
    if (dist < r - _ringWidth / 2 || dist > r + _ringWidth / 2) return null;
    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    double acc = 0;
    for (var i = 0; i < widget.slices.length; i++) {
      final s = widget.slices[i];
      if (s.count == 0) continue;
      final sweep = s.count / total * 2 * math.pi;
      if (angle >= acc && angle < acc + sweep) return i;
      acc += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: _C.muted,
          ),
        ),
        const SizedBox(height: 10),
        if (total == 0)
          Container(
            height: _size,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_chart_outlined, size: 32, color: _C.border),
                const SizedBox(height: 6),
                Text(
                  widget.emptyText,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: _C.muted,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  MouseRegion(
                    onHover: (e) => _setHover(_hitTest(e.localPosition)),
                    onExit: (_) => _setHover(null),
                    child: SizedBox(
                      width: _size,
                      height: _size,
                      child: CustomPaint(
                        painter: _DonutPainter(
                          slices: widget.slices,
                          hoveredIndex: _hovered,
                          centerBig: widget.centerBig,
                          centerSmall: widget.centerSmall,
                        ),
                      ),
                    ),
                  ),
                  if (_hovered != null)
                    Positioned(
                      top: -32,
                      child: IgnorePointer(
                        child: _HoverInfoChip(
                          slice: widget.slices[_hovered!],
                          total: total,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < widget.slices.length; i++)
                      _legendRow(i, total),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _legendRow(int i, int total) {
    final s = widget.slices[i];
    final pct = total > 0 ? (s.count / total * 100).toStringAsFixed(0) : '0';
    return MouseRegion(
      onEnter: (_) => _setHover(i),
      onExit: (_) => _setHover(null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              s.label,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.muted),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _C.chipBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$pct%',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.charcoal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverInfoChip extends StatelessWidget {
  final _DonutSlice slice;
  final int total;
  const _HoverInfoChip({required this.slice, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0
        ? (slice.count / total * 100).toStringAsFixed(0)
        : '0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _C.charcoal,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '${slice.label} · $pct% · ${slice.count}',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DonutSlice {
  final String label;
  final int count;
  final Color color;
  const _DonutSlice(this.label, this.count, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSlice> slices;
  final int? hoveredIndex;
  final String centerBig;
  final String centerSmall;
  const _DonutPainter({
    required this.slices,
    required this.centerBig,
    required this.centerSmall,
    this.hoveredIndex,
  });

  int get _total => slices.fold(0, (s, e) => s + e.count);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 14;
    const sw = 24.0, gap = 0.012;
    final total = _total;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    if (total == 0) {
      paint
        ..color = const Color(0xFFE5E7EB)
        ..strokeWidth = sw;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    } else {
      double start = -math.pi / 2;
      final nonZero = slices.where((s) => s.count > 0).length;
      for (var i = 0; i < slices.length; i++) {
        final s = slices[i];
        if (s.count == 0) continue;
        final sweep = s.count / total * 2 * math.pi;
        final actual = nonZero > 1 ? math.max(0.0, sweep - gap) : sweep;
        final isHovered = hoveredIndex == i;
        final dim = hoveredIndex != null && !isHovered;
        paint
          ..color = dim ? s.color.withValues(alpha: 0.35) : s.color
          ..strokeWidth = isHovered ? sw + 5 : sw;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          start,
          actual,
          false,
          paint,
        );
        start += sweep;
      }
    }

    final bigStyle = GoogleFonts.beVietnamPro(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: _C.charcoal,
    );
    final smStyle = GoogleFonts.beVietnamPro(
      fontSize: 11,
      color: _C.muted,
      fontWeight: FontWeight.w500,
    );

    final tp1 = TextPainter(
      text: TextSpan(text: centerBig, style: bigStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final tp2 = TextPainter(
      text: TextSpan(text: centerSmall, style: smStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    tp1.paint(canvas, ui.Offset(cx - tp1.width / 2, cy - tp1.height / 2 - 7));
    tp2.paint(canvas, ui.Offset(cx - tp2.width / 2, cy + tp1.height / 2 - 3));
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old._total != _total ||
      old.centerBig != centerBig ||
      old.hoveredIndex != hoveredIndex;
}
