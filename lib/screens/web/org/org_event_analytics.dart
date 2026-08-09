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
import '../../../widgets/student/event_image.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import 'export_util.dart';
import 'export_pdf.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
  );
}

// ── Color aliases ────────────────────────────────────────────────────────────
class _C {
  static const Color amber = Color(0xFFF59E0B);
  static const Color green = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);
  static const Color blue = Color(0xFF3B82F6);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color muted = Color(0xFF64748B);
  static const Color charcoal = Color(0xFF0F172A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
}

// ── Data model ───────────────────────────────────────────────────────────────
class _AnalyticsData {
  final List<Map<String, dynamic>> feedbacks;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> evalForms;
  final List<Map<String, dynamic>> transactions;

  final Map<String, String> _eventTitleCache = {};

  _AnalyticsData({
    required this.feedbacks,
    this.transactions = const [],
    required this.events,
    required this.evalForms,
  });

  int get totalFeedbacks => feedbacks.length;

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

  String? eventIdByTitle(String title) {
    for (final event in events) {
      final t = event['title'] as String? ?? '';
      if (t == title) {
        return event['id'] as String?;
      }
    }
    return null;
  }

  List<String> get eventTitles {
    final titles = <String>{};
    for (final event in events) {
      final title = event['title'] as String? ?? '';
      if (title.isNotEmpty) titles.add(title);
    }
    return titles.toList()..sort();
  }

  // A representative written comment for one event, picked from its
  // lowest- or highest-rated feedback so an insight card can show real
  // student wording instead of just a number.
  String? representativeComment(String eventId, {required bool lowest}) {
    final matches = feedbacks
        .where((f) => (f['eventId'] ?? '') == eventId)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final ra = a['rating'] as int? ?? 0;
      final rb = b['rating'] as int? ?? 0;
      return lowest ? ra.compareTo(rb) : rb.compareTo(ra);
    });
    for (final f in matches) {
      final comment = (f['comment'] as String? ?? '').trim();
      if (comment.isNotEmpty) return comment;
    }
    return null;
  }

  // Per-event income/expense rollup, keyed by event TITLE — transactions
  // only reliably denormalize `eventName` (not a matching `eventId`), and
  // title is the one identity feedback and finance data can both resolve
  // to (see eventTitle()'s own fallback-matching for why eventId alone
  // isn't a safe join key here).
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

