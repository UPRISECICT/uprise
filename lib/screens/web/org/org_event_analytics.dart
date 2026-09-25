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

  // Star ratings read as sentiment: 5 = good (green) down to 1 = bad (red),
  // so the share of happy vs unhappy attendees shows at a glance and the
  // donut sits comfortably next to the green/amber/red attendance donut.
  static const Color rating5 = Color(0xFF16A34A);
  static const Color rating4 = Color(0xFF14B8A6);
  static const Color rating3 = Color(0xFFF59E0B);
  static const Color rating2 = Color(0xFFF97316);
  static const Color rating1 = Color(0xFFEF4444);

  // KPI card accents - the same four hues the Event Proposals stat cards
  // use, so the summary strip looks like the one on the other tabs.
  static const Color kpiEvents = UpriseColors.primaryDark;
  static const Color kpiRegistrations = Color(0xFF2563EB);
  static const Color kpiAttendance = Color(0xFF059669);
  static const Color kpiRating = Color(0xFFFB923C);

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
              // Page actions (Live sync, Export) sit on a slim row at the
              // top, then the four KPI cards, then the charts - the cards
              // and charts sit one normal gap apart instead of having an
              // actions row wedged between them.
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isMobile ? _DS.s4 : _DS.s5,
                  horizontalPadding,
                  _DS.s7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isMobile: isMobile),
                    const SizedBox(height: _DS.s3),
                    _KpiStatsRow(
                      data: data,
                      onTapEvents: () => _scrollToSection(_distributionKey),
                      onTapRegistrations: () =>
                          _scrollToSection(_regAttendanceKey),
                      onTapAttendance: () =>
                          _scrollToSection(_regAttendanceKey),
                      onTapRating: () => _scrollToSection(_ratingKey),
                    ),
                    const SizedBox(height: _DS.s5),
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

  // Actions row above the KPI cards. No page-level heading here: the app
  // bar already says "Analytics".
  //
  // Export is the only action. The Refresh button that used to sit next to
  // it is gone: every collection this page reads is watched (see
  // _listenForUpdates), so a manual refresh would fetch nothing new.
  // _refresh() itself stays for the Retry in the error state.
  Widget _buildHeader({required bool isMobile}) {
    return Row(
      mainAxisAlignment: isMobile
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        const _LiveSyncPill(),
        const SizedBox(width: _DS.s3),
        AdminExportButton(onSelected: _exportAnalytics),
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
        const SizedBox(height: _DS.s5),
        KeyedSubtree(
          key: _ratingKey,
          child: _RatingByEventChart(data: data),
        ),
        const SizedBox(height: _DS.s5),
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
  final String? subtitle;
  final String? trailing;
  const _CardHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_DS.s4, _DS.s4, _DS.s4, _DS.s3),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _C.chartBrand.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _C.chartBrand),
          ),
          const SizedBox(width: _DS.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _C.charcoal,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: _C.muted,
                    ),
                  ),
              ],
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
    // One accent per card, matching the stat strips on the other org tabs.
    final stats = [
      (
        'Total Events',
        '${data.events.length}',
        Icons.event_outlined,
        onTapEvents,
        _C.kpiEvents,
      ),
      (
        'Registrations',
        '${data.totalRegistrations}',
        Icons.how_to_reg_outlined,
        onTapRegistrations,
        _C.kpiRegistrations,
      ),
      (
        'Attendance Rate',
        '${data.attendanceRate.toStringAsFixed(0)}%',
        Icons.fact_check_outlined,
        onTapAttendance,
        _C.kpiAttendance,
      ),
      (
        'Avg. Rating',
        data.totalFeedbacks == 0 ? '—' : data.avgRating.toStringAsFixed(1),
        Icons.star_outline_rounded,
        onTapRating,
        _C.kpiRating,
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
                child: _kpiCard(s.$1, s.$2, s.$3, s.$4, s.$5),
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
    Color color,
  ) {
    return _HoverLift(
      child: StatCard(
        label: label,
        value: value,
        icon: icon,
        color: color,
        onTap: onTap,
      ),
    );
  }
}

