// lib/screens/student/student_organization_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/student/app_colors.dart';
import 'student_broadcast_screen.dart';
import 'student_events_screen.dart';
import 'student_announcements_screen.dart';

// ─────────────────────────────────────────────────────────────
//  ORGANIZATION DETAILS SCREEN
// ─────────────────────────────────────────────────────────────
class StudentOrganizationsDetailsScreen extends StatefulWidget {
  final String orgId;
  const StudentOrganizationsDetailsScreen({super.key, required this.orgId});

  @override
  State<StudentOrganizationsDetailsScreen> createState() =>
      _StudentOrganizationsDetailsScreenState();
}

class _StudentOrganizationsDetailsScreenState
    extends State<StudentOrganizationsDetailsScreen> {
  bool _coverImageFailed = false;

  ImageProvider? _buildLogoImage(String? logoUrl) {
    if (logoUrl == null || logoUrl.isEmpty) return null;

    if (logoUrl.startsWith('data:')) {
      try {
        final base64Str = logoUrl.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) {
        return null;
      }
    }

    return NetworkImage(logoUrl);
  }

  DecorationImage? _buildCoverImage(String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) return null;

    if (coverUrl.startsWith('data:image')) {
      try {
        final base64Str = coverUrl.split(',').last;
        return DecorationImage(
          image: MemoryImage(base64Decode(base64Str)),
          fit: BoxFit.cover,
        );
      } catch (_) {
        return null;
      }
    }

    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
      return DecorationImage(
        image: NetworkImage(coverUrl),
        fit: BoxFit.cover,
        onError: (_, __) {
          if (mounted) {
            setState(() => _coverImageFailed = true);
          }
        },
      );
    }

    return null;
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDark.withOpacity(0.3),
            AppColors.primaryDark.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 48,
              color: AppColors.primaryDark.withOpacity(0.2),
            ),
            const SizedBox(height: 8),
            Text(
              'No Cover Image',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryDark.withOpacity(0.3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ SIMPLIFIED: Go to Events tab
  void _navigateToEventDetail(String eventId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StudentEventsScreen(initialTabIndex: 1),
      ),
    );
  }

  // ⭐ SIMPLIFIED: Go to Announcements screen
  void _navigateToAnnouncementDetail(String announcementId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentAnnouncementsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.orgId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryDark),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.business_center_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Organization not found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }

          final org = snapshot.data!.data() as Map<String, dynamic>;
          final officers = (org['officers'] as List?) ?? [];

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text(
                'Organization',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Colors.black87,
                ),
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              centerTitle: true,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: Colors.grey.shade200),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentBroadcastScreen(
                          orgId: widget.orgId,
                          orgName: org['name'] ?? 'Organization',
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── COVER IMAGE WITH LOGO OVERLAY ──
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                        child: Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            image:
                                (org['coverPhotoUrl'] != null &&
                                    (org['coverPhotoUrl'] as String)
                                        .isNotEmpty &&
                                    !_coverImageFailed)
                                ? _buildCoverImage(org['coverPhotoUrl'])
                                : null,
                            color: AppColors.primaryDark.withOpacity(0.08),
                          ),
                          child:
                              (org['coverPhotoUrl'] == null ||
                                  (org['coverPhotoUrl'] as String).isEmpty ||
                                  _coverImageFailed)
                              ? _buildCoverPlaceholder()
                              : null,
                        ),
                      ),

                      Positioned.fill(
                        child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.2),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: -35,
                        left: 16,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.white,
                            backgroundImage: _buildLogoImage(org['logoUrl']),
                            child:
                                (org['logoUrl'] == null ||
                                    (org['logoUrl'] as String).isEmpty)
                                ? Text(
                                    (org['name'] ?? 'O')[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDark,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),

                  // ── Organization Info ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          org['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          org['category'] ?? 'Student Organization',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            'ACCREDITED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'About',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          org['description'] ?? 'No description available',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Organization Adviser(s) ──
                        Builder(
                          builder: (context) {
                            final adviserList = (org['advisers'] as List?)
                                ?.whereType<Map<String, dynamic>>()
                                .toList();
                            final hasMultiple =
                                adviserList != null && adviserList.isNotEmpty;
                            final photoUrl = org['adviserPhotoUrl'] as String?;
                            ImageProvider? photoProvider;
                            if (photoUrl != null && photoUrl.isNotEmpty) {
                              try {
                                photoProvider = photoUrl.startsWith('data:')
                                    ? MemoryImage(
                                        base64Decode(photoUrl.split(',').last),
                                      )
                                    : NetworkImage(photoUrl) as ImageProvider;
                              } catch (_) {}
                            }
                            final advisersToShow = hasMultiple
                                ? adviserList!
                                : [
                                    {
                                      'name':
                                          org['adviserName'] ??
                                          'No adviser listed',
                                      'title': org['adviserTitle'],
                                    },
                                  ];
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final adv in advisersToShow)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          photoProvider != null
                                              ? CircleAvatar(
                                                  radius: 20,
                                                  backgroundImage:
                                                      photoProvider,
                                                )
                                              : Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primaryDark
                                                        .withOpacity(0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.person_outline,
                                                    color:
                                                        AppColors.primaryDark,
                                                    size: 20,
                                                  ),
                                                ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Organization Adviser',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  (adv['name'] ??
                                                          'No adviser listed')
                                                      .toString(),
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                if ((adv['title'] ?? '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Text(
                                                    (adv['title']).toString(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // ── Connect / Social Links ──
                        if ([
                          org['facebook'],
                          org['instagram'],
                          org['twitter'],
                          org['gmail'],
                        ].any(
                          (v) => (v ?? '').toString().trim().isNotEmpty,
                        )) ...[
                          const Text(
                            'Connect',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if ((org['facebook'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                _SocialChip(
                                  icon: Icons.facebook_rounded,
                                  label: 'Facebook',
                                  url: org['facebook'],
                                ),
                              if ((org['instagram'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                _SocialChip(
                                  icon: Icons.camera_alt_outlined,
                                  label: 'Instagram',
                                  url: org['instagram'],
                                ),
                              if ((org['twitter'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                _SocialChip(
                                  icon: Icons.alternate_email_rounded,
                                  label: 'Twitter/X',
                                  url: org['twitter'],
                                ),
                              if ((org['gmail'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                _SocialChip(
                                  icon: Icons.email_outlined,
                                  label: org['gmail'],
                                  url: 'mailto:${org['gmail']}',
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── Executive Officers ──
                        const Text(
                          'Executive Officers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (officers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Center(
                              child: Text(
                                'No officers listed',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: officers.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 0, color: Colors.grey),
                            itemBuilder: (context, index) {
                              final officer = officers[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: AppColors.primaryDark
                                          .withOpacity(0.08),
                                      backgroundImage: _buildLogoImage(
                                        officer['photoUrl'],
                                      ),
                                      child:
                                          (officer['photoUrl'] == null ||
                                              (officer['photoUrl'] as String?)
                                                      ?.isEmpty ==
                                                  true)
                                          ? Text(
                                              (officer['name'] ?? '')[0]
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                color: AppColors.primaryDark,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            officer['name'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          Text(
                                            officer['position'] ?? '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 24),

                        // ── Upcoming Events (CLICKABLE) ──
                        const Text(
                          'Upcoming Events',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _UpcomingEventsList(
                          orgId: widget.orgId,
                          onEventTap: _navigateToEventDetail,
                        ),
                        const SizedBox(height: 24),

                        // ── Recent Announcements (CLICKABLE) ──
                        const Text(
                          'Recent Announcements',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _RecentAnnouncementsList(
                          orgId: widget.orgId,
                          onAnnouncementTap: _navigateToAnnouncementDetail,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  UPCOMING EVENTS LIST (CLICKABLE)
// ─────────────────────────────────────────────────────────────
class _UpcomingEventsList extends StatelessWidget {
  final String orgId;
  final Function(String) onEventTap;

  const _UpcomingEventsList({required this.orgId, required this.onEventTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('orgId', isEqualTo: orgId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.now())
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 80,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryDark,
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                'Failed to load events',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        var docs = snapshot.data?.docs ?? [];

        docs.sort((a, b) {
          final dateA = (a.data() as Map<String, dynamic>)['date'] as Timestamp;
          final dateB = (b.data() as Map<String, dynamic>)['date'] as Timestamp;
          return dateA.compareTo(dateB);
        });

        if (docs.length > 5) docs = docs.sublist(0, 5);

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                'No upcoming events',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp).toDate();
            final month = DateFormat('MMM').format(date);
            final day = DateFormat('dd').format(date);

            return GestureDetector(
              onTap: () => onEventTap(doc.id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryDark,
                            AppColors.primaryDark.withOpacity(0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            month,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            day,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Untitled Event',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                data['startTime'] ?? 'TBA',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  data['location'] ?? 'TBA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RECENT ANNOUNCEMENTS LIST (CLICKABLE)
// ─────────────────────────────────────────────────────────────
class _RecentAnnouncementsList extends StatelessWidget {
  final String orgId;
  final Function(String) onAnnouncementTap;

  const _RecentAnnouncementsList({
    required this.orgId,
    required this.onAnnouncementTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('announcements')
          .where('orgId', isEqualTo: orgId)
          .where('isPublished', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 80,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryDark,
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                'Failed to load announcements',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        var docs = snapshot.data?.docs ?? [];

        docs.sort((a, b) {
          final dateA =
              (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final dateB =
              (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;

          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;

          return dateB.compareTo(dateA);
        });

        if (docs.length > 5) docs = docs.sublist(0, 5);

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                'No announcements available',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final timestamp = data['timestamp'] as Timestamp?;
            final date = timestamp != null
                ? timestamp.toDate()
                : DateTime.now();
            final timeAgo = DateFormat('MMM dd, yyyy').format(date);

            final isUrgent =
                (data['category'] ?? '').toString().toLowerCase() == 'urgent' ||
                (data['title'] ?? '').toString().toLowerCase().contains(
                  'urgent',
                );

            return GestureDetector(
              onTap: () => onAnnouncementTap(doc.id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUrgent ? Colors.red.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isUrgent
                        ? Colors.red.shade200
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isUrgent
                            ? Colors.red.shade100
                            : AppColors.primaryDark.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isUrgent ? Icons.priority_high : Icons.campaign,
                        size: 18,
                        color: isUrgent ? Colors.red : AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Untitled',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isUrgent
                                  ? Colors.red.shade800
                                  : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data['content'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SOCIAL CHIP
// ─────────────────────────────────────────────────────────────
class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _SocialChip({
    required this.icon,
    required this.label,
    required this.url,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null && await canLaunchUrl(uri)
        ? await launchUrl(uri, mode: LaunchMode.externalApplication)
        : false;
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryDark.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primaryDark.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.primaryDark),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
