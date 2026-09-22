// lib/screens/guest/guest_feedback_screen.dart
//
// GUEST FEEDBACK SCREEN — Only visible to authenticated guests.
//
// Shows all events the guest attended (via the `registrations` + `attendance`
// collections) and allows submitting feedback for each.
//
// Firestore reads:
//   - registrations   where email == guestEmail && isGuest == true
//   - attendance      where email == guestEmail
//   - feedback        where guestEmail == guestEmail  (to detect already-submitted)
//
// Firestore writes:
//   - feedback        (on submit)
//
// UI states per event:
//   • not_attended   → grey, "Not Attended"
//   • pending        → orange "Leave Feedback" button
//   • submitted      → green "Feedback Submitted" badge
//

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'guest_auth_service.dart';
import '../../services/certificate_auto_issue_service.dart';
import '../../utils/feedback_helper.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/review_identity.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

// ─────────────────────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────────────────────
const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;
const _kSuccess = AppColors.success;
const _kSuccessBg = AppColors.successBg;
const _kGrey        = Color(0xFF9CA3AF);

// ─────────────────────────────────────────────────────────────
//  MODEL
// ─────────────────────────────────────────────────────────────
class _AttendedEvent {
  final String   eventId;
  final String   title;
  final String   orgName;
  final String   location;
  final DateTime date;
  bool   attended     = false;
  bool   feedbackDone = false;
  String feedbackId   = '';

  /// The submitted review itself, for the My Reviews tab. Null until rated.
  Map<String, dynamic>? review;

  _AttendedEvent({
    required this.eventId,
    required this.title,
    required this.orgName,
    required this.location,
    required this.date,
  });
}

// ─────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────
class GuestFeedbackScreen extends StatefulWidget {
  const GuestFeedbackScreen({super.key});

  @override
  State<GuestFeedbackScreen> createState() => _GuestFeedbackScreenState();
}