// Shared bar chart body for the rating and performance cards. One fl_chart
// scaffold so both read the same: bars widen with the space available (12-32px
// rather than fl_chart's thin default), the exact value is printed above each
// bar when the slot is wide enough to hold it, and event names wrap to two
// lines under the bar instead of being cut after a few characters. Hover
// tooltips are unchanged and still carry the full event name.
class _EventBarChart extends StatefulWidget {
  final List<MapEntry<String, double>> entries;
  final Color color;
  final double? fixedMaxY;
  final double? fixedInterval;
  final double leftReserved;
  final String Function(double) axisLabel;
  final String Function(double) valueLabel;
  final String Function(double) tooltipValue;

  const _EventBarChart({
    required this.entries,
    required this.color,
    required this.leftReserved,
    required this.axisLabel,
    required this.valueLabel,
    required this.tooltipValue,
    this.fixedMaxY,
    this.fixedInterval,
  });

  static const double _height = 250;
  // Headroom above the plot so the value label on the tallest bar is not
  // clipped by the card.
  static const double _topPad = 22;
  static const double _bottomReserved = 42;

  @override
  State<_EventBarChart> createState() => _EventBarChartState();
}

class _EventBarChartState extends State<_EventBarChart> {
  static const double _height = _EventBarChart._height;
  static const double _topPad = _EventBarChart._topPad;
  static const double _bottomReserved = _EventBarChart._bottomReserved;