class _OrgEventAnalyticsScreenState extends State<OrgEventAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late Future<_AnalyticsData> _dataFuture;
  late TabController _tabCtrl;

  // Feedback is currently split across two collections from an incomplete
  // migration — see the comment in _loadAll() — so both are watched.
  StreamSubscription<QuerySnapshot>? _feedbackSubscription;
  StreamSubscription<QuerySnapshot>? _eventFeedbackSubscription;

  final TextEditingController _eventsSearchCtrl = TextEditingController();
  String _eventsSearchQuery = '';
  String _eventsSortBy = 'Most Recent';
  static const List<String> _eventsSortOptions = [
    'Most Recent',
    'Highest Rated',
    'Most Responses',
    'Name (A-Z)',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _dataFuture = _loadAll();
    _eventsSearchCtrl.addListener(
      () => setState(
        () => _eventsSearchQuery = _eventsSearchCtrl.text.toLowerCase().trim(),
      ),
    );
    _listenForUpdates();
    activity_log.ActivityLogger.log(
      action: 'view_analytics',
      module: 'event_analytics',
      details: {'orgId': widget.orgId},
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _eventsSearchCtrl.dispose();
    _feedbackSubscription?.cancel();
    _eventFeedbackSubscription?.cancel();
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

      final evalFormsSnapshot = await db
          .collection('eval_forms')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      final transactionsSnapshot = await db
          .collection('transactions')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

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

      final evalForms = evalFormsSnapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

      final transactions = transactionsSnapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

      return _AnalyticsData(
        feedbacks: feedbacks,
        events: events,
        evalForms: evalForms,
        transactions: transactions,
      );
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      rethrow;
    }
  }

  void _listenForUpdates() {
    _feedbackSubscription?.cancel();
    _eventFeedbackSubscription?.cancel();
    // Unfiltered — this only triggers a full _loadAll() re-fetch on any
    // change, and _loadAll() itself does the real event-membership
    // filtering (feedback docs have no orgId field to filter by here).
    // Both collections are watched — see _loadAll() for why.
    _feedbackSubscription = FirebaseFirestore.instance
        .collection('feedback')
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _dataFuture = _loadAll();
              });
            }
          },
          onError: (error) {
            debugPrint('Feedback listener error: $error');
          },
        );
    _eventFeedbackSubscription = FirebaseFirestore.instance
        .collection('event_feedback')
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _dataFuture = _loadAll();
              });
            }
          },
          onError: (error) {
            debugPrint('Event feedback listener error: $error');
          },
        );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadAll();
    });
  }

  // Feedback is split across two collections (see _loadAll() for why) — this
  // merges live updates from both into one stream so this dialog's counts
  // don't silently miss whichever collection the real submissions landed in.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _mergedFeedbackStream(String eventId) {
    final controller =
        StreamController<
          List<QueryDocumentSnapshot<Map<String, dynamic>>>
        >.broadcast();
    var latestOld = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var latestNew = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    void emit() {
      if (!controller.isClosed) controller.add([...latestOld, ...latestNew]);
    }

    final sub1 = FirebaseFirestore.instance
        .collection('feedback')
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .listen((snap) {
          latestOld = snap.docs;
          emit();
        });
    final sub2 = FirebaseFirestore.instance
        .collection('event_feedback')
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .listen((snap) {
          latestNew = snap.docs;
          emit();
        });
    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };
    return controller.stream;
  }

  // ── Event Summary Dialog ──────────────────────────────────────────────────
  void _showEventSummaryDialog(
    BuildContext context, {
    required String eventId,
    required String eventTitle,
    required String orgId,
    required _AnalyticsData analyticsData,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 680,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventTitle,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _C.charcoal,
                          ),
                        ),
                        Text(
                          'Event summary',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _C.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const Divider(height: 24, color: _C.border),
              Expanded(
                child: SingleChildScrollView(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('events')
                        .doc(eventId)
                        .collection('attendances')
                        .snapshots(),
                    builder: (ctx, attSnap) {
                      final attDocs = attSnap.data?.docs ?? [];
                      final checkedIn = attDocs.length;
                      final present = attDocs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['status'] == 'present';
                      }).length;
                      final late = attDocs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['status'] == 'late';
                      }).length;

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('registrations')
                            .where('eventId', isEqualTo: eventId)
                            .snapshots(),
                        builder: (ctx, regSnap) {
                          final regCount = regSnap.data?.docs.length;
                          // Attendance docs are only created on check-in, so
                          // regCount (real registrants) — not checkedIn — is the
                          // correct denominator for a true "Absent" tally.
                          final totalAttendees = regCount != null
                              ? (regCount > checkedIn ? regCount : checkedIn)
                              : checkedIn;
                          final absent = (totalAttendees - present - late)
                              .clamp(0, totalAttendees);

                          return StreamBuilder<
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          >(
                            stream: _mergedFeedbackStream(eventId),
                            builder: (ctx, feedbackSnap) {
                              final feedbackDocs = feedbackSnap.data ?? [];
                              final feedbackCount = feedbackDocs.length;
                              final notYetFeedback = checkedIn - feedbackCount;

                              final studentIdsWithFeedback = feedbackDocs
                                  .map(
                                    (d) => d.data()['userId']?.toString() ?? '',
                                  )
                                  .where((id) => id.isNotEmpty)
                                  .toSet();

                              return FutureBuilder<List<Map<String, dynamic>>>(
                                future: _getAttendeesWithNames(attDocs),
                                builder: (ctx, attendeeSnap) {
                                  final attendees = attendeeSnap.data ?? [];

                                  // ── Per-event insights: real ratings/
                                  // comments/finance for THIS event only,
                                  // not a cross-event "best vs worst" pick.
                                  final feedbackMaps = feedbackDocs
                                      .map((d) => d.data())
                                      .toList();
                                  final ratings = feedbackMaps
                                      .map((f) => f['rating'] as int? ?? 0)
                                      .where((r) => r > 0)
                                      .toList();
                                  final avgRating = ratings.isEmpty
                                      ? null
                                      : ratings.reduce((a, b) => a + b) /
                                            ratings.length;
                                  final byRatingDesc = [...feedbackMaps]
                                    ..sort(
                                      (a, b) => (b['rating'] as int? ?? 0)
                                          .compareTo(a['rating'] as int? ?? 0),
                                    );
                                  String? topComment;
                                  String? lowComment;
                                  for (final f in byRatingDesc) {
                                    final c = (f['comment'] as String? ?? '')
                                        .trim();
                                    if (c.isNotEmpty) {
                                      topComment = c;
                                      break;
                                    }
                                  }
                                  for (final f in byRatingDesc.reversed) {
                                    final c = (f['comment'] as String? ?? '')
                                        .trim();
                                    if (c.isNotEmpty) {
                                      lowComment = c;
                                      break;
                                    }
                                  }
                                  final eventFinance = analyticsData
                                      .financeForEvent(eventTitle);
                                  final money = NumberFormat('#,###.00');
                                  final insightBody = StringBuffer(
                                    avgRating != null
                                        ? 'Average rating: ${avgRating.toStringAsFixed(1)}★ from ${ratings.length} response${ratings.length == 1 ? '' : 's'}.'
                                        : 'No feedback submitted for this event yet.',
                                  );
                                  if (checkedIn > 0) {
                                    insightBody.write(
                                      '\n$feedbackCount of $checkedIn checked-in attendee${checkedIn == 1 ? '' : 's'} '
                                      'have submitted feedback${notYetFeedback > 0 ? ' ($notYetFeedback still pending)' : ''}.',
                                    );
                                  }
                                  if (topComment != null) {
                                    insightBody.write(
                                      '\n"$topComment" — highest-rated response.',
                                    );
                                  }
                                  if (lowComment != null &&
                                      lowComment != topComment &&
                                      avgRating != null &&
                                      avgRating < 4.5) {
                                    insightBody.write(
                                      '\n"$lowComment" — lowest-rated response, worth a look.',
                                    );
                                  }
                                  String? insightNote;
                                  if (eventFinance != null) {
                                    final net =
                                        eventFinance.income -
                                        eventFinance.expense;
                                    insightNote = net >= 0
                                        ? 'Net gain of ₱${money.format(net)}.'
                                        : 'Net loss of ₱${money.format(-net)}.';
                                  }

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _buildSummaryStat(
                                            'Registrants',
                                            '$totalAttendees',
                                            Icons.people_alt_rounded,
                                            _C.blue,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildSummaryStat(
                                            'Present',
                                            '$present',
                                            Icons.check_circle_rounded,
                                            _C.green,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildSummaryStat(
                                            'Late',
                                            '$late',
                                            Icons.access_time_rounded,
                                            _C.amber,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildSummaryStat(
                                            'Absent',
                                            '$absent',
                                            Icons.cancel_rounded,
                                            _C.red,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      _InsightTile(
                                        icon: Icons.auto_awesome_rounded,
                                        color: avgRating == null
                                            ? _C.muted
                                            : _ratingColor(avgRating),
                                        label: 'Insights',
                                        body: insightBody.toString(),
                                        note: insightNote,
                                      ),
                                      const SizedBox(height: 20),
                                      const Divider(
                                        height: 1,
                                        color: _C.border,
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Text(
                                            'Feedback',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _C.charcoal,
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: feedbackDocs.isEmpty
                                                ? null
                                                : () => _showFeedbackListDialog(
                                                    context,
                                                    eventTitle: eventTitle,
                                                    feedbacks: feedbackMaps
                                                        .asMap()
                                                        .entries
                                                        .map(
                                                          (e) => {
                                                            ...e.value,
                                                            'id':
                                                                feedbackDocs[e
                                                                        .key]
                                                                    .id,
                                                          },
                                                        )
                                                        .toList(),
                                                    data: analyticsData,
                                                  ),
                                            child: Text(
                                              'View all (${feedbackDocs.length})',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Text(
                                            'Attendees',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _C.charcoal,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${attendees.length} total',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: _C.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Flexible(
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            maxHeight: 280,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: _C.border.withOpacity(0.4),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: SingleChildScrollView(
                                            child: attendees.isEmpty
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          32,
                                                        ),
                                                    child: Center(
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .people_outline,
                                                            size: 40,
                                                            color: _C.border,
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Text(
                                                            'No attendees yet',
                                                            style:
                                                                GoogleFonts.inter(
                                                                  fontSize: 13,
                                                                  color:
                                                                      _C.muted,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : Column(
                                                    children: attendees.map((
                                                      attendee,
                                                    ) {
                                                      final studentName =
                                                          attendee['studentName'] ??
                                                          'Unknown';
                                                      final uid =
                                                          attendee['studentId']
                                                              ?.toString() ??
                                                          '';
                                                      final isPresent =
                                                          attendee['status'] ==
                                                          'present';
                                                      final hasFeedback =
                                                          uid.isNotEmpty &&
                                                          studentIdsWithFeedback
                                                              .contains(uid);

                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          border: Border(
                                                            bottom: BorderSide(
                                                              color: _C.border
                                                                  .withOpacity(
                                                                    0.3,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              isPresent
                                                                  ? Icons
                                                                        .check_circle_rounded
                                                                  : Icons
                                                                        .access_time_rounded,
                                                              color: isPresent
                                                                  ? _C.green
                                                                  : _C.amber,
                                                              size: 16,
                                                            ),
                                                            const SizedBox(
                                                              width: 10,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                studentName,
                                                                style: GoogleFonts.inter(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: _C
                                                                      .charcoal,
                                                                ),
                                                              ),
                                                            ),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical: 3,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    hasFeedback
                                                                    ? const Color(
                                                                        0xFFECFDF5,
                                                                      )
                                                                    : const Color(
                                                                        0xFFF1F5F9,
                                                                      ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                hasFeedback
                                                                    ? '✓ Feedback'
                                                                    : 'Pending',
                                                                style: GoogleFonts.inter(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      hasFeedback
                                                                      ? const Color(
                                                                          0xFF166534,
                                                                        )
                                                                      : _C.muted,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
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

  Future<List<Map<String, dynamic>>> _getAttendeesWithNames(
    List<QueryDocumentSnapshot> attDocs,
  ) async {
    final List<Map<String, dynamic>> result = [];

    for (final doc in attDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['studentId']?.toString() ?? '';

      if (uid.isNotEmpty) {
        try {
          final studentDoc = await FirebaseFirestore.instance
              .collection('students')
              .doc(uid)
              .get();
          if (studentDoc.exists) {
            final studentData = studentDoc.data() as Map<String, dynamic>;
            result.add({
              'studentName':
                  studentData['fullName'] ?? data['studentName'] ?? 'Unknown',
              'studentId': uid,
              'status': data['status'] ?? 'present',
              'timestamp': data['timestamp'],
            });
            continue;
          }
        } catch (_) {}
      }

      result.add({
        'studentName': data['studentName'] ?? 'Unknown',
        'studentId': uid,
        'status': data['status'] ?? 'present',
        'timestamp': data['timestamp'],
      });
    }

    return result;
  }

  Widget _buildSummaryStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _C.charcoal,
              ),
            ),
            Text(label, style: GoogleFonts.inter(fontSize: 9, color: _C.muted)),
          ],
        ),
      ),
    );
  }

  // Feedback docs only carry `userId` + `isAnonymous` — this resolves real
  // names for the non-anonymous ones in one batched pass instead of a
  // per-row FutureBuilder (which would fire one Firestore read per row on
  // every rebuild).
  Future<Map<String, String>> _resolveFeedbackNames(
    List<Map<String, dynamic>> feedbacks,
  ) async {
    final names = <String, String>{};
    final uids = feedbacks
        .where((f) => f['isAnonymous'] != true)
        .map((f) => f['userId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final uid in uids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('students')
            .doc(uid)
            .get();
        if (doc.exists) {
          names[uid] = (doc.data()?['fullName'] as String?) ?? 'Unknown';
        }
      } catch (_) {}
    }
    return names;
  }

  // ── Feedback List Dialog ──────────────────────────────────────────────────
  void _showFeedbackListDialog(
    BuildContext context, {
    required String eventTitle,
    required List<Map<String, dynamic>> feedbacks,
    required _AnalyticsData data,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 640,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventTitle,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _C.charcoal,
                          ),
                        ),
                        Text(
                          '${feedbacks.length} feedback response${feedbacks.length == 1 ? '' : 's'}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _C.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const Divider(height: 20, color: _C.border),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: FutureBuilder<Map<String, String>>(
                    future: _resolveFeedbackNames(feedbacks),
                    builder: (context, nameSnap) {
                      final names = nameSnap.data ?? const {};
                      return SingleChildScrollView(
                        child: Column(
                          children: feedbacks.map((f) {
                            final rating = f['rating'] as int? ?? 0;
                            final comment = f['comment'] as String? ?? '';
                            final createdAt =
                                (f['submittedAt'] as Timestamp?)?.toDate() ??
                                DateTime.now();
                            final isAnonymous = f['isAnonymous'] == true;
                            final uid = f['userId']?.toString() ?? '';
                            final displayName = isAnonymous
                                ? 'Anonymous Student'
                                : (names[uid] ?? 'Unknown Student');

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _C.border.withOpacity(0.4),
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person_outline,
                                      size: 18,
                                      color: _C.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              displayName,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _C.muted,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildRatingStarsSmall(rating),
                                            const Spacer(),
                                            Text(
                                              DateFormat(
                                                'MMM dd, yyyy',
                                              ).format(createdAt),
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: _C.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (comment.isNotEmpty)
                                          Text(
                                            comment,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: _C.charcoal,
                                              height: 1.5,
                                            ),
                                          )
                                        else
                                          Text(
                                            'No comment provided',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: _C.muted,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
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

  Widget _buildRatingStarsSmall(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_border_rounded,
          size: 12,
          color: i < rating ? _C.amber : _C.border,
        );
      }),
    );
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
                const Icon(Icons.error_outline, color: _C.red, size: 48),
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

              return SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_DS.radiusLg),
                        border: Border.all(color: _C.border),
                        boxShadow: _DS.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTabBar(data),
                          [
                            _buildAnalyticsTab(data),
                            _buildEventsTab(data),
                          ][_tabCtrl.index],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTabBar(_AnalyticsData data) {
    final tabs = [
      ('Analytics', Icons.bar_chart_rounded, null),
      (
        'Events',
        Icons.event_note_rounded,
        data.events.isNotEmpty ? data.events.length.toString() : null,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _C.border)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(_DS.radiusLg)),
      ),
      child: Row(
        children: [
          ...tabs.asMap().entries.map((e) {
            final idx = e.key;
            final label = e.value.$1;
            final icon = e.value.$2;
            final badge = e.value.$3;
            final active = _tabCtrl.index == idx;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _tabCtrl.animateTo(idx)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: active
                            ? UpriseColors.primaryDark
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: active ? UpriseColors.primaryDark : _C.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? UpriseColors.primaryDark : _C.muted,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _C.blue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _C.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Live sync',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _C.green,
                  ),
                ),
                const SizedBox(width: 14),
                _RefreshButton(onTap: _refresh),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Analytics tab ──────────────────────────────────────────────────────────
  // Pure aggregate/graph view — anything about one specific event now lives
  // in that event's own detail dialog (see _buildEventsTab), not here, so
  // this tab doesn't duplicate the same per-event numbers two different ways.
  Widget _buildAnalyticsTab(_AnalyticsData data) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DistributionCard(data: data),
          const SizedBox(height: 20),
          _RatingByEventChart(data: data),
          const SizedBox(height: 20),
          _FinanceByEventChart(data: data),
        ],
      ),
    );
  }

  // ── Events tab — one card per event (banner, title, date, rating), tap
  // through to that event's own attendees/feedback/insights. ─────────────────
  Widget _buildEventsTab(_AnalyticsData data) {
    final avgByEvent = data.avgByEvent;
    final countByEvent = data.feedbackCountByEvent;

    var events = [...data.events];
    if (_eventsSearchQuery.isNotEmpty) {
      events = events
          .where(
            (e) => (e['title'] as String).toLowerCase().contains(
              _eventsSearchQuery,
            ),
          )
          .toList();
    }
    switch (_eventsSortBy) {
      case 'Highest Rated':
        events.sort(
          (a, b) =>
              (avgByEvent[b['id']] ?? -1).compareTo(avgByEvent[a['id']] ?? -1),
        );
        break;
      case 'Most Responses':
        events.sort(
          (a, b) => (countByEvent[b['id']] ?? 0).compareTo(
            countByEvent[a['id']] ?? 0,
          ),
        );
        break;
      case 'Name (A-Z)':
        events.sort(
          (a, b) => (a['title'] as String).toLowerCase().compareTo(
            (b['title'] as String).toLowerCase(),
          ),
        );
        break;
      default: // Most Recent
        events.sort((a, b) {
          final da = a['date'] as Timestamp?;
          final dbb = b['date'] as Timestamp?;
          if (da == null || dbb == null) return 0;
          return dbb.compareTo(da);
        });
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 640;
              final searchField = TextField(
                controller: _eventsSearchCtrl,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: _C.muted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: _C.muted,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: _C.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _C.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _C.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                ),
              );
              final sortDropdown = SizedBox(
                width: narrow ? double.infinity : 190,
                child: AnchoredDropdownField<String>(
                  value: _eventsSortBy,
                  items: _eventsSortOptions
                      .map(
                        (o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            o,
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _eventsSortBy = v ?? 'Most Recent'),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: _C.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _C.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _C.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: UpriseColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              );
              final exportButton = AdminExportButton(
                label: 'Export',
                enabled: events.isNotEmpty,
                onSelected: (choice) =>
                    _exportEventsSummary(choice, events, data),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: sortDropdown),
                        const SizedBox(width: 10),
                        exportButton,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  sortDropdown,
                  const SizedBox(width: 12),
                  exportButton,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy_outlined, size: 48, color: _C.border),
                    const SizedBox(height: 12),
                    Text(
                      data.events.isEmpty
                          ? 'No events found'
                          : 'No events match your search',
                      style: GoogleFonts.inter(fontSize: 14, color: _C.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width < 520
                    ? 1
                    : (width < 860 ? 2 : (width < 1180 ? 3 : 4));
                const spacing = 16.0;
                final cardWidth = (width - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: events.map((event) {
                    final eventId = event['id'] as String;
                    final title = event['title'] as String;
                    final bannerUrl = event['bannerUrl'] as String? ?? '';
                    final date = event['date'] as Timestamp?;
                    return SizedBox(
                      width: cardWidth,
                      child: _EventProductCard(
                        title: title,
                        bannerUrl: bannerUrl,
                        date: date?.toDate(),
                        avgRating: avgByEvent[eventId],
                        responseCount: countByEvent[eventId] ?? 0,
                        onTap: () => _showEventSummaryDialog(
                          context,
                          eventId: eventId,
                          eventTitle: title,
                          orgId: widget.orgId,
                          analyticsData: data,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _exportEventsSummary(
    String choice,
    List<Map<String, dynamic>> events,
    _AnalyticsData data,
  ) async {
    if (events.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No events to export')));
      return;
    }
    final avgByEvent = data.avgByEvent;
    final countByEvent = data.feedbackCountByEvent;
    final money = NumberFormat('#,###.00');
    final headers = [
      'Event',
      'Date',
      'Avg Rating',
      'Responses',
      'Income',
      'Expense',
      'Net',
    ];
    final rows = events.map((event) {
      final eventId = event['id'] as String;
      final title = event['title'] as String;
      final date = event['date'] as Timestamp?;
      final avg = avgByEvent[eventId];
      final count = countByEvent[eventId] ?? 0;
      final finance = data.financeForEvent(title);
      return [
        title,
        date != null ? DateFormat('MMM dd, yyyy').format(date.toDate()) : '—',
        avg != null ? avg.toStringAsFixed(1) : '—',
        '$count',
        finance != null ? money.format(finance.income) : '0.00',
        finance != null ? money.format(finance.expense) : '0.00',
        finance != null
            ? money.format(finance.income - finance.expense)
            : '0.00',
      ];
    }).toList();

    try {
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      if (choice == 'csv') {
        final csv = [
          headers,
          ...rows,
        ].map((row) => row.map((c) => '"$c"').join(',')).join('\n');
        await OrgExportUtil.saveText(
          csv,
          'event_analytics_$stamp.csv',
          mimeType: 'text/csv',
        );
      } else if (choice == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Event Analytics',
          headers: headers,
          rows: rows,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'event_analytics_$stamp.pdf',
          mimeType: 'application/pdf',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${rows.length} events')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Supporting widgets
// ════════════════════════════════════════════════════════════════════════════

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RefreshButton({required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: const Icon(
      Icons.refresh_rounded,
      size: 15,
      color: UpriseColors.darkGray,
    ),
    label: Text(
      'Refresh',
      style: GoogleFonts.beVietnamPro(
        fontSize: 12.5,
        color: UpriseColors.darkGray,
      ),
    ),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: UpriseColors.mediumGray),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// Color for a 1-5 rating, shared by every rating pill/bar in this file.
Color _ratingColor(double score) =>
    score >= 4.0 ? _C.green : (score >= 3.0 ? _C.amber : _C.red);

// Ecommerce-style product card for one event: banner, title, date, avg
// rating. Tapping it opens the full attendees/feedback/insights dialog.
class _EventProductCard extends StatelessWidget {
  final String title;
  final String bannerUrl;
  final DateTime? date;
  final double? avgRating;
  final int responseCount;
  final VoidCallback onTap;
  const _EventProductCard({
    required this.title,
    required this.bannerUrl,
    required this.date,
    required this.avgRating,
    required this.responseCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avg = avgRating;
    return Container(
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border),
        boxShadow: _DS.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0xFFF8F9FB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: bannerUrl.isNotEmpty
                    ? EventImage(
                        imageUrl: bannerUrl,
                        fit: BoxFit.cover,
                        showLoadingIndicator: false,
                      )
                    : Container(
                        color: _C.surface,
                        child: Icon(
                          Icons.image_outlined,
                          size: 32,
                          color: _C.border,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _C.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (date != null)
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: _C.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(date!),
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: _C.muted,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    if (avg != null)
                      Row(
                        children: [
                          Icon(Icons.star_rounded, size: 15, color: _C.amber),
                          const SizedBox(width: 3),
                          Text(
                            avg.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _ratingColor(avg),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '($responseCount)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _C.muted,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'No ratings yet',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: _C.muted,
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
}

class _RatingByEventChart extends StatelessWidget {
  final _AnalyticsData data;
  const _RatingByEventChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final sorted = data.avgByEvent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border.withOpacity(0.5)),
        boxShadow: _DS.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    size: 16,
                    color: _C.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Average rating by event',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _C.charcoal,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No feedback data yet',
                  style: GoogleFonts.inter(fontSize: 13, color: _C.muted),
                ),
              ),
            )
          else
            // Capped to ~5 rows visible with the rest reachable by scrolling
            // inside this box, instead of the list just growing the whole
            // page taller the more events an org has.
            SizedBox(
              height: math.min(sorted.length * 50.0, 5 * 50.0),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final entry = sorted[i];
                  final title = data.eventDisplayTitle(entry.key);
                  final score = entry.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: _C.charcoal,
                              ),
                            ),
                          ),
                          Text(
                            score.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _ratingColor(score),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: score / 5.0,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: _ratingColor(score),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FinanceByEventChart extends StatelessWidget {
  final _AnalyticsData data;
  const _FinanceByEventChart({required this.data});

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: _C.muted)),
      ],
    );
  }

  Widget _financeBar(double value, double maxValue, Color color) {
    final fraction = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: fraction,
        backgroundColor: const Color(0xFFF1F5F9),
        color: color,
        minHeight: 6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final finance = data.financeByEventTitle;
    final money = NumberFormat('#,###.00');

    if (finance.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.payments_outlined, size: 18, color: _C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No financial records tied to an event yet — transactions '
                'in Finance whose event name matches an event here will show '
                'up as a chart.',
                style: GoogleFonts.inter(fontSize: 12.5, color: _C.muted),
              ),
            ),
          ],
        ),
      );
    }

    final maxValue = finance.values.fold<double>(
      0,
      (m, f) => math.max(m, math.max(f.income, f.expense)),
    );
    final entries = finance.entries.toList()
      ..sort(
        (a, b) => (b.value.income - b.value.expense).abs().compareTo(
          (a.value.income - a.value.expense).abs(),
        ),
      );

    return Container(
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border.withOpacity(0.5)),
        boxShadow: _DS.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    size: 16,
                    color: _C.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Income vs. expense by event',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _C.charcoal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _legendDot(_C.green, 'Income'),
                          const SizedBox(width: 14),
                          _legendDot(_C.red, 'Expense'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          // Same capped-and-scrollable treatment as _RatingByEventChart's
          // list, just a taller per-row estimate since each row here has two
          // bars (income + expense) instead of one.
          SizedBox(
            height: math.min(entries.length * 70.0, 5 * 70.0),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final entry = entries[i];
                final title = entry.key;
                final f = entry.value;
                final net = f.income - f.expense;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: _C.charcoal,
                            ),
                          ),
                        ),
                        Text(
                          net >= 0
                              ? '+₱${money.format(net)}'
                              : '-₱${money.format(-net)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: net >= 0 ? _C.green : _C.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _financeBar(f.income, maxValue, _C.green),
                    const SizedBox(height: 4),
                    _financeBar(f.expense, maxValue, _C.red),
                  ],
                );
              },
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
    final total = data.totalFeedbacks;

    final segs = [
      _Seg(5, counts[5]!, const Color(0xFF10B981)),
      _Seg(4, counts[4]!, const Color(0xFF34D399)),
      _Seg(3, counts[3]!, const Color(0xFFFBBF24)),
      _Seg(2, counts[2]!, const Color(0xFFFB923C)),
      _Seg(1, counts[1]!, const Color(0xFFF87171)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border.withOpacity(0.5)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insert_chart_outlined,
                  size: 16,
                  color: _C.amber,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Rating distribution',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _C.charcoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Container(
              height: 140,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.insert_chart_outlined, size: 40, color: _C.border),
                  const SizedBox(height: 8),
                  Text(
                    'No feedback yet',
                    style: GoogleFonts.inter(fontSize: 13, color: _C.muted),
                  ),
                ],
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      segs: segs,
                      total: total,
                      label: data.avgRating.toStringAsFixed(1),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: segs.map((s) {
                      final pct = total > 0
                          ? (s.count / total * 100).toStringAsFixed(0)
                          : '0';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: s.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${s.stars} star${s.stars > 1 ? 's' : ''}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _C.muted,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: s.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$pct%',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: s.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Seg {
  final int stars, count;
  final Color color;
  const _Seg(this.stars, this.count, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<_Seg> segs;
  final int total;
  final String label;
  const _DonutPainter({
    required this.segs,
    required this.total,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 14;
    const sw = 24.0, gap = 0.012;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;

    if (total == 0) {
      paint.color = const Color(0xFFE5E7EB);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    } else {
      double start = -math.pi / 2;
      final nonZero = segs.where((s) => s.count > 0).length;
      for (final s in segs) {
        if (s.count == 0) continue;
        final sweep = s.count / total * 2 * math.pi;
        final actual = nonZero > 1 ? math.max(0.0, sweep - gap) : sweep;
        paint.color = s.color;
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

    final bigStyle = GoogleFonts.inter(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: _C.charcoal,
    );
    final smStyle = GoogleFonts.inter(
      fontSize: 11,
      color: _C.muted,
      fontWeight: FontWeight.w500,
    );

    final tp1 = TextPainter(
      text: TextSpan(text: label, style: bigStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final tp2 = TextPainter(
      text: TextSpan(text: 'average', style: smStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    tp1.paint(canvas, ui.Offset(cx - tp1.width / 2, cy - tp1.height / 2 - 7));
    tp2.paint(canvas, ui.Offset(cx - tp2.width / 2, cy + tp1.height / 2 - 3));
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total || old.label != label;
}

class _InsightTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String body;
  final String? note;
  const _InsightTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.body,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: color.withAlpha(46)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _C.charcoal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _C.muted,
                    height: 1.4,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    note!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