class _GuestFeedbackScreenState extends State<GuestFeedbackScreen>
    with SingleTickerProviderStateMixin {
  final List<_AttendedEvent> _events = [];
  bool _loading = true;
  String? _error;

  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  // Lowercased to match the write side: org_attendance_qr.dart lowercases
  // guestEmail on every attendance write, and every other guest screen that
  // queries by email (guest_participated_events_screen.dart, guest_events_
  // screen.dart's registered-ids stream) already does the same on read.
  String get _email => (GuestAuthService().email ?? '').toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_email.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }

    try {
      // 1. Get all events this guest registered for
      final regSnap = await FirebaseFirestore.instance
          .collection('registrations')
          .where('email', isEqualTo: _email)
          .where('isGuest', isEqualTo: true)
          .get();

      final eventIds = regSnap.docs
          .map((d) => (d.data())['eventId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (eventIds.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 2. Fetch event details
      final eventDocs = await Future.wait(eventIds.map((id) =>
          FirebaseFirestore.instance.collection('events').doc(id).get()));

      // 3. Check attendance records — real check-ins are written by the org's
      // QR scanner into events/{id}/attendances (see org_attendance_qr.dart
      // _markGuestAttendance), keyed by guestEmail.
      //
      // Isolated in its own try/catch: this is the only query on this screen
      // that needs a custom collection-group index, so its failure must not
      // take the rest of the screen down with it. Steps 1, 2 and 4 don't
      // depend on the result — attendance only decides whether a card can be
      // tapped to leave a review — so falling through with nothing attended
      // still renders the guest's events and past reviews.
      var attendedIds = <String>{};
      try {
        final attendSnap = await FirebaseFirestore.instance
            .collectionGroup('attendances')
            .where('guestEmail', isEqualTo: _email)
            .get();
        attendedIds = attendSnap.docs
            .map((d) => d.reference.parent.parent?.id ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      } catch (_) {
        // Leaves every event un-attended: cards stay untappable rather than
        // the whole screen collapsing into an error state.
      }

      // 4. Existing feedback, from BOTH collections — this form dual-writes,
      // and reading only `feedback` would miss a review submitted through any
      // other path. The review body (not just its id) is kept so the My
      // Reviews tab can render the rating and comment without a second read.
      final feedbackSnaps = await Future.wait([
        FirebaseFirestore.instance
            .collection('feedback')
            .where('guestEmail', isEqualTo: _email)
            .get(),
        FirebaseFirestore.instance
            .collection('event_feedback')
            .where('guestEmail', isEqualTo: _email)
            .get(),
      ]);
      final feedbackMap = <String, String>{};
      final reviewMap = <String, Map<String, dynamic>>{};
      for (final snap in feedbackSnaps) {
        for (final d in snap.docs) {
          final eventId = (d.data())['eventId'] as String? ?? '';
          if (eventId.isEmpty) continue;
          feedbackMap[eventId] = d.id;
          reviewMap[eventId] = Map<String, dynamic>.from(d.data());
        }
      }

      final list = <_AttendedEvent>[];
      for (final doc in eventDocs) {
        if (!doc.exists) continue;
        final d    = doc.data() as Map<String, dynamic>;
        final ev   = _AttendedEvent(
          eventId : doc.id,
          title   : d['title']    as String? ?? 'Untitled',
          orgName : d['orgName']  as String? ?? '',
          location: d['location'] as String? ?? 'TBA',
          date    : d['date'] is Timestamp
              ? (d['date'] as Timestamp).toDate()
              : DateTime.now(),
        );
        ev.attended     = attendedIds.contains(doc.id);
        ev.feedbackDone = feedbackMap.containsKey(doc.id);
        ev.feedbackId   = feedbackMap[doc.id] ?? '';
        ev.review       = reviewMap[doc.id];
        list.add(ev);
      }

      list.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) setState(() { _events
        ..clear()
        ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openFeedbackForm(_AttendedEvent ev) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedbackFormSheet(
        event:    ev,
        email:    _email,
        // Reload rather than just flipping the flag: the event moves to the
        // My Reviews tab, which needs the review body the reload fetches.
        onSubmit: () {
          setState(() => ev.feedbackDone = true);
          _load();
        },
      ),
    );
  }

  /// Not yet reviewed. Events the guest registered for but never attended stay
  /// here too — the card renders them as "Not Attended" and isn't tappable.
  List<_AttendedEvent> get _toRate =>
      _events.where((e) => !e.feedbackDone).toList();

  List<_AttendedEvent> get _reviewed =>
      _events.where((e) => e.feedbackDone).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'My Reviews'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kOrange))
          : _error != null
              ? ErrorStateView(
                  title: 'Could not load feedback',
                  detail: _error,
                  onRetry: _load,
                )
              : _events.isEmpty
                  ? _EmptyView()
                  : Column(
                      children: [
                        _statsHeader(),
                        Container(
                          color: Colors.white,
                          child: TabBar(
                            controller: _tabController,
                            labelColor: _kOrange,
                            unselectedLabelColor: Colors.grey.shade600,
                            indicatorColor: _kOrange,
                            indicatorWeight: 2.5,
                            labelStyle: GoogleFonts.beVietnamPro(
                                fontSize: 14, fontWeight: FontWeight.w700),
                            unselectedLabelStyle: GoogleFonts.beVietnamPro(
                                fontSize: 14, fontWeight: FontWeight.w500),
                            tabs: [
                              Tab(text: 'To Rate (${_toRate.length})'),
                              Tab(text: 'My Reviews (${_reviewed.length})'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [_toRateTab(), _myReviewsTab()],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _statsHeader() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Row(
      children: [
        _stat('${_events.length}', 'Registered'),
        _statDivider(),
        _stat('${_reviewed.length}', 'Reviewed'),
        _statDivider(),
        _stat('${_toRate.length}', 'To Rate'),
      ],
    ),
  );

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(value,
            style: GoogleFonts.beVietnamPro(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.beVietnamPro(
                fontSize: 11.5, color: Colors.grey.shade600)),
      ],
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFFE8ECF0));

  Widget _toRateTab() {
    if (_toRate.isEmpty) {
      return _tabEmpty(
        Icons.check_circle_outline_rounded,
        'Nothing left to rate',
        'You\'ve reviewed every event you attended. Thank you!',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _InfoBanner(),
          const SizedBox(height: 16),
          ..._toRate.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FeedbackEventCard(
                  event: e,
                  onTap: e.attended && !e.feedbackDone
                      ? () => _openFeedbackForm(e)
                      : null,
                ),
              )),
        ],
      ),
    );
  }

  Widget _myReviewsTab() {
    if (_reviewed.isEmpty) {
      return _tabEmpty(
        Icons.rate_review_outlined,
        'No reviews yet',
        'Ratings and comments you submit will be kept here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: _reviewed
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SubmittedReviewCard(event: e),
                ))
            .toList(),
      ),
    );
  }

  Widget _tabEmpty(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 13, color: Colors.grey.shade500, height: 1.5)),
        ],
      ),
    ),
  );
}

