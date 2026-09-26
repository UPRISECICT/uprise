// lib/screens/student/student_feedback_screen.dart
// SIMPLIFIED AND IMPROVED VERSION

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../utils/feedback_helper.dart';
import '../../widgets/common/review_identity.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/event_image.dart';
import '../../services/certificate_auto_issue_service.dart';

class StudentFeedbackScreen extends StatefulWidget {
  /// When set, the screen is just this event's Event Feedback form — no list,
  /// no tabs. Submitting or going back replaces it with the My Reviews list.
  /// Comes from an `evaluation` notification's `data['eventId']`; the form
  /// itself lives here rather than in the notification, so there is only one
  /// to maintain.
  final String? initialEventId;

  /// The list tab to open on: 0 = To Rate, 1 = My Reviews.
  final int initialTab;

  const StudentFeedbackScreen({
    super.key,
    this.initialEventId,
    this.initialTab = 0,
  });

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  /// Events with a surviving attendance record. Not `_events.length` — that
  /// also holds reviews recovered without one, which are reviewed but can no
  /// longer be proven attended.
  int _attendedCount = 0;

  bool get _isDeepLink => widget.initialEventId?.isNotEmpty ?? false;

  // Deep-link state — only the one event the notification named.
  bool _deepLinkLoading = true;

  /// The event's row, in the same shape [_loadEvents] builds. Null with no
  /// error means the student has no present/late attendance for it.
  Map<String, dynamic>? _deepLinkRow;

  /// Set when a read failed, so a network or permission error is never
  /// reported as "you didn't attend".
  String? _deepLinkError;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  /// Guards [_openMyReviews] so a back press racing a submit can't push the
  /// list twice.
  bool _leavingDeepLink = false;

