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
  const StudentFeedbackScreen({super.key});

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _loadEvents();
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

      // Every attendance write (QR/manual check-in and webinar codes) stores
      // the Firebase Auth UID in `studentId` — not the school-issued student
      // number — so querying by anything else here silently returns nothing.
      final attendanceSnap = await FirebaseFirestore.instance
          .collectionGroup('attendances')
          .where('studentId', isEqualTo: user.uid)
          .get();

      // Both feedback collections, not just event_feedback: the "rate this
      // event" notification wrote to the legacy `feedback` one for a long
      // time, so reading only the newer collection showed most students an
      // empty review history and re-offered events they'd already rated.
      final myFeedback = await FeedbackHelper.loadMyFeedback(user.uid);

      // Build the list of events
      final List<Map<String, dynamic>> events = [];

      for (final doc in attendanceSnap.docs) {
        final status = doc.data()['status']?.toString() ?? '';
        if (status != 'present' && status != 'late') continue;

        final eventRef = doc.reference.parent.parent;
        if (eventRef == null) continue;

        final eventDoc = await eventRef.get();
        if (!eventDoc.exists) continue;

        final eventData = eventDoc.data() as Map<String, dynamic>;
        final review = myFeedback[eventRef.id];

        events.add({
          'eventId': eventRef.id,
          'eventName': eventData['title'] ?? 'Event',
          'organization': eventData['orgName'] ?? '',
          'orgId': eventData['orgId'] ?? '',
          'bannerUrl': (eventData['bannerUrl'] ?? '').toString(),
          'rated': review != null,
          'review': review,
        });
      }

      // Most recently reviewed first within My Reviews; To Rate keeps the
      // attendance order it came back in.
      events.sort((a, b) {
        final ra = a['review'] as Map<String, dynamic>?;
        final rb = b['review'] as Map<String, dynamic>?;
        if (ra == null || rb == null) return 0;
        final da = FeedbackHelper.submittedAt(ra);
        final db = FeedbackHelper.submittedAt(rb);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading events: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitFeedback({
    required Map<String, dynamic> event,
    required int rating,
    required String comment,
    required bool isAnonymous,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // authorName only when the reviewer opted in to attribution — an
      // anonymous review stores no name at all, so there is nothing for a
      // display bug to leak later.
      final authorName = isAnonymous
          ? ''
          : await FeedbackHelper.currentStudentReviewerName();

      await FirebaseFirestore.instance.collection('event_feedback').add({
        'eventId': event['eventId'],
        'eventName': event['eventName'],
        'organization': event['organization'],
        'orgId': event['orgId'],
        'rating': rating,
        'comment': comment.trim(),
        'userId': user.uid,
        'isAnonymous': isAnonymous,
        if (authorName.isNotEmpty) 'authorName': authorName,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      // If the org already distributed certificates for this event before
      // this feedback came in, issue this student's certificate right now
      // instead of leaving them waiting for the org to re-run it.
      await CertificateAutoIssueService.tryIssueForFeedback(
        eventDocId: event['eventId'] as String,
        recipientKey: user.uid,
        isGuest: false,
      );

      // Refresh the list
      await _loadEvents();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted! Thank you! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFeedbackDialog(
    Map<String, dynamic> event, {
    int initialRating = 0,
  }) {
    // Preset when the caller came from the card's inline star row, so tapping
    // 4 stars opens the form already showing 4.
    int selectedRating = initialRating;
    final commentController = TextEditingController();
    bool isSubmitting = false;
    bool isAnonymous = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Text(
                    'Rate this Event',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event['eventName'] ?? 'Event',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),

                  // Stars
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (index) {
                        final starNumber = index + 1;
                        return IconButton(
                          onPressed: () => setSheetState(() {
                            selectedRating = starNumber;
                          }),
                          icon: Icon(
                            starNumber <= selectedRating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: starNumber <= selectedRating
                                ? AppColors.primaryDark
                                : Colors.grey.shade400,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Comment field
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Share your thoughts (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Anonymous toggle — the shared Switch, so this form and the
                  // event-details one present the same control.
                  AnonymityToggle(
                    value: isAnonymous,
                    onChanged: (v) => setSheetState(() => isAnonymous = v),
                  ),
                  const SizedBox(height: 8),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (selectedRating == 0) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please select a rating'),
                                    backgroundColor: AppColors.primaryDark,
                                  ),
                                );
                                return;
                              }

                              setSheetState(() => isSubmitting = true);
                              await _submitFeedback(
                                event: event,
                                rating: selectedRating,
                                comment: commentController.text,
                                isAnonymous: isAnonymous,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Submit Feedback',
                              style: TextStyle(fontWeight: FontWeight.w600),
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
  }

  List<Map<String, dynamic>> get _toRate =>
      _events.where((e) => e['rated'] != true).toList();

  List<Map<String, dynamic>> get _reviewed =>
      _events.where((e) => e['rated'] == true).toList();

  @override
  Widget build(BuildContext context) {
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
          _stat('${_events.length}', 'Attended'),
          _statDivider(),
          _stat('${_reviewed.length}', 'Reviewed'),
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
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
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