/// One submitted review in the guest's My Reviews tab. Mirrors the student
/// screen's card: identity line, stars, comment, then the event it belongs to.
class _SubmittedReviewCard extends StatelessWidget {
  final _AttendedEvent event;
  const _SubmittedReviewCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final review = event.review ?? const <String, dynamic>{};
    // Guest reviews store the headline score under `overallRating` in the
    // legacy collection and `rating` in event_feedback.
    final rating = ((review['rating'] ?? review['overallRating']) as num?)
            ?.toInt() ??
        0;
    final comment = (review['comment'] ?? '').toString().trim();
    final submitted = FeedbackHelper.submittedAt(review);
    final anonymous = reviewIsAnonymous(review);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFFF0F2F5),
                child: Icon(
                  anonymous
                      ? Icons.visibility_off_outlined
                      : Icons.person_outline_rounded,
                  size: 15,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // Own history — shown unmasked; the masking is for other
                  // people's eyes.
                  reviewerDisplayName(review, isOwnReview: true),
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                ),
              ),
              if (submitted != null)
                Text(
                  DateFormat('dd-MM-yyyy HH:mm').format(submitted),
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(Icons.star_rounded,
                    size: 18,
                    color: i <= rating
                        ? const Color(0xFFF59E0B)
                        : Colors.grey.shade300),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment,
                style: GoogleFonts.beVietnamPro(
                    fontSize: 13, height: 1.5, color: Colors.black87)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_rounded, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),
                    if (event.orgName.isNotEmpty)
                      Text(event.orgName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  INFO BANNER
// ─────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kOrangeLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange.withAlpha(64)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: _kOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You can only leave feedback for events you attended. Events you registered for but did not attend are shown in grey.',
              style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF7A3300),
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EVENT FEEDBACK CARD
// ─────────────────────────────────────────────────────────────
class _FeedbackEventCard extends StatelessWidget {
  final _AttendedEvent event;
  final VoidCallback?  onTap;

