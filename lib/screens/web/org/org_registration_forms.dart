// Dedicated "Registration Forms" screen — org officers previously could
// only see a student's submitted registration-form answers inside the
// Mark Attendance screen, and only for an event that hadn't ended yet
// (EventManagementScreen's event switcher excludes _EState.ended events
// entirely, so once an event finished there was no way to reselect it and
// review who answered what). This screen queries `registrations` directly
// by event, with no such exclusion, so form answers stay reachable before,
// during, and after an event.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../theme/org_theme.dart';
import 'org_attendance_qr.dart' show EventModel, showRegistrationAnswers;

class OrgRegistrationFormsScreen extends StatefulWidget {
  final String orgId;
  const OrgRegistrationFormsScreen({super.key, required this.orgId});

  @override
  State<OrgRegistrationFormsScreen> createState() =>
      _OrgRegistrationFormsScreenState();
}

class _OrgRegistrationFormsScreenState
    extends State<OrgRegistrationFormsScreen> {
  EventModel? _event;
  String? _eventDocId;
  String _query = '';
  final Map<String, Map<String, dynamic>> _studentCache = {};

  // Queries `events` directly (most recent first), not `event_proposals` —
  // unlike EventManagementScreen this deliberately does NOT filter out
  // events whose date has passed. Previously this queried `event_proposals`
  // and then looked up the matching `events` doc via `createdFromProposalId`
  // — but a proposal can be deleted/archived after its event is published
  // (event_proposals and events are independent docs once publish creates
  // the events doc), so any event whose source proposal was removed simply
  // never appeared in this dropdown at all, silently hiding its
  // registrations/forms. Querying `events` directly means every published
  // event shows up regardless of what happened to the proposal it came from.
  // No .orderBy('date') here on purpose — every other screen with this
  // exact orgId+status query sorts ascending (org_events_schedule.dart,
  // org_reports.dart), and Firestore needs its own composite index per sort
  // direction. This page was the only one asking for descending order, its
  // index was never provisioned, and the query failed outright — silently,
  // since nothing here checked for a stream error, so it just looked like
  // "no events" instead of "the query is broken." Sorting client-side below
  // avoids needing a new index at all.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('events')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .snapshots();

  void _selectEvent(EventModel e) {
    setState(() {
      _event = e;
      _eventDocId = e.id;
    });
  }

  Future<void> _ensureStudentsLoaded(Iterable<String> uids) async {
    final missing = uids
        .where((u) => u.isNotEmpty && !_studentCache.containsKey(u))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    for (var i = 0; i < missing.length; i += 30) {
      final chunk = missing.sublist(i, (i + 30).clamp(0, missing.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          _studentCache[d.id] = d.data();
        }
      } catch (_) {}
      for (final id in chunk) {
        _studentCache.putIfAbsent(id, () => const {});
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final horizontalPadding = isMobile ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              0,
            ),
            child: _buildHeader(),
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: _buildEventPicker(),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: _buildSearchField(),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                24,
              ),
              child: _buildTable(),
            ),
          ),
        ],
      ),
    );
  }

  // The org dashboard's shared top bar already renders "Registration Forms"
  // as the page title above this — repeating it as a big H1 here was a
  // straight duplicate. Just the one-line explanation of what the page
  // does stays; it ties into the "Registrants for <event>" label above the
  // table (see _buildTable) so the picker and results still read as one
  // flow instead of two disconnected pieces.
  Widget _buildHeader() {
    return Text(
      'Pick an event to see who registered and review their submitted answers — even after the event has ended.',
      style: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF64748B),
      ),
    );
  }

  Widget _buildEventPicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (ctx, snap) {
        // Surfaced instead of silently falling through to the "no events"
        // empty state — that's exactly what hid the missing-index failure
        // this query used to have.
        if (snap.hasError) {
          return _banner('Could not load events: ${snap.error}');
        }
        final events =
            (snap.data?.docs ?? []).map((d) => EventModel.fromDoc(d)).toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        if (events.isNotEmpty && _event == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _event == null) _selectEvent(events.first);
          });
        }
        if (events.isEmpty) {
          return _banner('No events found for this organization yet.');
        }
        // This is the primary control on the page — everything below it
        // (search, results) depends on what's picked here. It used to be a
        // slim, easy-to-scroll-past bar with a tiny unlabeled icon; sized
        // and labeled up so it reads as "start here," not just another
        // filter chip.
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: UpriseColors.primaryDark.withAlpha(60),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_note_rounded,
                  size: 19,
                  color: UpriseColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SELECT EVENT',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: UpriseColors.primaryDark,
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _event?.id,
                        isExpanded: true,
                        // No max height here defaults to unbounded, so with
                        // enough events the menu just grew to fill nearly
                        // the whole screen instead of staying a compact,
                        // internally-scrollable panel near the button.
                        menuMaxHeight: 320,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: Color(0xFFB0BAC8),
                        ),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                        items: events
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  '${e.title} — ${DateFormat('MMM d, yyyy').format(e.date)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            _selectEvent(events.firstWhere((e) => e.id == v));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search by name or student ID',
        hintStyle: GoogleFonts.beVietnamPro(fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 19,
          color: Color(0xFFB0BAC8),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEBEEF3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEBEEF3)),
        ),
      ),
      style: GoogleFonts.beVietnamPro(fontSize: 13.5),
    );
  }

  Widget _banner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEBEEF3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: Color(0xFFB0BAC8),
          ),
          const SizedBox(width: 8),
          Text(
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFFB0BAC8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_eventDocId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Select an event above to view its submitted forms.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('registrations')
          .where('eventId', isEqualTo: _eventDocId)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final regs = snap.data?.docs ?? [];
        _ensureStudentsLoaded(
          regs.map((r) => ((r.data() as Map)['userId'] ?? '').toString()),
        );

        Map<String, dynamic> studentOf(Map<String, dynamic> m) =>
            _studentCache[(m['userId'] ?? '').toString()] ?? const {};
        String nameOf(Map<String, dynamic> m) =>
            (studentOf(m)['fullName'] ??
                    m['studentName'] ??
                    m['fullName'] ??
                    '')
                .toString();
        String idOf(Map<String, dynamic> m) =>
            (studentOf(m)['studentId'] ?? m['studentId'] ?? '').toString();
        bool hasAnswers(Map<String, dynamic> m) {
          final r = m['formResponses'];
          final a = m['formAnswers'];
          return (r is Map && r.isNotEmpty) || (a is Map && a.isNotEmpty);
        }

        final filtered = regs.where((d) {
          if (_query.isEmpty) return true;
          final m = d.data() as Map<String, dynamic>;
          return nameOf(m).toLowerCase().contains(_query) ||
              idOf(m).toLowerCase().contains(_query);
        }).toList();

        // Explicitly names which event these rows belong to — the dropdown
        // above and this list used to have no visible connection to each
        // other, which is what made the page hard to follow at a glance.
        final resultsLabel = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
              children: [
                const TextSpan(text: 'Registrants for '),
                TextSpan(
                  text: _event?.title ?? 'this event',
                  style: const TextStyle(color: Color(0xFF1A202C)),
                ),
                TextSpan(text: ' · ${regs.length} submitted'),
              ],
            ),
          ),
        );

        if (filtered.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              resultsLabel,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    regs.isEmpty
                        ? 'No one has registered for this event yet.'
                        : 'No records match your search.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            resultsLabel,
            Container(
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
                  for (var i = 0; i < filtered.length; i++)
                    _FormRow(
                      name: nameOf(filtered[i].data() as Map<String, dynamic>),
                      studentId: idOf(
                        filtered[i].data() as Map<String, dynamic>,
                      ),
                      hasAnswers: hasAnswers(
                        filtered[i].data() as Map<String, dynamic>,
                      ),
                      isLast: i == filtered.length - 1,
                      onView: () => showRegistrationAnswers(
                        context,
                        nameOf(
                              filtered[i].data() as Map<String, dynamic>,
                            ).isEmpty
                            ? 'Student'
                            : nameOf(
                                filtered[i].data() as Map<String, dynamic>,
                              ),
                        filtered[i].data() as Map<String, dynamic>,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FormRow extends StatelessWidget {
  final String name;
  final String studentId;
  final bool hasAnswers;
  final bool isLast;
  final VoidCallback onView;

  const _FormRow({
    required this.name,
    required this.studentId,
    required this.hasAnswers,
    required this.isLast,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = name.isEmpty ? '—' : name;
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final initials =
        parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (displayName.isNotEmpty && displayName != '—'
              ? displayName[0].toUpperCase()
              : '?');

    // Whole row is tappable (with a trailing chevron affordance, same
    // pattern as the dashboard's drill-down tables) instead of a bare text
    // link being the only clickable thing — plus an avatar so the row
    // isn't just two lines of plain text.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onView,
        hoverColor: const Color(0xFFF8F9FB),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (studentId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        studentId,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!hasAnswers)
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'No form data',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
