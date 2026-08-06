// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme/org_theme.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import 'export_pdf.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../services/notification_service.dart';
import '../../../services/webinar_attendance_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  // Refined card shadow — softer, more layered
  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static InputDecoration inputDeco(
    String label, {
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null
          ? Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Icon(icon, size: 17, color: const Color(0xFFB0BAC8)),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      labelStyle: GoogleFonts.beVietnamPro(
        fontSize: 12.5,
        color: const Color(0xFF8492A6),
        fontWeight: FontWeight.w500,
      ),
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFFB0BAC8),
      ),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE5484D)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1.5),
      ),
    );
  }

  static InputDecoration searchDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFFB0BAC8),
    ),
    prefixIcon: const Padding(
      padding: EdgeInsets.only(left: 14, right: 10),
      child: Icon(Icons.search_rounded, size: 17, color: Color(0xFFB0BAC8)),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: const BorderSide(color: Color(0xFFE4E8EF)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: const BorderSide(color: Color(0xFFE4E8EF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: Row(
    children: [
      if (icon != null) ...[
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: UpriseColors.primaryDark.withOpacity(0.09),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: UpriseColors.primaryDark),
        ),
        const SizedBox(width: 9),
      ],
      Text(
        text,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Divider(color: Color(0xFFEEF0F4), thickness: 1)),
    ],
  ),
);

Widget _headerCell(String text) => Text(
  text,
  style: GoogleFonts.beVietnamPro(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF64748B),
    letterSpacing: 0.7,
  ),
);

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
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      style.$4,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: style.$2,
        letterSpacing: 0.6,
      ),
    ),
  );
}

