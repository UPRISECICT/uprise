// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../utils/platform_file_utils.dart' as platform_file_utils;
import '../../../utils/school_year.dart';
import '../../../theme/org_theme.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/app_confirmation_dialog.dart';
// Already the banner renderer for admin/reports_management.dart and the
// shared event_card — it resolves data: URIs, raw base64 and http URLs, so
// this screen does not need its own decoding path.
import '../../../widgets/student/event_image.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/org_attachment_preview.dart';
import '../../../widgets/org_modal_shell.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/stat_cards.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — enhanced for a more polished look
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  // Was a stale, more-vivid orange (0xFFEA580C) that didn't match the
  // deepened brand primary the rest of the org portal was moved to (see
  // theme/org_theme.dart's UpriseColors.primaryDark) — same drift bug as
  // org_events_schedule.dart's calendar page had.
  static const Color primary = UpriseColors.primaryDark;

  // Was 0xFFFEF3C7, an amber/yellow left over from a palette this screen no
  // longer uses. It is the fill behind the confirm dialog's icon badge and
  // behind a selected report-type card, and both of those sit directly above
  // a #C2410C button - so the pairing read as two brands in one modal, not
  // as one accent. 0xFFFFF7ED is the soft brand tint sixteen other spots in
  // the org portal already use.
  static const Color primaryBg = Color(0xFFFFF7ED);

  // Checked as a set with the dataviz validator against a light surface,
  // all pairs. These three pass every check. The pair they replace did not:
  // overdue #DC2626 against due-soon #C2410C came out at ΔE 6.0 for normal
  // vision and 2.4 under protanopia — two states this page treats as
  // different that most people cannot actually tell apart.
  static const Color statusOverdue = Color(0xFFB91C1C);
  static const Color statusDueSoon = Color(0xFFD97706);
  static const Color statusOnTrack = Color(0xFF059669);

  // The two report types are identity, not severity — which is what
  // colouring a button by what it does has to mean. Deliberately nowhere
  // near the three status hues above, so a button never reads as a state,
  // and ΔE 21.4 apart from each other (16.4 under deuteranopia).
  static const Color typeFinancial = Color(0xFF0891B2);
  static const Color typeAccomplishment = Color(0xFF4F46E5);

  static const Color surface = Color(0xFFFBFCFE);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE8ECF0);
  static const Color textPrimary = Color(0xFF1A202C);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF9AA5B4);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // A widget-based `label:` (RichText, to color just the "*" red) doesn't
  // report correct intrinsic sizing to OutlineInputBorder's floating-label
  // notch calculation — it left every required field's border broken or
  // overlapping around the label instead of a clean gap. Plain labelText
  // (a String) is what the notch math is actually built for, so the
  // colored asterisk isn't worth the broken border.
  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    int? maxLines,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      // [icon] intentionally unused now — a generic prefixIcon on every
      // field (label text already says what it is) was clutter, not
      // disambiguation. Kept for existing call sites.
      alignLabelWithHint: maxLines != null && maxLines > 1,
      labelStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF64748B),
      ),
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF9AA5B4),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _DS.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
// Standalone field label ("Covers", "Select Event", …) with a red " *"
// appended — matches the red-asterisk treatment other org modals give
// required TextFormFields (see org_event_proposals.dart's
// _orgEventProposalsInputDecoration), for labels that sit above a picker
// instead of inside an InputDecoration.
Widget _requiredLabel(String label) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: _DS.textSecondary,
          ),
        ),
        TextSpan(
          text: ' *',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFDC2626),
          ),
        ),
      ],
    ),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgReportsScreen extends StatefulWidget {
  final String orgId;
  const OrgReportsScreen({super.key, required this.orgId});

  @override
  State<OrgReportsScreen> createState() => _OrgReportsScreenState();
}