  const _FeedbackEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final canFeedback = event.attended && !event.feedbackDone;
    final isDone      = event.feedbackDone;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date badge
                Container(
                  width: 48, height: 54,
                  decoration: BoxDecoration(
                    color: event.attended
                        ? _kOrangeLight
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM').format(event.date).toUpperCase(),
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: event.attended ? _kOrange : _kGrey,
                            letterSpacing: 0.5),
                      ),
                      Text(
                        DateFormat('dd').format(event.date),
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: event.attended ? _kOrange : _kGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.business_outlined,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(event.orgName,
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 11, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(event.location,
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 11, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Status chip
                      if (!event.attended)
                        _StatusChip(
                          label: 'Not Attended',
                          color: _kGrey,
                          icon: Icons.event_busy_outlined,
                        )
                      else if (isDone)
                        _StatusChip(
                          label: 'Feedback Submitted',
                          color: _kSuccess,
                          icon: Icons.check_circle_outline_rounded,
                        )
                      else
                        _StatusChip(
                          label: 'Pending Feedback',
                          color: _kOrange,
                          icon: Icons.hourglass_top_rounded,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action row
          if (canFeedback)
            _ActionBar(onTap: onTap!),
          if (isDone)
            _SubmittedBar(),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData icon;
  const _StatusChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(64)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onTap;
  const _ActionBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          color: _kOrange,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rate_review_outlined,
                color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Leave Feedback',
                style: GoogleFonts.beVietnamPro(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SubmittedBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: _kSuccessBg,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: _kSuccess, size: 16),
          const SizedBox(width: 8),
          Text('Feedback Submitted — Thank you!',
              style: GoogleFonts.beVietnamPro(
                  color: _kSuccess,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  FEEDBACK FORM SHEET
// ─────────────────────────────────────────────────────────────
class _FeedbackFormSheet extends StatefulWidget {
  final _AttendedEvent event;
  final String         email;
  final VoidCallback   onSubmit;

  const _FeedbackFormSheet({
    required this.event,
    required this.email,
    required this.onSubmit,
  });

  @override
  State<_FeedbackFormSheet> createState() => _FeedbackFormSheetState();
}

class _FeedbackFormSheetState extends State<_FeedbackFormSheet> {
  int    _rating       = 0;
  final  _commentCtrl  = TextEditingController();
  bool   _isLoading    = false;
  bool   _submitted    = false;
  // Defaults off, matching the student forms — a guest who wants privacy opts
  // in, the same way a student does.
  bool   _isAnonymous  = false;

  static const _questions = [
    'How would you rate the overall event?',
    'How was the venue and facilities?',
    'How relevant was the content to you?',
    'How would you rate the organizers?',
  ];
  final _questionRatings = <int>[0, 0, 0, 0];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select an overall rating.',
              style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Duplicate guard
      final dup = await FirebaseFirestore.instance
          .collection('feedback')
          .where('guestEmail', isEqualTo: widget.email)
          .where('eventId', isEqualTo: widget.event.eventId)
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        widget.onSubmit();
        if (mounted) Navigator.pop(context);
        return;
      }

      // authorName only when the guest opted in to attribution — an anonymous
      // review stores no name at all, so there is nothing for a display bug to
      // leak later.
      final authorName = _isAnonymous
          ? ''
          : (GuestAuthService().fullName ?? '').trim();

      await FirebaseFirestore.instance.collection('feedback').add({
        'guestEmail'      : widget.email,
        'eventId'         : widget.event.eventId,
        'eventTitle'      : widget.event.title,
        'overallRating'   : _rating,
        'questionRatings' : _questionRatings,
        'comment'         : _commentCtrl.text.trim(),
        'isAnonymous'     : _isAnonymous,
        if (authorName.isNotEmpty) 'authorName': authorName,
        'submittedAt'     : FieldValue.serverTimestamp(),
        'type'            : 'guest',
      });

      // Mirror into event_feedback (the collection org_certificates.dart
      // reads for eligibility) so this guest counts as "evaluated" when
      // the org generates & distributes certificates for this event.
      await FirebaseFirestore.instance.collection('event_feedback').add({
        'eventId'     : widget.event.eventId,
        'eventTitle'  : widget.event.title,
        // eventName as well: it's the field event_feedback uses everywhere
        // else, and the reviews history reads it.
        'eventName'   : widget.event.title,
        'guestEmail'  : widget.email,
        'isGuest'     : true,
        'rating'      : _rating,
        'questionRatings': _questionRatings,
        'comment'     : _commentCtrl.text.trim(),
        'isAnonymous' : _isAnonymous,
        if (authorName.isNotEmpty) 'authorName': authorName,
        'submittedAt' : FieldValue.serverTimestamp(),
      });

      // If the org already distributed certificates for this event before
      // this feedback came in, issue this guest's certificate right now
      // instead of leaving them waiting for the org to re-run it.
      await CertificateAutoIssueService.tryIssueForFeedback(
        eventDocId: widget.event.eventId,
        recipientKey: widget.email,
        isGuest: true,
      );

      widget.onSubmit();
      if (mounted) setState(() { _isLoading = false; _submitted = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit: $e',
              style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _submitted
            ? _SuccessView(onClose: () => Navigator.pop(context))
            : Column(
                children: [
                  // Handle
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kOrangeLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.rate_review_outlined,
                              color: _kOrange, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Event Feedback',
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87)),
                              Text(widget.event.title,
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.black45),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  // Form
                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                      children: [
                        // Overall star rating
                        Text('Overall Rating',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        const SizedBox(height: 10),
                        _StarRating(
                          value:    _rating,
                          size:     36,
                          onChanged: (v) => setState(() => _rating = v),
                        ),

                        const SizedBox(height: 24),

                        // Per-question ratings
                        Text('Detailed Feedback',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        const SizedBox(height: 12),
                        ...List.generate(_questions.length, (i) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(_questions[i],
                                    style: GoogleFonts.beVietnamPro(
                                        fontSize: 12,
                                        color: Colors.black54)),
                                const SizedBox(height: 6),
                                _StarRating(
                                  value:    _questionRatings[i],
                                  size:     26,
                                  onChanged: (v) => setState(
                                      () => _questionRatings[i] = v),
                                ),
                              ],
                            ),
                          )),

                        const SizedBox(height: 4),

                        // Comment
                        Text('Additional Comments (optional)',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _commentCtrl,
                          maxLines:   4,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 13, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText:
                                'Share your thoughts about the event…',
                            hintStyle: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: const Color(0xFFBBBBBB)),
                            filled:      true,
                            fillColor:   const Color(0xFFF8F9FB),
                            contentPadding: const EdgeInsets.all(14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: _kOrange, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // This form had no anonymity control at all — guests
                        // get the same choice students do.
                        AnonymityToggle(
                          value: _isAnonymous,
                          onChanged: (v) =>
                              setState(() => _isAnonymous = v),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white))
                                : Text('Submit Feedback',
                                    style: GoogleFonts.beVietnamPro(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                          ),
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

// ─────────────────────────────────────────────────────────────
//  STAR RATING WIDGET
// ─────────────────────────────────────────────────────────────
class _StarRating extends StatelessWidget {
  final int               value;
  final double            size;
  final ValueChanged<int> onChanged;

  const _StarRating({
    required this.value,
    required this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < value;
        return GestureDetector(
          onTap: () => onChanged(i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: filled ? const Color(0xFFFBBF24) : Colors.grey[300],
              size: size,
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SUCCESS VIEW
// ─────────────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  final VoidCallback onClose;
  const _SuccessView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(
                  color: _kSuccessBg, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  color: _kSuccess, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Thank You!',
                style: GoogleFonts.beVietnamPro(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(
                'Your feedback has been submitted successfully.\nIt helps us improve future events.',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                    fontSize: 13, color: Colors.grey, height: 1.5)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Done',
                    style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EMPTY / ERROR STATES
// ─────────────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                  color: _kOrangeLight, shape: BoxShape.circle),
              child: const Icon(Icons.rate_review_outlined,
                  color: _kOrange, size: 44),
            ),
            const SizedBox(height: 20),
            Text('No Events Yet',
                style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(
                'You haven\'t registered for any events yet.\nRegister and attend events to leave feedback.',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                    fontSize: 13, color: Colors.grey, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
