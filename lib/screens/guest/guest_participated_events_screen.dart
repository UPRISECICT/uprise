// lib/screens/guest/guest_participated_events_screen.dart
//
// GUEST PARTICIPATED EVENTS — Only meaningful for authenticated guests.
//
// Reads real check-ins written by the org's QR scanner into
// events/{id}/attendances (see org_attendance_qr.dart _markGuestAttendance),
// keyed by guestEmail — this is the guest's attendance history.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'guest_auth_service.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

const _kOrange = AppColors.primaryDark;
const _kSuccess = AppColors.success;
const _kSuccessBg = AppColors.successBg;
const _kBg = AppColors.background;

class _ParticipatedEvent {
  final String eventId;
  final String title;
  final String orgName;
  final DateTime date;
  final String attendanceStatus; // present | late
  _ParticipatedEvent({
    required this.eventId,
    required this.title,
    required this.orgName,
    required this.date,
    required this.attendanceStatus,
  });
}

class GuestParticipatedEventsScreen extends StatefulWidget {
  const GuestParticipatedEventsScreen({super.key});

  @override
  State<GuestParticipatedEventsScreen> createState() => _GuestParticipatedEventsScreenState();
}

class _GuestParticipatedEventsScreenState extends State<GuestParticipatedEventsScreen> {
  bool _loading = true;
  String? _error;
  final List<_ParticipatedEvent> _events = [];

  String get _email => (GuestAuthService().email ?? '').toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_email.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }
    try {
      final attSnap = await FirebaseFirestore.instance
          .collectionGroup('attendances')
          .where('guestEmail', isEqualTo: _email)
          .get();

      final list = <_ParticipatedEvent>[];
      for (final doc in attSnap.docs) {
        final eventRef = doc.reference.parent.parent;
        if (eventRef == null) continue;
        final eventDoc = await eventRef.get();
        if (!eventDoc.exists) continue;
        final ed = eventDoc.data() as Map<String, dynamic>;
        list.add(_ParticipatedEvent(
          eventId: eventRef.id,
          title: ed['title'] as String? ?? 'Untitled',
          orgName: ed['orgName'] as String? ?? '',
          date: ed['date'] is Timestamp ? (ed['date'] as Timestamp).toDate() : DateTime.now(),
          attendanceStatus: (doc.data()['status'] as String?) ?? 'present',
        ));
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      if (mounted) setState(() { _events..clear()..addAll(list); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Participated Events'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)))
              : _events.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.event_available_outlined, size: 48, color: Color(0xFFD1D5DB)),
                          const SizedBox(height: 14),
                          Text('No attendance history yet', style: GoogleFonts.beVietnamPro(
                              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                          const SizedBox(height: 6),
                          Text('Events you check into with your Digital ID QR will show up here.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey)),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _kOrange,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        itemBuilder: (_, i) {
                          final e = _events[i];
                          final isLate = e.attendanceStatus == 'late';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFF0F0F0)),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(children: [
                                Container(
                                  width: 48, height: 54,
                                  decoration: BoxDecoration(
                                      color: _kSuccessBg, borderRadius: BorderRadius.circular(10)),
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Text(DateFormat('MMM').format(e.date).toUpperCase(),
                                        style: GoogleFonts.beVietnamPro(fontSize: 9, fontWeight: FontWeight.w700, color: _kSuccess)),
                                    Text(DateFormat('dd').format(e.date),
                                        style: GoogleFonts.beVietnamPro(fontSize: 22, fontWeight: FontWeight.w900, color: _kSuccess)),
                                  ]),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 3),
                                    Text(e.orgName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey)),
                                  ]),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isLate ? const Color(0xFFFFFBEB) : _kSuccessBg,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(isLate ? 'Late' : 'Present',
                                      style: GoogleFonts.beVietnamPro(
                                          fontSize: 10, fontWeight: FontWeight.w700,
                                          color: isLate ? const Color(0xFFD97706) : _kSuccess)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