class _OrgReportsScreenState extends State<OrgReportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _typeFilter; // null = no filter, 'Financial' or 'Accomplishment'
  int? _selectedStatCard;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Countdown
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  DateTime? _eventDate;
  String _eventLabel = '';
  bool _eventLoaded = false;

  // Deadlines — one entry per (finished event × report type) for this org.
  List<_PendingEventDeadline> _finishedEventDeadlines = [];
  bool _deadlinesLoaded = false;
  // Distinguishes "checked, and genuinely nothing pending" from "the check
  // itself failed" — these used to be indistinguishable (both left
  // _finishedEventDeadlines empty), so a silent query failure showed the
  // reassuring "All reports submitted" banner even when reports were
  // actually overdue, because there was no way to tell the difference.
  bool _deadlinesLoadFailed = false;

  // Set while the Pending Reports page is showing — build() swaps to it in
  // place of the table rather than opening a dialog over it, so the sidebar
  // and top bar org_dashboard.dart wraps this screen in stay visible. Same
  // pattern as org_events_schedule.dart's _overviewEvent.
  bool _showPendingPage = false;
  final TextEditingController _pendingSearchController =
      TextEditingController();
  // Quick filters on the Pending Reports page — kept separate from the
  // table's own _typeFilter so switching one never resets the other.
  String? _pendingUrgencyFilter; // null | 'overdue' | 'dueSoon'
  String? _pendingTypeFilter; // null | 'financial' | 'accomplishment'

  @override
  void initState() {
    super.initState();
    _loadEventDate();
    _loadReportDeadlines();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchController.dispose();
    _pendingSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadEventDate() async {
    try {
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .get();

      DateTime? nextDate;
      String nextLabel = '';
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['date'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate();
        if (date.isBefore(now)) continue;
        if (nextDate == null || date.isBefore(nextDate)) {
          nextDate = date;
          nextLabel = data['title']?.toString() ?? 'Upcoming Event';
        }
      }

      if (nextDate != null) {
        _eventDate = nextDate;
        _eventLabel = nextLabel;
        _updateRemaining();
        _countdownTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _updateRemaining(),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _eventLoaded = true);
  }

  void _updateRemaining() {
    if (_eventDate == null) return;
    final diff = _eventDate!.difference(DateTime.now());
    if (mounted)
      setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  Future<void> _loadReportDeadlines() async {
    try {
      final now = DateTime.now();
      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .get();

      final finishedEvents = <Map<String, dynamic>>[];
      for (final doc in eventsSnap.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp?)?.toDate();
        if (date == null || !date.isBefore(now)) continue;
        finishedEvents.add({
          'eventId': doc.id,
          'eventTitle': data['title']?.toString() ?? 'Untitled Event',
          'eventDate': date,
          // Already on the doc and already what the student and guest event
          // lists render; this query just never asked for it.
          'bannerUrl': data['bannerUrl']?.toString() ?? '',
        });
      }

      final overrides = <String, DateTime>{};
      if (finishedEvents.isNotEmpty) {
        final overridesSnap = await FirebaseFirestore.instance
            .collection('report_deadline_overrides')
            .where('orgId', isEqualTo: widget.orgId)
            .get();
        for (final doc in overridesSnap.docs) {
          final data = doc.data();
          final eventId = data['eventId']?.toString();
          final type = data['type']?.toString();
          final deadline = (data['deadline'] as Timestamp?)?.toDate();
          if (eventId != null &&
              eventId.isNotEmpty &&
              type != null &&
              deadline != null) {
            overrides['${eventId}_$type'] = deadline;
          }
        }
      }

      final deadlines = <_PendingEventDeadline>[];
      for (final ev in finishedEvents) {
        final eventId = ev['eventId'] as String;
        final eventDate = ev['eventDate'] as DateTime;
        for (final type in const ['financial', 'accomplishment']) {
          final deadline =
              overrides['${eventId}_$type'] ??
              eventDate.add(const Duration(days: 7));
          deadlines.add(
            _PendingEventDeadline(
              eventId: eventId,
              eventTitle: ev['eventTitle'] as String,
              eventDate: eventDate,
              type: type,
              deadline: deadline,
              bannerUrl: ev['bannerUrl'] as String,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _finishedEventDeadlines = deadlines;
          _deadlinesLoadFailed = false;
        });
      }
    } catch (e) {
      debugPrint('org_reports: failed to load report deadlines: $e');
      if (mounted) setState(() => _deadlinesLoadFailed = true);
    }
    if (mounted) setState(() => _deadlinesLoaded = true);
  }

  late final Stream<QuerySnapshot> _reportsStream = FirebaseFirestore.instance
      .collection('reports')
      .where('orgId', isEqualTo: widget.orgId)
      .snapshots();

  List<ReportModel> _applyFilters(List<ReportModel> raw) {
    final sorted = [...raw]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    return sorted.where((r) {
      if (r.status == 'archived') return false;
      if (_typeFilter != null) {
        final typeVal = _typeFilter == 'Financial'
            ? 'financial'
            : 'accomplishment';
        if (r.type != typeVal) return false;
      }
      final term = _searchController.text.trim().toLowerCase();
      if (term.isNotEmpty) {
        return r.title.toLowerCase().contains(term) ||
            r.reportId.toLowerCase().contains(term) ||
            r.description.toLowerCase().contains(term);
      }
      return true;
    }).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DS.surface,
      body: StreamBuilder<QuerySnapshot>(
        stream: _reportsStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final all = (snap.data?.docs ?? [])
              .map(ReportModel.fromFirestore)
              .toList();

          // The pending/overdue list takes over the body instead of opening
          // on top of it. It lives inside this StreamBuilder so a report
          // submitted from the page drops off the list as soon as Firestore
          // acknowledges the write, with no separate refresh.
          if (_showPendingPage) return _buildPendingPage(all);

          final filtered = _applyFilters(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsRow(all),
              if (_deadlinesLoaded) ...[_buildDeadlineRow(all)],
              _buildToolbar(),
              const SizedBox(height: 16),
              Expanded(child: _buildTable(filtered, snap)),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────────
  Widget _buildStatsRow(List<ReportModel> all) {
    final total = all.length;
    final financial = all.where((r) => r.type == 'financial').length;
    final accompl = all.where((r) => r.type == 'accomplishment').length;

    void selectCard(int index, String? type) {
      setState(() {
        if (_selectedStatCard == index) {
          _selectedStatCard = null;
          _typeFilter = null;
        } else {
          _selectedStatCard = index;
          _typeFilter = type;
        }
        _currentPage = 1;
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      child: Row(
        children: [
          _StatCard(
            label: 'Total Reports',
            value: '$total',
            icon: Icons.article_outlined,
            color: _DS.primary,
            isSelected: _selectedStatCard == 0,
            onTap: () => selectCard(0, null),
          ),
          const SizedBox(width: 14),
          _StatCard(
            label: 'Financial',
            value: '$financial',
            icon: Icons.account_balance_outlined,
            color: const Color(0xFF059669),
            isSelected: _selectedStatCard == 1,
            onTap: () => selectCard(1, 'Financial'),
          ),
          const SizedBox(width: 14),
          _StatCard(
            label: 'Accomplishment',
            value: '$accompl',
            icon: Icons.assignment_turned_in_outlined,
            color: const Color(0xFF2563EB),
            isSelected: _selectedStatCard == 2,
            onTap: () => selectCard(2, 'Accomplishment'),
          ),
        ],
      ),
    );
  }

  // What is still owed, grouped by event and ordered by how soon it is due.
  // The banner and the Pending Reports page both read this, so the count in
  // the banner and the rows on the page can never disagree about what counts
  // as pending.
  ({
    List<_PendingEventDeadline> pending,
    Map<String, List<_PendingEventDeadline>> groups,
    List<String> orderedEventIds,
    Map<String, Set<String>> submittedTypesByEvent,
  })
  _pendingDeadlines(List<ReportModel> all) {
    final submittedReports = all.where(
      (r) => r.status != 'archived' && (r.eventId ?? '').isNotEmpty,
    );
    final submittedKeys = submittedReports
        .map((r) => '${r.eventId}_${r.type}')
        .toSet();

    // Which of the two report types already came in for a given event —
    // read alongside submittedKeys above, not a new source of truth. Lets
    // a card that still owes one report say the other was already
    // submitted instead of just omitting it.
    final submittedTypesByEvent = <String, Set<String>>{};
    for (final r in submittedReports) {
      submittedTypesByEvent.putIfAbsent(r.eventId!, () => {}).add(r.type);
    }

    final pending =
        _finishedEventDeadlines
            .where((d) => !submittedKeys.contains('${d.eventId}_${d.type}'))
            .toList()
          ..sort((a, b) => a.deadline.compareTo(b.deadline));

    final groups = <String, List<_PendingEventDeadline>>{};
    for (final d in pending) {
      groups.putIfAbsent(d.eventId, () => []).add(d);
    }

    final orderedEventIds = groups.keys.toList()
      ..sort((a, b) {
        final da = groups[a]!
            .map((d) => d.deadline)
            .reduce((x, y) => x.isBefore(y) ? x : y);
        final db = groups[b]!
            .map((d) => d.deadline)
            .reduce((x, y) => x.isBefore(y) ? x : y);
        return da.compareTo(db);
      });

    return (
      pending: pending,
      groups: groups,
      orderedEventIds: orderedEventIds,
      submittedTypesByEvent: submittedTypesByEvent,
    );
  }

  // ── Deadline row ── UPDATED WITH PROFESSIONAL UI ──────────────────────────
  Widget _buildDeadlineRow(List<ReportModel> all) {
    final deadlines = _pendingDeadlines(all);
    final pending = deadlines.pending;

    // Never claim "all clear" when the deadline check itself failed to load
    // — that used to look identical to genuinely having nothing pending,
    // which meant overdue reports could sit hidden behind a reassuring
    // green banner if this query errored out.
    if (_deadlinesLoadFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFB45309),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Couldn't check for pending/overdue reports — this doesn't mean you're clear.",
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _loadReportDeadlines,
                child: Text(
                  'Retry',
                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withAlpha(26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF059669),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'All reports for your finished events are submitted.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF065F46),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final orderedEventIds = deadlines.orderedEventIds;

    // Calculate stats
    final overdueCount = pending
        .where((d) => DateTime.now().isAfter(d.deadline))
        .length;
    final totalPending = pending.length;
    final eventCount = orderedEventIds.length;

    final isUrgent = overdueCount > 0;
    final accentColor = isUrgent
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);

    // Single compact row instead of a header + a wrapped grid of per-event
    // chips — the chip grid grew as tall as the page for orgs with many
    // pending events without adding information "View all" doesn't already
    // give in one click.
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isUrgent
                ? [const Color(0xFFFEF2F2), const Color(0xFFFEE2E2)]
                : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUrgent ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A),
            width: isUrgent ? 1.5 : 1,
          ),
          boxShadow: isUrgent
              ? [
                  BoxShadow(
                    color: accentColor.withAlpha(46),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : _DS.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withAlpha(70),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                isUrgent
                    ? Icons.warning_amber_rounded
                    : Icons.pending_actions_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUrgent
                        ? 'Reports overdue — action needed'
                        : 'Pending reports',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isUrgent
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF92400E),
                    ),
                  ),
                  Text(
                    '$totalPending report${totalPending > 1 ? 's' : ''} needed from $eventCount event${eventCount > 1 ? 's' : ''}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isUrgent
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (overdueCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.priority_high_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$overdueCount Overdue',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showPendingPage = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isUrgent
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isUrgent
                              ? const Color(0xFF991B1B)
                              : const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: isUrgent
                            ? const Color(0xFF991B1B)
                            : const Color(0xFF92400E),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closePendingPage() => setState(() {
    _showPendingPage = false;
    _pendingSearchController.clear();
  });

  // ── Pending Reports page ──────────────────────────────────────────────────
  // This was a 640px dialog. It carries a search field, a list with no cap on
  // how long it can get, and an action button on every overdue row — and
  // pressing one of those buttons opened the upload modal on top of it, so
  // the org was looking at a modal, over a modal, over the page. As a page it
  // has room for the list, the back arrow replaces the Close button, and the
  // upload modal has nothing behind it but this.
  Widget _buildPendingPage(List<ReportModel> all) {
    final now = DateTime.now();
    final deadlines = _pendingDeadlines(all);
    final groups = deadlines.groups;
    final orderedEventIds = deadlines.orderedEventIds;
    final submittedTypesByEvent = deadlines.submittedTypesByEvent;
    final eventCount = orderedEventIds.length;
    final overdueCount = orderedEventIds
        .where((id) => groups[id]!.any((d) => now.isAfter(d.deadline)))
        .length;

    bool isOverdue(_PendingEventDeadline d) => now.isAfter(d.deadline);
    bool isDueSoonItem(_PendingEventDeadline d) =>
        !isOverdue(d) && now.difference(d.deadline).inDays.abs() <= 3;

    final query = _pendingSearchController.text.trim().toLowerCase();
    // Chained, not combined into one predicate — search narrows by name,
    // urgency and type each narrow by their own facet of the same list, so
    // any combination (e.g. "Overdue" + "Financial") is just two filters
    // applied in sequence rather than a special case to keep in sync.
    final visibleEventIds = orderedEventIds
        .where(
          (id) =>
              query.isEmpty ||
              groups[id]!.any(
                (d) => d.eventTitle.toLowerCase().contains(query),
              ),
        )
        .where(
          (id) =>
              _pendingUrgencyFilter == null ||
              groups[id]!.any(
                (d) => _pendingUrgencyFilter == 'overdue'
                    ? isOverdue(d)
                    : isDueSoonItem(d),
              ),
        )
        .where(
          (id) =>
              _pendingTypeFilter == null ||
              groups[id]!.any((d) => d.type == _pendingTypeFilter),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        // Light and compact, matching the Event Overview header: this sits
        // directly under org_dashboard.dart's own top bar, so a second heavy
        // block would just be banner chrome twice.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _DS.border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: _DS.primary,
                  size: 20,
                ),
                tooltip: 'Back to Report Submissions',
                onPressed: _closePendingPage,
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _DS.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: _DS.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pending Reports',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _DS.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      eventCount == 0
                          ? 'Nothing left to submit'
                          : '$eventCount event${eventCount > 1 ? 's' : ''} need${eventCount > 1 ? '' : 's'} attention',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        color: _DS.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Red here is the status, not the chrome — it is the same red
              // the overdue rows below use, and it is the only red on the
              // page now that the upload buttons wear the brand colour.
              if (overdueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _DS.statusOverdue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$overdueCount Overdue',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _DS.statusOverdue,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // ── Search ────────────────────────────────────────────────────────
        // Capped rather than full-bleed: a search box as wide as the window
        // reads as the page's main input, and this one only narrows a list.
        if (eventCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _pendingSearchController,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.beVietnamPro(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by event name…',
                    hintStyle: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      color: _DS.textHint,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: _DS.textHint,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear Search',
                            onPressed: () => setState(
                              () => _pendingSearchController.clear(),
                            ),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _DS.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _DS.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _DS.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // ── Quick filters ─────────────────────────────────────────────────
        // Each facet narrows the same list from a different angle — urgency
        // and type are independent, so both can be active at once.
        if (eventCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PendingFilterChip(
                  label: 'All',
                  selected:
                      _pendingUrgencyFilter == null &&
                      _pendingTypeFilter == null,
                  color: _DS.textSecondary,
                  onTap: () => setState(() {
                    _pendingUrgencyFilter = null;
                    _pendingTypeFilter = null;
                  }),
                ),
                _PendingFilterChip(
                  label: 'Overdue',
                  selected: _pendingUrgencyFilter == 'overdue',
                  color: _DS.statusOverdue,
                  onTap: () => setState(
                    () => _pendingUrgencyFilter =
                        _pendingUrgencyFilter == 'overdue' ? null : 'overdue',
                  ),
                ),
                _PendingFilterChip(
                  label: 'Due Soon',
                  selected: _pendingUrgencyFilter == 'dueSoon',
                  color: _DS.statusDueSoon,
                  onTap: () => setState(
                    () => _pendingUrgencyFilter =
                        _pendingUrgencyFilter == 'dueSoon' ? null : 'dueSoon',
                  ),
                ),
                _PendingFilterChip(
                  label: 'Financial',
                  selected: _pendingTypeFilter == 'financial',
                  color: _DS.typeFinancial,
                  onTap: () => setState(
                    () => _pendingTypeFilter = _pendingTypeFilter == 'financial'
                        ? null
                        : 'financial',
                  ),
                ),
                _PendingFilterChip(
                  label: 'Accomplishment',
                  selected: _pendingTypeFilter == 'accomplishment',
                  color: _DS.typeAccomplishment,
                  onTap: () => setState(
                    () => _pendingTypeFilter =
                        _pendingTypeFilter == 'accomplishment'
                        ? null
                        : 'accomplishment',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        // ── Grid ──────────────────────────────────────────────────────────
        // A catalogue grid rather than a table, on the merch screen's
        // pattern: an org recognises its own event by its banner faster
        // than by reading a title down a column of them.
        Expanded(
          child: visibleEventIds.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        eventCount == 0
                            ? Icons.check_circle_outline_rounded
                            : Icons.search_off_rounded,
                        size: 44,
                        color: eventCount == 0
                            ? const Color(0xFF059669)
                            : _DS.textHint,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        eventCount == 0
                            ? 'All reports for your finished events are submitted.'
                            : query.isNotEmpty
                            ? 'No pending reports match "$query".'
                            : 'No pending reports match the selected filters.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13.5,
                          color: _DS.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  // mainAxisExtent, not childAspectRatio: it pins every
                  // card to the same height whatever width the column
                  // lands on, so a long event title cannot make one card
                  // taller than the row it sits in.
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    // Wider than the merch grid's 280. A product photo is
                    // square; an event banner is not, and a narrower column
                    // squeezed the report rows against the edge of the card.
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 306,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: visibleEventIds.length,
                  itemBuilder: (_, idx) {
                    final eventId = visibleEventIds[idx];
                    final eventItems = groups[eventId]!;
                    final eventSubmitted =
                        submittedTypesByEvent[eventId] ?? const {};
                    return _PendingEventCard(
                      items: eventItems,
                      submittedTypes: eventSubmitted,
                      onUpload: (type) => _openPrefillModal(eventId, type),
                      onOpenDetails: () => _openPendingReportDetails(
                        eventItems,
                        eventSubmitted,
                        (type) => _openPrefillModal(eventId, type),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.beVietnamPro(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by ID, title, or description…',
                  hintStyle: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: _DS.textHint,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: _DS.textHint,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Clear Search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _currentPage = 1);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _DS.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _DS.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DS.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() => _currentPage = 1),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _FilterDropdown(
            value: _typeFilter,
            items: const ['Financial', 'Accomplishment'],
            hint: 'Type',
            icon: Icons.category_outlined,
            onChanged: (v) => setState(() {
              _typeFilter = v;
              _selectedStatCard = null;
              _currentPage = 1;
            }),
          ),
          const SizedBox(width: 12),
          _ExportButton(orgId: widget.orgId),
          const SizedBox(width: 12),
          _ToolbarButton(
            label: 'Upload Report',
            icon: Icons.upload_file_outlined,
            onPressed: _openCreateModal,
          ),
        ],
      ),
    );
  }

  // ── Table ──────────────────────────────────────────────────────────────────
  Widget _buildTable(
    List<ReportModel> filtered,
    AsyncSnapshot<QuerySnapshot> snap,
  ) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _pageSize).ceil();
    final safePage = _currentPage.clamp(1, totalPages);
    final start = (safePage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    final pageItems = filtered.isEmpty
        ? <ReportModel>[]
        : filtered.sublist(start, end);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      clipBehavior: Clip.antiAlias,
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
        children: [
          _buildTableHeader(),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: pageItems.length,
                    itemBuilder: (_, i) => _buildReportRow(
                      pageItems[i],
                      isLast: i == pageItems.length - 1,
                    ),
                  ),
          ),
          _buildFooter(filtered.length, totalPages, start, end),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: _DS.primary.withAlpha(60))),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: _headerCell('EVENT')),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _headerCell('TYPE')),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _headerCell('DATE SUBMITTED')),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
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
      color: _DS.textSecondary,
      letterSpacing: 0.7,
    ),
  );

  Widget _buildReportRow(ReportModel report, {required bool isLast}) {
    final isFinancial = report.type == 'financial';
    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _openViewModal(report),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            // EVENT (Title + Description)
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    report.title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _DS.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (report.description.isNotEmpty)
                    Text(
                      report.description,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: _DS.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Type chip
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isFinancial
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isFinancial ? 'Financial' : 'Accomplishment',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isFinancial
                            ? const Color(0xFF059669)
                            : const Color(0xFF2563EB),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Date
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('MMM dd, yyyy').format(report.submittedAt.toDate()),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: _DS.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            // Actions
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OrgActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    onTap: () => _openViewModal(report),
                  ),
                  const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit Report',
                    color: UpriseColors.primaryDark,
                    onTap: () => _openEditModal(report),
                  ),
                  const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: Icons.archive_outlined,
                    tooltip: 'Archive',
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
              Icons.article_outlined,
              size: 40,
              color: _DS.textHint,
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
            'Try adjusting your filters or upload a new report.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: _DS.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int total, int totalPages, int start, int end) {
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
        border: Border(top: BorderSide(color: _DS.border)),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total reports',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: _DS.textSecondary,
            ),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left_rounded,
                enabled: _currentPage > 1,
                tooltip: 'Previous Page',
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
                      color: _DS.textSecondary,
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
                tooltip: 'Next Page',
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  void _openCreateModal() => showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => _ReportModal(orgId: widget.orgId),
  );

  void _openEditModal(ReportModel r) => showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => _ReportModal(orgId: widget.orgId, existingReport: r),
  );

  void _openViewModal(ReportModel r) => showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _ViewReportModal(report: r),
  );

  // Jumps straight into the upload modal with the event + type already
  // selected — used by the "Upload now" shortcut on overdue items instead of
  // the normal flow of clicking "Upload Report" and picking the event/type
  // from scratch. It used to pop() first, to dismiss the overdue-list dialog
  // it was raised from; that list is a page now, so there is nothing to
  // dismiss and the pop would have closed the page out from under the modal.
  void _openPrefillModal(String eventId, String type) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _ReportModal(
        orgId: widget.orgId,
        prefillEventId: eventId,
        prefillType: type,
      ),
    );
  }

  // Raised by a tap on a _PendingEventCard's body. Takes the same
  // per-event items/submittedTypes the card itself was built from — no
  // extra Firestore read — and hands its own Upload taps straight to
  // onUpload after closing itself, so the flow is identical to pressing
  // Upload on the card directly.
  void _openPendingReportDetails(
    List<_PendingEventDeadline> items,
    Set<String> submittedTypes,
    ValueChanged<String> onUpload,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _PendingReportDetailsModal(
        items: items,
        submittedTypes: submittedTypes,
        onUpload: (type) {
          Navigator.pop(dialogContext);
          onUpload(type);
        },
      ),
    );
  }

  Future<void> _archiveReport(ReportModel report) async {
    final ok = await _confirm(
      title: 'Archive Report',
      message:
          'Archive "${report.title}"? It will be removed from the active list.',
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(report.id)
          .update({'status': 'archived'});
      await activity_log.ActivityLogger.log(
        action: 'archive_report',
        module: 'reports',
        details: {
          'orgId': widget.orgId,
          'reportId': report.id,
          'title': report.title,
        },
      );
      _snack('Report archived');
    } catch (e) {
      _snack('Failed to archive report: $e', error: true);
    }
  }

  Future<void> _deleteReport(ReportModel report) async {
    final ok = await _confirm(
      title: 'Delete Report',
      message: 'Delete "${report.title}"? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(report.id)
          .delete();
      await activity_log.ActivityLogger.log(
        action: 'delete_report',
        module: 'reports',
        details: {
          'orgId': widget.orgId,
          'reportId': report.id,
          'title': report.title,
        },
      );
      _snack('Report deleted successfully');
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    error ? AppToast.error(context, msg) : AppToast.success(context, msg);
  }

  // AppConfirmationDialog is the shell thirteen other admin and org screens
  // already confirm through. This one used to raise its own _ConfirmDialog -
  // narrower, squarer corners, icon and title side by side instead of
  // centred, half-width buttons instead of full - so the same "are you sure"
  // looked like a different product depending on which tab you asked it from.
  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) => showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      accentColor: destructive ? const Color(0xFFDC2626) : _DS.primary,
      icon: destructive
          ? Icons.delete_outline_rounded
          : Icons.check_circle_outline_rounded,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PENDING DEADLINE WIDGETS - PROFESSIONAL UI
