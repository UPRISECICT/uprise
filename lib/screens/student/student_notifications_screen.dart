import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/feedback_helper.dart';
import '../../widgets/common/review_identity.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/loading_widget.dart';
import '../../models/event_model.dart';
import 'student_broadcast_screen.dart';
import 'student_events_screen.dart';
import 'student_certificates_screen.dart';
import 'student_feedback_screen.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String type;
  final String orgId;
  final String orgName;
  final Map<String, dynamic>? data;

  /// Which portal surface this notification belongs to.
  /// null / absent = student (backward-compatible default).
  /// 'organization' = org portal.
  /// 'admin' = admin dashboard.
  final String? portal;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.type,
    required this.orgId,
    required this.orgName,
    this.data,
    this.portal,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
      type: data['type'] ?? 'announcement',
      orgId: data['orgId'] ?? '',
      orgName: data['orgName'] ?? 'Organization',
      data: data['data'] as Map<String, dynamic>?,
      portal: data['portal'] as String?,
    );
  }

  /// Whether this notification belongs to the student surface.
  /// Notifications without a portal field are treated as student-facing
  /// for backward compatibility with existing data.
  bool get isStudentFacing =>
      portal == null || portal == '' || portal == 'student';
}

/// Whether a raw notification doc is student-facing. Used by streams that
/// operate on [QueryDocumentSnapshot] directly (e.g. the unread badge)
/// instead of the parsed [AppNotification] model.
bool _isStudentNotification(QueryDocumentSnapshot doc) {
  final portal = (doc.data() as Map<String, dynamic>)['portal'];
  return portal == null || portal == '' || portal == 'student';
}

class StudentNotificationsScreen extends StatefulWidget {
  /// When set, the notification with this id is opened as if the student had
  /// tapped it in the list. Used by PushNotificationService when a student
  /// taps an OS push: routing a push through this screen reuses
  /// [_onNotificationTap] wholesale instead of duplicating it, so in-app
  /// taps and push taps can never drift apart, and it leaves the student on
  /// the notification list when they press back.
  final String? initialNotificationId;