void _toast(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.beVietnamPro(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: error
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class EventModel {
  final String id, title, location, startTime, endTime;
  final DateTime date;
  const EventModel({
    required this.id,
    required this.title,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.date,
  });
  factory EventModel.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    return EventModel(
      id: d.id,
      title: m['title'] ?? 'Untitled',
      location: m['location'] ?? 'TBA',
      startTime: m['startTime'] ?? '—',
      endTime: m['endTime'] ?? '—',
      date: (m['date'] as Timestamp).toDate(),
    );
  }
}

// Handles both "7:30 PM" and 24-hour "19:30" startTime/endTime strings —
// DateFormat.jm().parse() only understands the former and throws on the
// latter, which org_event_proposals.dart's time picker can produce when the
// organizer's device is set to 24-hour format (mirrors the same dual-format
// logic as EventModel.fullDateTime in lib/models/event_model.dart).
DateTime _timeOfDay(DateTime date, String timeStr) {
  try {
    int hour = 0;
    int minute = 0;
    if (timeStr.isNotEmpty) {
      if (timeStr.toLowerCase().contains('am') ||
          timeStr.toLowerCase().contains('pm')) {
        final clean = timeStr
            .replaceAll(RegExp(r'[AP]M', caseSensitive: false), '')
            .trim();
        final parts = clean.split(':');
        hour = int.parse(parts[0].trim());
        minute = int.parse(parts.length > 1 ? parts[1].trim() : '0');
        if (timeStr.toLowerCase().contains('pm') && hour < 12) hour += 12;
        if (timeStr.toLowerCase().contains('am') && hour == 12) hour = 0;
      } else {
        final parts = timeStr.split(':');
        hour = int.parse(parts[0]);
        minute = int.parse(
          parts.length > 1 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : '0',
        );
      }
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  } catch (_) {
    return date;
  }
}

enum _EState { future, todayInactive, active, ended }

_EState _eventState(EventModel e, {bool? activeOverride}) {
  if (activeOverride == true) return _EState.active;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final eDay = DateTime(e.date.year, e.date.month, e.date.day);
  if (eDay.isAfter(today)) return _EState.future;
  if (eDay.isBefore(today)) return _EState.ended;
  try {
    final startDt = _timeOfDay(e.date, e.startTime);
    var endDt = _timeOfDay(e.date, e.endTime);
    if (endDt.isBefore(startDt)) endDt = endDt.add(const Duration(days: 1));
    if (now.isAfter(endDt.add(const Duration(minutes: 15))))
      return _EState.ended;
    if (now.isAfter(startDt.subtract(const Duration(minutes: 15))))
      return _EState.active;
  } catch (_) {}
  return _EState.todayInactive;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class EventManagementScreen extends StatefulWidget {
  final String orgId;
  final int initialTabIndex;
  // Passed straight through to AttendanceTab — see its own doc comment for
  // why this needs to be a ValueListenable rather than a plain bool.
  final ValueListenable<int>? visibleTabIndex;
  final int myTabIndex;
  const EventManagementScreen({
    super.key,
    required this.orgId,
    this.initialTabIndex = 0,
    this.visibleTabIndex,
    this.myTabIndex = -1,
  });

  @override
  State<EventManagementScreen> createState() => _EventManagementScreenState();
}

class _EventManagementScreenState extends State<EventManagementScreen> {
  EventModel? _event;
  String? _eventDocId;

  // Created once, not a getter — widget.orgId never changes for this
  // screen's lifetime, so a getter here was re-subscribing on every rebuild.
  late final Stream<QuerySnapshot> _eventsStream = FirebaseFirestore.instance
      .collection('event_proposals')
      .where('orgId', isEqualTo: widget.orgId)
      .where('status', isEqualTo: 'approved')
      .orderBy('date')
      .snapshots();

  @override
  void dispose() {
    super.dispose();
  }

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
    if (mounted && q.docs.isNotEmpty)
      setState(() => _eventDocId = q.docs.first.id);
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
          // ── Event switcher (only shown when there's more than one live/upcoming event) ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              0,
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: _eventsStream,
              builder: (ctx, snap) {
                final events = (snap.data?.docs ?? [])
                    .map((d) => EventModel.fromDoc(d))
                    .toList();
                final activeEvents = events
                    .where((e) => _eventState(e) != _EState.ended)
                    .toList();
                if (activeEvents.isNotEmpty && _event == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _selectEvent(activeEvents.first);
                  });
                }

                if (activeEvents.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(_DS.radiusMd),
                      border: Border.all(color: const Color(0xFFEBEEF3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: const Color(0xFFB0BAC8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'No upcoming or active events available',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: const Color(0xFFB0BAC8),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // A single event is already fully described by the banner below —
                // no need for a second card just to name it again.
                if (activeEvents.length == 1) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_DS.radiusMd),
                    border: Border.all(color: const Color(0xFFEBEEF3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_rounded,
                        size: 14,
                        color: UpriseColors.primaryDark,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Switch event',
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
                            items: activeEvents
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.id,
                                    child: Text(e.title),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                _selectEvent(
                                  activeEvents.firstWhere((e) => e.id == v),
                                );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: isMobile ? 12 : 14),
          Expanded(
            child: AttendanceTab(
              key: const PageStorageKey('att'),
              orgId: widget.orgId,
              event: _event,
              eventDocId: _eventDocId,
              visibleTabIndex: widget.visibleTabIndex,
              myTabIndex: widget.myTabIndex,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE PILL — improved with dot indicator
// ─────────────────────────────────────────────────────────────────────────────
class _StatePill extends StatelessWidget {
  final EventModel event;
  const _StatePill(this.event);

  @override
  Widget build(BuildContext context) {
    final state = _eventState(event);
    final (
      Color bg,
      Color fg,
      Color border,
      String txt,
      IconData icon,
    ) = switch (state) {
      _EState.active => (
        const Color(0xFFECFDF5),
        const Color(0xFF059669),
        const Color(0xFFBBF7D0),
        'LIVE',
        Icons.fiber_manual_record,
      ),
      _EState.todayInactive => (
        const Color(0xFFFFFBEB),
        const Color(0xFFFB923C),
        const Color(0xFFFDE68A),
        'TODAY',
        Icons.today_rounded,
      ),
      _EState.future => (
        const Color(0xFFEFF6FF),
        const Color(0xFF2563EB),
        const Color(0xFFBFD7FF),
        'UPCOMING',
        Icons.event_rounded,
      ),
      _EState.ended => (
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        const Color(0xFFE5E7EB),
        'ENDED',
        Icons.lock_outline_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: state == _EState.active ? 8 : 11, color: fg),
          const SizedBox(width: 5),
          Text(
            txt,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ATTENDANCE TAB
// =============================================================================
class AttendanceTab extends StatefulWidget {
  final String orgId;
  final EventModel? event;
  final String? eventDocId;
  // Lets the parent sidebar (org_dashboard.dart's IndexedStack, which
  // deliberately keeps every section's state alive instead of tearing it
  // down on tab switch) tell this screen when it's been navigated away from,
  // so the QR camera can be stopped even though this widget stays mounted.
  // A ValueListenable (not a plain bool prop) because org_dashboard.dart
  // builds its screens list once and reuses the same instances — a bool
  // prop wouldn't update on tab switches without rebuilding that list.
  final ValueListenable<int>? visibleTabIndex;
  final int myTabIndex;
  const AttendanceTab({
    super.key,
    required this.orgId,
    this.event,
    this.eventDocId,
    this.visibleTabIndex,
    this.myTabIndex = -1,
  });

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final _scanner = MobileScannerController();
  final _search = TextEditingController();
  final _manualCtrl = TextEditingController();

  bool _scanning = true;
  String _lastCode = '';
  String _query = '';
  String _statusFilter = 'All';
  int _inputMode = 0;
  int _subTab = 0;
  bool _sendingEvaluations = false;
  // Mirrors the `active` value build() computes from the event stream —
  // cached here so the camera lifecycle handlers (which fire outside
  // build(), e.g. from app-lifecycle or tab-visibility callbacks) know
  // whether attendance is even open before trying to restart the scanner.
  bool _attendanceActive = false;

  // _statusFilter defaults to 'All' so filtering starts unfiltered — but
  // that same default made the "Total Registrants" stat card render as
  // visually selected (colored border/shadow) before the org ever clicked
  // anything, since its isSelected check was just `_statusFilter == 'All'`.
  // This flag is UI-only and never touches the actual filter value or the
  // filtering methods below — it only tracks whether a card has genuinely
  // been clicked yet, so the highlight reflects a real user action.
  bool _filterTouched = false;

  // `registrations` docs only ever carry `userId` (plus whatever the
  // registration form itself asked for) — name/student number/course/year
  // live on `students` (doc ID = uid), so every registrant list needs this
  // looked up alongside the raw registration doc to show more than just a
  // bare ID.
  final Map<String, Map<String, dynamic>> _studentCache = {};

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

  void _showMarkedModal(BuildContext context, String name, String status) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        final isLate = status == 'late';
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 72,
                  color: isLate
                      ? const Color(0xFFFB923C)
                      : const Color(0xFF059669),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Marked ${status.toUpperCase()}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.visibleTabIndex?.addListener(_onVisibleTabChanged);
  }

  void _stopScanner() {
    // Best-effort: mobile_scanner's own start/stop calls can throw if the
    // camera is already in the target state or permissions were revoked
    // mid-session — none of that should ever surface as an app error, this
    // is just resource cleanup.
    _scanner.stop().catchError((_) {});
  }

  void _startScannerIfDue() {
    if (!mounted || _inputMode != 0 || !_attendanceActive) return;
    final tabVisible =
        widget.visibleTabIndex == null ||
        widget.visibleTabIndex!.value == widget.myTabIndex;
    if (!tabVisible) return;
    _scanner.start().catchError((_) {});
  }

  // org_dashboard.dart's IndexedStack keeps this whole screen mounted when
  // the org switches to a different sidebar section — so leaving Attendance
  // never unmounts this widget or its MobileScannerController, and the
  // camera would otherwise stay on indefinitely in the background.
  void _onVisibleTabChanged() {
    if (widget.visibleTabIndex!.value == widget.myTabIndex) {
      _startScannerIfDue();
    } else {
      _stopScanner();
    }
  }

  // Same problem as above but for backgrounding the whole app (switching
  // apps, locking the phone) — the widget stays mounted, so the camera
  // needs to be stopped explicitly here too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startScannerIfDue();
    } else {
      _stopScanner();
    }
  }

  // Switching the QR Scan / Manual Entry / Roll Call / Webinar Code chips
  // removes the MobileScanner widget from the tree entirely when leaving QR
  // mode, but mobile_scanner never stops a controller that was passed in
  // (rather than created by the widget itself) just because the widget
  // using it was unmounted — so the camera kept running in the background
  // after switching to any of the other three modes until this explicit stop.
  void _setInputMode(int mode) {
    if (_inputMode == mode) return;
    setState(() => _inputMode = mode);
    if (mode == 0) {
      _startScannerIfDue();
    } else {
      _stopScanner();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.visibleTabIndex?.removeListener(_onVisibleTabChanged);
    _scanner.dispose();
    _search.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot>? get _attStream => widget.eventDocId == null
      ? null
      : FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventDocId)
            .collection('attendances')
            .orderBy('timestamp')
            .snapshots();

  Stream<QuerySnapshot>? get _regStream => widget.eventDocId == null
      ? null
      : FirebaseFirestore.instance
            .collection('registrations')
            .where('eventId', isEqualTo: widget.eventDocId)
            .snapshots();

  Stream<DocumentSnapshot>? get _eventStream => widget.eventDocId == null
      ? null
      : FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventDocId)
            .snapshots();

  bool _isActive(DocumentSnapshot? doc) {
    // An explicit isActive flag (set via the Open/Close button) always wins —
    // otherwise closing attendance mid-event would be silently overridden by
    // the time-based auto-active check below.
    final flag = doc == null ? null : (doc.data() as Map?)?['isActive'];
    if (flag is bool) return flag;
    if (widget.event == null) return false;
    return _eventState(widget.event!) == _EState.active;
  }

  bool get _isEventDay {
    if (widget.event == null) return false;
    final now = DateTime.now();
    final eventDate = widget.event!.date;
    return now.year == eventDate.year &&
        now.month == eventDate.month &&
        now.day == eventDate.day;
  }

  Future<void> _markAttendance(String uid, {bool isManual = false}) async {
    if (widget.eventDocId == null || widget.event == null) return;
    try {
      final evDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventDocId)
          .get();
      if (!_isActive(evDoc))
        throw Exception('Attendance is not open for this event');

      DocumentSnapshot? userDoc;

      final direct = await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .get();
      if (direct.exists) {
        userDoc = direct;
      } else {
        final q = await FirebaseFirestore.instance
            .collection('students')
            .where('studentId', isEqualTo: uid)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) userDoc = q.docs.first;
      }

      if (userDoc == null) throw Exception('Student not found');

      // Registration docs are keyed deterministically as `${uid}_${eventId}`
      // (see student_events_screen.dart's register flow). Without this,
      // anyone whose QR code gets scanned — or any manually-entered ID —
      // could be marked present for an event they never registered for.
      final regDoc = await FirebaseFirestore.instance
          .collection('registrations')
          .doc('${userDoc.id}_${widget.eventDocId}')
          .get();
      if (!regDoc.exists) {
        throw Exception(
          '${(userDoc.data() as Map)['fullName'] ?? 'Student'} is not registered for this event',
        );
      }

      // Deterministic doc ID (one attendance record per student per event)
      // instead of an auto-generated one — a get-then-add on an auto ID
      // leaves a race window where two near-simultaneous scans/taps can both
      // pass the "not yet marked" check before either write commits,
      // producing duplicate attendance rows. Keying by student UID makes a
      // second attempt land on the exact same document instead.
      final attRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventDocId)
          .collection('attendances')
          .doc(userDoc.id);
      final existingAtt = await attRef.get();
      if (existingAtt.exists) {
        throw Exception(
          '${(userDoc.data() as Map)['fullName'] ?? 'Student'} already marked',
        );
      }

      String status = 'present';
      try {
        final startDt = _timeOfDay(widget.event!.date, widget.event!.startTime);
        if (DateTime.now().isAfter(startDt.add(const Duration(minutes: 15))))
          status = 'late';
      } catch (_) {}

      final data = userDoc.data() as Map<String, dynamic>;
      await attRef.set({
        'studentId': userDoc.id,
        'studentName': data['fullName'] ?? data['email'] ?? 'Unknown',
        'studentEmail': data['email'] ?? '',
        'program': data['course'] ?? 'N/A',
        'yearLevel': data['yearLevel'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': status,
        'method': isManual ? 'manual' : 'qr',
      });

      await activity_log.ActivityLogger.log(
        action: 'mark_attendance',
        module: 'attendance',
        details: {
          'orgId': widget.orgId,
          'eventId': widget.eventDocId,
          'studentId': userDoc.id,
          'status': status,
          'method': isManual ? 'manual' : 'qr',
        },
      );

      // 🔔 Notify the student that they've been marked for this event.
      // Wrapped in its own try/catch so a notification failure never
      // undoes or blocks the attendance that was already recorded.
      try {
        await NotificationService.sendToUser(
          userId: userDoc.id,
          title: status == 'late' ? 'Marked Late' : "You're Marked Present!",
          body: status == 'late'
              ? 'You checked in late to "${widget.event?.title ?? 'the event'}".'
              : 'You\'ve been marked present for "${widget.event?.title ?? 'the event'}".',
          type: 'event',
          orgId: widget.orgId,
          data: {'eventId': widget.eventDocId, 'status': status},
        );
      } catch (_) {
        // Non-critical — attendance is already recorded, so don't surface this.
      }

      if (mounted) {
        _showMarkedModal(context, data['fullName'] ?? 'Student', status);
      }
    } catch (e) {
      if (mounted) {
        _toast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    }
  }

  Future<void> _onScan(BarcodeCapture cap) async {
    if (!_scanning) return;
    final code = cap.barcodes.firstOrNull?.rawValue;
    if (code == null || code == _lastCode) return;
    _lastCode = code;
    setState(() => _scanning = false);
    if (code.startsWith('UPRISE|GUEST|')) {
      await _markGuestAttendance(code);
    } else {
      await _markAttendance(code);
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted)
      setState(() {
        _scanning = true;
        _lastCode = '';
      });
  }

  // Guest QR payload: 'UPRISE|GUEST|{docId}|{FIRST}|{LAST}|{email}'
  // (see lib/screens/guest/guest_digital_id_screen.dart _qrPayload).
  // Guests have no `users` doc, so they're validated against
  // external_requests instead, and attendance is keyed by email rather
  // than studentId — kept as a distinct field so existing student-only
  // aggregations (roll-call, eligible-recipient lookup, exporters) never
  // see a foreign identity space mixed into `studentId`.
  Future<void> _markGuestAttendance(String payload) async {
    if (widget.eventDocId == null || widget.event == null) return;
    try {
      final parts = payload.split('|');
      if (parts.length != 6 || parts[0] != 'UPRISE' || parts[1] != 'GUEST') {
        throw Exception('Invalid guest QR code');
      }
      final docId = parts[2];
      final email = parts[5].trim().toLowerCase();
      if (email.isEmpty) throw Exception('Invalid guest QR code');

      final evDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventDocId)
          .get();
      if (!_isActive(evDoc))
        throw Exception('Attendance is not open for this event');

      final guestDoc = await FirebaseFirestore.instance
          .collection('external_requests')
          .doc(docId)
          .get();
      if (!guestDoc.exists) throw Exception('Guest record not found');
      final guestData = guestDoc.data() as Map<String, dynamic>;
      if ((guestData['status'] ?? '') != 'approved') {
        throw Exception('Guest is not an approved visitor');
      }
      final name = (guestData['userName'] as String?)?.trim().isNotEmpty == true
          ? guestData['userName'] as String
          : '${parts[3]} ${parts[4]}';

      final attCol = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventDocId)
          .collection('attendances');
      final existing = await attCol.where('guestEmail', isEqualTo: email).get();
      if (existing.docs.any((d) => d.data()['isGuest'] == true)) {
        throw Exception('$name already marked');
      }

      String status = 'present';
      try {
        final startDt = _timeOfDay(widget.event!.date, widget.event!.startTime);
        if (DateTime.now().isAfter(startDt.add(const Duration(minutes: 15))))
          status = 'late';
      } catch (_) {}

      await attCol.add({
        'isGuest': true,
        'guestEmail': email,
        'guestDocId': docId,
        'studentName': name,
        'studentEmail': email,
        'program': 'N/A',
        'yearLevel': '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': status,
        'method': 'qr',
      });

      await activity_log.ActivityLogger.log(
        action: 'mark_attendance',
        module: 'attendance',
        details: {
          'orgId': widget.orgId,
          'eventId': widget.eventDocId,
          'guestEmail': email,
          'status': status,
          'method': 'qr',
        },
      );
      if (mounted) {
        _showMarkedModal(context, name, status);
      }
    } catch (e) {
      if (mounted) {
        _toast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    }
  }

  Future<void> _toggleActive(bool currentlyActive) async {
    if (widget.eventDocId == null) return;
    if (!currentlyActive && !_isEventDay) {
      throw Exception('Attendance can only be opened on the day of the event.');
    }
    await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventDocId)
        .update({
          'isActive': !currentlyActive,
          if (!currentlyActive) 'startedAt': FieldValue.serverTimestamp(),
          if (currentlyActive) 'endedAt': FieldValue.serverTimestamp(),
        });
    if (mounted)
      _toast(
        context,
        currentlyActive
            ? 'Attendance closed'
            : 'Attendance opened — scanning enabled',
      );
  }

  // Notifies every present/late attendee who hasn't evaluated yet — they need
  // to evaluate before a certificate can be generated for them.
  Future<void> _sendEvaluationRequests(
    List<QueryDocumentSnapshot> attDocs,
  ) async {
    if (widget.eventDocId == null || attDocs.isEmpty) return;
    setState(() => _sendingEvaluations = true);
    try {
      final feedbackSnap = await FirebaseFirestore.instance
          .collection('event_feedback')
          .where('eventId', isEqualTo: widget.eventDocId)
          .get();
      final alreadyEvaluated = feedbackSnap.docs
          .map((d) => d.data()['userId']?.toString())
          .whereType<String>()
          .toSet();

      final toNotify = attDocs.where((d) {
        final m = d.data() as Map<String, dynamic>;
        final sid = (m['studentId'] ?? '').toString();
        return sid.isNotEmpty && !alreadyEvaluated.contains(sid);
      }).toList();

      if (toNotify.isEmpty) {
        if (mounted)
          _toast(
            context,
            'Everyone who attended has already evaluated this event.',
          );
        return;
      }

      await Future.wait(
        toNotify.map((d) {
          final m = d.data() as Map<String, dynamic>;
          return NotificationService.sendToUser(
            userId: (m['studentId'] ?? '').toString(),
            title: 'Evaluate "${widget.event?.title ?? 'the event'}"',
            body:
                'You attended this event — share your feedback to receive your certificate.',
            type: 'evaluation',
            orgId: widget.orgId,
            data: {'eventId': widget.eventDocId},
          );
        }),
      );

      await activity_log.ActivityLogger.log(
        action: 'send_evaluation_requests',
        module: 'attendance',
        details: {
          'orgId': widget.orgId,
          'eventId': widget.eventDocId,
          'count': toNotify.length,
        },
      );

      if (mounted)
        _toast(
          context,
          'Evaluation request sent to ${toNotify.length} participant${toNotify.length == 1 ? '' : 's'}.',
        );
    } catch (e) {
      if (mounted)
        _toast(context, 'Failed to send evaluation requests: $e', error: true);
    } finally {
      if (mounted) setState(() => _sendingEvaluations = false);
    }
  }

  List<QueryDocumentSnapshot> _filterAttendanceDocs(
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs.where((d) {
      final m = d.data() as Map<String, dynamic>;
      if (_query.isNotEmpty) {
        final name = (m['studentName'] ?? '').toString().toLowerCase();
        final id = (m['studentId'] ?? '').toString().toLowerCase();
        if (!name.contains(_query) && !id.contains(_query)) return false;
      }
      if (_statusFilter != 'All' && m['status'] != _statusFilter) return false;
      return true;
    }).toList();
  }

  // `registrations` docs only reliably carry `userId` — this fills in
  // name/student number/program/year/registeredAt from the `students`
  // lookup cache (falling back to whatever the registration doc itself has,
  // for the older form-based flows that do write fullName/email directly).
  Map<String, dynamic> _enrichedReg(Map<String, dynamic> m) {
    final uid = (m['userId'] ?? '').toString();
    final student = _studentCache[uid] ?? const {};
    return {
      'uid': uid,
      'studentName':
          student['fullName'] ?? m['studentName'] ?? m['fullName'] ?? '',
      'studentId': student['studentId'] ?? m['studentId'] ?? '',
      'studentEmail': student['email'] ?? m['studentEmail'] ?? m['email'] ?? '',
      'program': student['course'] ?? m['program'] ?? 'N/A',
      'yearLevel': student['yearLevel'] ?? m['yearLevel'] ?? '',
      'registeredAt': m['registeredAt'] ?? m['createdAt'],
    };
  }

  List<QueryDocumentSnapshot> _filterRegistrantDocs(
    List<QueryDocumentSnapshot> regs,
    List<QueryDocumentSnapshot> attDocs,
  ) {
    final attMap = {
      for (final d in attDocs)
        (d.data() as Map)['studentId']?.toString() ?? '':
            (d.data() as Map)['status']?.toString() ?? 'absent',
    };
    return regs.where((d) {
      final reg = _enrichedReg(d.data() as Map<String, dynamic>);
      if (_query.isNotEmpty) {
        final name = (reg['studentName'] ?? '').toString().toLowerCase();
        final id = (reg['studentId'] ?? '').toString().toLowerCase();
        if (!name.contains(_query) && !id.contains(_query)) return false;
      }
      final status = attMap[(reg['uid'] ?? '').toString()] ?? 'absent';
      if (_statusFilter != 'All' && status != _statusFilter) return false;
      return true;
    }).toList();
  }

  Future<void> _exportAttendanceCsv(List<QueryDocumentSnapshot> docs) async {
    final rows = [
      [
        'Student Name',
        'Student ID',
        'Program',
        'Year Level',
        'Time In',
        'Status',
        'Method',
      ],
      ...docs.map((d) {
        final m = d.data() as Map<String, dynamic>;
        final ts = (m['timestamp'] as Timestamp?)?.toDate();
        final uid = m['studentId']?.toString() ?? '';
        final realStudentNo =
            _studentCache[uid]?['studentId']?.toString() ??
            m['studentId'] ??
            '';
        return [
          m['studentName'] ?? '',
          realStudentNo,
          m['program'] ?? '',
          m['yearLevel'] ?? '',
          ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts) : '',
          m['status'] ?? '',
          m['method'] ?? 'qr',
        ];
      }),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    await FileSaver.instance.saveAs(
      name:
          'attendance_${(widget.event?.title ?? 'export').replaceAll(' ', '_')}',
      bytes: Uint8List.fromList(utf8.encode(csv)),
      file: 'csv',
      mimeType: MimeType.csv,
    );
    if (mounted) _toast(context, 'Exported ${docs.length} records');
  }

  Future<void> _exportRegistrantCsv(
    List<QueryDocumentSnapshot> regs,
    List<QueryDocumentSnapshot> attDocs,
  ) async {
    final attMap = {
      for (final d in attDocs)
        (d.data() as Map)['studentId']?.toString() ?? '':
            (d.data() as Map)['status']?.toString() ?? 'absent',
    };
    final rows = [
      [
        'Student Name',
        'Student ID',
        'Program',
        'Year Level',
        'Registered At',
        'Status',
      ],
      ...regs.map((d) {
        final reg = _enrichedReg(d.data() as Map<String, dynamic>);
        final ts = (reg['registeredAt'] as Timestamp?)?.toDate();
        final status = attMap[(reg['uid'] ?? '').toString()] ?? 'absent';
        return [
          reg['studentName'] ?? '',
          reg['studentId'] ?? '',
          reg['program'] ?? '',
          reg['yearLevel'] ?? '',
          ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts) : '',
          status,
        ];
      }),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    await FileSaver.instance.saveAs(
      name:
          'registrants_${(widget.event?.title ?? 'export').replaceAll(' ', '_')}',
      bytes: Uint8List.fromList(utf8.encode(csv)),
      file: 'csv',
      mimeType: MimeType.csv,
    );
    if (mounted) _toast(context, 'Exported ${regs.length} records');
  }

  Future<void> _exportPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required String filePrefix,
  }) async {
    final pdfBytes = await OrgExportPdf.generateTablePdf(
      title: title,
      headers: headers,
      rows: rows,
    );
    await FileSaver.instance.saveAs(
      name: filePrefix,
      bytes: pdfBytes,
      file: 'pdf',
      mimeType: MimeType.pdf,
    );
    if (mounted) _toast(context, 'PDF exported successfully');
  }

  Future<void> _exportAttendancePdf(List<QueryDocumentSnapshot> docs) async {
    final rows = docs.map<List<String>>((d) {
      final m = d.data() as Map<String, dynamic>;
      final ts = (m['timestamp'] as Timestamp?)?.toDate();
      final uid = m['studentId']?.toString() ?? '';
      final realStudentNo =
          _studentCache[uid]?['studentId']?.toString() ?? m['studentId'] ?? '';
      return <String>[
        m['studentName'] ?? '',
        realStudentNo, // <-- use looked-up number
        m['program'] ?? '',
        m['yearLevel'] ?? '',
        ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts) : '',
        m['status'] ?? '',
        m['method'] ?? 'qr',
      ];
    }).toList();
    await _exportPdf(
      title: 'Attendance Report',
      headers: [
        'Student Name',
        'Student ID',
        'Program',
        'Year Level',
        'Time In',
        'Status',
        'Method',
      ],
      rows: rows,
      filePrefix:
          'attendance_${(widget.event?.title ?? 'export').replaceAll(' ', '_')}',
    );
  }

  Future<void> _exportRegistrantPdf(
    List<QueryDocumentSnapshot> regs,
    List<QueryDocumentSnapshot> attDocs,
  ) async {
    final attMap = {
      for (final d in attDocs)
        (d.data() as Map)['studentId']?.toString() ?? '':
            (d.data() as Map)['status']?.toString() ?? 'absent',
    };
    final rows = regs.map<List<String>>((d) {
      final reg = _enrichedReg(d.data() as Map<String, dynamic>);
      final ts = (reg['registeredAt'] as Timestamp?)?.toDate();
      final status = attMap[(reg['uid'] ?? '').toString()] ?? 'absent';
      return <String>[
        reg['studentName'] ?? '',
        reg['studentId'] ?? '',
        reg['program'] ?? '',
        reg['yearLevel'] ?? '',
        ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts) : '',
        status,
      ];
    }).toList();
    await _exportPdf(
      title: 'Registrant Report',
      headers: [
        'Student Name',
        'Student ID',
        'Program',
        'Year Level',
        'Registered At',
        'Status',
      ],
      rows: rows,
      filePrefix:
          'registrants_${(widget.event?.title ?? 'export').replaceAll(' ', '_')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<DocumentSnapshot>(
      stream: _eventStream,
      builder: (ctx, evSnap) {
        final active = _isActive(evSnap.data);
        _attendanceActive = active;
        return StreamBuilder<QuerySnapshot>(
          stream: _attStream,
          builder: (ctx, attSnap) {
            final attDocs = attSnap.data?.docs ?? [];
            // Load student info for all attendance records
            final uids = attDocs
                .map((d) => (d.data() as Map)['studentId']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();
            if (uids.isNotEmpty) {
              _ensureStudentsLoaded(uids);
            }
            final present = attDocs
                .where((d) => (d.data() as Map)['status'] == 'present')
                .length;
            final late = attDocs
                .where((d) => (d.data() as Map)['status'] == 'late')
                .length;

            final horizontalPadding = MediaQuery.of(ctx).size.width < 720
                ? 16.0
                : 28.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _regStream,
                    builder: (ctx, regSnap) {
                      final regCount = regSnap.data?.docs.length;
                      // Registrations load separately from attendances; fall
                      // back to check-ins so the row doesn't show 0/0/0
                      // while the registrants query is still in flight.
                      final total = regCount != null
                          ? (regCount > attDocs.length
                                ? regCount
                                : attDocs.length)
                          : attDocs.length;
                      return _buildStatsRow(total, present, late);
                    },
                  ),
                  const SizedBox(height: 20),
                  if (widget.event != null) ...[
                    _buildEventBanner(active, evSnap.data, attDocs.cast()),
                    const SizedBox(height: 16),
                  ],
                  _buildInputModeRow(active, attSnap.data),
                  const SizedBox(height: 14),
                  if (_inputMode == 0)
                    _buildQRPanel(active, attSnap.data)
                  else if (_inputMode == 1)
                    _buildManualPanel(active)
                  else if (_inputMode == 2)
                    _buildRollCallPanel(attSnap.data)
                  else
                    _buildWebinarPanel(active),
                  const SizedBox(height: 24),
                  _buildSubTabToolbar(attDocs.cast()),
                  const SizedBox(height: 12),
                  if (_subTab == 0)
                    _AttendanceTable(
                      docs: attDocs.cast(),
                      query: _query,
                      statusFilter: _statusFilter,
                      studentCache: _studentCache, // <-- ADD THIS
                    )
                  else
                    _RegistrantsTable(
                      stream: _regStream,
                      attendanceDocs: attDocs.cast(),
                      studentCache: _studentCache,
                      ensureStudentsLoaded: _ensureStudentsLoaded,
                      query: _query,
                      statusFilter: _statusFilter,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatsRow(int total, int present, int late) {
    void selectStatus(String status) => setState(() {
      _statusFilter = _statusFilter == status ? 'All' : status;
      _filterTouched = true;
      _subTab = 0;
    });

    return Row(
      children: [
        _StatCard(
          label: 'Total Registrants',
          value: '$total',
          icon: Icons.people_alt_rounded,
          color: UpriseColors.primaryDark,
          isSelected: _statusFilter == 'All' && _filterTouched,
          onTap: () => setState(() {
            _statusFilter = 'All';
            _filterTouched = true;
            _subTab = 0;
          }),
        ),
        const SizedBox(width: 14),
        _StatCard(
          label: 'Present',
          value: '$present',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF059669),
          isSelected: _statusFilter == 'present',
          onTap: () => selectStatus('present'),
        ),
        const SizedBox(width: 14),
        _StatCard(
          label: 'Late',
          value: '$late',
          icon: Icons.schedule_rounded,
          color: const Color(0xFFFB923C),
          isSelected: _statusFilter == 'late',
          onTap: () => selectStatus('late'),
        ),
        const SizedBox(width: 14),
        _StatCard(
          label: 'Absent',
          value: '${(total - present - late).clamp(0, total)}',
          icon: Icons.cancel_rounded,
          color: const Color(0xFFDC2626),
          isSelected: _statusFilter == 'absent',
          onTap: () => selectStatus('absent'),
        ),
      ],
    );
  }

  Widget _buildEventBanner(
    bool active,
    DocumentSnapshot? evDoc,
    List<QueryDocumentSnapshot> attDocs,
  ) {
    final e = widget.event!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(
          color: active
              ? const Color(0xFF059669).withOpacity(0.35)
              : const Color(0xFFEBEEF3),
        ),
        boxShadow: _DS.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withOpacity(0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.event_rounded,
              size: 22,
              color: UpriseColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatePill(e),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 12,
                      color: const Color(0xFFB0BAC8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      e.location,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule_outlined,
                      size: 12,
                      color: const Color(0xFFB0BAC8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${e.startTime} – ${e.endTime}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: const Color(0xFFB0BAC8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      DateFormat('MMM dd, yyyy').format(e.date),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _PrimaryButton(
                label: active
                    ? 'Close Attendance'
                    : widget.eventDocId == null
                    ? 'Sync Pending'
                    : _isEventDay
                    ? 'Open Attendance'
                    : 'Open on Event Day',
                icon: active
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline_rounded,
                color: active
                    ? const Color(0xFFDC2626)
                    : UpriseColors.primaryDark,
                onPressed: active
                    ? () => _toggleActive(active)
                    : widget.eventDocId == null || !_isEventDay
                    ? null
                    : () => _toggleActive(active),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    (widget.eventDocId == null ||
                        attDocs.isEmpty ||
                        _sendingEvaluations)
                    ? null
                    : () => _sendEvaluationRequests(attDocs),
                icon: _sendingEvaluations
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: UpriseColors.primaryDark,
                        ),
                      )
                    : const Icon(Icons.forward_to_inbox_outlined, size: 14),
                label: Text(
                  'Send Evaluation',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UpriseColors.primaryDark,
                  side: BorderSide(
                    color: UpriseColors.primaryDark.withOpacity(0.4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputModeRow(bool active, QuerySnapshot? attSnap) {
    return Row(
      children: [
        for (final (i, lbl, ico) in [
          (0, 'QR Scan', Icons.qr_code_scanner_rounded),
          (1, 'Manual Entry', Icons.badge_outlined),
          (2, 'Roll Call', Icons.list_alt_rounded),
          (3, 'Webinar Code', Icons.podcasts_rounded),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ModeChip(
              label: lbl,
              icon: ico,
              selected: _inputMode == i,
              onTap: () => _setInputMode(i),
            ),
          ),
      ],
    );
  }

  Widget _buildWebinarPanel(bool active) {
    if (widget.eventDocId == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusLg),
          border: Border.all(color: const Color(0xFFEBEEF3)),
          boxShadow: _DS.cardShadow,
        ),
        child: Center(
          child: Text(
            'Select an event to manage webinar attendance',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }
    return _WebinarCodePanel(
      orgId: widget.orgId,
      eventDocId: widget.eventDocId!,
      event: widget.event,
      attendanceIsOpen: active,
    );
  }

  Widget _buildQRPanel(bool active, QuerySnapshot? attSnap) {
    final recent = (attSnap?.docs ?? []).reversed.take(3).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        final scanSize = isNarrow ? constraints.maxWidth : 300.0;

        final scannerBox = SizedBox(
          width: scanSize,
          height: scanSize,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_DS.radiusLg),
              border: Border.all(
                color: active
                    ? const Color(0xFF059669).withOpacity(0.4)
                    : const Color(0xFFEBEEF3),
              ),
              boxShadow: _DS.cardShadow,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: active
                      ? MobileScanner(controller: _scanner, onDetect: _onScan)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFFFF7ED),
                                const Color(0xFFFFFBEB),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: UpriseColors.primaryDark.withOpacity(
                                      0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 32,
                                    color: UpriseColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Open attendance to enable scanning',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12.5,
                                    color: const Color(0xFF8A6D3B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      gradient: active
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.65),
                              ],
                            )
                          : null,
                      color: active ? null : const Color(0xFFFFF7ED),
                      border: active
                          ? null
                          : const Border(
                              top: BorderSide(color: Color(0xFFFDE9CC)),
                            ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFF059669)
                                : const Color(0xFF9AA5B4),
                            shape: BoxShape.circle,
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF059669,
                                      ).withOpacity(0.5),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          active
                              ? (_scanning ? 'Scanning…' : 'Processing…')
                              : 'Scanner offline',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11.5,
                            color: active
                                ? Colors.white70
                                : const Color(0xFF8A6D3B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (active) ...[
                          const Spacer(),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _scanning = !_scanning),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _scanning ? 'Pause' : 'Resume',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        final recentPanel = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_DS.radiusLg),
            border: Border.all(color: const Color(0xFFEBEEF3)),
            boxShadow: _DS.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF9AA5B4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'RECENT CHECK-INS',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 28,
                          color: const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No check-ins yet',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFFB0BAC8),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: recent.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFF3F4F8)),
                    itemBuilder: (_, i) {
                      final d = recent[i].data() as Map<String, dynamic>;
                      final ts = (d['timestamp'] as Timestamp?)?.toDate();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            _StudentAvatar(
                              name: d['studentName'] ?? '',
                              size: 30,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d['studentName'] ?? '—',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1A202C),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    ts != null
                                        ? DateFormat('hh:mm a').format(ts)
                                        : '—',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: const Color(0xFFB0BAC8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _attBadge(d['status'] ?? 'present'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            children: [
              scannerBox,
              const SizedBox(height: 14),
              SizedBox(height: 220, width: double.infinity, child: recentPanel),
            ],
          );
        }
        return SizedBox(
          height: scanSize,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              scannerBox,
              const SizedBox(width: 14),
              Expanded(child: recentPanel),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManualPanel(bool active) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: const Color(0xFFEBEEF3)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Manual Attendance Entry', icon: Icons.badge_outlined),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualCtrl,
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  decoration: _DS.inputDeco(
                    'Student ID or UID',
                    hint: 'Enter ID and press Enter',
                    icon: Icons.badge_outlined,
                  ),
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty || !active) return;
                    await _markAttendance(v.trim(), isManual: true);
                    _manualCtrl.clear();
                  },
                ),
              ),
              const SizedBox(width: 12),
              _PrimaryButton(
                label: 'Mark Present',
                icon: Icons.check_rounded,
                color: UpriseColors.primaryDark,
                onPressed: !active
                    ? null
                    : () async {
                        final v = _manualCtrl.text.trim();
                        if (v.isEmpty) return;
                        await _markAttendance(v, isManual: true);
                        _manualCtrl.clear();
                      },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoBanner(
            color: const Color(0xFFEFF6FF),
            border: const Color(0xFFBFD7FF),
            icon: Icons.info_outline_rounded,
            iconColor: const Color(0xFF2563EB),
            text:
                'Enter the student\'s ID number or system UID. Attendance opens 15 min before start time. Check-ins after 15 min grace period are marked LATE.',
            textColor: const Color(0xFF1D4ED8),
          ),
        ],
      ),
    );
  }

  Widget _buildRollCallPanel(QuerySnapshot? attSnap) {
    final marked = (attSnap?.docs ?? [])
        .map((d) => (d.data() as Map)['studentId']?.toString() ?? '')
        .toSet();
    return StreamBuilder<QuerySnapshot>(
      stream: widget.eventDocId == null
          ? null
          : FirebaseFirestore.instance
                .collection('registrations')
                .where('eventId', isEqualTo: widget.eventDocId)
                .snapshots(),
      builder: (ctx, snap) {
        final regs = snap.data?.docs ?? [];
        _ensureStudentsLoaded(
          regs.map((r) => ((r.data() as Map)['userId'] ?? '').toString()),
        );
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_DS.radiusLg),
            border: Border.all(color: const Color(0xFFEBEEF3)),
            boxShadow: _DS.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'Roll Call — Registered Participants',
                icon: Icons.list_alt_rounded,
              ),
              if (regs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No registered participants found.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFFB0BAC8),
                    ),
                  ),
                )
              else
                ...regs.map((reg) {
                  final d = reg.data() as Map<String, dynamic>;
                  final uid = (d['userId'] ?? '').toString();
                  final student = _studentCache[uid] ?? const {};
                  final name =
                      (student['fullName'] ??
                              d['studentName'] ??
                              d['fullName'] ??
                              '')
                          .toString();
                  final sid = (student['studentId'] ?? d['studentId'] ?? '')
                      .toString();
                  final isMarked = marked.contains(uid);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF3F4F8)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _StudentAvatar(name: name, size: 36),
                        const SizedBox(width: 12),
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
                              Text(
                                sid,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        isMarked
                            ? _attBadge('present')
                            : _PrimaryButton(
                                label: 'Mark',
                                icon: Icons.check_rounded,
                                color: UpriseColors.primaryDark,
                                onPressed: () =>
                                    _markAttendance(uid, isManual: true),
                                compact: true,
                              ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubTabToolbar(List<QueryDocumentSnapshot> attDocs) {
    return StreamBuilder<QuerySnapshot?>(
      stream: _regStream,
      builder: (ctx, regSnap) {
        final regDocs = regSnap.data?.docs.cast<QueryDocumentSnapshot>() ?? [];
        _ensureStudentsLoaded(
          regDocs.map((r) => ((r.data() as Map)['userId'] ?? '').toString()),
        );
        final filteredAttDocs = _filterAttendanceDocs(attDocs);
        final filteredRegDocs = _filterRegistrantDocs(regDocs, attDocs);
        final canExport = _subTab == 0
            ? filteredAttDocs.isNotEmpty
            : filteredRegDocs.isNotEmpty;

        return Row(
          children: [
            _SubTab(
              'Attendance',
              _subTab == 0,
              () => setState(() => _subTab = 0),
            ),
            const SizedBox(width: 8),
            _SubTab(
              'Registered Participants',
              _subTab == 1,
              () => setState(() => _subTab = 1),
            ),
            const Spacer(),
            SizedBox(
              width: 230,
              height: 40,
              child: TextField(
                controller: _search,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: _DS.searchDeco('Search name or ID…'),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 10),
            _FilterDropdown(
              value: _statusFilter,
              items: const ['All', 'present', 'late', 'absent'],
              hint: 'Status',
              onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
            ),
            const SizedBox(width: 10),
            AdminExportButton(
              enabled: canExport,
              label: 'Export',
              onSelected: (choice) {
                if (_subTab == 0) {
                  if (choice == 'csv') _exportAttendanceCsv(filteredAttDocs);
                  if (choice == 'pdf') _exportAttendancePdf(filteredAttDocs);
                } else {
                  if (choice == 'csv')
                    _exportRegistrantCsv(filteredRegDocs, attDocs);
                  if (choice == 'pdf')
                    _exportRegistrantPdf(filteredRegDocs, attDocs);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _AttendanceTable extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String query, statusFilter;
  final Map<String, Map<String, dynamic>> studentCache; // <-- NEW
  const _AttendanceTable({
    required this.docs,
    required this.query,
    required this.statusFilter,
    required this.studentCache, // <-- NEW
  });

  @override
  Widget build(BuildContext context) {
    final filtered = docs.where((d) {
      final m = d.data() as Map<String, dynamic>;
      if (query.isNotEmpty) {
        final name = (m['studentName'] ?? '').toString().toLowerCase();
        final id = (m['studentId'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !id.contains(query)) return false;
      }
      if (statusFilter != 'All' && m['status'] != statusFilter) return false;
      return true;
    }).toList();

    return _DataTable(
      columns: const [
        _Col('STUDENT', 4),
        _Col('STUDENT ID', 2),
        _Col('PROGRAM', 3),
        _Col('YEAR', 2),
        _Col('TIME IN', 2),
        _Col('METHOD', 2),
        _Col('STATUS', 2),
      ],
      isEmpty: filtered.isEmpty,
      emptyMessage: docs.isEmpty
          ? 'No check-ins yet. Open attendance and start scanning.'
          : 'No records match your filter.',
      footer: '${docs.length} attendee${docs.length == 1 ? '' : 's'} recorded',
      rows: filtered.map((d) {
        final m = d.data() as Map<String, dynamic>;
        final ts = (m['timestamp'] as Timestamp?)?.toDate();
        // ---- START CHANGE ----
        // Get the student number from the cache
        final uid = m['studentId']?.toString() ?? '';
        final studentData = studentCache[uid];
        final studentNumber = studentData != null
            ? (studentData['studentId']?.toString() ?? '—')
            : (m['studentId']?.toString() ?? '—');
        // ---- END CHANGE ----
        return _TableRow(
          cells: [
            _NameCell(m['studentName'] ?? '—', m['studentEmail'] ?? ''),
            _IdText(studentNumber), // <-- USE THE FETCHED NUMBER
            Text(
              m['program'] ?? 'N/A',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              m['yearLevel'] ?? '—',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            Text(
              ts != null ? DateFormat('hh:mm a').format(ts) : '—',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A202C),
              ),
            ),
            _MethodBadge(m['method'] ?? 'qr'),
            _attBadge(m['status'] ?? 'present'),
          ],
          flex: const [4, 2, 3, 2, 2, 2, 2],
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTRANTS TABLE
// ─────────────────────────────────────────────────────────────────────────────
class _RegistrantsTable extends StatelessWidget {
  final Stream<QuerySnapshot>? stream;
  final List<QueryDocumentSnapshot> attendanceDocs;
  final Map<String, Map<String, dynamic>> studentCache;
  final void Function(Iterable<String> uids) ensureStudentsLoaded;
  final String query, statusFilter;
  const _RegistrantsTable({
    required this.stream,
    required this.attendanceDocs,
    required this.studentCache,
    required this.ensureStudentsLoaded,
    required this.query,
    required this.statusFilter,
  });

  @override
  Widget build(BuildContext context) {
    if (stream == null)
      return _EmptyState(
        'Select a synced event to view registered participants.',
      );
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final regs = snap.data?.docs ?? [];
        // `registrations` docs only reliably carry `userId` — name/student
        // number/program live on `students`, looked up by that uid.
        ensureStudentsLoaded(
          regs.map((r) => ((r.data() as Map)['userId'] ?? '').toString()),
        );
        final attMap = {
          for (final d in attendanceDocs)
            (d.data() as Map)['studentId']?.toString() ?? '':
                (d.data() as Map)['status']?.toString() ?? 'present',
        };
        Map<String, dynamic> studentOf(Map<String, dynamic> m) =>
            studentCache[(m['userId'] ?? '').toString()] ?? const {};
        String nameOf(Map<String, dynamic> m) =>
            (studentOf(m)['fullName'] ??
                    m['studentName'] ??
                    m['fullName'] ??
                    '')
                .toString();
        String idOf(Map<String, dynamic> m) =>
            (studentOf(m)['studentId'] ?? m['studentId'] ?? '').toString();

        final filtered = regs.where((d) {
          final m = d.data() as Map<String, dynamic>;
          if (query.isNotEmpty) {
            final name = nameOf(m).toLowerCase();
            final id = idOf(m).toLowerCase();
            if (!name.contains(query) && !id.contains(query)) return false;
          }
          final uid = (m['userId'] ?? '').toString();
          final status = attMap[uid] ?? 'absent';
          if (statusFilter != 'All' && status != statusFilter) return false;
          return true;
        }).toList();

        return _DataTable(
          columns: const [
            _Col('STUDENT', 4),
            _Col('STUDENT ID', 2),
            _Col('PROGRAM', 3),
            _Col('REGISTERED AT', 3),
            _Col('STATUS', 2),
            _Col('', 1),
          ],
          isEmpty: filtered.isEmpty,
          emptyMessage: regs.isEmpty
              ? 'No registered participants yet.'
              : 'No records match your filter.',
          footer:
              '${regs.length} registered participant${regs.length == 1 ? '' : 's'}',
          rows: filtered.map((d) {
            final m = d.data() as Map<String, dynamic>;
            final student = studentOf(m);
            final uid = (m['userId'] ?? '').toString();
            final status = attMap[uid] ?? 'absent';
            final name = nameOf(m);
            final sid = idOf(m);
            final email =
                (student['email'] ?? m['studentEmail'] ?? m['email'] ?? '')
                    .toString();
            final program = (student['course'] ?? m['program'] ?? 'N/A')
                .toString();
            final reg = ((m['registeredAt'] ?? m['createdAt']) as Timestamp?)
                ?.toDate();
            return _TableRow(
              cells: [
                _NameCell(name.isEmpty ? '—' : name, email),
                _IdText(sid),
                Text(
                  program,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  reg != null ? DateFormat('MMM dd, hh:mm a').format(reg) : '—',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
                _attBadge(status),
                OrgActionIconButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View registration answers',
                  color: const Color(0xFF2563EB),
                  onTap: () => _showRegistrationAnswers(
                    context,
                    name.isEmpty ? 'Student' : name,
                    m,
                  ),
                ),
              ],
              flex: const [4, 2, 3, 3, 2, 1],
            );
          }).toList(),
        );
      },
    );
  }
}

// Registration form answers are stored on the registration doc itself —
// either as `formResponses` (self-describing: {label, value} per field, the
// current student registration flow) or the older `formAnswers` (raw field
// id -> value, no labels). Handles either shape so older registrations
// still show something instead of nothing.
void _showRegistrationAnswers(
  BuildContext context,
  String studentName,
  Map<String, dynamic> regData,
) {
  final responses = regData['formResponses'];
  final rawAnswers = regData['formAnswers'];
  final entries = <MapEntry<String, String>>[];

  String displayOf(dynamic value) {
    if (value is List) return value.isEmpty ? '—' : value.join(', ');
    final s = (value ?? '').toString();
    return s.isEmpty ? '—' : s;
  }

  if (responses is Map && responses.isNotEmpty) {
    for (final v in responses.values) {
      if (v is Map) {
        final label = (v['label'] ?? '').toString();
        entries.add(
          MapEntry(label.isEmpty ? 'Question' : label, displayOf(v['value'])),
        );
      }
    }
  } else if (rawAnswers is Map && rawAnswers.isNotEmpty) {
    rawAnswers.forEach(
      (k, v) => entries.add(MapEntry(k.toString(), displayOf(v))),
    );
  }

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Registration Answers',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(ctx),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  studentName,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  Text(
                    'No additional info was collected for this registration.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                  )
                else
                  ...entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF9AA5B4),
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (e.value.startsWith('http://') ||
                              e.value.startsWith('https://'))
                            InkWell(
                              onTap: () async {
                                final uri = Uri.tryParse(e.value);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.attach_file_rounded,
                                    size: 14,
                                    color: UpriseColors.info,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'View uploaded photo/video',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: UpriseColors.info,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              e.value,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13.5,
                                color: const Color(0xFF1A202C),
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
      ),
    ),
  );
}

// =============================================================================
// GENERIC DATA TABLE WRAPPER
// =============================================================================
class _Col {
  final String label;
  final int flex;
  final bool rightAlign;
  const _Col(this.label, this.flex, {this.rightAlign = false});
}

class _DataTable extends StatelessWidget {
  final List<_Col> columns;
  final List<_TableRow> rows;
  final bool isEmpty;
  final String emptyMessage;
  final String? footer;
  final Widget? customFooter;

  const _DataTable({
    required this.columns,
    required this.rows,
    required this.isEmpty,
    required this.emptyMessage,
    required this.footer,
    this.customFooter,
  });

  @override
  Widget build(BuildContext context) {
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              border: Border(
                bottom: BorderSide(
                  color: UpriseColors.primaryDark.withAlpha(60),
                ),
              ),
            ),
            child: Row(
              children: [
                for (final col in columns)
                  Expanded(
                    flex: col.flex,
                    child: col.rightAlign
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: _headerCell(col.label),
                          )
                        : _headerCell(col.label),
                  ),
              ],
            ),
          ),
          // Rows or empty state
          if (isEmpty) _EmptyState(emptyMessage) else ...rows,
          // Footer
          customFooter ??
              (footer != null
                  ? _TableFooter(footer!)
                  : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED REUSABLE WIDGETS
// =============================================================================

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
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFEBEEF3),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withAlpha(46),
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
                      color: color.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StudentAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _StudentAvatar({required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final init = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UpriseColors.primaryDark.withOpacity(0.09),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Center(
        child: Text(
          init,
          style: GoogleFonts.beVietnamPro(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            color: UpriseColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final String name, email;
  const _NameCell(this.name, this.email);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      _StudentAvatar(name: name),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A202C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              email,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                color: const Color(0xFFB0BAC8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ],
  );
}

class _IdText extends StatelessWidget {
  final String id;
  const _IdText(this.id);
  @override
  Widget build(BuildContext context) => Text(
    id,
    style: GoogleFonts.beVietnamPro(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: UpriseColors.primaryDark,
      letterSpacing: 0.2,
    ),
  );
}

class _MethodBadge extends StatelessWidget {
  final String method;
  const _MethodBadge(this.method);
  @override
  Widget build(BuildContext context) {
    final isManual = method == 'manual';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: isManual ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF),
        border: Border.all(
          color: isManual ? const Color(0xFFFDE68A) : const Color(0xFFBFD7FF),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isManual ? 'Manual' : 'QR Scan',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isManual ? const Color(0xFFFB923C) : const Color(0xFF2563EB),
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final List<Widget> cells;
  final List<int> flex;
  final VoidCallback? onTap;
  const _TableRow({required this.cells, required this.flex, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    hoverColor: const Color(0xFFF8F9FB),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(flex: flex[i], child: cells[i]),
        ],
      ),
    ),
  );
}

class _TableFooter extends StatelessWidget {
  final String text;
  const _TableFooter(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
      color: Color(0xFFF8F9FB),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
    ),
    child: Text(
      text,
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        color: const Color(0xFF94A3B8),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.inbox_rounded,
              size: 34,
              color: Color(0xFFCDD5DF),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  final Color color, border, iconColor, textColor;
  final IconData icon;
  final String text;
  const _InfoBanner({
    required this.color,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textColor,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      border: Border.all(color: border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: textColor,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SubTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubTab(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? UpriseColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusSm),
          border: Border.all(
            color: selected
                ? UpriseColors.primaryDark
                : const Color(0xFFE4E8EF),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: UpriseColors.primaryDark.withOpacity(0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: icon != null ? 12 : 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? UpriseColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusSm),
          border: Border.all(
            color: selected
                ? UpriseColors.primaryDark
                : const Color(0xFFE4E8EF),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: UpriseColors.primaryDark.withOpacity(0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : UpriseColors.darkGray,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : UpriseColors.darkGray,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
  });
  static String _displayLabel(String s) =>
      s == 'All' ? 'All Status' : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) => AnchoredMenuTrigger<String>(
    items: items,
    labelOf: _displayLabel,
    selectedValue: value,
    onSelected: onChanged,
    trigger: Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _displayLabel(value),
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFFB0BAC8),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIFIED BUTTON COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool loading;
  final bool compact;
  const _PrimaryButton({
    required this.label,
    this.icon,
    required this.color,
    this.onPressed,
    this.loading = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: color.withOpacity(0.45),
      disabledForegroundColor: Colors.white.withOpacity(0.7),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
      ),
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
        else if (icon != null) ...[
          Icon(icon, size: compact ? 14 : 15),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WEBINAR ATTENDANCE PANEL — rotating check-in/check-out codes for online
// events. The rotation timer only runs while this widget is mounted (i.e.
// while an organizer has this tab open); on (re)mount it resumes from
// whatever the session doc already says instead of assuming a fresh start,
// so refreshing the page or reopening the tab doesn't reset/duplicate it.
// ─────────────────────────────────────────────────────────────────────────────
class _WebinarCodePanel extends StatefulWidget {
  final String orgId;
  final String eventDocId;
  final EventModel? event;
  final bool attendanceIsOpen;
  const _WebinarCodePanel({
    required this.orgId,
    required this.eventDocId,
    this.event,
    required this.attendanceIsOpen,
  });

  @override
  State<_WebinarCodePanel> createState() => _WebinarCodePanelState();
}

class _WebinarCodePanelState extends State<_WebinarCodePanel> {
  Timer? _rotationTimer;
  int _intervalMinutes = 5;
  bool _requireCheckOut = false;
  bool _busy = false;

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  void _scheduleRotation(String type, int intervalMinutes) {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      WebinarAttendanceService.rotateCode(
        widget.eventDocId,
        type,
        intervalMinutes,
      );
    });
  }

  // Idempotent — called on every build while a session is active, but only
  // actually schedules something the first time (guarded by _rotationTimer).
  void _ensureRotationRunning(
    Map<String, dynamic> session,
    Map<String, dynamic>? currentCode,
  ) {
    if (_rotationTimer != null || session['isActive'] != true) return;
    final phase = session['phase'] as String? ?? 'checkin';
    final intervalMinutes = (session['intervalMinutes'] as num?)?.toInt() ?? 5;

    if (currentCode == null) {
      WebinarAttendanceService.rotateCode(
        widget.eventDocId,
        phase,
        intervalMinutes,
      );
      _scheduleRotation(phase, intervalMinutes);
      return;
    }
    final expiresAt = (currentCode['expiresAt'] as Timestamp).toDate();
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      WebinarAttendanceService.rotateCode(
        widget.eventDocId,
        phase,
        intervalMinutes,
      );
      _scheduleRotation(phase, intervalMinutes);
    } else {
      _rotationTimer = Timer(remaining, () {
        WebinarAttendanceService.rotateCode(
          widget.eventDocId,
          phase,
          intervalMinutes,
        );
        _scheduleRotation(phase, intervalMinutes);
      });
    }
  }

  Future<void> _start() async {
    // Gating on the same "Open Attendance" toggle the other tabs use —
    // the org opens attendance once from the event banner, and every
    // input mode (QR, manual, roll call, webinar) becomes available at once.
    if (!widget.attendanceIsOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open attendance from the event banner above first.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await WebinarAttendanceService.startSession(
        eventDocId: widget.eventDocId,
        startedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        intervalMinutes: _intervalMinutes,
        requireCheckOut: _requireCheckOut,
      );
      await activity_log.ActivityLogger.log(
        action: 'start_webinar_attendance',
        module: 'attendance',
        details: {
          'orgId': widget.orgId,
          'eventId': widget.eventDocId,
          'intervalMinutes': _intervalMinutes,
        },
      );
    } catch (e) {
      if (mounted)
        _toast(context, 'Failed to start attendance: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startCheckOut(int intervalMinutes) async {
    if (!widget.attendanceIsOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open attendance from the event banner above first.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      _rotationTimer?.cancel();
      _rotationTimer = null;
      await WebinarAttendanceService.startCheckOutPhase(
        widget.eventDocId,
        intervalMinutes,
      );
    } catch (e) {
      if (mounted)
        _toast(context, 'Failed to start check-out: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    setState(() => _busy = true);
    try {
      _rotationTimer?.cancel();
      _rotationTimer = null;
      await WebinarAttendanceService.endSession(widget.eventDocId);
      await activity_log.ActivityLogger.log(
        action: 'end_webinar_attendance',
        module: 'attendance',
        details: {'orgId': widget.orgId, 'eventId': widget.eventDocId},
      );
    } catch (e) {
      if (mounted) _toast(context, 'Failed to end session: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_DS.radiusLg),
        border: Border.all(color: const Color(0xFFEBEEF3)),
        boxShadow: _DS.cardShadow,
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: WebinarAttendanceService.sessionStream(widget.eventDocId),
        builder: (context, sessionSnap) {
          final session = sessionSnap.data?.data();
          final isActive = session != null && session['isActive'] == true;

          if (!isActive) {
            return _buildStartForm();
          }

          final phase = session['phase'] as String? ?? 'checkin';
          final intervalMinutes =
              (session['intervalMinutes'] as num?)?.toInt() ?? 5;
          final requireCheckOut = session['requireCheckOut'] == true;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: WebinarAttendanceService.codeStream(
              widget.eventDocId,
              phase,
            ),
            builder: (context, codeSnap) {
              final currentCode = codeSnap.data?.data();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ensureRotationRunning(session, currentCode);
              });
              return _buildActiveSession(
                phase,
                intervalMinutes,
                requireCheckOut,
                currentCode,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStartForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: UpriseColors.primaryDark.withAlpha(23),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.podcasts_rounded,
                size: 22,
                color: UpriseColors.primaryDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Webinar Attendance',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Students self-check-in by entering a rotating code shown on this screen.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Code rotates every',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      border: Border.all(color: const Color(0xFFE4E8EF)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _intervalMinutes,
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        items: const [1, 2, 5, 10, 15]
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  'Every $m minute${m == 1 ? '' : 's'}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _intervalMinutes = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Check-out code',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      border: Border.all(color: const Color(0xFFE4E8EF)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Require check-out at the end',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12.5,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        Switch(
                          value: _requireCheckOut,
                          activeThumbColor: UpriseColors.primaryDark,
                          onChanged: (v) =>
                              setState(() => _requireCheckOut = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!widget.attendanceIsOpen)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _InfoBanner(
              color: const Color(0xFFFFFBEB),
              border: const Color(0xFFFDE68A),
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFFFB923C),
              text:
                  'Open attendance from the event banner above to enable this.',
              textColor: const Color(0xFF8A6D3B),
            ),
          ),
        _PrimaryButton(
          label: 'Start Check-In Session',
          icon: Icons.play_circle_outline_rounded,
          color: UpriseColors.primaryDark,
          loading: _busy,
          onPressed: (_busy || !widget.attendanceIsOpen) ? null : _start,
        ),
      ],
    );
  }

  Widget _buildActiveSession(
    String phase,
    int intervalMinutes,
    bool requireCheckOut,
    Map<String, dynamic>? currentCode,
  ) {
    final isCheckOut = phase == 'checkout';
    final code = currentCode?['code'] as String? ?? '——————';
    final expiresAt = currentCode != null
        ? (currentCode['expiresAt'] as Timestamp).toDate()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withAlpha(128),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isCheckOut ? 'CHECK-OUT IN PROGRESS' : 'CHECK-IN IN PROGRESS',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF059669),
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _busy ? null : _end,
              icon: const Icon(Icons.stop_circle_outlined, size: 14),
              label: Text(
                'End Session',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFECACA)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              Text(
                isCheckOut ? 'Check-out code' : 'Check-in code',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      UpriseColors.primaryDark,
                      UpriseColors.primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                ),
                child: Text(
                  code,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (expiresAt != null)
                _CodeCountdown(
                  expiresAt: expiresAt,
                  intervalMinutes: intervalMinutes,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!isCheckOut && requireCheckOut) ...[
          _PrimaryButton(
            label: 'End Check-In, Start Check-Out',
            icon: Icons.logout_rounded,
            color: const Color(0xFF2563EB),
            loading: _busy,
            onPressed: _busy ? null : () => _startCheckOut(intervalMinutes),
          ),
          const SizedBox(height: 16),
        ],
        _sectionLabel('Recent Code Submissions', icon: Icons.history_rounded),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: WebinarAttendanceService.submissionsStream(widget.eventDocId),
          builder: (context, subSnap) {
            final docs = subSnap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                'No submissions yet.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                ),
              );
            }
            return Column(
              children: docs.take(10).map((d) {
                final m = d.data();
                final result = (m['result'] as String?) ?? 'error';
                final isSuccess = result == 'success';
                final ts = (m['timestamp'] as Timestamp?)?.toDate();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        isSuccess
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 15,
                        color: isSuccess
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (m['studentName'] as String?) ?? 'Unknown',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            color: const Color(0xFF1A202C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${m['type'] ?? ''} · ${_submissionResultLabel(result)}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          color: isSuccess
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        ts != null ? DateFormat('h:mm a').format(ts) : '—',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  String _submissionResultLabel(String result) {
    switch (result) {
      case 'success':
        return 'Success';
      case 'invalid_code':
        return 'Wrong code';
      case 'expired':
        return 'Code expired';
      case 'session_inactive':
        return 'Session closed';
      case 'no_active_code':
        return 'No active code';
      case 'duplicate':
        return 'Already submitted';
      case 'not_checked_in':
        return 'Not checked in';
      case 'not_registered':
        return 'Not registered';
      default:
        return 'Error';
    }
  }
}

// Live "expires in Xs" countdown for the currently displayed code.
class _CodeCountdown extends StatefulWidget {
  final DateTime expiresAt;
  final int intervalMinutes;
  const _CodeCountdown({
    required this.expiresAt,
    required this.intervalMinutes,
  });

  @override
  State<_CodeCountdown> createState() => _CodeCountdownState();
}

class _CodeCountdownState extends State<_CodeCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    final secs = remaining.isNegative ? 0 : remaining.inSeconds;
    return Text(
      'New code in ${secs}s',
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        color: const Color(0xFF94A3B8),
      ),
    );
  }
}