  // Bar under the pointer; it takes the full colour while the rest stay
  // soft, so the chart is easy on the eyes but still answers the hover.
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final maxValue = widget.entries.fold<double>(
      0,
      (m, e) => math.max(m, e.value),
    );
    final maxY = widget.fixedMaxY ?? (maxValue <= 0 ? 1.0 : maxValue * 1.15);
    final interval = widget.fixedInterval ?? maxY / 4;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = widget.entries.length;
          final plotW = math.max(
            0.0,
            constraints.maxWidth - widget.leftReserved,
          );
          final slot = plotW / n;
          final barW = (slot * 0.4).clamp(12.0, 28.0).toDouble();
          final plotH = _height - _topPad - _bottomReserved;
          final labelWidth = math.max(24.0, math.min(slot - 8, 140.0));

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: _topPad,
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: interval,
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
                          reservedSize: widget.leftReserved,
                          interval: interval,
                          getTitlesWidget: (v, _) => Text(
                            widget.axisLabel(v),
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
                          reservedSize: _bottomReserved,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= n) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SizedBox(
                                width: labelWidth,
                                child: Text(
                                  widget.entries[i].key,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 10.5,
                                    height: 1.2,
                                    color: _C.muted,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchCallback: (event, response) {
                        final i = event.isInterestedForInteractions
                            ? response?.spot?.touchedBarGroupIndex
                            : null;
                        if (i != _hovered) setState(() => _hovered = i);
                      },
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => _C.charcoal,
                        getTooltipItem: (group, _, rod, __) {
                          return BarTooltipItem(
                            '${widget.entries[group.x].key}\n',
                            GoogleFonts.beVietnamPro(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                            children: [
                              TextSpan(
                                text: widget.tooltipValue(rod.toY),
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
                    barGroups: List.generate(n, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: widget.entries[i].value,
                            color: _hovered == i
                                ? widget.color
                                : widget.color.withAlpha(150),
                            width: barW,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
              // Value labels. Laid over the chart from the same geometry
              // fl_chart uses (equal slots under spaceAround, plot area =
              // chart minus the reserved axis titles). IgnorePointer keeps
              // the bar tooltips reachable.
              if (slot >= 30)
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: widget.leftReserved + slot * i,
                    width: slot,
                    bottom:
                        _bottomReserved +
                        (widget.entries[i].value / maxY).clamp(0.0, 1.0) *
                            plotH +
                        3,
                    child: IgnorePointer(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.valueLabel(widget.entries[i].value),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _C.charcoal,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// Average rating per event. Capped to the top N so bars and labels stay
// legible however many events an org has - the Events tab already lists every
// event individually if a full breakdown is needed.
class _RatingByEventChart extends StatelessWidget {
  final _AnalyticsData data;
  const _RatingByEventChart({required this.data});

  static const int _maxBars = 8;

  @override
  Widget build(BuildContext context) {
    final sorted = data.avgByEvent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = sorted.take(_maxBars).toList();
    final entries = [
      for (final e in shown) MapEntry(data.eventDisplayTitle(e.key), e.value),
    ];

    return Container(
      decoration: _DS.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: Icons.bar_chart_rounded,
            title: 'Average Rating by Event',
            subtitle: 'Compare attendee feedback across your events.',
            trailing: sorted.length > shown.length
                ? 'Top ${shown.length} of ${sorted.length}'
                : null,
          ),
          _DS.fadeDivider(),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(_DS.s7),
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
              padding: const EdgeInsets.fromLTRB(
                _DS.s4,
                _DS.s3,
                _DS.s4,
                _DS.s3,
              ),
              child: _EventBarChart(
                entries: entries,
                // One hue for every bar - the bar's height already encodes
                // the score, so colouring by value would say it twice.
                color: _C.chartBrand,
                fixedMaxY: 5,
                fixedInterval: 1,
                leftReserved: 24,
                axisLabel: (v) => '${v.toInt()}',
                valueLabel: (v) => v.toStringAsFixed(1),
                tooltipValue: (v) => '${v.toStringAsFixed(1)} ★ average',
              ),
            ),
        ],
      ),
    );
  }
}

// Single "Performance Overview" card with a tab per metric instead of four
// full-size stacked bar charts - switching tabs keeps the same data on screen
// at a fraction of the vertical space.
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
              title: 'Performance Overview',
              subtitle:
                  'Compare engagement and financial performance by event.',
            ),
            _DS.fadeDivider(),
            // Restrained selected state: a soft brand tint behind the label
            // rather than four button-like tabs.
            Padding(
              padding: const EdgeInsets.fromLTRB(_DS.s4, _DS.s3, _DS.s4, 0),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                padding: EdgeInsets.zero,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: _C.chartBrand.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                splashBorderRadius: BorderRadius.circular(8),
                overlayColor: WidgetStatePropertyAll(
                  _C.chartBrand.withAlpha(10),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelColor: _C.chartBrand,
                unselectedLabelColor: _C.muted,
                labelStyle: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(height: 34, text: 'Registrations'),
                  Tab(height: 34, text: 'Attendance'),
                  Tab(height: 34, text: 'Income'),
                  Tab(height: 34, text: 'Expenses'),
                ],
              ),
            ),
            SizedBox(
              height: 300,
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
                    // Money in. statusGood: it clears the 3:1 floor for a
                    // chart mark on the white card.
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
          ],
        ),
      ),
    );
  }
}

// Body of one Performance Overview tab: the shared bar chart plus its
// "Top N of M" note and empty state.
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
        padding: const EdgeInsets.all(_DS.s5),
        child: Row(
          children: [
            const Icon(Icons.bar_chart_rounded, size: 18, color: _C.muted),
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
    final money = NumberFormat('#,###.00');
    final compact = NumberFormat.compact();

    return Padding(
      padding: const EdgeInsets.fromLTRB(_DS.s4, _DS.s3, _DS.s4, _DS.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entries.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(bottom: _DS.s1),
              child: Text(
                'Top ${shown.length} of ${entries.length}',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: _C.muted),
              ),
            ),
          _EventBarChart(
            entries: shown,
            color: color,
            leftReserved: moneyFormat ? 48 : 32,
            axisLabel: (v) =>
                moneyFormat ? '₱${compact.format(v)}' : compact.format(v),
            valueLabel: (v) =>
                moneyFormat ? '₱${compact.format(v)}' : '${v.toInt()}',
            tooltipValue: (v) =>
                moneyFormat ? '₱${money.format(v)}' : v.toInt().toString(),
          ),
        ],
      ),
    );
  }
}

