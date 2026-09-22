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

    // Evaluation notifications only point at the Event Feedback screen — the
    // rating form itself lives there (student_feedback_screen.dart) so there
    // is one form and one write path. A null eventId just lands on the list.
    //
    // Only `data['eventId']` is read because that is all the sole producer
    // sends (org_attendance_qr.dart `_sendEvaluationRequests`); the title,
    // date, location and image this used to unpack were always absent.
    if (notif.type == 'evaluation' || notif.type == 'feedback_required') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentFeedbackScreen(
            initialEventId: notif.data?['eventId'] as String?,
          ),
        ),
      );
      return;
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
