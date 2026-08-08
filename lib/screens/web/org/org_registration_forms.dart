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

  // All approved proposals, most recent first — unlike EventManagementScreen
  // this deliberately does NOT filter out events whose date has passed.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .orderBy('date', descending: true)
      .snapshots();

  Future<void> _selectEvent(EventModel e) async {
    setState(() {
      _event = e;
      _eventDocId = null;
    });
    final q = await FirebaseFirestore.instance
        .collection('events')
        .where('createdFromProposalId', isEqualTo: e.id)
        .limit(1)
        .get();
    if (mounted && q.docs.isNotEmpty) {
      setState(() => _eventDocId = q.docs.first.id);
    }
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
      backgroundColor: const Color(0xFFF6F7F9),
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

  Widget _buildHeader() {
    return Text(
      'Registration Forms',
      style: GoogleFonts.beVietnamPro(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A202C),
      ),
    );
  }

  Widget _buildEventPicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (ctx, snap) {
        final events = (snap.data?.docs ?? [])
            .map((d) => EventModel.fromDoc(d))
            .toList();
        if (events.isNotEmpty && _event == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _event == null) _selectEvent(events.first);
          });
        }
        if (events.isEmpty) {
          return _banner('No events found for this organization yet.');
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEBEEF3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 14,
                color: UpriseColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Text(
                'Event',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _event?.id,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFFB0BAC8),
                    ),
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
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
            _event == null
                ? 'Select an event above to view its submitted forms.'
                : 'This event hasn\'t been published yet, so it has no '
                      'registrations.',
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

        if (filtered.isEmpty) {
          return Padding(
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
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEBEEF3)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < filtered.length; i++)
                _FormRow(
                  name: nameOf(filtered[i].data() as Map<String, dynamic>),
                  studentId: idOf(filtered[i].data() as Map<String, dynamic>),
                  hasAnswers: hasAnswers(
                    filtered[i].data() as Map<String, dynamic>,
                  ),
                  isLast: i == filtered.length - 1,
                  onView: () => showRegistrationAnswers(
                    context,
                    nameOf(filtered[i].data() as Map<String, dynamic>).isEmpty
                        ? 'Student'
                        : nameOf(filtered[i].data() as Map<String, dynamic>),
                    filtered[i].data() as Map<String, dynamic>,
                  ),
                ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF3F4F8))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '—' : name,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
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
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'No form on this event',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: const Color(0xFFB0BAC8),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: Text(
              'View Answers',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: UpriseColors.info),
          ),
        ],
      ),
    );
  }
}