// Rating & attendance: two equal cards - one donut each - side by side,
// stacking on narrow widths.
class _DistributionCard extends StatelessWidget {
  final _AnalyticsData data;
  const _DistributionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final counts = data.starCounts;
    final totalRatings = data.totalFeedbacks;
    // An ordinal one-hue ramp, darkest at 5 - one ordered scale, not five
    // unrelated categories.
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

    final ratingCard = _DonutCard(
      icon: Icons.star_outline_rounded,
      title: 'Average Rating',
      subtitle: 'Share of feedback at each star level.',
      child: _DonutSection(
        slices: ratingSlices,
        centerBig: totalRatings == 0 ? '—' : data.avgRating.toStringAsFixed(1),
        centerSmall: 'average',
        emptyText: 'No feedback yet',
      ),
    );
    final attendanceCard = _DonutCard(
      icon: Icons.fact_check_outlined,
      title: 'Attendance Rate',
      subtitle: 'Present, late and absent across registered slots.',
      child: _DonutSection(
        slices: attendanceSlices,
        centerBig: attTotal == 0
            ? '—'
            : '${data.attendanceRate.toStringAsFixed(0)}%',
        centerSmall: 'attended',
        emptyText: 'No attendance yet',
      ),
    );

    // The cards' own titles already say what they are, so no section
    // heading sits above them.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              ratingCard,
              const SizedBox(height: _DS.s5),
              attendanceCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ratingCard),
              const SizedBox(width: _DS.s4),
              Expanded(child: attendanceCard),
            ],
          ),
        );
      },
    );
  }
}

// One card of the pair above: the shared card header, then its donut.
class _DonutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  const _DonutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _DS.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(icon: icon, title: title, subtitle: subtitle),
          _DS.fadeDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(_DS.s5, _DS.s4, _DS.s5, _DS.s5),
            child: child,
          ),
        ],
      ),
    );
  }
}

// One donut + its own legend, with hover: hovering a wedge or a legend row
// highlights the other and pops a small info chip above the donut showing
// that slice's exact label/percentage/count - the counts underneath were
// already there, this just surfaces them without a click.
class _DonutSection extends StatefulWidget {
  final List<_DonutSlice> slices;
  final String centerBig;
  final String centerSmall;
  final String emptyText;
  const _DonutSection({
    required this.slices,
    required this.centerBig,
    required this.centerSmall,
    required this.emptyText,
  });

  @override
  State<_DonutSection> createState() => _DonutSectionState();
}

class _DonutSectionState extends State<_DonutSection> {
  static const double _size = 150;
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
    if (total == 0) {
      return Container(
        height: _size + _DS.s4,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_chart_outlined, size: 32, color: _C.border),
            const SizedBox(height: 6),
            Text(
              widget.emptyText,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.muted),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Room above the donut for the hover chip.
        const SizedBox(height: _DS.s5),
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
                top: -28,
                child: IgnorePointer(
                  child: _HoverInfoChip(
                    slice: widget.slices[_hovered!],
                    total: total,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: _DS.s5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              for (var i = 0; i < widget.slices.length; i++)
                _legendRow(i, total),
            ],
          ),
        ),
      ],
    );
  }

  // Dot + label on the left; count and percentage in fixed-width right
  // columns so the numbers line up down the legend.
  Widget _legendRow(int i, int total) {
    final s = widget.slices[i];
    final pct = total > 0 ? (s.count / total * 100).toStringAsFixed(0) : '0';
    final hovered = _hovered == i;
    return MouseRegion(
      onEnter: (_) => _setHover(i),
      onExit: (_) => _setHover(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _DS.s2, vertical: 4),
        decoration: BoxDecoration(
          color: hovered ? _C.chipBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: _DS.s2),
            Expanded(
              child: Text(
                s.label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: _C.charcoal,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${s.count}',
                textAlign: TextAlign.right,
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.muted),
              ),
            ),
            const SizedBox(width: _DS.s2),
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
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
