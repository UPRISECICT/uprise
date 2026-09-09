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
  static const Color primaryBg = Color(0xFFFEF3C7);

  static const Color surface = Color(0xFFFBFCFE);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE8ECF0);
  static const Color textPrimary = Color(0xFF1A202C);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF9AA5B4);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // Required fields are labeled "Foo *" — the asterisk used to render in the
  // same muted gray as the rest of the label and was easy to miss. Splitting
  // it into its own red TextSpan (matching org_event_proposals.dart's
  // _orgEventProposalsInputDecoration) makes it actually stand out.
  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    int? maxLines,
  }) {
    final trimmed = label.trimRight();
    final isRequired = trimmed.endsWith('*');
    final baseLabel = isRequired
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : label;

    return InputDecoration(
      labelText: isRequired ? null : label,
      label: isRequired
          ? RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: baseLabel,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  TextSpan(
                    text: ' *',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          : null,
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

  // ── Deadline row ── UPDATED WITH PROFESSIONAL UI ──────────────────────────
  Widget _buildDeadlineRow(List<ReportModel> all) {
    final submittedKeys = all
        .where((r) => r.status != 'archived' && (r.eventId ?? '').isNotEmpty)
        .map((r) => '${r.eventId}_${r.type}')
        .toSet();

    final pending =
        _finishedEventDeadlines
            .where((d) => !submittedKeys.contains('${d.eventId}_${d.type}'))
            .toList()
          ..sort((a, b) => a.deadline.compareTo(b.deadline));

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

    // Group by event
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
                onTap: () =>
                    _showAllDeadlines(context, groups, orderedEventIds),
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

  // ── Show all deadlines in a beautiful bottom sheet ────────────────────────
  void _showAllDeadlines(
    BuildContext context,
    Map<String, List<_PendingEventDeadline>> groups,
    List<String> orderedEventIds,
  ) {
    final now = DateTime.now();
    final totalPending = orderedEventIds.length;
    final overdueCount = orderedEventIds
        .where((id) => groups[id]!.any((d) => now.isAfter(d.deadline)))
        .length;

    final searchCtrl = TextEditingController();

    // A centered Dialog instead of a bottom sheet — every other detail/edit
    // panel in the org web portal (certificates, event overview, etc.) uses
    // a centered Dialog; the mobile-style bottom sheet was the odd one out
    // here and read as less "desktop admin tool" than the rest of the app.
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final visibleEventIds = query.isEmpty
                ? orderedEventIds
                : orderedEventIds
                      .where(
                        (id) => groups[id]!.any(
                          (d) => d.eventTitle.toLowerCase().contains(query),
                        ),
                      )
                      .toList();
            return Container(
              width: 640,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _DS.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.pending_actions_rounded,
                            size: 24,
                            color: _DS.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'All Pending Reports',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _DS.textPrimary,
                                ),
                              ),
                              Text(
                                '$totalPending event${totalPending > 1 ? 's' : ''} need${totalPending > 1 ? '' : 's'} attention',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: _DS.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (overdueCount > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$overdueCount Overdue',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  // Search — this list has no cap on how many events can show
                  // up here, so once an org has more than a handful of
                  // pending reports it becomes a long scroll with nothing to
                  // narrow it down.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by event name…',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: _DS.textSecondary,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Color(0xFF9AA5B4),
                        ),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                tooltip: 'Clear Search',
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSheetState(() {});
                                },
                              ),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8F9FB),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _DS.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _DS.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _DS.primary),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 20, color: _DS.border),
                  // List — Flexible (not Expanded) so a short list just
                  // shrinks to fit instead of leaving a big empty area
                  // below it, while a long one still scrolls within the
                  // dialog's max height.
                  Flexible(
                    child: visibleEventIds.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'No pending reports match "$query"',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: _DS.textSecondary,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            itemCount: visibleEventIds.length,
                            itemBuilder: (_, idx) {
                              final eventId = visibleEventIds[idx];
                              final items = groups[eventId]!;
                              return _PendingDeadlineListItem(
                                items: items,
                                onUpload: (type) =>
                                    _openPrefillModal(eventId, type),
                              );
                            },
                          ),
                  ),
                  // Close button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _DS.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
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
          Expanded(flex: 2, child: _headerCell('REPORT ID')),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _headerCell('EVENT')),
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
            // Report ID
            Expanded(
              flex: 2,
              child: Text(
                report.reportId,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _DS.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            // EVENT (Title + Description)
            Expanded(
              flex: 3,
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

  // Closes the overdue-list bottom sheet (if open) and jumps straight into
  // the upload modal with the event + type already selected — used by the
  // "Upload now" shortcut on overdue items instead of the normal flow of
  // clicking "Upload Report" and picking the event/type from scratch.
  void _openPrefillModal(String eventId, String type) {
    Navigator.of(context).pop();
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

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) => showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
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
  const _PendingEventDeadline({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.type,
    required this.deadline,
  });
}

// ── List item for the bottom sheet ────────────────────────────────────────
class _PendingDeadlineListItem extends StatelessWidget {
  final List<_PendingEventDeadline> items;
  // Only offered for items that are actually overdue — for reports that
  // still have time left, the normal "Upload Report" flow already covers it.
  final ValueChanged<String> onUpload;
  const _PendingDeadlineListItem({required this.items, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdueItems = items.where((d) => now.isAfter(d.deadline)).toList();
    final anyOverdue = overdueItems.isNotEmpty;
    final earliest = items
        .map((d) => d.deadline)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final typesLabel = items
        .map((d) => d.type == 'financial' ? 'Financial' : 'Accomplishment')
        .join(' & ');
    final daysLeft = now.difference(earliest).inDays.abs();
    final isDueSoon = !anyOverdue && daysLeft <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: anyOverdue
              ? const Color(0xFFFCA5A5)
              : isDueSoon
              ? const Color(0xFFFFE4CC)
              : _DS.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status indicator bar
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: anyOverdue
                      ? const Color(0xFFDC2626)
                      : isDueSoon
                      ? _DS.primary
                      : const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items.first.eventTitle,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _DS.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: anyOverdue
                                ? const Color(0xFFFEF2F2)
                                : isDueSoon
                                ? const Color(0xFFFFF7ED)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            typesLabel,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: anyOverdue
                                  ? const Color(0xFFDC2626)
                                  : isDueSoon
                                  ? _DS.primary
                                  : const Color(0xFF059669),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          anyOverdue
                              ? 'Overdue by ${daysLeft} day${daysLeft > 1 ? 's' : ''}'
                              : 'Due in $daysLeft day${daysLeft > 1 ? 's' : ''}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: _DS.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: anyOverdue
                      ? const Color(0xFFFEF2F2)
                      : isDueSoon
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: anyOverdue
                        ? const Color(0xFFFCA5A5)
                        : isDueSoon
                        ? const Color(0xFFFFE4CC)
                        : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      anyOverdue
                          ? Icons.error_outline_rounded
                          : isDueSoon
                          ? Icons.schedule_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: anyOverdue
                          ? const Color(0xFFDC2626)
                          : isDueSoon
                          ? _DS.primary
                          : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      anyOverdue
                          ? 'Overdue'
                          : isDueSoon
                          ? 'Due Soon'
                          : 'On Track',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: anyOverdue
                            ? const Color(0xFFDC2626)
                            : isDueSoon
                            ? _DS.primary
                            : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (anyOverdue) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: overdueItems
                  .map(
                    (d) => _UploadNowButton(
                      label: d.type == 'financial'
                          ? 'Upload Financial'
                          : 'Upload Accomplishment',
                      onTap: () => onUpload(d.type),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _UploadNowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _UploadNowButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.upload_file_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
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
                        color: _DS.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        size: 20,
                        color: _DS.primary,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening attachment: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
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
      builder: (_) => _ConfirmDialog(
        title: isEdit ? 'Save Changes' : 'Submit Report',
        message: isEdit
            ? 'Save changes to this report?'
            : 'Submit this report?',
        confirmLabel: 'Confirm',
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
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF059669), width: 1.5),
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
                      color: const Color(0xFF065F46),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_fileSize != null)
                    Text(
                      _fileSize!,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF059669),
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
// Confirm dialog
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
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
                  color: destructive ? const Color(0xFFFEF2F2) : _DS.primaryBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  destructive
                      ? Icons.delete_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: destructive ? const Color(0xFFDC2626) : _DS.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _DS.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: _DS.textSecondary,
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
                      : _DS.primary,
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
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              'No reports to export.',
              style: GoogleFonts.beVietnamPro(),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
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
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'Export failed: $e',
            style: GoogleFonts.beVietnamPro(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
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
