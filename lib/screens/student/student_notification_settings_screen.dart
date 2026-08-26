// lib/screens/student/student_notification_settings_screen.dart
//
// The notification switch turned out to be entirely role-agnostic — it is
// keyed on the Firebase Auth uid and writes `users/{uid}/settings/
// notifications`, which an approved guest has just as a student does. It now
// lives in screens/common so the guest settings screen can use the same one
// instead of a near-identical copy.
//
// This alias keeps the existing student import path working.

export '../common/notification_settings_screen.dart';

import 'package:flutter/material.dart';

import '../common/notification_settings_screen.dart';

/// Retained so `StudentNotificationSettingsScreen()` call sites still resolve.
class StudentNotificationSettingsScreen extends StatelessWidget {
  const StudentNotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotificationSettingsScreen();
}
