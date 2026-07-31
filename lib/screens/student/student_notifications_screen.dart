import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/loading_widget.dart';
import 'student_broadcast_screen.dart';
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
    );
  }
}

class StudentNotificationsScreen extends StatefulWidget {
  const StudentNotificationsScreen({super.key});

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
              final hasUnread = snap.hasData && snap.data!.docs.isNotEmpty;
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

        final all =
            snapshot.data!.docs
                .map((d) => AppNotification.fromFirestore(d))
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
      final doc = await FirebaseFirestore.instance
          .collection('feedback')
          .doc(docId)
          .get();
      if (mounted) {
        setState(() {
          if (doc.exists) {
            final d = doc.data()!;
            _feedbackSubmitted = true;
            _rating = (d['rating'] ?? 0) as int;
            _feedbackCtrl.text = (d['comment'] ?? '').toString();
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
      await FirebaseFirestore.instance.collection('feedback').doc(docId).set({
        'userId': user.uid,
        'eventId': widget.eventId,
        'eventTitle': widget.eventTitle,
        'rating': _rating,
        'comment': _feedbackCtrl.text.trim(),
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
