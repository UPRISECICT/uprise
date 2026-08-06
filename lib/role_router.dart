import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';
import 'services/push_notification_service.dart';
import 'screens/web/admin/admin_login.dart';
import 'screens/web/admin/admin_dashboard.dart';
import 'package:uprise/screens/web/org/org_dashboard.dart';
import 'screens/student/student_login.dart';
import 'screens/student/student_home_screen.dart';
import 'screens/student/student_change_password_screen.dart';

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final AuthService _auth = AuthService();
  late Stream<User?> _authStream;

  String? _cachedUid;
  Future<String?>? _roleFuture;

  @override
  void initState() {
    super.initState();
    _authStream = _auth.user;
  }

  Future<String?> _getRoleFuture(String uid) {
    if (_cachedUid != uid || _roleFuture == null) {
      _cachedUid = uid;
      _roleFuture = _auth.getUserRole(uid);
      // Piggybacks on the same per-uid caching as the role fetch so this
      // only fires once per signed-in session, not on every stream rebuild.
      PushNotificationService.register(uid);
    }
    return _roleFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData) {
          debugPrint('🔐 No user logged in');
          _cachedUid = null;
          _roleFuture = null;
          if (!kIsWeb) return const StudentLogin();
          return const AdminLogin();
        }

        final user = snapshot.data!;

        return FutureBuilder<String?>(
          future: _getRoleFuture(user.uid),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final String role =
                (roleSnapshot.data ?? 'guest').toLowerCase();
            debugPrint('📋 Role: $role');

            Widget screen;
            if (!kIsWeb) {
  // Mobile
  if (role == 'student') {
    screen = FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get(),
      builder: (context, userDocSnapshot) {
        if (userDocSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (userDocSnapshot.hasData &&
            userDocSnapshot.data!.docs.isNotEmpty) {
          final data = userDocSnapshot.data!.docs.first.data()
              as Map<String, dynamic>;
          final mustChange = data['mustChangePassword'] ?? false;
          final archived = data['archived'] == true;
          debugPrint(
              '📋 Student doc: $data, mustChangePassword: $mustChange, archived: $archived');

          // Checked here (not just at the login screen) so a session that
          // was already signed in when an admin archived the account also
          // gets bounced, instead of only blocking fresh sign-ins.
          if (archived) {
            return const WrongPlatformScreen(
              message: 'This account has been archived. Contact your administrator.',
              icon: Icons.lock_outline,
            );
          } else if (mustChange == true) {
            return const StudentChangePasswordScreen();
          } else {
            return const StudentHomeScreen();
          }
        } else {
          return const StudentHomeScreen();
        }
      },
    );
  } else if (role == 'admin') {
    screen = const WrongPlatformScreen(
      message: 'Admin accounts are only available on Web.',
      icon: Icons.computer,
    );
  } else if (role == 'org') {
    screen = const WrongPlatformScreen(
      message: 'Organization accounts are only available on Web.',
      icon: Icons.business,
    );
  } else {
    screen = const StudentLogin();
  }
} else {
              // Web
              if (role == 'admin') {
                screen = const AdminDashboard();
              } else if (role == 'org') {
                screen = OrgDashboard();
              } else if (role == 'student') {
                screen = const WrongPlatformScreen(
                  message:
                      'Student accounts are only available on Mobile.',
                  icon: Icons.phone_android,
                );
              } else {
                screen = const AdminLogin();
              }
            }

            return KeyedSubtree(
              key: ValueKey('${user.uid}-$role'),
              child: screen,
            );
          },
        );
      },
    );
  }
}

// ============ WrongPlatformScreen ============
class WrongPlatformScreen extends StatelessWidget {
  final String message;
  final IconData icon;
  const WrongPlatformScreen(
      {super.key, required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final AuthService auth = AuthService();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 70, color: Colors.orange),
              const SizedBox(height: 20),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const RoleRouter()),
                    );
                  }
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
