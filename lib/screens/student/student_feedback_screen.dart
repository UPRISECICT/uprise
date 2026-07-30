// lib/screens/student/student_feedback_screen.dart
// SIMPLIFIED AND IMPROVED VERSION

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/student/app_colors.dart';
import '../../services/certificate_auto_issue_service.dart';

class StudentFeedbackScreen extends StatefulWidget {
  const StudentFeedbackScreen({super.key});

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 👇 KUNIN ANG STUDENT DOCUMENT PARA MAKUHA ANG STUDENT ID
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();

      String studentId = user.uid;
      if (studentDoc.exists) {
        final data = studentDoc.data() as Map<String, dynamic>;
        studentId = data['studentId']?.toString() ?? user.uid;
        print('✅ Using studentId: $studentId');
      } else {
        print('⚠️ No student document found, using UID: $studentId');
      }

      // 👇 GAMITIN ANG STUDENT ID SA PAGHAHANAP NG ATTENDANCE
      final attendanceSnap = await FirebaseFirestore.instance
          .collectionGroup('attendances')
          .where('studentId', isEqualTo: studentId)
          .get();

      print('📋 Attendance records found: ${attendanceSnap.docs.length}');

      // Get existing feedback
      final feedbackSnap = await FirebaseFirestore.instance
          .collection('event_feedback')
          .where('userId', isEqualTo: user.uid)
          .get();

      final ratedEventIds = feedbackSnap.docs
          .map((doc) => doc.data()['eventId']?.toString())
          .whereType<String>()
          .toSet();

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

        events.add({
          'eventId': eventRef.id,
          'eventName': eventData['title'] ?? 'Event',
          'organization': eventData['orgName'] ?? '',
          'orgId': eventData['orgId'] ?? '',
          'rated': ratedEventIds.contains(eventRef.id),
        });
      }

      // Sort: unrated events first
      events.sort((a, b) {
        if (a['rated'] == true && b['rated'] == false) return 1;
        if (a['rated'] == false && b['rated'] == true) return -1;
        return 0;
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
      await FirebaseFirestore.instance.collection('event_feedback').add({
        'eventId': event['eventId'],
        'eventName': event['eventName'],
        'organization': event['organization'],
        'orgId': event['orgId'],
        'rating': rating,
        'comment': comment.trim(),
        'userId': user.uid,
        'isAnonymous': isAnonymous,
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

  void _showFeedbackDialog(Map<String, dynamic> event) {
    int selectedRating = 0;
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

                  // Anonymous toggle
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setSheetState(() {
                      isAnonymous = !isAnonymous;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isAnonymous,
                            activeColor: AppColors.primaryDark,
                            onChanged: (v) => setSheetState(() {
                              isAnonymous = v ?? false;
                            }),
                          ),
                          Expanded(
                            child: Text(
                              'Submit anonymously (your name won\'t be shown to the organization)',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Feedback'),
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
          : _events.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadEvents,
              color: AppColors.primaryDark,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  final isRated = event['rated'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8ECF0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event['eventName'] ?? 'Event',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              if (event['organization'] != null &&
                                  event['organization'].isNotEmpty)
                                Text(
                                  event['organization'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (isRated)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '✅ Done',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF059669),
                              ),
                            ),
                          )
                        else
                          ElevatedButton(
                            onPressed: () => _showFeedbackDialog(event),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Evaluate',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.feedback_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No events to evaluate',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Once you attend an event, it will appear here for feedback.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}
