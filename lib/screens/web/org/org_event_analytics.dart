// lib/screens/web/org/org_event_analytics.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import '../../../theme/app_theme.dart';

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

  static final cardShadowHover = [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
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

  final Map<String, String> _eventTitleCache = {};

  _AnalyticsData({
    required this.feedbacks,
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

  ({String title, double score})? get highestRatedEvent {
    final avg = avgByEvent;
    if (avg.isEmpty) return null;
    final entry = avg.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (title: eventDisplayTitle(entry.key), score: entry.value);
  }

  ({String title, double score})? get lowestRatedEvent {
    final avg = avgByEvent;
    if (avg.isEmpty) return null;
    final entry = avg.entries.reduce((a, b) => a.value <= b.value ? a : b);
    return (title: eventDisplayTitle(entry.key), score: entry.value);
  }
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

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedEvent = 'All Events';
  int? _selectedRating;
  static const int _feedbackPageSize = 5;
  int _feedbackShowCount = _feedbackPageSize;

  // For attendees tab
  String _selectedAttendeeEvent = '';
  String _attendeeStatusFilter = 'All';
  final TextEditingController _attendeeSearchCtrl = TextEditingController();
  String _attendeeSearchQuery = '';

  StreamSubscription<QuerySnapshot>? _feedbackSubscription;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _dataFuture = _loadAll();
    _searchCtrl.addListener(
      () => setState(() {
        _searchQuery = _searchCtrl.text.toLowerCase().trim();
        _feedbackShowCount = _feedbackPageSize;
      }),
    );
    _attendeeSearchCtrl.addListener(
      () => setState(
        () => _attendeeSearchQuery = _attendeeSearchCtrl.text
            .toLowerCase()
            .trim(),
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
    _searchCtrl.dispose();
    _attendeeSearchCtrl.dispose();
    _feedbackSubscription?.cancel();
    super.dispose();
  }

  Future<_AnalyticsData> _loadAll() async {
    final db = FirebaseFirestore.instance;

    try {
      final feedbackSnapshot = await db.collection('feedback').get();

      final eventsSnapshot = await db
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      final evalFormsSnapshot = await db
          .collection('eval_forms')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      final feedbacks = feedbackSnapshot.docs
          .map(
            (d) => {
              ...d.data(),
              'id': d.id,
              'eventId': d.data()['eventId'] as String? ?? '',
            },
          )
          .toList();

      final events = eventsSnapshot.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': data['title'] as String? ?? 'Untitled Event',
          'eventId': data['eventId'] as String? ?? d.id,
          'date': data['date'],
        };
      }).toList();

      final evalForms = evalFormsSnapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

      return _AnalyticsData(
        feedbacks: feedbacks,
        events: events,
        evalForms: evalForms,
      );
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      rethrow;
    }
  }

  void _listenForUpdates() {
    _feedbackSubscription?.cancel();
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
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadAll();
      _searchCtrl.clear();
      _selectedEvent = 'All Events';
      _selectedRating = null;
      _selectedAttendeeEvent = '';
      _attendeeStatusFilter = 'All';
      _attendeeSearchCtrl.clear();
    });
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> feedbacks,
    _AnalyticsData data,
  ) {
    return feedbacks.where((f) {
      final eventId = f['eventId'] as String? ?? '';
      final eventTitle = data.eventDisplayTitle(eventId).toLowerCase();
      final comment = (f['comment'] as String? ?? '').toLowerCase();
      final rating = f['rating'] as int? ?? 0;

      final matchSearch =
          _searchQuery.isEmpty ||
          eventTitle.contains(_searchQuery) ||
          comment.contains(_searchQuery);
      final matchEvent =
          _selectedEvent == 'All Events' ||
          data.eventTitle(eventId) == _selectedEvent;
      final matchRating = _selectedRating == null || rating == _selectedRating;

      return matchSearch && matchEvent && matchRating;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedEvent != 'All Events' ||
      _selectedRating != null;

  Future<void> _exportAnalytics(String choice, _AnalyticsData data) async {
    final filtered = _applyFilters([...data.feedbacks], data)
      ..sort((a, b) {
        final ta =
            (a['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb =
            (b['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

    if (filtered.isEmpty) {
      _snack('No records to export', isError: true);
      return;
    }

    final rows = filtered.asMap().entries.map((e) {
      final f = e.value;
      final title = data.eventDisplayTitle(f['eventId'] as String? ?? '');
      final date = (f['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      return [
        '${e.key + 1}',
        title,
        '${f['rating'] ?? ''}',
        (f['comment'] as String? ?? '').replaceAll('"', '""'),
        DateFormat('MMM dd, yyyy').format(date),
      ];
    }).toList();

    try {
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      if (choice == 'csv') {
        final csv = [
          ['#', 'Event', 'Rating', 'Comment', 'Date'],
          ...rows,
        ].map((row) => row.map((c) => '"$c"').join(',')).join('\n');
        await OrgExportUtil.saveText(
          csv,
          'feedback_$stamp.csv',
          mimeType: 'text/csv',
        );
      } else if (choice == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Event Feedback',
          headers: ['#', 'Event', 'Rating', 'Comment', 'Date'],
          rows: rows,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'feedback_$stamp.pdf',
          mimeType: 'application/pdf',
        );
      }
      _snack('Exported ${filtered.length} records');
    } catch (e) {
      _snack('Export failed: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: isError ? _C.red : _C.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Event Summary Dialog ──────────────────────────────────────────────────
  void _showEventSummaryDialog(
    BuildContext context, {
    required String eventId,
    required String eventTitle,
    required String orgId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 640,
          constraints: const BoxConstraints(maxHeight: 640),
          padding: const EdgeInsets.all(24),
          child: Column(
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
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('events')
                    .doc(eventId)
                    .collection('attendances')
                    .snapshots(),
                builder: (ctx, attSnap) {
                  final attDocs = attSnap.data?.docs ?? [];
                  final totalAttendees = attDocs.length;
                  final present = attDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return data['status'] == 'present';
                  }).length;
                  final late = attDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return data['status'] == 'late';
                  }).length;
                  final absent = totalAttendees - present - late;

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('feedback')
                        .where('eventId', isEqualTo: eventId)
                        .snapshots(),
                    builder: (ctx, feedbackSnap) {
                      final feedbackDocs = feedbackSnap.data?.docs ?? [];
                      final feedbackCount = feedbackDocs.length;
                      final notYetFeedback = totalAttendees - feedbackCount;

                      final studentIdsWithFeedback = feedbackDocs
                          .map(
                            (d) =>
                                (d.data() as Map<String, dynamic>)['userId']
                                    ?.toString() ??
                                '',
                          )
                          .where((id) => id.isNotEmpty)
                          .toSet();

                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: _getAttendeesWithNames(attDocs),
                        builder: (ctx, attendeeSnap) {
                          final attendees = attendeeSnap.data ?? [];

                          return Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildSummaryStat(
                                      'Total',
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
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _C.surface,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.feedback_rounded,
                                        size: 16,
                                        color: _C.blue,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$feedbackCount gave feedback',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _C.charcoal,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Icon(
                                        Icons.pending_rounded,
                                        size: 16,
                                        color: _C.amber,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$notYetFeedback pending',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _C.charcoal,
                                        ),
                                      ),
                                    ],
                                  ),
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
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _C.border.withOpacity(0.4),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SingleChildScrollView(
                                      child: attendees.isEmpty
                                          ? Padding(
                                              padding: const EdgeInsets.all(32),
                                              child: Center(
                                                child: Column(
                                                  children: [
                                                    Icon(
                                                      Icons.people_outline,
                                                      size: 40,
                                                      color: _C.border,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'No attendees yet',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        color: _C.muted,
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
                                                            .withOpacity(0.3),
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
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          studentName,
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color:
                                                                    _C.charcoal,
                                                              ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: hasFeedback
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
                                                                FontWeight.w600,
                                                            color: hasFeedback
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
                            ),
                          );
                        },
                      );
                    },
                  );
                },
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
          constraints: const BoxConstraints(maxHeight: 560),
          padding: const EdgeInsets.all(24),
          child: Column(
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
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: i < rating ? _C.amber : _C.border,
        );
      }),
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
        final filtered = _applyFilters([...data.feedbacks], data);
        final eventOptions = ['All Events', ...data.eventTitles];

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
                    _buildStatsRow(data, isMobile),
                    SizedBox(height: isMobile ? 14 : 20),
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
                            _buildFeedbackTab(
                              data,
                              filtered,
                              eventOptions,
                              isMobile,
                            ),
                            _buildAttendeesTab(data),
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

  Widget _buildStatsRow(_AnalyticsData data, bool isMobile) {
    final highest = data.highestRatedEvent;
    final lowest = data.lowestRatedEvent;

    void goToTab(int index) => setState(() => _tabCtrl.animateTo(index));

    final cards = [
      _StatCardData(
        'Total evaluations',
        data.totalFeedbacks.toString(),
        Icons.assignment_outlined,
        _C.blue,
        isSelected: _tabCtrl.index == 1,
        onTap: () => goToTab(1),
      ),
      _StatCardData(
        'Average rating',
        data.totalFeedbacks > 0 ? data.avgRating.toStringAsFixed(1) : '—',
        Icons.star_outline,
        _C.amber,
        isSelected: _tabCtrl.index == 1,
        onTap: () => goToTab(1),
      ),
      _StatCardData(
        'Highest rated',
        highest != null ? highest.title : '—',
        Icons.emoji_events_outlined,
        _C.green,
        isSelected: _tabCtrl.index == 0,
        onTap: () => goToTab(0),
        valueFontSize: 15,
      ),
      _StatCardData(
        'Needs improvement',
        lowest != null ? lowest.title : '—',
        Icons.trending_down_rounded,
        UpriseColors.primaryDark,
        isSelected: _tabCtrl.index == 0,
        onTap: () => goToTab(0),
        valueFontSize: 15,
      ),
    ];

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StatCard(c),
              ),
            )
            .toList(),
      );
    }

    return Row(
      children: cards.asMap().entries.map((e) {
        final c = e.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key == 0 ? 0 : 14),
            child: _StatCard(c),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabBar(_AnalyticsData data) {
    final tabs = [
      ('Analytics', Icons.bar_chart_rounded, null),
      (
        'Feedback',
        Icons.forum_outlined,
        data.totalFeedbacks > 0 ? data.totalFeedbacks.toString() : null,
      ),
      ('Attendees', Icons.people_alt_rounded, null),
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
            return GestureDetector(
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
  Widget _buildAnalyticsTab(_AnalyticsData data) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 900;
              final satisfaction = _SatisfactionCard(data: data);
              final distribution = _DistributionCard(data: data);
              if (stack) {
                return Column(
                  children: [
                    satisfaction,
                    const SizedBox(height: 20),
                    distribution,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: satisfaction),
                  const SizedBox(width: 20),
                  Expanded(child: distribution),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _CompletionCard(
            data: data,
            orgId: widget.orgId,
            onEventTap: (eventId, eventTitle) {
              _showEventSummaryDialog(
                context,
                eventId: eventId,
                eventTitle: eventTitle,
                orgId: widget.orgId,
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Feedback tab ───────────────────────────────────────────────────────────
  Widget _buildFeedbackTab(
    _AnalyticsData data,
    List<Map<String, dynamic>> filtered,
    List<String> eventOptions,
    bool isMobile,
  ) {
    final Map<String, List<Map<String, dynamic>>> feedbackByEvent = {};
    for (final f in filtered) {
      final eventId = f['eventId'] as String? ?? '';
      final title = data.eventDisplayTitle(eventId);
      feedbackByEvent.putIfAbsent(title, () => []).add(f);
    }

    final sortedEvents = feedbackByEvent.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Feedback by event',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _C.charcoal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${filtered.length} total responses',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildFeedbackFilterBar(data, eventOptions),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 12),
            _ActiveFilterChips(
              searchQuery: _searchQuery,
              selectedEvent: _selectedEvent,
              selectedRating: _selectedRating,
              filteredCount: filtered.length,
              totalCount: data.totalFeedbacks,
              onRemoveSearch: () => _searchCtrl.clear(),
              onRemoveEvent: () => setState(() {
                _selectedEvent = 'All Events';
                _feedbackShowCount = _feedbackPageSize;
              }),
              onRemoveRating: () => setState(() {
                _selectedRating = null;
                _feedbackShowCount = _feedbackPageSize;
              }),
              onClearAll: () => setState(() {
                _searchCtrl.clear();
                _selectedEvent = 'All Events';
                _selectedRating = null;
                _feedbackShowCount = _feedbackPageSize;
              }),
            ),
          ],
          const SizedBox(height: 16),
          if (sortedEvents.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_DS.radiusMd),
                border: Border.all(color: _C.border),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off,
                      size: 42,
                      color: Color(0xFFD1D5DB),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No feedback matches your filters',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...sortedEvents.take(_feedbackShowCount).map((entry) {
              final eventTitle = entry.key;
              final feedbacks = entry.value;
              final count = feedbacks.length;
              final avgRating =
                  feedbacks.fold<double>(
                    0.0,
                    (sum, f) => sum + ((f['rating'] as int? ?? 0) as double),
                  ) /
                  count;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusMd),
                  border: Border.all(color: _C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eventTitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _C.charcoal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _buildRatingStars(avgRating.round()),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${avgRating.toStringAsFixed(1)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _C.charcoal,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _C.surface,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$count response${count == 1 ? '' : 's'}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _C.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              _showFeedbackListDialog(
                                context,
                                eventTitle: eventTitle,
                                feedbacks: feedbacks,
                                data: data,
                              );
                            },
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                            ),
                            label: Text(
                              'View',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: UpriseColors.primaryDark,
                              side: BorderSide(
                                color: UpriseColors.primaryDark.withOpacity(
                                  0.3,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (feedbacks.isNotEmpty) ...[
                      const Divider(height: 1, color: _C.border),
                      FutureBuilder<Map<String, String>>(
                        future: _resolveFeedbackNames(
                          feedbacks.take(2).toList(),
                        ),
                        builder: (context, nameSnap) {
                          final names = nameSnap.data ?? const {};
                          return Column(
                            children: feedbacks.take(2).map((f) {
                              final comment = f['comment'] as String? ?? '';
                              if (comment.isEmpty)
                                return const SizedBox.shrink();
                              final isAnonymous = f['isAnonymous'] == true;
                              final uid = f['userId']?.toString() ?? '';
                              final displayName = isAnonymous
                                  ? 'Anonymous Student'
                                  : (names[uid] ?? 'Unknown Student');
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.person_outline,
                                        size: 14,
                                        color: _C.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: _C.muted,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            comment,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: _C.charcoal,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildRatingStarsSmall(
                                      f['rating'] as int? ?? 0,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      if (feedbacks.length > 2)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            '+${feedbacks.length - 2} more responses',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _C.muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            }),
          if (sortedEvents.length > _feedbackShowCount)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _feedbackShowCount += _feedbackPageSize),
                  icon: const Icon(Icons.expand_more_rounded, size: 16),
                  label: Text(
                    'Show more (${sortedEvents.length - _feedbackShowCount} remaining)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: UpriseColors.primaryDark,
                    side: BorderSide(
                      color: UpriseColors.primaryDark.withOpacity(0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackFilterBar(
    _AnalyticsData data,
    List<String> eventOptions,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth > 900;
        final fieldWidth = useRow ? 360.0 : double.infinity;

        final searchField = SizedBox(
          width: fieldWidth,
          height: 42,
          child: TextField(
            controller: _searchCtrl,
            style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.charcoal),
            decoration: InputDecoration(
              hintText: 'Search event name or feedback comment…',
              hintStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: _C.muted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: _C.muted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 15, color: _C.muted),
                      onPressed: _searchCtrl.clear,
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _C.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: UpriseColors.primaryDark,
                  width: 1.5,
                ),
              ),
            ),
          ),
        );

        final actionControls = [
          _FilterDropdown(
            value: _selectedEvent,
            items: eventOptions,
            onChanged: (v) => setState(() {
              _selectedEvent = v ?? 'All Events';
              _feedbackShowCount = _feedbackPageSize;
            }),
          ),
          _FilterDropdown(
            value: _selectedRating == null
                ? 'All Ratings'
                : '$_selectedRating ★',
            items: ['All Ratings', ...List.generate(5, (i) => '${5 - i} ★')],
            onChanged: (v) => setState(() {
              _feedbackShowCount = _feedbackPageSize;
              _selectedRating = v == 'All Ratings'
                  ? null
                  : int.tryParse(v?.split(' ').first ?? '');
            }),
          ),
          AdminExportButton(
            label: 'Export',
            onSelected: (c) => _exportAnalytics(c, data),
          ),
        ];

        if (useRow) {
          return Row(
            children: [
              searchField,
              const SizedBox(width: 12),
              ...actionControls
                  .expand((w) => [w, const SizedBox(width: 10)])
                  .toList()
                ..removeLast(),
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [searchField, ...actionControls],
        );
      },
    );
  }

  Widget _hCell(String t) => Text(
    t.toUpperCase(),
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: _C.muted,
      letterSpacing: 0.8,
    ),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // ATTENDEES TAB
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildAttendeesTab(_AnalyticsData data) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Event Attendees',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _C.charcoal,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${data.events.length} events',
                  style: GoogleFonts.inter(fontSize: 12, color: _C.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildAttendeeFilterBar(data),
          const SizedBox(height: 16),
          _buildAttendeeContent(data),
        ],
      ),
    );
  }

  Widget _buildAttendeeFilterBar(_AnalyticsData data) {
    final eventOptions = ['Select an event...', ...data.eventTitles];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border.withOpacity(0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRow = constraints.maxWidth > 700;

          final eventDropdown = Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedAttendeeEvent.isEmpty
                    ? 'Select an event...'
                    : _selectedAttendeeEvent,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: _C.muted,
                ),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.charcoal,
                ),
                isExpanded: true,
                items: eventOptions.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null && v != 'Select an event...') {
                    setState(() {
                      _selectedAttendeeEvent = v;
                    });
                  } else {
                    setState(() {
                      _selectedAttendeeEvent = '';
                    });
                  }
                },
              ),
            ),
          );

          final searchField = SizedBox(
            width: useRow ? 200 : double.infinity,
            height: 42,
            child: TextField(
              controller: _attendeeSearchCtrl,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.charcoal),
              decoration: InputDecoration(
                hintText: 'Search attendees...',
                hintStyle: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: _C.muted,
                ),
                suffixIcon: _attendeeSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 15,
                          color: _C.muted,
                        ),
                        onPressed: () {
                          _attendeeSearchCtrl.clear();
                          setState(() => _attendeeSearchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _C.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _C.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: UpriseColors.primaryDark,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          );

          final statusFilter = Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _attendeeStatusFilter,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: _C.muted,
                ),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.charcoal,
                ),
                items: const ['All', 'present', 'late', 'absent'].map((s) {
                  final label = s == 'All'
                      ? 'All Status'
                      : s[0].toUpperCase() + s.substring(1);
                  return DropdownMenuItem(
                    value: s,
                    child: Text(
                      label,
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _attendeeStatusFilter = v);
                  }
                },
              ),
            ),
          );

          if (useRow) {
            return Row(
              children: [
                Expanded(flex: 2, child: eventDropdown),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: searchField),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: statusFilter),
              ],
            );
          }

          return Column(
            children: [
              eventDropdown,
              const SizedBox(height: 10),
              searchField,
              const SizedBox(height: 10),
              statusFilter,
            ],
          );
        },
      ),
    );
  }

  Widget _buildAttendeeContent(_AnalyticsData data) {
    if (_selectedAttendeeEvent.isEmpty ||
        _selectedAttendeeEvent == 'Select an event...') {
      return _buildEventList(data);
    }

    final selectedEvent = data.events.firstWhere(
      (e) => e['title'] == _selectedAttendeeEvent,
      orElse: () => {},
    );
    final eventId = selectedEvent['id'] as String?;

    if (eventId == null) {
      return _buildEventList(data);
    }

    return _buildAttendeeList(data, eventId);
  }

  Widget _buildEventList(_AnalyticsData data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border(
                bottom: BorderSide(
                  color: UpriseColors.primaryDark.withAlpha(60),
                ),
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: _hCell('EVENT')),
                Expanded(flex: 2, child: _hCell('DATE')),
                Expanded(flex: 2, child: _hCell('ATTENDEES')),
                Expanded(flex: 2, child: _hCell('STATUS')),
              ],
            ),
          ),
          if (data.events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 42, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 10),
                    Text(
                      'No events found',
                      style: TextStyle(fontSize: 13, color: _C.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            ...data.events.asMap().entries.map((entry) {
              final i = entry.key;
              final event = entry.value;
              final eventId = event['id'] as String;
              final title = event['title'] as String;
              final date = event['date'] as Timestamp?;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('events')
                    .doc(eventId)
                    .collection('attendances')
                    .snapshots(),
                builder: (ctx, attSnap) {
                  final attDocs = attSnap.data?.docs ?? [];
                  final total = attDocs.length;
                  final present = attDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return data['status'] == 'present';
                  }).length;
                  final late = attDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return data['status'] == 'late';
                  }).length;

                  final isLast = i == data.events.length - 1;
                  final hasAttendees = total > 0;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedAttendeeEvent = title;
                      });
                    },
                    hoverColor: const Color(0xFFF8F9FB),
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
                            flex: 4,
                            child: Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: hasAttendees ? _C.green : _C.muted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      color: _C.charcoal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              date != null
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(date.toDate())
                                  : '—',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _C.muted,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: hasAttendees
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hasAttendees ? '$total' : '0',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: hasAttendees
                                      ? const Color(0xFF166534)
                                      : _C.muted,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                if (present > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _C.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$present ✓',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _C.green,
                                      ),
                                    ),
                                  ),
                                if (late > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _C.amber.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$late ⏰',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _C.amber,
                                      ),
                                    ),
                                  ),
                                ],
                                if (total == 0)
                                  Text(
                                    'No check-ins',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: _C.muted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (hasAttendees)
                            AnchoredMenuTrigger<String>(
                              items: const ['csv', 'pdf'],
                              menuWidth: 170,
                              itemBuilder: (value, selected) => Row(
                                children: [
                                  Icon(
                                    value == 'csv'
                                        ? Icons.table_chart_rounded
                                        : Icons.picture_as_pdf_rounded,
                                    size: 15,
                                    color: const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value == 'csv'
                                        ? 'Export as CSV'
                                        : 'Export as PDF',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                              onSelected: (choice) async {
                                final attendees = await _getAttendeesWithNames(
                                  attDocs,
                                );
                                _exportAttendees(
                                  choice,
                                  attendees,
                                  data,
                                  eventTitleOverride: title,
                                );
                              },
                              trigger: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.download_rounded,
                                  size: 17,
                                  color: _C.muted,
                                ),
                              ),
                            ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: _C.muted,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          if (data.events.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: const Border(top: BorderSide(color: _C.border)),
                color: _C.surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(_DS.radiusMd),
                ),
              ),
              child: Text(
                '${data.events.length} events',
                style: GoogleFonts.inter(fontSize: 12, color: _C.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendeeList(_AnalyticsData data, String eventId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .collection('attendances')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (ctx, attSnap) {
        if (attSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final attDocs = attSnap.data?.docs ?? [];

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getAttendeesWithNames(attDocs),
          builder: (ctx, attendeeSnap) {
            if (attendeeSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final attendees = attendeeSnap.data ?? [];

            final filtered = attendees.where((a) {
              final name = (a['studentName'] ?? '').toLowerCase();
              final status = (a['status'] ?? '').toLowerCase();

              final matchSearch =
                  _attendeeSearchQuery.isEmpty ||
                  name.contains(_attendeeSearchQuery);
              final matchStatus =
                  _attendeeStatusFilter == 'All' ||
                  status == _attendeeStatusFilter;

              return matchSearch && matchStatus;
            }).toList();

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('feedback')
                  .where('eventId', isEqualTo: eventId)
                  .snapshots(),
              builder: (ctx, feedbackSnap) {
                final feedbackDocs = feedbackSnap.data?.docs ?? [];
                final studentIdsWithFeedback = feedbackDocs
                    .map(
                      (d) =>
                          (d.data() as Map<String, dynamic>)['userId']
                              ?.toString() ??
                          '',
                    )
                    .where((id) => id.isNotEmpty)
                    .toSet();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedAttendeeEvent = '';
                              _attendeeSearchCtrl.clear();
                              _attendeeSearchQuery = '';
                              _attendeeStatusFilter = 'All';
                            });
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: Text(
                            'Back to events',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _C.muted,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _C.muted,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _C.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${filtered.length} of ${attendees.length} attendees',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _C.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AdminExportButton(
                          enabled: filtered.isNotEmpty,
                          label: 'Export',
                          onSelected: (choice) {
                            _exportAttendees(choice, filtered, data);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8ECF0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              border: Border(
                                bottom: BorderSide(
                                  color: UpriseColors.primaryDark.withAlpha(60),
                                ),
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(14),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 4, child: _hCell('STUDENT')),
                                Expanded(flex: 2, child: _hCell('STATUS')),
                                Expanded(flex: 3, child: _hCell('TIME IN')),
                                Expanded(flex: 2, child: _hCell('FEEDBACK')),
                              ],
                            ),
                          ),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 42,
                                      color: Color(0xFFD1D5DB),
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'No attendees match your filters',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _C.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ...filtered.asMap().entries.map((entry) {
                              final i = entry.key;
                              final attendee = entry.value;
                              final isLast = i == filtered.length - 1;
                              final name = attendee['studentName'] ?? 'Unknown';
                              final status = attendee['status'] ?? 'present';
                              final uid =
                                  attendee['studentId']?.toString() ?? '';
                              final hasFeedback =
                                  uid.isNotEmpty &&
                                  studentIdsWithFeedback.contains(uid);

                              // Find timestamp from attendance doc
                              QueryDocumentSnapshot attDoc;
                              try {
                                attDoc = attDocs.firstWhere(
                                  (d) =>
                                      (d.data()
                                              as Map<
                                                String,
                                                dynamic
                                              >)['studentId']
                                          ?.toString() ==
                                      uid,
                                );
                              } catch (_) {
                                attDoc = attDocs.isNotEmpty
                                    ? attDocs.first
                                    : attDocs.first;
                              }

                              final attData =
                                  attDoc.data() as Map<String, dynamic>;
                              final timestamp =
                                  (attData['timestamp'] as Timestamp?)
                                      ?.toDate();

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : const Border(
                                          bottom: BorderSide(
                                            color: Color(0xFFF1F5F9),
                                          ),
                                        ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _C.blue,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: GoogleFonts.inter(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w500,
                                                color: _C.charcoal,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(flex: 2, child: _attBadge(status)),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        timestamp != null
                                            ? DateFormat(
                                                'hh:mm a, MMM dd',
                                              ).format(timestamp)
                                            : '—',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: _C.muted,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hasFeedback
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          hasFeedback ? '✓ Given' : 'Pending',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: hasFeedback
                                                ? const Color(0xFF166534)
                                                : _C.muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          if (filtered.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: const Border(
                                  top: BorderSide(color: _C.border),
                                ),
                                color: _C.surface,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(_DS.radiusMd),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${filtered.length} attendee${filtered.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _C.muted,
                                    ),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      _buildStatusDot('present', _C.green),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${attendees.where((a) => a['status'] == 'present').length}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _C.muted,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildStatusDot('late', _C.amber),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${attendees.where((a) => a['status'] == 'late').length}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _C.muted,
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
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatusDot(String status, Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ── Export Attendees ──────────────────────────────────────────────────────
  Future<void> _exportAttendees(
    String choice,
    List<Map<String, dynamic>> attendees,
    _AnalyticsData data, {
    String? eventTitleOverride,
  }) async {
    if (attendees.isEmpty) {
      _snack('No attendees to export', isError: true);
      return;
    }

    final List<List<String>> rows = attendees.asMap().entries.map((e) {
      final a = e.value;
      final ts = a['timestamp'] as Timestamp?;
      return <String>[
        '${e.key + 1}',
        '${a['studentName'] ?? ''}',
        '${a['studentId'] ?? ''}',
        '${a['status'] ?? ''}',
        ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : '—',
      ];
    }).toList();

    final titleForExport = eventTitleOverride ?? _selectedAttendeeEvent;

    try {
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final eventTitle = titleForExport.replaceAll(' ', '_');

      if (choice == 'csv') {
        final csv = [
          ['#', 'Student Name', 'Student ID', 'Status', 'Time In'],
          ...rows,
        ].map((row) => row.map((c) => '"$c"').join(',')).join('\n');
        await OrgExportUtil.saveText(
          csv,
          'attendees_${eventTitle}_$stamp.csv',
          mimeType: 'text/csv',
        );
      } else if (choice == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Attendees - $titleForExport',
          headers: ['#', 'Student Name', 'Student ID', 'Status', 'Time In'],
          rows: rows,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'attendees_${eventTitle}_$stamp.pdf',
          mimeType: 'application/pdf',
        );
      }
      _snack('Exported ${attendees.length} attendees');
    } catch (e) {
      _snack('Export failed: $e', isError: true);
    }
  }

  Widget _attBadge(String status) {
    final Map<String, (Color, Color, Color, String)> s = {
      'present': (
        const Color(0xFFECFDF5),
        const Color(0xFF059669),
        const Color(0xFFBBF7D0),
        'PRESENT',
      ),
      'late': (
        const Color(0xFFFFFBEB),
        const Color(0xFFFB923C),
        const Color(0xFFFDE68A),
        'LATE',
      ),
      'absent': (
        const Color(0xFFFEF2F2),
        const Color(0xFFDC2626),
        const Color(0xFFFECACA),
        'ABSENT',
      ),
    };
    final style =
        s[status.toLowerCase()] ??
        (
          const Color(0xFFF3F4F6),
          const Color(0xFF6B7280),
          const Color(0xFFE5E7EB),
          status.toUpperCase(),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: style.$1,
        border: Border.all(color: style.$3, width: 1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        style.$4,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: style.$2,
          letterSpacing: 0.6,
        ),
      ),
    );
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
      color: UpriseColors.primaryDark,
    ),
    label: Text(
      'Refresh',
      style: GoogleFonts.beVietnamPro(
        fontSize: 12.5,
        color: UpriseColors.primaryDark,
      ),
    ),
    style: OutlinedButton.styleFrom(
      side: BorderSide(color: UpriseColors.primaryDark.withOpacity(0.35)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  final double valueFontSize;
  const _StatCardData(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.isSelected = false,
    this.onTap,
    this.valueFontSize = 28,
  });
}

class _StatCard extends StatelessWidget {
  final _StatCardData c;
  const _StatCard(this.c);

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: c.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _C.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: c.isSelected ? c.color : _C.border.withAlpha(128),
            width: c.isSelected ? 2 : 1,
          ),
          boxShadow: c.isSelected
              ? [
                  BoxShadow(
                    color: c.color.withAlpha(46),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : _DS.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.color.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(c.icon, color: c.color, size: 20),
                ),
                Flexible(
                  child: Text(
                    c.value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: c.valueFontSize,
                      fontWeight: FontWeight.w800,
                      color: _C.charcoal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              c.label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: _C.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SatisfactionCard extends StatelessWidget {
  final _AnalyticsData data;
  const _SatisfactionCard({required this.data});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.emoji_events_outlined,
                    size: 16,
                    color: _C.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Event satisfaction scores',
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
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: _C.border),
                    const SizedBox(height: 8),
                    Text(
                      'No feedback data yet',
                      style: GoogleFonts.inter(fontSize: 13, color: _C.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            ...sorted.asMap().entries.map((entry) {
              final eventKey = entry.value.key;
              final score = entry.value.value;
              final title = data.eventDisplayTitle(eventKey);
              final isLast = entry.key == sorted.length - 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _C.charcoal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: score >= 4.0
                                    ? const Color(0xFFECFDF5)
                                    : score >= 3.0
                                    ? const Color(0xFFFFFBEB)
                                    : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                score.toStringAsFixed(1),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: score >= 4.0
                                      ? _C.green
                                      : (score >= 3.0 ? _C.amber : _C.red),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: score / 5.0,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: score >= 4.0
                                ? _C.green
                                : (score >= 3.0 ? _C.amber : _C.red),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, color: _C.border),
                ],
              );
            }),
          const SizedBox(height: 8),
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
    const sw = 24.0, gap = 0.04;
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

class _CompletionCard extends StatelessWidget {
  final _AnalyticsData data;
  final String orgId;
  final void Function(String eventId, String eventTitle) onEventTap;

  const _CompletionCard({
    required this.data,
    required this.orgId,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final countByEvent = data.feedbackCountByEvent;

    final rows = [...data.events];
    rows.sort((a, b) {
      final ra = countByEvent[a['id']] ?? 0;
      final rb = countByEvent[b['id']] ?? 0;
      if (ra != rb) return rb.compareTo(ra);
      return (a['title'] as String).toLowerCase().compareTo(
        (b['title'] as String).toLowerCase(),
      );
    });

    final withFeedback = rows
        .where((e) => (countByEvent[e['id']] ?? 0) > 0)
        .length;

    return Container(
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _C.border.withOpacity(0.5)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.checklist_outlined,
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
                        'Evaluation completion by event',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _C.charcoal,
                        ),
                      ),
                      if (rows.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$withFeedback of ${rows.length} events have received feedback',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: _C.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No events found')),
            )
          else
            SizedBox(
              height: math.min(rows.length * 52.0, 360.0),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, i) {
                  final event = rows[i];
                  final eventId = event['id'] as String;
                  final title = event['title'] as String;
                  final received = countByEvent[eventId] ?? 0;
                  final hasFeedback = received > 0;

                  return InkWell(
                    onTap: () {
                      onEventTap(eventId, title);
                    },
                    hoverColor: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: hasFeedback
                                  ? _C.green
                                  : const Color(0xFFCBD5E1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _C.charcoal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: _C.muted.withOpacity(0.5),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasFeedback
                                  ? const Color(0xFFECFDF5)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              hasFeedback
                                  ? '$received response${received == 1 ? '' : 's'}'
                                  : 'No responses yet',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: hasFeedback
                                    ? const Color(0xFF166534)
                                    : _C.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final String searchQuery, selectedEvent;
  final int? selectedRating;
  final int filteredCount, totalCount;
  final VoidCallback onRemoveSearch, onRemoveEvent, onRemoveRating, onClearAll;

  const _ActiveFilterChips({
    required this.searchQuery,
    required this.selectedEvent,
    required this.selectedRating,
    required this.filteredCount,
    required this.totalCount,
    required this.onRemoveSearch,
    required this.onRemoveEvent,
    required this.onRemoveRating,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(
          'Showing $filteredCount of $totalCount',
          style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.muted),
        ),
        if (searchQuery.isNotEmpty)
          _Chip(label: '"$searchQuery"', onRemove: onRemoveSearch),
        if (selectedEvent != 'All Events')
          _Chip(label: selectedEvent, onRemove: onRemoveEvent),
        if (selectedRating != null)
          _Chip(label: '$selectedRating★ only', onRemove: onRemoveRating),
        TextButton(
          onPressed: onClearAll,
          child: Text(
            'Clear all',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.red),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: UpriseColors.primaryDark.withOpacity(0.08),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: UpriseColors.primaryDark.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            color: UpriseColors.primaryDark,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(
            Icons.close,
            size: 11,
            color: UpriseColors.primaryDark,
          ),
        ),
      ],
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 17,
          color: _C.muted,
        ),
        style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.charcoal),
        items: items
            .map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: GoogleFonts.beVietnamPro(fontSize: 13)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ),
  );
}