// ─────────────────────────────────────────────────────────────────────────────

class _PendingEventDeadline {
  final String eventId;
  final String eventTitle;
  final DateTime eventDate;
  final String type;
  final DateTime deadline;
  // Empty for an event whose org never uploaded one — the card falls back
  // to the event's initial rather than a grey box that looks identical on
  // every card it appears on.
  final String bannerUrl;
  const _PendingEventDeadline({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.type,
    required this.deadline,
    this.bannerUrl = '',
  });
}

// ── Card for the Pending Reports grid ────────────────────────────────────
// A task queue, not a catalogue. The banner used to be the card — full
// height, with "Upload Financial"/"Upload Accomplishment" hidden behind an
// AnimatedOpacity overlay that only appeared on hover, so 15 of 16 cards in
// a grid showed no action at all. The banner is now a small identifier, and
// every report the event still owes gets its own row with its own
// always-visible button — nothing here needs a hover to be understood.
class _PendingEventCard extends StatefulWidget {
  final List<_PendingEventDeadline> items;
  // Types already submitted for this event — disjoint from `items` by
  // construction (_pendingDeadlines only ever puts a type in one or the
  // other), read here only to render a "Submitted" row instead of letting
  // the report silently disappear from the card.
  final Set<String> submittedTypes;
  final ValueChanged<String> onUpload;
  // Opens the Pending Report Details modal — fired by a tap anywhere on the
  // card body. The Upload buttons nested inside carry their own InkWell, so
  // a tap on one of those is claimed by that inner recognizer during the
  // gesture arena's sweep and never reaches this outer handler as well.
  final VoidCallback onOpenDetails;
  const _PendingEventCard({
    required this.items,
    required this.submittedTypes,
    required this.onUpload,
    required this.onOpenDetails,
  });

