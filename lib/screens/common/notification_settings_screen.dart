// lib/screens/common/notification_settings_screen.dart
//
// The in-app notification switch, shared by students and guests.
//
// The enforcement half of this already existed:
// NotificationService._isEnabledFor reads
// `users/{uid}/settings/notifications` → `push_notifications` and skips the
// write when it's false, defaulting to enabled when the doc is absent. Until
// now only the org portal (org_settings.dart `_NotificationsTab`) ever wrote
// that doc, so neither students nor guests could mute anything.
//
// Nothing here is role-specific: it is keyed purely on the Firebase Auth uid,
// and an approved guest has a real `users/{uid}` doc (role: 'guest') just as
// a student does. That's why this is one screen rather than two.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/shared/app_support.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? get _prefsDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications');
  }

  Future<void> _setEnabled(bool value) async {
    final doc = _prefsDoc;
    if (doc == null) return;
    setState(() => _saving = true);
    try {
      // merge so this never clobbers other keys the org portal may add.
      await doc.set({'push_notifications': value}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _prefsDoc;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const StudentAppBar(title: 'Notifications'),
      body: doc == null
          ? const Center(child: Text('You need to be signed in.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: doc.snapshots(),
              builder: (context, snap) {
                // Absent doc means "never configured", which is enabled —
                // matching the default in NotificationService.
                final enabled =
                    (snap.data?.data()?['push_notifications'] as bool?) ?? true;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: SwitchListTile(
                        value: enabled,
                        onChanged: _saving ? null : _setEnabled,
                        activeThumbColor: AppColors.primaryDark,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        title: const Text(
                          'In-app notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Event reminders, announcements, registration '
                          'updates and certificates',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        enabled
                            ? 'You\'ll keep receiving notifications in the app.'
                            : 'New notifications won\'t be delivered while '
                                  'this is off. Anything already in your '
                                  'notifications list stays there.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // System-level permission is separate from the in-app
                    // switch above, so point at the OS settings too.
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Icon(
                          Icons.phone_android_outlined,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                        title: const Text(
                          'System notification settings',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Manage this app\'s permissions on your device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        trailing: const Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () => openNotificationSettings(context),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
