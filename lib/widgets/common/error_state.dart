// lib/widgets/common/error_state.dart
//
// "Couldn't load this" + Retry.
//
// From guest's `_ErrorView`. Nothing shared existed: the student side builds a
// Retry button by hand in student_announcements_screen, student_certificates_
// screen and student_notifications_screen, each with its own wording, icon and
// button styling. This is the one of them worth keeping.
//
// [detail] is the raw error string. It's rendered small and grey underneath
// the headline rather than hidden, because these failures are usually a
// missing Firestore composite index during development, and the index-creation
// URL is in that text.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

class ErrorStateView extends StatelessWidget {
  /// What failed, in the caller's words — e.g. "Could not load events".
  final String title;

  /// The underlying error, shown small. Omit to show only the headline.
  final String? detail;

  final VoidCallback onRetry;
  final IconData icon;

  const ErrorStateView({
    super.key,
    required this.title,
    required this.onRetry,
    this.detail,
    this.icon = Icons.cloud_off_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