  @override
  State<_PendingEventCard> createState() => _PendingEventCardState();
}

class _PendingEventCardState extends State<_PendingEventCard> {
  bool _hovering = false;

  // Financial first, so it never swaps position with Accomplishment
  // between cards — same order the report rows below are drawn in.
  List<_PendingEventDeadline> get _ordered {
    final sorted = [...widget.items];
    sorted.sort(
      (a, b) => a.type == b.type ? 0 : (a.type == 'financial' ? -1 : 1),
    );
    return sorted;
  }

  DateTime? _deadlineFor(String type) {
    for (final d in widget.items) {
      if (d.type == type) return d.deadline;
    }
    return null;
  }

  Widget _banner(_PendingEventDeadline first) {
    if (first.bannerUrl.isEmpty) {
      final title = first.eventTitle.trim();
      return Container(
        color: _DS.primaryBg,
        alignment: Alignment.center,
        child: Text(
          title.isEmpty ? '?' : title[0].toUpperCase(),
          style: GoogleFonts.beVietnamPro(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: _DS.primary.withAlpha(80),
          ),
        ),
      );
    }
    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: _hovering ? 1.05 : 1.0,
      child: EventImage(
        imageUrl: first.bannerUrl,
        fit: BoxFit.cover,
        showLoadingIndicator: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _ordered;
    final first = items.first;
    final now = DateTime.now();
    final anyOverdue = items.any((d) => now.isAfter(d.deadline));
    final earliest = items
        .map((d) => d.deadline)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final isDueSoon = !anyOverdue && now.difference(earliest).inDays.abs() <= 3;

    final statusColor = anyOverdue
        ? _DS.statusOverdue
        : isDueSoon
        ? _DS.statusDueSoon
        : _DS.statusOnTrack;
    final statusIcon = anyOverdue
        ? Icons.error_outline_rounded
        : isDueSoon
        ? Icons.schedule_rounded
        : Icons.check_circle_outline_rounded;

    // Fixed order — Financial, then Accomplishment — built from whichever
    // of the two are either still pending or already submitted, so a type
    // this event never required (not pending, not submitted) draws no row.
    final requiredTypes = <String>[
      if (items.any((d) => d.type == 'financial') ||
          widget.submittedTypes.contains('financial'))
        'financial',
      if (items.any((d) => d.type == 'accomplishment') ||
          widget.submittedTypes.contains('accomplishment'))
        'accomplishment',
    ];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenDetails,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovering ? _DS.primary.withAlpha(90) : _DS.border,
            ),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(26),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : _DS.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner ── identifies the event; no longer carries the
              // page's only action, so it no longer needs most of the card.
              SizedBox(
                height: 76,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _banner(first),
                      Positioned(
                        left: 7,
                        top: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                _cardStatusLabel(anyOverdue, earliest, now),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── Event info ── name carries the most weight; when it
              // happened is secondary, read off the same eventDate the
              // deadline itself was computed from.
              Text(
                first.eventTitle,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _DS.textPrimary,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: 12,
                    color: _DS.textHint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Held ${DateFormat('MMM d, yyyy').format(first.eventDate)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: _DS.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'REPORTS REQUIRED',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: _DS.textHint,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < requiredTypes.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _ReportRequirementRow(
                  type: requiredTypes[i],
                  deadline: _deadlineFor(requiredTypes[i]),
                  submitted: widget.submittedTypes.contains(requiredTypes[i]),
                  now: now,
                  onUpload: () => widget.onUpload(requiredTypes[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// "Overdue · N days" / "Due today" / "Due tomorrow" / "Due Sep 30" for the
// banner pill — the card-level rollup across every report this event still
// owes. _ReportRequirementRow phrases the same math per report ("Overdue
// by N days") since each report can carry its own deadline.
String _cardStatusLabel(bool anyOverdue, DateTime deadline, DateTime now) {
  if (anyOverdue) {
    final days = _daysBetween(deadline, now);
    return 'Overdue · $days day${days == 1 ? '' : 's'}';
  }
  final diff = _daysBetween(now, deadline);
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  return 'Due ${DateFormat('MMM d').format(deadline)}';
}

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays.abs();
}

// "Overdue by N days" / "Due today" / "Due tomorrow" / "Due Sep 30" for a
// single report's own deadline — shared by _ReportRequirementRow (grid
// card) and the Pending Report Details modal so the wording never drifts
// between the two places the same deadline gets shown.
String _reportDueLabel(DateTime deadline, DateTime now) {
  final overdue = now.isAfter(deadline);
  if (overdue) {
    final days = _daysBetween(deadline, now);
    return 'Overdue by $days day${days == 1 ? '' : 's'}';
  }
  final diff = _daysBetween(now, deadline);
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  return 'Due ${DateFormat('MMM d').format(deadline)}';
}

// One row per report the event owes — replaces the old "FINANCIAL &
// ACCOMPLISHMENT" caption line. Financial and Accomplishment are told apart
// by icon and label, not colour — both share the one UPRISE brand colour
// (_DS.primary), matching the Pending Report Details modal's upload
// buttons. _DS.typeFinancial/typeAccomplishment still exist for the page's
// own quick-filter chips, just not for this row anymore. A report already
// turned in renders as a resolved state instead of just vanishing.
class _ReportRequirementRow extends StatelessWidget {
  final String type; // 'financial' | 'accomplishment'
  final DateTime? deadline;
  final bool submitted;
  final DateTime now;
  final VoidCallback onUpload;
  const _ReportRequirementRow({
    required this.type,
    required this.deadline,
    required this.submitted,
    required this.now,
    required this.onUpload,
  });

  bool get _isFinancial => type == 'financial';

  @override
  Widget build(BuildContext context) {
    final typeLabel = _isFinancial
        ? 'Financial Report'
        : 'Accomplishment Report';

    IconData badgeIcon;
    Color badgeColor;
    Color subColor;
    String subLabel;

    if (submitted) {
      badgeIcon = Icons.check_circle_rounded;
      badgeColor = _DS.statusOnTrack;
      subColor = _DS.statusOnTrack;
      subLabel = 'Submitted';
    } else {
      badgeIcon = _isFinancial
          ? Icons.account_balance_outlined
          : Icons.assignment_turned_in_outlined;
      // One UPRISE brand color for both report types, matching the Pending
      // Report Details modal's _ModalUploadButton — the row's own icon and
      // label already say Financial vs Accomplishment, so the button only
      // needs to read as "act on this", not restate which report it is.
      badgeColor = _DS.primary;
      final d = deadline ?? now;
      final overdue = now.isAfter(d);
      final dueSoon = !overdue && now.difference(d).inDays.abs() <= 3;
      subColor = overdue
          ? _DS.statusOverdue
          : dueSoon
          ? _DS.statusDueSoon
          : _DS.statusOnTrack;
      subLabel = _reportDueLabel(d, now);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withAlpha(28),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(badgeIcon, size: 12, color: badgeColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                typeLabel,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _DS.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subLabel,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (!submitted) ...[
          const SizedBox(width: 6),
          _UploadNowButton(color: _DS.primary, onTap: onUpload),
        ],
      ],
    );
  }
}

// Compact and always visible — this used to be a full-width button hidden
// inside an AnimatedOpacity overlay that only appeared on hover. It is now
// sized to its own label so a grid of many cards doesn't turn into a wall
// of saturated colour, but it never needs a hover to be seen or pressed.
// `color` is now always _DS.primary at the one call site (see
// _ReportRequirementRow) — kept as a parameter rather than hardcoded so a
// future caller isn't forced to reuse this exact brand colour.
class _UploadNowButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _UploadNowButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upload_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                'Upload',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small toggle pill for the Pending Reports quick filters — see
// _buildPendingPage's chained .where() calls for how urgency and type each
// narrow the grid independently.
class _PendingFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _PendingFilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(24) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color.withAlpha(140) : _DS.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? color : _DS.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending Report Details Modal
// ─────────────────────────────────────────────────────────────────────────────
// Opened by tapping a _PendingEventCard. Built on the same OrgModalShell /
// OrgModalSection / OrgDetailItem shell org_event_proposals.dart's own
// details modal (_ViewProposalModal) uses — dark compact header, image on
// the left, sectioned details on the right — so the two read as one
// system. Takes the exact items/submittedTypes the card already computed
// from _pendingDeadlines; no separate Firestore read of its own.
class _PendingReportDetailsModal extends StatelessWidget {
  final List<_PendingEventDeadline> items;
  final Set<String> submittedTypes;
  final ValueChanged<String> onUpload;
  const _PendingReportDetailsModal({
    required this.items,
    required this.submittedTypes,
    required this.onUpload,
  });

  // Financial first, matching the card and every other list on this page.
  List<_PendingEventDeadline> get _ordered {
    final sorted = [...items];
    sorted.sort(
      (a, b) => a.type == b.type ? 0 : (a.type == 'financial' ? -1 : 1),
    );
    return sorted;
  }

  DateTime? _deadlineFor(String type) {
    for (final d in items) {
      if (d.type == type) return d.deadline;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final first = ordered.first;
    final now = DateTime.now();
    final anyOverdue = ordered.any((d) => now.isAfter(d.deadline));
    final earliest = ordered
        .map((d) => d.deadline)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final isDueSoon = !anyOverdue && now.difference(earliest).inDays.abs() <= 3;
    final overallLabel = anyOverdue
        ? 'Overdue'
        : isDueSoon
        ? 'Due Soon'
        : 'On Track';
    final overallColor = anyOverdue
        ? _DS.statusOverdue
        : isDueSoon
        ? _DS.statusDueSoon
        : _DS.statusOnTrack;

    // Same fixed order and membership rule the card uses: a type draws a
    // row only if it is still pending or was already submitted for this
    // event, so a type this event never required is simply absent.
    final requiredTypes = <String>[
      if (ordered.any((d) => d.type == 'financial') ||
          submittedTypes.contains('financial'))
        'financial',
      if (ordered.any((d) => d.type == 'accomplishment') ||
          submittedTypes.contains('accomplishment'))
        'accomplishment',
    ];

    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      headerColor: UpriseColors.primaryDark,
      compactHeader: true,
      icon: Icons.assignment_late_rounded,
      title: first.eventTitle,
      width: 840,
      maxHeightFraction: 0.85,
      subtitleWidget: Row(
        children: [
          _pendingStatusBadge(overallLabel, overallColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${requiredTypes.length} report${requiredTypes.length == 1 ? '' : 's'} required',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: Colors.white.withAlpha(180),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      footerActions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: _DS.textSecondary,
            side: const BorderSide(color: _DS.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
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
      // Fixed-height Row, image left / details right — the same shape
      // _ViewProposalModal's body uses, just with report content instead
      // of proposal fields on the right.
      body: SizedBox(
        height: 460,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _DS.primaryBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: first.bannerUrl.isEmpty
                            ? Center(
                                child: Text(
                                  first.eventTitle.trim().isEmpty
                                      ? '?'
                                      : first.eventTitle
                                            .trim()[0]
                                            .toUpperCase(),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                    color: _DS.primary.withAlpha(80),
                                  ),
                                ),
                              )
                            : EventImage(
                                imageUrl: first.bannerUrl,
                                fit: BoxFit.cover,
                                showLoadingIndicator: false,
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // ── Deadline summary ── red for overdue, the same
                    // soft warning tint the "Due Soon" pill elsewhere on
                    // this page uses for upcoming ones.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: anyOverdue
                            ? const Color(0xFFFEF2F2)
                            : isDueSoon
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: anyOverdue
                              ? const Color(0xFFFCA5A5)
                              : isDueSoon
                              ? const Color(0xFFFDE68A)
                              : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REPORT DEADLINE',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _DS.textHint,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('MMM d, yyyy').format(earliest),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _DS.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _reportDueLabel(earliest, now),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: overallColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(4, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrgModalSection(
                      title: 'Event / Report Details',
                      icon: Icons.info_outline_rounded,
                      accentColor: UpriseColors.primaryDark,
                      child: Column(
                        children: [
                          OrgDetailItem(
                            label: 'Event Date',
                            value: DateFormat(
                              'MMMM d, yyyy',
                            ).format(first.eventDate),
                            icon: Icons.event_rounded,
                            iconColor: UpriseColors.primaryDark,
                          ),
                          const SizedBox(height: 14),
                          OrgDetailItem(
                            label: 'Report Deadline',
                            value: DateFormat('MMMM d, yyyy').format(earliest),
                            icon: Icons.schedule_rounded,
                            iconColor: UpriseColors.primaryDark,
                          ),
                          const SizedBox(height: 14),
                          OrgDetailItem(
                            label: 'Overall Status',
                            value: overallLabel,
                            icon: anyOverdue
                                ? Icons.error_outline_rounded
                                : isDueSoon
                                ? Icons.schedule_rounded
                                : Icons.check_circle_outline_rounded,
                            iconColor: overallColor,
                            valueColor: overallColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OrgModalSection(
                      title: 'Reports Required',
                      icon: Icons.assignment_outlined,
                      accentColor: UpriseColors.primaryDark,
                      child: Column(
                        children: [
                          for (var i = 0; i < requiredTypes.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _ModalReportRow(
                              type: requiredTypes[i],
                              deadline: _deadlineFor(requiredTypes[i]),
                              submitted: submittedTypes.contains(
                                requiredTypes[i],
                              ),
                              now: now,
                              onUpload: () => onUpload(requiredTypes[i]),
                            ),
                          ],
                        ],
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

// Small status pill for the details modal's header — same bg/border/fg
// recipe _buildPendingPage's own "N Overdue" header badge already uses, so
// the color language stays identical between the page and this modal.
Widget _pendingStatusBadge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      label.toUpperCase(),
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      ),
    ),
  );
}

// One row per required report inside the details modal — the boxed
// counterpart of _ReportRequirementRow on the card, laid out the same way
// ([icon] [info Expanded] [Upload]) so long titles never push the button
// out of the card, per _ModalUploadButton's fixed size below.
class _ModalReportRow extends StatelessWidget {
  final String type; // 'financial' | 'accomplishment'
  final DateTime? deadline;
  final bool submitted;
  final DateTime now;
  final VoidCallback onUpload;
  const _ModalReportRow({
    required this.type,
    required this.deadline,
    required this.submitted,
    required this.now,
    required this.onUpload,
  });

  bool get _isFinancial => type == 'financial';

  @override
  Widget build(BuildContext context) {
    final typeLabel = _isFinancial
        ? 'Financial Report'
        : 'Accomplishment Report';

    IconData badgeIcon;
    Color badgeColor;
    Color subColor;
    String subLabel;

    if (submitted) {
      badgeIcon = Icons.check_circle_rounded;
      badgeColor = _DS.statusOnTrack;
      subColor = _DS.statusOnTrack;
      subLabel = 'Submitted';
    } else {
      badgeIcon = _isFinancial
          ? Icons.account_balance_outlined
          : Icons.assignment_turned_in_outlined;
      // One brand color for both report types in this modal — deliberately
      // not the card's cyan/indigo identity colors. The row's own icon and
      // label already say which report this is; the button only has to
      // say "act on this", so both buttons read as the same UPRISE action.
      badgeColor = _DS.primary;
      final d = deadline ?? now;
      final overdue = now.isAfter(d);
      final dueSoon = !overdue && now.difference(d).inDays.abs() <= 3;
      subColor = overdue
          ? _DS.statusOverdue
          : dueSoon
          ? _DS.statusDueSoon
          : _DS.statusOnTrack;
      subLabel = _reportDueLabel(d, now);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DS.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(28),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(badgeIcon, size: 16, color: badgeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  typeLabel,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _DS.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subLabel,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!submitted) ...[
            const SizedBox(width: 12),
            _ModalUploadButton(onTap: onUpload),
          ],
        ],
      ),
    );
  }
}

// Both report rows share this exact button — same color, size, radius,
// typography and padding — so the right edge of every Upload button in the
// modal lines up regardless of which row it belongs to. Fixed width rather
// than sized to the "Upload" label so that alignment can't drift.
class _ModalUploadButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ModalUploadButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 96,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _DS.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                'Upload',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View Report Modal
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// View Report Modal - REDESIGNED with Professional + Cute aesthetic
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// View Report Modal - CLEAN & PROFESSIONAL
// ─────────────────────────────────────────────────────────────────────────────
class _ViewReportModal extends StatelessWidget {
  final ReportModel report;
  const _ViewReportModal({required this.report});

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
    final hasEventId = (report.eventId ?? '').isNotEmpty;
    final showTxnSection =
        isFinancial &&
        report.scope == 'event' &&
        (hasEventId || report.title.isNotEmpty);
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    final typeLabel = isFinancial
        ? 'Financial Report'
        : 'Accomplishment Report';
    final typeColor = isFinancial
        ? const Color(0xFF059669)
        : const Color(0xFF2563EB);
    final typeBgColor = isFinancial
        ? const Color(0xFFECFDF5)
        : const Color(0xFFEFF6FF);

    return OrgModalShell(
      accentColor: _DS.primary,
      icon: isFinancial
          ? Icons.account_balance_wallet_rounded
          : Icons.assignment_rounded,
      title: 'Report Details',
      subtitle: report.reportId,
      width: 560,
      maxHeightFraction: 0.85,
      footerActions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE2E6EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(
            'Close',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _DS.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DS.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            'Done',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    report.title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _DS.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: typeBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OrgModalSection(
              title: 'Report Information',
              icon: Icons.info_outline_rounded,
              accentColor: _DS.primary,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Report ID',
                          value: report.reportId,
                          icon: Icons.confirmation_number_outlined,
                          iconColor: _DS.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OrgDetailItem(
                          label: 'Date Submitted',
                          value: DateFormat(
                            'MMM dd, yyyy',
                          ).format(report.submittedAt.toDate()),
                          icon: Icons.calendar_today_outlined,
                          iconColor: _DS.primary,
                        ),
                      ),
                    ],
                  ),
                  if (report.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE8ECF0)),
                    const SizedBox(height: 12),
                    OrgDetailItem(
                      label: 'Description',
                      value: report.description,
                      icon: Icons.notes_rounded,
                      iconColor: _DS.primary,
                    ),
                  ],
                ],
              ),
            ),
            if (hasFile) ...[
              const SizedBox(height: 20),
              OrgModalSection(
                title: 'File Attachment',
                icon: Icons.attach_file_rounded,
                accentColor: _DS.primary,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _DS.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.insert_drive_file_rounded,
                        size: 20,
                        color: Colors.white,
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
                              color: _DS.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (report.fileSize != null)
                            Text(
                              report.fileSize!,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: _DS.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openAttachment(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                      style: TextButton.styleFrom(foregroundColor: _DS.primary),
                    ),
                  ],
                ),
              ),
            ],
            if (showTxnSection) ...[
              const SizedBox(height: 20),
              OrgModalSection(
                title: 'Event Transactions',
                icon: Icons.account_balance_wallet_rounded,
                accentColor: _DS.primary,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('transactions')
                      .where('orgId', isEqualTo: report.orgId)
                      .snapshots(),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Text(
                        'Failed to load transactions',
                        style: GoogleFonts.beVietnamPro(
                          color: const Color(0xFFDC2626),
                          fontSize: 12,
                        ),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    final filteredDocs = docs.where((d) {
                      final m = d.data() as Map<String, dynamic>;
                      if (hasEventId) {
                        return (m['eventId']?.toString() ?? '') ==
                            report.eventId;
                      }
                      return (m['eventName']?.toString().toLowerCase() ?? '') ==
                          report.title.toLowerCase();
                    }).toList();

                    if (filteredDocs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'No transactions recorded for this event.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: _DS.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }

                    double total = 0.0;
                    final items = filteredDocs.map((d) {
                      final m = d.data() as Map<String, dynamic>;
                      final amt = (m['amount'] ?? 0).toDouble();
                      total += amt;
                      final cat = m['category']?.toString() ?? '';
                      final seg = m['segment']?.toString() ?? '';
                      final ts = m['date'] as Timestamp?;
                      final dateStr = ts != null
                          ? DateFormat('MMM dd, yyyy').format(ts.toDate())
                          : '';
                      final type = (m['type'] ?? 'income').toString();
                      final isIncome = type == 'income';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE8ECF0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isIncome
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: isIncome
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$cat • $seg',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _DS.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: _DS.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              currency.format(amt),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isIncome
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _DS.primary.withAlpha(10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _DS.primary.withAlpha(30),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Total:',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _DS.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                currency.format(total),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _DS.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView(shrinkWrap: true, children: items),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Open Attachment ──────────────────────────────────────────────────
  Future<void> _openAttachment(BuildContext context) async {
    final b64 = report.fileBase64;
    if (b64 == null || b64.isEmpty) return;
    try {
      final bytes = base64Decode(b64);
      final name = report.fileName ?? 'document';
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFromExt(ext);

      if (mime.startsWith('image/')) {
        OrgAttachmentPreview.showImage(
          context: context,
          bytes: bytes,
          fileName: name,
        );
      } else if (mime == 'text/plain') {
        final text = utf8.decode(bytes);
        OrgAttachmentPreview.showText(
          context: context,
          fileName: name,
          text: text,
        );
      } else {
        await platform_file_utils.saveBytesToTempAndOpen(
          bytes,
          name,
          mimeType: mime,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Error opening attachment: $e');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create / Edit Report Modal (base64 approach)
// ─────────────────────────────────────────────────────────────────────────────
class _ReportModal extends StatefulWidget {
  final String orgId;
  final ReportModel? existingReport;
  // Pre-selects the event + report type when opened from the overdue-reports
  // list, so uploading against an already-known-overdue item skips the
  // manual "cover/event/type" picking a from-scratch upload needs.
  final String? prefillEventId;
  final String? prefillType;
  const _ReportModal({
    required this.orgId,
    this.existingReport,
    this.prefillEventId,
    this.prefillType,
  });

  @override
  State<_ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<_ReportModal> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();

  String _type = 'financial';
  String? _fileBase64;
  String? _fileName;
  String? _fileSize;
  bool _isSubmitting = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _errorMsg;

  List<Map<String, dynamic>> _events = [];
  bool _eventsLoaded = false;
  String? _selectedEventId;
  String _scope = 'event';
  String _schoolYear = SchoolYearUtil.currentSchoolYear();
  String _semester = SchoolYearUtil.semesters.first;

  @override
  void initState() {
    super.initState();
    final r = widget.existingReport;
    if (r != null) {
      _descCtrl.text = r.description;
      _type = r.type;
      _fileBase64 = r.fileBase64;
      _fileName = r.fileName;
      _fileSize = r.fileSize;
      _scope = r.scope;
      if ((r.schoolYear ?? '').isNotEmpty) _schoolYear = r.schoolYear!;
      if ((r.semester ?? '').isNotEmpty) _semester = r.semester!;
    } else if (widget.prefillType != null) {
      _type = widget.prefillType!;
    }
    _loadEvents();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('orgId', isEqualTo: widget.orgId)
          .where('status', isEqualTo: 'approved')
          .orderBy('date', descending: false)
          .get();

      final List<Map<String, dynamic>> loaded = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final title = data['title']?.toString() ?? 'Untitled Event';
        final date = (data['date'] as Timestamp?)?.toDate();
        final dateStr = date != null
            ? DateFormat('MMM dd, yyyy').format(date)
            : 'No date';
        loaded.add({'id': doc.id, 'title': title, 'dateStr': dateStr});
      }
      // The picker above only loads 'approved' events — right for the normal
      // create flow, but the "Upload Now" shortcut off an overdue-reports
      // reminder can prefill an event that's since been archived (still
      // very much needing its report). Without this, _selectedEventId would
      // point at an id missing from _events entirely, and _submit()'s
      // `_events.firstWhere(...)` (no orElse) would throw before the write
      // ever ran — the upload would silently do nothing and never reach
      // Firestore, let alone the admin side.
      if (widget.prefillEventId != null &&
          !loaded.any((e) => e['id'] == widget.prefillEventId)) {
        try {
          final evDoc = await FirebaseFirestore.instance
              .collection('events')
              .doc(widget.prefillEventId)
              .get();
          if (evDoc.exists) {
            final data = evDoc.data()!;
            final date = (data['date'] as Timestamp?)?.toDate();
            loaded.add({
              'id': evDoc.id,
              'title': data['title']?.toString() ?? 'Untitled Event',
              'dateStr': date != null
                  ? DateFormat('MMM dd, yyyy').format(date)
                  : 'No date',
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _events = loaded;
          _eventsLoaded = true;
          if (widget.existingReport != null &&
              widget.existingReport!.eventId != null) {
            _selectedEventId = widget.existingReport!.eventId;
          } else if (widget.existingReport != null) {
            final title = widget.existingReport!.title;
            final match = _events.firstWhere(
              (e) => e['title'] == title,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              _selectedEventId = match['id'];
            }
          } else if (widget.prefillEventId != null) {
            _selectedEventId = widget.prefillEventId;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _eventsLoaded = true);
        _snack('Failed to load events: $e', error: true);
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xlsx', 'jpg', 'png'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _snack('Cannot read file!', error: true);
      return;
    }
    const maxSize = 700 * 1024;
    if (file.bytes!.length > maxSize) {
      _snack('File too large. Max 700 KB allowed.', error: true);
      return;
    }
    final sizeKB = (file.bytes!.length / 1024).toStringAsFixed(1);
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _fileName = file.name;
      _fileSize = '$sizeKB KB';
    });
    for (int i = 0; i <= 100; i += 20) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) setState(() => _uploadProgress = i / 100);
    }
    setState(() {
      _fileBase64 = base64Encode(file.bytes!);
      _uploadProgress = 1.0;
      _isUploading = false;
    });
    _snack('File ready: ${file.name}');
  }

  void _removeFile() => setState(() {
    _fileBase64 = null;
    _fileName = null;
    _fileSize = null;
    _uploadProgress = 0.0;
  });

  Future<void> _submit() async {
    setState(() => _errorMsg = null);
    if (!_formKey.currentState!.validate()) return;

    if (_scope == 'event' && _selectedEventId == null) {
      setState(() => _errorMsg = 'Please select an event');
      return;
    }

    if (_fileBase64 == null || _fileBase64!.isEmpty) {
      setState(() => _errorMsg = 'Please attach a file before submitting');
      return;
    }

    final isEdit = widget.existingReport != null;

    Query<Map<String, dynamic>> dupQuery = FirebaseFirestore.instance
        .collection('reports')
        .where('orgId', isEqualTo: widget.orgId)
        .where('type', isEqualTo: _type);
    if (_scope == 'event') {
      dupQuery = dupQuery.where('eventId', isEqualTo: _selectedEventId);
    } else {
      dupQuery = dupQuery
          .where('scope', isEqualTo: _scope)
          .where('schoolYear', isEqualTo: _schoolYear);
      if (_scope == 'semester') {
        dupQuery = dupQuery.where('semester', isEqualTo: _semester);
      }
    }
    final dupSnap = await dupQuery.get();
    final hasDuplicate = dupSnap.docs.any(
      (d) => d.id != widget.existingReport?.id,
    );
    if (hasDuplicate) {
      setState(
        () => _errorMsg =
            'A ${_type == 'financial' ? 'financial' : 'accomplishment'} report has already been uploaded for that selection. Only one of each type is allowed.',
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AppConfirmationDialog(
        title: isEdit ? 'Save Changes' : 'Submit Report',
        message: isEdit
            ? 'Save changes to this report?'
            : 'Submit this report?',
        confirmLabel: 'Confirm',
        accentColor: _DS.primary,
        // The badge repeats the verb of the modal this is raised from
        // rather than a generic tick, since this dialog lands on top of
        // that modal and the two are read together.
        icon: isEdit ? Icons.save_outlined : Icons.upload_file_rounded,
      ),
    );
    if (ok != true) return;

    final String title;
    if (_scope == 'event') {
      final selectedEvent = _events.firstWhere(
        (e) => e['id'] == _selectedEventId,
        // Belt-and-suspenders: _loadEvents() now backfills a prefilled
        // event that's missing from the normal 'approved'-only list, but
        // this keeps a bad _selectedEventId from throwing here and
        // silently killing the whole submit before it reaches Firestore.
        orElse: () => {'title': 'Untitled Event'},
      );
      title = selectedEvent['title'] as String;
    } else if (_scope == 'semester') {
      title = '$_schoolYear — $_semester';
    } else {
      title = '$_schoolYear (Whole Year)';
    }

    setState(() => _isSubmitting = true);

    final Map<String, dynamic> data = {
      'orgId': widget.orgId,
      'title': title,
      'type': _type,
      'description': _descCtrl.text.trim(),
      'fileBase64': _fileBase64,
      'fileName': _fileName,
      'fileSize': _fileSize,
      'scope': _scope,
      'eventId': _scope == 'event' ? _selectedEventId : null,
      'schoolYear': _scope == 'event' ? null : _schoolYear,
      'semester': _scope == 'semester' ? _semester : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final col = FirebaseFirestore.instance.collection('reports');
      if (isEdit) {
        await col.doc(widget.existingReport!.id).update(data);
        await activity_log.ActivityLogger.log(
          action: 'edit_report',
          module: 'reports',
          details: {
            'orgId': widget.orgId,
            'reportId': widget.existingReport!.id,
          },
        );
      } else {
        final snap = await col.where('orgId', isEqualTo: widget.orgId).get();
        final nextNum = (snap.docs.length + 1).toString().padLeft(3, '0');
        data['reportId'] = 'REP-$nextNum';
        data['status'] = 'pending';
        data['submittedAt'] = FieldValue.serverTimestamp();
        data['submittedBy'] = FirebaseAuth.instance.currentUser?.uid ?? '';
        await col.add(data);
        await activity_log.ActivityLogger.log(
          action: 'create_report',
          module: 'reports',
          details: {'orgId': widget.orgId, 'title': data['title']},
        );
        _notifyAdminsOfReportSubmission(title);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _isSubmitting = false;
      });
    }
  }

  Future<void> _notifyAdminsOfReportSubmission(String eventTitle) async {
    try {
      String orgName = widget.orgId;
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (orgDoc.exists) {
        orgName =
            (orgDoc.data()?['name'] ??
                    orgDoc.data()?['orgName'] ??
                    widget.orgId)
                .toString();
      }
      final reportLabel = _type == 'financial'
          ? 'financial report'
          : 'accomplishment report';
      await NotificationService.sendToAllAdmins(
        title: 'New $reportLabel submitted',
        body: '$orgName submitted a $reportLabel for "$eventTitle".',
        type: 'report_submission',
        orgId: widget.orgId,
        data: {'orgId': widget.orgId, 'reportType': _type},
      );
    } catch (_) {}
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    error ? AppToast.error(context, msg) : AppToast.success(context, msg);
  }

  // True when this modal was opened via the overdue-report "Upload now"
  // shortcut — the event + report type are already known in that case, so
  // the Covers/Event/Type pickers are replaced with a locked summary instead
  // of asking the org officer to re-pick something that's already fixed.
  bool get _locked =>
      widget.existingReport == null && widget.prefillEventId != null;

  Widget _buildLockedSummary() {
    final match = _events.firstWhere(
      (e) => e['id'] == _selectedEventId,
      orElse: () => {},
    );
    final eventTitle = match['title'] as String? ?? 'Loading…';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DS.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: _DS.primary.withAlpha(46)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded, size: 20, color: _DS.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventTitle,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _DS.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_type == 'financial' ? 'Financial' : 'Accomplishment'} '
                  'report — auto-detected from the overdue reminder',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    color: _DS.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingReport != null;
    final hasFile = _fileBase64 != null && _fileBase64!.isNotEmpty;

    return OrgModalShell(
      accentColor: _DS.primary,
      icon: isEdit ? Icons.edit_outlined : Icons.upload_file_outlined,
      title: isEdit ? 'Edit Report' : 'Upload Report',
      width: 520,
      maxHeightFraction: 0.88,
      closeEnabled: !_isSubmitting,
      footerActions: [
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE2E6EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          ),
          child: Text(
            'Cancel',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _isSubmitting || _isUploading || !_eventsLoaded
              ? null
              : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isEdit ? Icons.save_rounded : Icons.upload_file_outlined,
                  size: 16,
                ),
          label: Text(
            isEdit ? 'Save Changes' : 'Submit Report',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DS.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            disabledBackgroundColor: _DS.primary.withAlpha(128),
          ),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_locked) ...[
                _buildLockedSummary(),
                const SizedBox(height: 20),
              ] else ...[
                OrgModalSection(
                  title: 'Report Details',
                  icon: Icons.article_outlined,
                  accentColor: _DS.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _requiredLabel('Covers'),
                      Row(
                        children: [
                          _TypeCard(
                            label: 'Specific Event',
                            icon: Icons.event_outlined,
                            selected: _scope == 'event',
                            onTap: () => setState(() => _scope = 'event'),
                          ),
                          const SizedBox(width: 10),
                          _TypeCard(
                            label: 'Semester',
                            icon: Icons.date_range_outlined,
                            selected: _scope == 'semester',
                            onTap: () => setState(() => _scope = 'semester'),
                          ),
                          const SizedBox(width: 10),
                          _TypeCard(
                            label: 'Whole School Year',
                            icon: Icons.school_outlined,
                            selected: _scope == 'year',
                            onTap: () => setState(() => _scope = 'year'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_scope == 'event') ...[
                        _requiredLabel('Select Event'),
                        _buildEventDropdown(),
                        if (_errorMsg != null &&
                            _selectedEventId == null &&
                            _errorMsg!.contains('event')) ...[
                          const SizedBox(height: 6),
                          Text(
                            _errorMsg!,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _requiredLabel('School Year'),
                                  AnchoredDropdownField<String>(
                                    value: _schoolYear,
                                    decoration: _DS.inputDecoration(
                                      'School Year',
                                    ),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      color: _DS.textPrimary,
                                    ),
                                    items: SchoolYearUtil.schoolYears()
                                        .map(
                                          (y) => DropdownMenuItem(
                                            value: y,
                                            child: Text(y),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _schoolYear = v!),
                                  ),
                                ],
                              ),
                            ),
                            if (_scope == 'semester') ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _requiredLabel('Semester'),
                                    AnchoredDropdownField<String>(
                                      value: _semester,
                                      decoration: _DS.inputDecoration(
                                        'Semester',
                                      ),
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                        color: _DS.textPrimary,
                                      ),
                                      items: SchoolYearUtil.semesters
                                          .map(
                                            (s) => DropdownMenuItem(
                                              value: s,
                                              child: Text(s),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _semester = v!),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Report Type',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: _DS.textSecondary,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _TypeCard(
                            label: 'Financial',
                            icon: Icons.account_balance_outlined,
                            selected: _type == 'financial',
                            onTap: () => setState(() => _type = 'financial'),
                          ),
                          const SizedBox(width: 10),
                          _TypeCard(
                            label: 'Accomplishment',
                            icon: Icons.assignment_turned_in_outlined,
                            selected: _type == 'accomplishment',
                            onTap: () =>
                                setState(() => _type = 'accomplishment'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              OrgModalSection(
                title: 'Additional Details',
                icon: Icons.notes_rounded,
                accentColor: _DS.primary,
                child: TextFormField(
                  controller: _descCtrl,
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  decoration: _DS.inputDecoration(
                    'Description',
                    hint: 'Brief description of this report…',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                  ),
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 20),
              OrgModalSection(
                title: 'File Attachment',
                icon: Icons.attach_file_rounded,
                accentColor: _DS.primary,
                required: true,
                child: _buildFileZone(hasFile),
              ),
              if (_errorMsg != null && !_errorMsg!.contains('event')) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF991B1B),
                          ),
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
    );
  }

  Widget _buildEventDropdown() {
    if (!_eventsLoaded) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No approved events found. Please create an event first.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedEventId,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.event_rounded,
            size: 18,
            color: _DS.textHint,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        hint: Text(
          'Select an approved event',
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: _DS.textHint),
        ),
        selectedItemBuilder: (context) => _events
            .map(
              (event) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  event['title'] as String,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        items: _events.map((event) {
          return DropdownMenuItem<String>(
            value: event['id'] as String,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event['title'] as String,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  event['dateStr'] as String,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10,
                    color: _DS.textHint,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) => setState(() {
          _selectedEventId = value;
          if (_errorMsg != null && _errorMsg!.contains('event')) {
            _errorMsg = null;
          }
        }),
        validator: (value) => value == null ? 'Please select an event' : null,
      ),
    );
  }

  Widget _buildFileZone(bool hasFile) {
    if (_isUploading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _DS.primary.withAlpha(102), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: _DS.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _fileName ?? 'Uploading...',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _DS.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_fileSize != null)
                  Text(
                    _fileSize!,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: _DS.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E6EA),
                valueColor: AlwaysStoppedAnimation<Color>(_DS.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Processing ${(_uploadProgress * 100).toInt()}%',
              style: GoogleFonts.beVietnamPro(
                fontSize: 10,
                color: _DS.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (hasFile) {
      // A quiet card with a green tick, not a green card. The fill, the
      // 1.5px saturated border and the text were all #059669, which made the
      // one row confirming a file is attached louder than the Submit button
      // it sits above. The tick still carries the "attached" state; the card
      // no longer shouts it.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fileName ?? 'File attached',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _DS.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_fileSize != null)
                    Text(
                      _fileSize!,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: _DS.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _removeFile,
              child: Text(
                'Remove',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
            TextButton(
              onPressed: _pickFile,
              child: Text(
                'Change',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: _DS.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickFile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _DS.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  size: 24,
                  color: _DS.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: _DS.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: 'Click to browse ',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w600,
                        color: _DS.primary,
                      ),
                    ),
                    const TextSpan(text: 'or drop your file here'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF, DOC, DOCX, XLSX, JPG, PNG — max 700 KB',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: _DS.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type selector card
// ─────────────────────────────────────────────────────────────────────────────
class _TypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _DS.primaryBg : const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _DS.primary : const Color(0xFFE2E6EA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? _DS.primary : _DS.textHint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _DS.primary : _DS.textSecondary,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: _DS.primary,
              ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown card (not used in main build but kept for completeness)
// ─────────────────────────────────────────────────────────────────────────────
class _CountdownCard extends StatelessWidget {
  final Duration remaining;
  final DateTime eventDate;
  final String eventLabel;
  const _CountdownCard({
    required this.remaining,
    required this.eventDate,
    required this.eventLabel,
  });

  @override
  Widget build(BuildContext context) {
    final expired = remaining == Duration.zero;
    final d = remaining.inDays;
    final h = remaining.inHours % 24;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DS.border),
        boxShadow: _DS.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _DS.primaryBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: _DS.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expired
                    ? '$eventLabel has started!'
                    : 'Countdown to: $eventLabel',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _DS.textPrimary,
                ),
              ),
              Text(
                DateFormat('MMMM d, yyyy — h:mm a').format(eventDate),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: _DS.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!expired)
            Row(
              children: [
                _CountUnit(value: d, label: 'DAYS'),
                _Colon(),
                _CountUnit(value: h, label: 'HRS'),
                _Colon(),
                _CountUnit(value: m, label: 'MIN'),
                _Colon(),
                _CountUnit(value: s, label: 'SEC'),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Event Started!',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF059669),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountUnit extends StatelessWidget {
  final int value;
  final String label;
  const _CountUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 48,
        height: 42,
        decoration: BoxDecoration(
          color: _DS.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          value.toString().padLeft(2, '0'),
          style: GoogleFonts.beVietnamPro(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 9,
          color: _DS.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );
}

class _Colon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      ':',
      style: GoogleFonts.beVietnamPro(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: _DS.primary,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: Color(0xFFDC2626),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Failed to load reports',
          style: GoogleFonts.beVietnamPro(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        if (message.contains('index') ||
            message.contains('FAILED_PRECONDITION'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
            child: Text(
              'A Firestore composite index is missing. '
              'Check the debug console for an auto-create link.',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: _DS.textSecondary,
              ),
            ),
          )
        else
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: _DS.textSecondary,
            ),
          ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            'Retry',
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DS.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Export button
// ─────────────────────────────────────────────────────────────────────────────
class _ExportButton extends StatelessWidget {
  final String orgId;
  const _ExportButton({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return AdminExportButton(
      label: 'Export',
      onSelected: (choice) => _doExport(context, choice),
    );
  }

  Future<void> _doExport(BuildContext ctx, String format) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reports')
          .where('orgId', isEqualTo: orgId)
          .get();
      final rows = snap.docs.map(ReportModel.fromFirestore).toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      if (rows.isEmpty) {
        AppToast.info(ctx, 'No reports to export.');
        return;
      }

      final headers = [
        'Report ID',
        'Title',
        'Type',
        'Date Submitted',
        'Status',
      ];
      final dataRows = rows
          .map(
            (r) => [
              r.reportId,
              r.title,
              r.type == 'financial' ? 'Financial' : 'Accomplishment',
              DateFormat('yyyy-MM-dd').format(r.submittedAt.toDate()),
              r.status,
            ],
          )
          .toList();

      final now = DateTime.now().toString().substring(0, 10);
      // AdminExportButton's dropdown emits 'excel'/'pdf' (see
      // admin_export_button.dart's _items) — this used to check for
      // 'csv', which the button never actually sends, so "Export as
      // Excel" silently fell through to the PDF branch below every
      // single time (the heaviest path, triggered even when a fast CSV
      // was what was actually asked for).
      if (format == 'excel') {
        final csv = [headers, ...dataRows]
            .map(
              (row) => row.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
            )
            .join('\n');
        await OrgExportUtil.saveText(
          csv,
          'reports_$now.csv',
          mimeType: 'text/csv',
        );
      } else {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Reports',
          headers: headers,
          rows: dataRows,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'reports_$now.pdf',
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      AppToast.error(ctx, 'Export failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: StatCard(
      label: label,
      value: value,
      icon: icon,
      color: color,
      selected: isSelected,
      onTap: onTap,
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    this.value,
    required this.items,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => AnchoredMenuTrigger<String>(
    items: items,
    labelOf: (s) => s,
    selectedValue: value,
    onSelected: onChanged,
    trigger: Container(
      height: 44,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DS.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value ?? hint,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: value == null ? _DS.textHint : _DS.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: _DS.textHint,
          ),
        ],
      ),
    ),
  );
}

class _ToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 15),
    label: Text(
      label,
      style: GoogleFonts.beVietnamPro(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: UpriseColors.primaryDark,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
    ),
  );
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
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
    );
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
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
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? _DS.primary : Colors.transparent,
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

// ─────────────────────────────────────────────────────────────────────────────
// Report Model
// ─────────────────────────────────────────────────────────────────────────────
class ReportModel {
  final String id;
  final String reportId;
  final String title;
  final String type;
  final String description;
  final String? fileBase64;
  final String? fileName;
  final String? fileSize;
  final String status;
  final Timestamp submittedAt;
  final String submittedBy;
  final String orgId;
  final String? eventId;
  final String scope;
  final String? schoolYear;
  final String? semester;

  const ReportModel({
    required this.id,
    required this.reportId,
    required this.title,
    required this.type,
    required this.description,
    this.fileBase64,
    this.fileName,
    this.fileSize,
    required this.status,
    required this.submittedAt,
    required this.submittedBy,
    this.orgId = '',
    this.eventId,
    this.scope = 'event',
    this.schoolYear,
    this.semester,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ReportModel(
      id: doc.id,
      reportId:
          d['reportId'] as String? ??
          'REP-${doc.id.substring(0, 6).toUpperCase()}',
      title: d['title'] as String? ?? '',
      type: d['type'] as String? ?? 'financial',
      description: d['description'] as String? ?? '',
      fileBase64: d['fileBase64'] as String?,
      fileName: d['fileName'] as String?,
      fileSize: d['fileSize'] as String?,
      status: d['status'] as String? ?? 'pending',
      submittedAt: d['submittedAt'] as Timestamp? ?? Timestamp.now(),
      submittedBy: d['submittedBy'] as String? ?? '',
      orgId: d['orgId'] as String? ?? '',
      eventId: d['eventId'] as String?,
      scope: d['scope'] as String? ?? 'event',
      schoolYear: d['schoolYear'] as String?,
      semester: d['semester'] as String?,
    );
  }
}
