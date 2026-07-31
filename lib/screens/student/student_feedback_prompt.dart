// lib/screens/student/student_feedback_prompt.dart
// JUST COPY THIS WHOLE FILE - Replace your existing one

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/student/app_colors.dart';
import 'student_feedback_screen.dart';

// 👇 THIS FUNCTION CHECKS IF STUDENT NEEDS TO GIVE FEEDBACK
// AND SHOWS THE POP-UP IF THEY DO
Future<void> maybeShowFeedbackPrompt(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    // Every attendance write (QR/manual check-in and webinar codes) stores
    // the Firebase Auth UID in `studentId` — not the school-issued student
    // number — so querying by anything else here silently returns nothing.
    final attendanceDocs = await FirebaseFirestore.instance
        .collectionGroup('attendances')
        .where('studentId', isEqualTo: user.uid)
        .get();

    // 2. Get all feedback the student already gave
    final feedbackDocs = await FirebaseFirestore.instance
        .collection('event_feedback')
        .where('userId', isEqualTo: user.uid)
        .get();

    // 3. Make a list of event IDs that already have feedback
    final ratedEventIds = feedbackDocs.docs
        .map((doc) => doc.data()['eventId']?.toString())
        .whereType<String>()
        .toSet();

    // 4. Remember which pop-ups we already showed
    final prefs = await SharedPreferences.getInstance();

    // 5. Check each event the student attended
    for (final doc in attendanceDocs.docs) {
      final status = doc.data()['status']?.toString() ?? '';

      if (status != 'present' && status != 'late') continue;

      final eventRef = doc.reference.parent.parent;
      if (eventRef == null) continue;
      final eventId = eventRef.id;

      if (ratedEventIds.contains(eventId)) continue;

      final alreadyPrompted =
          prefs.getBool('feedback_prompt_$eventId') ?? false;
      if (alreadyPrompted) continue;

      final eventDoc = await eventRef.get();
      if (!eventDoc.exists) continue;
      final eventData = eventDoc.data() as Map<String, dynamic>;

      await prefs.setBool('feedback_prompt_$eventId', true);

      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _FeedbackPromptDialog(
          eventTitle: eventData['title'] ?? 'this event',
          eventId: eventId,
        ),
      );

      return; // only one pop-up per session
    }
  } catch (e) {
    print('Error: $e');
  }
}

class _FeedbackPromptDialog extends StatelessWidget {
  final String eventTitle;
  final String eventId;

  const _FeedbackPromptDialog({
    required this.eventTitle,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rate_review_rounded,
                size: 32,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 18),

            // Title
            const Text(
              'How was the event?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // Description
            Text(
              'You attended "$eventTitle". Share your feedback so the organizer can issue your certificate.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),

            // "Evaluate Now" button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentFeedbackScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Evaluate Now',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // "Maybe Later" button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Maybe Later',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