  const StudentNotificationsScreen({super.key, this.initialNotificationId});

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState
    extends State<StudentNotificationsScreen> {
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    final pushedId = widget.initialNotificationId;
    if (pushedId != null && pushedId.isNotEmpty) {
      // After the first frame so this screen is mounted and can be the
      // route the target screen is pushed on top of.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotificationById(pushedId);
      });
    }
  }

  Future<void> _openNotificationById(String notificationId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .get();
      if (!doc.exists || !mounted) return;
      final notif = AppNotification.fromFirestore(doc);
      // A push should only ever open a student-facing notification, and only
      // the recipient's own.
      if (!notif.isStudentFacing) return;
      _onNotificationTap(notif);
    } catch (e) {
      debugPrint('Could not open pushed notification $notificationId: $e');
    }
  }

  ({IconData icon, Color bg, Color fg}) _typeStyle(String type) {
    switch (type) {
      case 'event':
        return (
          icon: Icons.calendar_today_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'org':
        return (
          icon: Icons.business_center_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'schedule':
        return (
          icon: Icons.access_time_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'booth':
        return (
          icon: Icons.storefront_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'order':
        return (
          icon: Icons.shopping_bag_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'evaluation':
      case 'feedback_required':
        return (
          icon: Icons.rate_review_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'private_message':
        return (
          icon: Icons.chat_bubble_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
      case 'certificate':
        return (
          icon: Icons.workspace_premium_rounded,
          bg: AppColors.primaryDark.withAlpha(26),
          fg: AppColors.primaryDark,
        );
      default:
        return (
          icon: Icons.campaign_rounded,
          bg: AppColors.primaryDark.withOpacity(0.1),
          fg: AppColors.primaryDark,
        );
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Future<void> _markAsRead(String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notifId)
          .update({'isRead': true});
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        // Only mark student-facing notifications — leave org/admin ones
        // untouched so the other portals' unread state isn't affected.
        if (!_isStudentNotification(doc)) continue;
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }
    } catch (e) {
      print('Error marking all as read: $e');
    }
  }

  Future<void> _openEvent(String eventId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();
      if (!doc.exists || !mounted) return;
      final event = EventModel.fromFirestore(doc);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(
            event: event,
            onRegistered: () {},
            isPastEvent: event.fullDateTime.isBefore(DateTime.now()),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not open event $eventId: $e');
    }
  }

  void _onNotificationTap(AppNotification notif) {
    _markAsRead(notif.id);

    if (notif.type == 'private_message') {
      if (notif.orgId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentBroadcastScreen(
              orgId: notif.orgId,
              orgName: notif.title.isNotEmpty ? notif.title : notif.orgName,
            ),
          ),
        );
      }
      return;
    }

    if (notif.type == 'certificate') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StudentCertificatesScreen()),
      );
      return;
    }

    // Every 'event' notification this app writes carries an eventId in
    // `data`, so all of them open the event: the "new event published"
    // broadcast and the pre-event reminders (functions/index.js), and the
    // attendance check-in notices (org_attendance_qr.dart and
    // webinar_attendance_service.dart, which both send
    // data: {'eventId': ..., 'status': ...}).
    //
    // Note this changes what a check-in notification does: before this
    // branch existed they matched no case, fell through, and only got
    // marked read, so tapping "You're Marked Present!" did nothing
    // visible. It now opens that event, in past mode - the event has by
    // definition already started if someone checked in to it.
    if (notif.type == 'event') {
      final eventId = notif.data?['eventId'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        _openEvent(eventId);
      }
      return;
    }

    // Handle feedback/evaluation notifications
    if (notif.type == 'evaluation' || notif.type == 'feedback_required') {
      // Extract event data from notification
      final eventId = notif.data?['eventId'] as String?;
      final eventTitle = notif.data?['eventTitle'] as String? ?? notif.title;
      final eventDate = notif.data?['eventDate'] as String?;
      final eventLocation = notif.data?['eventLocation'] as String?;
      final eventImage = notif.data?['eventImage'] as String?;
      final eventDescription = notif.data?['eventDescription'] as String?;
      final orgName = notif.orgName;

      if (eventId != null) {
        // Navigate to event-specific feedback screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _EventFeedbackWrapper(
              eventId: eventId,
              eventTitle: eventTitle,
              eventDate: eventDate,
              eventLocation: eventLocation,
              eventImage: eventImage,
              eventDescription: eventDescription,
              orgName: orgName,
            ),
          ),
        );
      } else {
        // Fallback: navigate to general feedback screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                foregroundColor: Colors.black87,
                title: const Text(
                  'Evaluate Events',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              body: const StudentFeedbackScreen(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: StudentAppBar(
        title: 'Notifications',
        centerTitle: false,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: _uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snap) {
              // Only count student-facing unread notifications.
              final hasUnread = snap.hasData &&
                  snap.data!.docs.any(_isStudentNotification);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: _markAllAsRead,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                ),
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: _buildNotificationsList(),
    );
  }

  Widget _buildNotificationsList() {
    if (_uid == null) {
      return const Center(child: Text('Please log in.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _uid)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonLoader(count: 6, height: 72),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  'Could not load notifications.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _EmptyState();
        }

        // Filter to student-facing notifications only — org-portal and
        // admin-dashboard notifications are excluded so a student who is
        // also an org member doesn't see org-level items here.
        final all =
            snapshot.data!.docs
                .map((d) => AppNotification.fromFirestore(d))
                .where((n) => n.isStudentFacing)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (all.isEmpty) {
          return _EmptyState();
        }

        final visible = all.take(50).toList();

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));

        final today = visible
            .where((n) => n.createdAt.isAfter(todayStart))
            .toList();
        final yesterday = visible
            .where(
              (n) =>
                  n.createdAt.isAfter(yesterdayStart) &&
                  !n.createdAt.isAfter(todayStart),
            )
            .toList();
        final earlier = visible
            .where((n) => !n.createdAt.isAfter(yesterdayStart))
            .toList();

        return ListView(
          children: [
            if (today.isNotEmpty) ...[
              _SectionHeader(label: 'Today'),
              ...today.map(
                (n) => _NotifTile(
                  notif: n,
                  style: _typeStyle(n.type),
                  timeLabel: _formatTime(n.createdAt),
                  onTap: () => _onNotificationTap(n),
                ),
              ),
            ],
            if (yesterday.isNotEmpty) ...[
              _SectionHeader(label: 'Yesterday'),
              ...yesterday.map(
                (n) => _NotifTile(
                  notif: n,
                  style: _typeStyle(n.type),
                  timeLabel: _formatTime(n.createdAt),
                  onTap: () => _onNotificationTap(n),
                ),
              ),
            ],
            if (earlier.isNotEmpty) ...[
              _SectionHeader(label: 'Earlier'),
              ...earlier.map(
                (n) => _NotifTile(
                  notif: n,
                  style: _typeStyle(n.type),
                  timeLabel: _formatTime(n.createdAt),
                  onTap: () => _onNotificationTap(n),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ─── HELPER WIDGETS ─────────────────────────────────────────────

// ─── SECTION HEADER ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─── NOTIFICATION TILE ──────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final ({IconData icon, Color bg, Color fg}) style;
  final String timeLabel;
  final VoidCallback onTap;

  const _NotifTile({
    required this.notif,
    required this.style,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: notif.isRead
              ? Colors.white
              : AppColors.primaryDark.withOpacity(0.07),
          border: notif.isRead
              ? null
              : const Border(
                  left: BorderSide(color: AppColors.primaryDark, width: 3),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: style.fg, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: notif.isRead
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          notif.orgName,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      if (!notif.isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryDark,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
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

// ─── EMPTY STATE ────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "You're all caught up!",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ─── EVENT FEEDBACK WRAPPER ─────────────────────────────────────
class _EventFeedbackWrapper extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String? eventDate;
  final String? eventLocation;
  final String? eventImage;
  final String? eventDescription;
  final String orgName;

  const _EventFeedbackWrapper({
    required this.eventId,
    required this.eventTitle,
    this.eventDate,
    this.eventLocation,
    this.eventImage,
    this.eventDescription,
    required this.orgName,
  });

  @override
  State<_EventFeedbackWrapper> createState() => _EventFeedbackWrapperState();
}

class _EventFeedbackWrapperState extends State<_EventFeedbackWrapper> {
  int _rating = 0;
  final TextEditingController _feedbackCtrl = TextEditingController();
  bool _feedbackSubmitted = false;
  bool _isAnonymous = false;
  bool _checkingFeedback = true;
  bool _submittingFeedback = false;

  @override
  void initState() {
    super.initState();
    _checkFeedbackStatus();
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkFeedbackStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _checkingFeedback = false);
      return;
    }
    try {
      final docId = '${user.uid}_${widget.eventId}';
      final db = FirebaseFirestore.instance;
      // Both collections: this screen used to write to the legacy `feedback`
      // one, so a student's earlier review for this event may still live
      // there. event_feedback wins when both exist — it has the fuller shape.
      final results = await Future.wait([
        db.collection('feedback').doc(docId).get(),
        db.collection('event_feedback').doc(docId).get(),
      ]);
      final doc = results[1].exists ? results[1] : results[0];
      if (mounted) {
        setState(() {
          if (doc.exists) {
            final d = doc.data()!;
            _feedbackSubmitted = true;
            _rating = (d['rating'] ?? 0) as int;
            _feedbackCtrl.text = (d['comment'] ?? '').toString();
            _isAnonymous = d['isAnonymous'] == true;
          }
          _checkingFeedback = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingFeedback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load feedback status: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to submit feedback'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _submittingFeedback = true);
    try {
      final docId = '${user.uid}_${widget.eventId}';
      // authorName only when the reviewer opted in to attribution; delete
      // clears one left by an earlier attributed submission, since this merges.
      final authorName = _isAnonymous
          ? ''
          : await FeedbackHelper.currentStudentReviewerName();

      // event_feedback, not the legacy `feedback` this used to write to: it is
      // the collection the other three submit paths use and the one that
      // carries isAnonymous. Same deterministic docId, so a re-submission
      // still overwrites rather than piling up duplicates.
      await FirebaseFirestore.instance
          .collection('event_feedback')
          .doc(docId)
          .set({
            'userId': user.uid,
            'eventId': widget.eventId,
            'eventName': widget.eventTitle,
            // Kept alongside eventName so anything still reading the legacy
            // field name off this document keeps working.
            'eventTitle': widget.eventTitle,
            'rating': _rating,
            'comment': _feedbackCtrl.text.trim(),
            'isAnonymous': _isAnonymous,
            'authorName': authorName.isNotEmpty
                ? authorName
                : FieldValue.delete(),
            'submittedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _feedbackSubmitted = true;
          _submittingFeedback = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submittingFeedback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Widget _buildStarSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = starIndex <= _rating;
        return GestureDetector(
          onTap: _feedbackSubmitted
              ? null
              : () => setState(() => _rating = starIndex),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
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
            // Event Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.eventTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hosted by ${widget.orgName}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  if (widget.eventDate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.eventDate!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.eventLocation != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.eventLocation!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Feedback Section
            if (_checkingFeedback)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _feedbackSubmitted
                      ? Colors.green.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _feedbackSubmitted
                        ? Colors.green.shade200
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _feedbackSubmitted
                              ? Icons.check_circle_rounded
                              : Icons.rate_review_rounded,
                          color: _feedbackSubmitted
                              ? Colors.green
                              : AppColors.primaryDark,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _feedbackSubmitted
                              ? 'Feedback Submitted'
                              : 'Rate this event',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _feedbackSubmitted
                                ? Colors.green.shade700
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStarSelector(),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _feedbackCtrl,
                      readOnly: _feedbackSubmitted,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Share your thoughts about this event (optional)',
                        hintStyle: const TextStyle(fontSize: 13),
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
                    // This form had no anonymity control at all, while the
                    // other submit paths did — and it is the one most students
                    // actually use.
                    AnonymityToggle(
                      value: _isAnonymous,
                      onChanged: _feedbackSubmitted
                          ? null
                          : (v) => setState(() => _isAnonymous = v),
                    ),
                    if (!_feedbackSubmitted) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingFeedback
                              ? null
                              : _submitFeedback,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _submittingFeedback
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Submit Feedback',
                                  style: TextStyle(
                                    color: Colors.white,
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