  @override
  void initState() {
    super.initState();
    if (_isDeepLink) {
      _loadDeepLinkEvent();
    } else {
      _loadEvents();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final db = FirebaseFirestore.instance;

      // Both feedback collections, not just event_feedback: the "rate this
      // event" notification wrote to the legacy `feedback` one for a long
      // time, so reading only the newer collection showed most students an
      // empty review history and re-offered events they'd already rated.
      // Its own try: a failure here must not also cost the attended list.
      Map<String, Map<String, dynamic>> myFeedback = {};
      try {
        myFeedback = await FeedbackHelper.loadMyFeedback(user.uid);
      } catch (e) {
        print('Error loading my feedback: $e');
      }

      // Attendance is read per event, by direct doc get, rather than with a
      // collectionGroup('attendances') query: that query depends on a
      // collection-group index on studentId, and when it fails the whole
      // screen used to come up 0 / 0 / 0. Every attendance writer (QR/manual
      // check-in, webinar codes) keys the doc by the student's UID.
      final List<Map<String, dynamic>> events = [];
      try {
        final eventsSnap = await db
            .collection('events')
            .where('status', isEqualTo: 'approved')
            .get();

        final rows = await Future.wait(
          eventsSnap.docs.map((eventDoc) async {
            try {
              final att = await eventDoc.reference
                  .collection('attendances')
                  .doc(user.uid)
                  .get();
              final status = (att.data()?['status'] ?? '').toString();
              if (status != 'present' && status != 'late') return null;

              final eventData = eventDoc.data();
              final review = myFeedback[eventDoc.id];
              return <String, dynamic>{
                'eventId': eventDoc.id,
                'eventName': eventData['title'] ?? 'Event',
                'organization': eventData['orgName'] ?? '',
                'orgId': eventData['orgId'] ?? '',
                'bannerUrl': (eventData['bannerUrl'] ?? '').toString(),
                'rated': review != null,
                'review': review,
                'attended': true,
              };
            } catch (e) {
              // One unreadable event is skipped, not the whole list.
              print('Error reading attendance for ${eventDoc.id}: $e');
              return null;
            }
          }),
        );
        events.addAll(rows.whereType<Map<String, dynamic>>());
      } catch (e) {
        print('Error loading attended events: $e');
      }

      // Counted before any orphan is appended: "Attended" answers how many
      // events the student has an attendance record for, which is a different
      // question from how many they have reviewed.
      final attendedCount = events.length;

      // The loop above is attendance-driven, so it can only surface a review
      // that still has a live attendance doc AND a live events doc behind it.
      // Flip an attendance to 'absent', delete it, or delete the event, and a
      // review the student really did submit silently disappears from My
      // Reviews. loadMyFeedback already returned every one of them, so recover
      // the ones the join dropped and let the review stand on its own.
      try {
        final seen = events.map((e) => e['eventId'] as String).toSet();
        final orphanIds = myFeedback.keys
            .where((id) => !seen.contains(id))
            .toList();

        if (orphanIds.isNotEmpty) {
          // The common orphan is an attendance correction, where events/{id}
          // is still there and still has the banner — so fetch it, and fall
          // back to the review's own denormalised copy only when it is gone.
          // Each read may fail alone (e.g. an event students can no longer
          // read); that review then falls back to its own fields instead of
          // taking every recovered review down with it.
          final eventDocs = await Future.wait(
            orphanIds.map(
              (id) => db
                  .collection('events')
                  .doc(id)
                  .get()
                  .then<DocumentSnapshot<Map<String, dynamic>>?>((d) => d)
                  .catchError((_) => null),
            ),
          );

          for (var i = 0; i < orphanIds.length; i++) {
            // The event itself was deleted: its review goes with it, from the
            // list and every count. A failed read (null) is not a deletion,
            // so that review still stands.
            final eventDoc = eventDocs[i];
            if (eventDoc != null && !eventDoc.exists) continue;

            final review = myFeedback[orphanIds[i]]!;
            final eventData = eventDoc?.data() ?? const <String, dynamic>{};

            events.add({
              'eventId': orphanIds[i],
              'eventName':
                  (eventData['title'] ?? '').toString().trim().isNotEmpty
                  ? eventData['title']
                  : FeedbackHelper.eventTitle(review),
              'organization':
                  (eventData['orgName'] ?? review['organization'] ?? '')
                      .toString(),
              'orgId': (eventData['orgId'] ?? review['orgId'] ?? '').toString(),
              'bannerUrl': (eventData['bannerUrl'] ?? '').toString(),
              'rated': true,
              'review': review,
              // Still listed, but not one of the events counted as Attended
              // (attendance changed, or the event is no longer approved).
              'attended': false,
            });
          }
        }
      } catch (e) {
        // Recovering orphans must never cost the student the list that did
        // build — the outer catch would leave the whole screen empty.
        print('Error recovering orphaned reviews: $e');
      }

      // Most recently reviewed first within My Reviews. Undated rows sort
      // last: that is every unrated event, plus a review whose server
      // timestamp is still round-tripping. Returning 0 for those instead
      // would leave recovered reviews stuck wherever they were appended.
      events.sort((a, b) {
        final ra = a['review'] as Map<String, dynamic>?;
        final rb = b['review'] as Map<String, dynamic>?;
        final da = ra == null ? null : FeedbackHelper.submittedAt(ra);
        final db = rb == null ? null : FeedbackHelper.submittedAt(rb);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      setState(() {
        _events = events;
        _attendedCount = attendedCount;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading events: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Loads only the event an evaluation notification named, by direct reads:
  /// the event doc, this student's attendance doc under it, and their review.
  /// Deliberately not [_loadEvents] — that walks every attendance the student
  /// has, and one failing read there empties the whole list, which read as
  /// "not attended" for an event they plainly did attend.
  Future<void> _loadDeepLinkEvent() async {
    final eventId = widget.initialEventId!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _deepLinkError = 'Please log in again to rate this event.';
        _deepLinkLoading = false;
      });
      return;
    }

    setState(() {
      _deepLinkError = null;
      _deepLinkLoading = _deepLinkRow == null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final eventRef = db.collection('events').doc(eventId);

      final results = await Future.wait<Object>([
        eventRef.get(),
        // Every attendance writer (QR/manual check-in, webinar codes) keys
        // the doc by the student's UID.
        eventRef.collection('attendances').doc(user.uid).get(),
        FeedbackHelper.loadMyFeedback(user.uid),
      ]);
      final eventDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      var attendance = (results[1] as DocumentSnapshot<Map<String, dynamic>>)
          .data();
      final review = (results[2] as Map<String, Map<String, dynamic>>)[eventId];

      // Fallback for an attendance doc not keyed by UID, from any writer that
      // predates that convention.
      if (attendance == null) {
        final snap = await eventRef
            .collection('attendances')
            .where('studentId', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) attendance = snap.docs.first.data();
      }

      final status = (attendance?['status'] ?? '').toString();
      final attended = status == 'present' || status == 'late';
      final eventData = eventDoc.data() ?? const <String, dynamic>{};

      // A student who already reviewed still sees that review (read-only),
      // even if the attendance was corrected since.
      Map<String, dynamic>? row;
      if (attended || review != null) {
        final title = (eventData['title'] ?? '').toString().trim();
        row = {
          'eventId': eventId,
          'eventName': title.isNotEmpty
              ? title
              : (review != null ? FeedbackHelper.eventTitle(review) : 'Event'),
          'organization':
              (eventData['orgName'] ?? review?['organization'] ?? '')
                  .toString(),
          'orgId': (eventData['orgId'] ?? review?['orgId'] ?? '').toString(),
          'bannerUrl': (eventData['bannerUrl'] ?? '').toString(),
          'rated': review != null,
          'review': review,
        };
      }

      if (!mounted) return;
      setState(() {
        _deepLinkRow = row;
        _deepLinkLoading = false;
      });
    } catch (e) {
      print('Error loading evaluation event: $e');
      if (!mounted) return;
      setState(() {
        _deepLinkError =
            "Couldn't load this event. Check your connection "
            'and try again.';
        _deepLinkLoading = false;
      });
    }
  }

  AppBar _deepLinkAppBar() => AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    foregroundColor: Colors.black87,
    title: const Text(
      'Event Feedback',
      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    ),
    centerTitle: true,
  );

  /// Leaves the deep-link form for the My Reviews list, replacing this route
  /// so back from the list returns to Notifications, not to the form. After a
  /// submit it opens on My Reviews, where the new review is; otherwise on
  /// To Rate, where the event still waits.
  void _openMyReviews({required bool submitted}) {
    if (_leavingDeepLink || !mounted) return;
    _leavingDeepLink = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StudentFeedbackScreen(initialTab: submitted ? 1 : 0),
      ),
    );
  }

  /// What an evaluation notification opens: the form alone. An event already
  /// reviewed shows that review read-only — feedback is one submission per
  /// event. Every way back (app bar, system back, gesture) goes to My Reviews.
  Widget _buildDeepLinkView() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openMyReviews(submitted: false);
      },
      child: _buildDeepLinkBody(),
    );
  }

  Widget _buildDeepLinkBody() {
    if (_deepLinkLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryDark),
        ),
      );
    }

    if (_deepLinkError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _deepLinkAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _deepLinkError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _loadDeepLinkEvent,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.primaryDark),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final event = _deepLinkRow;

    // No present/late attendance for this event (and no earlier review).
    // Rating it anyway would bypass what the org's certificate gating
    // assumes, so say why instead of showing a form.
    if (event == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _deepLinkAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              "This event isn't in your attended list yet. You can rate it "
              'once your attendance has been recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }

    return _EventFeedbackPage(
      event: event,
      review: event['review'] as Map<String, dynamic>?,
      onSubmit: (rating, comment, isAnonymous) => _submitFeedback(
        event: event,
        rating: rating,
        comment: comment,
        isAnonymous: isAnonymous,
      ),
      onSubmitted: () => _openMyReviews(submitted: true),
    );
  }

  /// Returns whether the write landed, so the form page knows to close.
  Future<bool> _submitFeedback({
    required Map<String, dynamic> event,
    required int rating,
    required String comment,
    required bool isAnonymous,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // One review per event: an already-rated event is only ever shown
    // read-only, so a write here would be a second submission.
    if (event['rated'] == true) return false;

    try {
      // authorName only when the reviewer opted in to attribution — an
      // anonymous review stores no name at all, so there is nothing for a
      // display bug to leak later.
      final authorName = isAnonymous
          ? ''
          : await FeedbackHelper.currentStudentReviewerName();

      final data = {
        'eventId': event['eventId'],
        'eventName': event['eventName'],
        'organization': event['organization'],
        'orgId': event['orgId'],
        'rating': rating,
        'comment': comment.trim(),
        'userId': user.uid,
        'isAnonymous': isAnonymous,
        // Not a conditional key: this merges into a possibly existing doc, so
        // an anonymous re-submit has to actively clear a name left behind by
        // an earlier attributed one.
        'authorName': authorName.isNotEmpty ? authorName : FieldValue.delete(),
        'submittedAt': FieldValue.serverTimestamp(),
      };

      // A deterministic id rather than .add(): this screen is now the only
      // student-side writer, and a random id per submit is what let one
      // student accumulate several event_feedback docs for one event.
      // loadMyFeedback already handed us the existing doc's id, so reusing it
      // costs no extra read.
      final review = event['review'] as Map<String, dynamic>?;
      String? existingId;
      if (review != null && review['sourceCollection'] == 'event_feedback') {
        existingId = review['id'] as String?;
      }

      await FirebaseFirestore.instance
          .collection('event_feedback')
          .doc(existingId ?? '${user.uid}_${event['eventId']}')
          .set(data, SetOptions(merge: true));

      // If the org already distributed certificates for this event before
      // this feedback came in, issue this student's certificate right now
      // instead of leaving them waiting for the org to re-run it.
      await CertificateAutoIssueService.tryIssueForFeedback(
        eventDocId: event['eventId'] as String,
        recipientKey: user.uid,
        isGuest: false,
      );

      // The deep-link form is replaced by a freshly loaded My Reviews list
      // right after this, so only the list view needs a refresh.
      if (!_isDeepLink) await _loadEvents();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted! Thank you! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  /// Opens the full-page Event Feedback form. Only the presentation lives in
  /// [_EventFeedbackPage] — the write still goes through [_submitFeedback], so
  /// the event_feedback doc the org reads is shaped exactly as before.
  void _showFeedbackDialog(
    Map<String, dynamic> event, {
    int initialRating = 0,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EventFeedbackPage(
          event: event,
          initialRating: initialRating,
          onSubmit: (rating, comment, isAnonymous) => _submitFeedback(
            event: event,
            rating: rating,
            comment: comment,
            isAnonymous: isAnonymous,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _toRate =>
      _events.where((e) => e['rated'] != true).toList();

  List<Map<String, dynamic>> get _reviewed =>
      _events.where((e) => e['rated'] == true).toList();

  @override
  Widget build(BuildContext context) {
    if (_isDeepLink) return _buildDeepLinkView();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('My Reviews'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEvents),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryDark),
            )
          : Column(
              children: [
                _statsHeader(),
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primaryDark,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: AppColors.primaryDark,
                    indicatorWeight: 2.5,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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

  /// Attended / reviewed / pending counts, the row of figures the screen leads
  /// with in the reference design.
  Widget _statsHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        children: [
          _stat('$_attendedCount', 'Attended'),
          _statDivider(),
          // Reviews of the events counted as Attended, so Reviewed + To Rate
          // always adds up to Attended.
          _stat(
            '${_reviewed.where((e) => e['attended'] == true).length}',
            'Reviewed',
          ),
          _statDivider(),
          _stat('${_toRate.length}', 'To Rate'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFFE8ECF0));

  Widget _toRateTab() {
    if (_toRate.isEmpty) {
      return _emptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing left to rate',
        subtitle: _events.isEmpty
            ? 'Once you attend an event, it will appear here for feedback.'
            : 'You\'ve reviewed every event you attended. Thank you!',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: AppColors.primaryDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _toRate.length,
        itemBuilder: (context, index) => _toRateCard(_toRate[index]),
      ),
    );
  }

  Widget _myReviewsTab() {
    if (_reviewed.isEmpty) {
      return _emptyState(
        icon: Icons.rate_review_outlined,
        title: 'No reviews yet',
        subtitle: 'Ratings and comments you submit will be kept here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: AppColors.primaryDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reviewed.length,
        itemBuilder: (context, index) => _reviewCard(_reviewed[index]),
      ),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFE8ECF0)),
  );

  Widget _toRateCard(Map<String, dynamic> event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eventHeader(event),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Rate this event',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const Spacer(),
              // Tapping a star opens the form with that rating preselected,
              // the way the reference design's inline star row behaves.
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => _showFeedbackDialog(event, initialRating: i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.star_rounded,
                      size: 26,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showFeedbackDialog(event),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Review',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> event) {
    final review = event['review'] as Map<String, dynamic>? ?? {};
    // Legacy `feedback` docs store the headline score under `overallRating`,
    // and recovered reviews are disproportionately legacy ones — without the
    // fallback they render as five grey stars. Matches the guest card.
    final rating =
        ((review['rating'] ?? review['overallRating']) as num?)?.toInt() ?? 0;
    final comment = (review['comment'] ?? '').toString().trim();
    final submitted = FeedbackHelper.submittedAt(review);
    final anonymous = reviewIsAnonymous(review);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity line: the reader is looking at their own history, so
          // their name shows unmasked — the masking is for other people's
          // eyes. An anonymous review still says so, so they can tell which
          // way they submitted it.
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
                  reviewerDisplayName(review, isOwnReview: true),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (submitted != null)
                Text(
                  DateFormat('dd-MM-yyyy HH:mm').format(submitted),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: i <= rating
                      ? const Color(0xFFF59E0B)
                      : Colors.grey.shade300,
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          const SizedBox(height: 10),
          _eventHeader(event, compact: true),
        ],
      ),
    );
  }

  /// The event a card refers to — banner thumbnail, title and organization.
  Widget _eventHeader(Map<String, dynamic> event, {bool compact = false}) {
    final banner = (event['bannerUrl'] ?? '').toString();
    final org = (event['organization'] ?? '').toString();
    final side = compact ? 36.0 : 52.0;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: side,
            height: side,
            child: banner.isEmpty
                ? Container(
                    color: const Color(0xFFF0F2F5),
                    child: Icon(
                      Icons.event_rounded,
                      size: compact ? 18 : 24,
                      color: Colors.grey.shade400,
                    ),
                  )
                : EventImage(
                    imageUrl: banner,
                    width: side,
                    height: side,
                    fit: BoxFit.cover,
                    showLoadingIndicator: false,
                    expandable: true,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (event['eventName'] ?? 'Event').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12.5 : 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              if (org.isNotEmpty)
                Text(
                  org,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── EVENT FEEDBACK PAGE ────────────────────────────────────────
/// The full-page evaluation form. Owns only the form state; saving is the
/// caller's [onSubmit], which resolves true once the review is written.
/// With a [review] it is read-only: one submission per event.
class _EventFeedbackPage extends StatefulWidget {
  final Map<String, dynamic> event;
  final Map<String, dynamic>? review;
  final int initialRating;
  final Future<bool> Function(int rating, String comment, bool isAnonymous)
  onSubmit;

  /// Where to go once [onSubmit] succeeds. Null just closes the page.
  final VoidCallback? onSubmitted;

  const _EventFeedbackPage({
    required this.event,
    required this.onSubmit,
    this.onSubmitted,
    this.review,
    this.initialRating = 0,
  });

  @override
  State<_EventFeedbackPage> createState() => _EventFeedbackPageState();
}

class _EventFeedbackPageState extends State<_EventFeedbackPage> {
  late int _rating = widget.initialRating;
  final TextEditingController _feedbackCtrl = TextEditingController();
  bool _isAnonymous = false;
  bool _submitting = false;

  bool get _readOnly => widget.review != null;
  bool get _locked => _readOnly || _submitting;

  @override
  void initState() {
    super.initState();
    final review = widget.review;
    if (review != null) {
      // Legacy `feedback` docs keep the score under `overallRating`.
      _rating =
          ((review['rating'] ?? review['overallRating']) as num?)?.toInt() ?? 0;
      _feedbackCtrl.text = (review['comment'] ?? '').toString();
      _isAnonymous = reviewIsAnonymous(review);
    }
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(_rating, _feedbackCtrl.text, _isAnonymous);
    if (!mounted) return;
    if (ok) {
      final onSubmitted = widget.onSubmitted;
      if (onSubmitted != null) {
        onSubmitted();
      } else {
        Navigator.pop(context);
      }
    } else {
      setState(() => _submitting = false);
    }
  }

  /// What each star count means, shown under the stars once one is picked.
  static const List<String> _ratingLabels = [
    'Poor',
    'Fair',
    'Good',
    'Very Good',
    'Excellent',
  ];

  Widget _buildStarSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = starIndex <= _rating;
        return GestureDetector(
          onTap: _locked ? null : () => setState(() => _rating = starIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: 36,
              color: filled ? const Color(0xFFFBBF24) : Colors.grey.shade400,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventName = (widget.event['eventName'] ?? 'Event').toString();
    final orgName = (widget.event['organization'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          // maybePop, not pop: the deep-link view's PopScope turns this into
          // "go to My Reviews", and pop would bypass it.
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Event Feedback',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One card: which event, why it matters, then the form. The event
            // header and the form used to be two separate boxes.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _readOnly ? AppColors.successBg : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _readOnly
                      ? AppColors.success.withAlpha(90)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evaluate "$eventName"',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  // Hidden rather than printed as a bare "Hosted by" when the
                  // event doc carries no orgName.
                  if (orgName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Hosted by $orgName',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  // Certificates are only issued once the attendee's feedback
                  // is in (org_certificates.dart gates on it), which nothing
                  // on this form used to say.
                  if (!_readOnly) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Organizations issue certificates only after you submit '
                      'your feedback.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: _readOnly
                        ? AppColors.success.withAlpha(60)
                        : Colors.grey.shade200,
                  ),
                  const SizedBox(height: 14),
                  // The check stays once submitted — it says something. The
                  // icon beside "Rate this event" was decoration.
                  Row(
                    children: [
                      if (_readOnly) ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _readOnly ? 'Feedback Submitted' : 'Rate this event',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _readOnly ? AppColors.success : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStarSelector(),
                  const SizedBox(height: 6),
                  // What the picked star count means, or a prompt until one is
                  // picked — the stars alone never said what "3" stood for.
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        _rating == 0
                            ? 'Tap a star to rate'
                            : _ratingLabels[_rating - 1],
                        key: ValueKey(_rating),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _rating == 0
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: _rating == 0
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _feedbackCtrl,
                    readOnly: _locked,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText:
                          'Share your thoughts about this event (optional)',
                      // Spelled out in full: a bare fontSize merged with the
                      // app theme's bold, dark hint style and made the
                      // placeholder look like text already typed in.
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primaryDark,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnonymityToggle(
                    value: _isAnonymous,
                    onChanged: _locked
                        ? null
                        : (v) => setState(() => _isAnonymous = v),
                  ),
                  if (!_readOnly) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // Disabled until a star is picked, instead of letting
                        // the tap through only to answer with a red snackbar.
                        onPressed: _submitting || _rating == 0 ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryDark,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Submit Feedback',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
