// lib/screens/student/student_new_event_promo.dart
//
// Shopee-style "new arrival" popup — surfaces the most recently published
// upcoming event right after the student opens the app, so a freshly
// posted event doesn't just sit unnoticed at the bottom of the Events tab.
// Shown at most once per event (tracked in SharedPreferences), so reopening
// the app doesn't re-show the same promo — only a genuinely new event
// triggers it again.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uprise/models/event_model.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/event_image.dart';
import 'student_events_screen.dart';

Future<void> maybeShowNewEventPromo(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    // Deliberately a single `where` paired with `orderBy` — combining more
    // equality filters here needs a composite Firestore index that isn't
    // deployed, and the query fails outright without it (see the same note
    // in widgets/student/announcements_feed.dart). isPublic/isPast are
    // filtered client-side instead.
    final snap = await FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    if (snap.docs.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    for (final doc in snap.docs) {
      final event = EventModel.fromFirestore(doc);

      if (!event.isPublic) continue;
      // Only worth announcing if it hasn't happened yet.
      if (event.isPast) continue;

      final alreadyShown =
          prefs.getBool('new_event_promo_${event.id}') ?? false;
      if (alreadyShown) continue;

      await prefs.setBool('new_event_promo_${event.id}', true);

      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(140),
        builder: (_) => _NewEventPromoDialog(event: event),
      );

      return; // only one popup per app open
    }
  } catch (e) {
    debugPrint('maybeShowNewEventPromo error: $e');
  }
}

class _NewEventPromoDialog extends StatelessWidget {
  final EventModel event;
  const _NewEventPromoDialog({required this.event});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: event.hasImage
                          ? EventImage(
                              imageUrl: event.imageUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primaryDark,
                                    AppColors.primaryDark.withAlpha(180),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.celebration_rounded,
                                  size: 56,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.bolt_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'NEW EVENT',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(150),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.orgName.isEmpty
                            ? 'Just announced'
                            : '${event.orgName} · Just announced',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B1B1D),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: Color(0xFF8A8A90),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${event.formattedDate} · ${event.formattedTime}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF4B4B50),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (event.location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: Color(0xFF8A8A90),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                event.location,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF4B4B50),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EventDetailScreen(
                                  event: event,
                                  onRegistered: () {},
                                  isPastEvent: false,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'View Event',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Maybe Later',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A8A90),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
