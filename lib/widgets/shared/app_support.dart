import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_settings/app_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../screens/student/student_change_password_screen.dart';

const String kSupportEmailPrimary = 'cictuprise@gmail.com';
const String kSupportEmailSecondary = 'cictuprise@outlook.com';

Future<void> launchSupportEmail(
  BuildContext context, {
  required String subject,
}) async { /* unchanged */ }

Future<void> openNotificationSettings(BuildContext context) async { /* unchanged */ }

Future<String> getAppVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}+${info.buildNumber}';
}

// ─────────────────────────────────────────────────────────────
// NEW: About Screen — shows version + privacy policy
// ─────────────────────────────────────────────────────────────
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    getAppVersionLabel().then((v) {
      if (mounted) setState(() => _appVersion = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black87,
        title: const Text('About',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Image.asset('assets/images/logo.png', width: 48, height: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('UPRISE',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('BulSU CICT Event Management',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD93B21).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_appVersion,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD93B21))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _policySection('What we collect', [
            'Your name and email address, used to sign in and identify you.',
            'Your course, year level, and student ID, used for attendance and certificate records.',
            'Event registrations, attendance records, and certificates earned through UPRISE.',
            'Answers you submit on event registration forms.',
          ]),
          _policySection('How it\'s stored', [
            'All data is stored in Firebase (Firestore database and Firebase Authentication), operated for BulSU CICT.',
            'Profile photos and signatures are stored as part of your account record and are only shown to you, the organization running an event you registered for, and CICT admins.',
          ]),
          _policySection('Who can see it', [
            'Admins and the organization hosting an event you registered for can see your registration, attendance, and certificate data for that event.',
            'Other students and guests cannot see your personal data.',
          ]),
          _policySection('Your controls', [
            'You can change your password from the Privacy & Security screen.',
            'To request data correction or deletion, contact CICT UPRISE support.',
          ]),
        ],
      ),
    );
  }

  Widget _policySection(String title, List<String> points) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withAlpha(15),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
          const SizedBox(height: 10),
          ...points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                            color: Colors.grey, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(
                      child: Text(p,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REDESIGNED Privacy & Security Screen — actionable settings
// ─────────────────────────────────────────────────────────────
class PrivacySecurityScreen extends StatelessWidget {
  final bool isGuest;
  const PrivacySecurityScreen({super.key, this.isGuest = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black87,
        title: const Text('Privacy & Security',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isGuest) ...[
            _settingsTile(
              icon: Icons.lock_outline,
              title: 'Change Password',
              subtitle: 'Update your account password',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StudentChangePasswordScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _settingsTile(
              icon: Icons.fingerprint,
              title: 'Two-Factor Authentication',
              subtitle: 'Coming soon',
              trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('2FA will be available in a future update')),
                );
              },
            ),
            const SizedBox(height: 8),
            _settingsTile(
              icon: Icons.devices_outlined,
              title: 'Active Sessions',
              subtitle: 'Manage devices where you\'re signed in',
              trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              onTap: () {
                // TODO: navigate to session management
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Session management coming soon')),
                );
              },
            ),
            const SizedBox(height: 8),
            _settingsTile(
              icon: Icons.download_outlined,
              title: 'Download My Data',
              subtitle: 'Export your profile and event history',
              trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              onTap: () {
                // TODO: implement data export
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data export coming soon')),
                );
              },
            ),
            const SizedBox(height: 8),
            _settingsTile(
              icon: Icons.delete_outline,
              title: 'Delete Account',
              subtitle: 'Permanently remove your data',
              trailing: const Icon(Icons.chevron_right, color: Colors.red, size: 20),
              onTap: () {
                // TODO: show deletion confirmation flow
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account deletion is not yet supported')),
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
          ] else
            const SizedBox(height: 8),
          // For guests we still show a minimal explanation
          if (isGuest)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'As a guest, you do not have a permanent account. '
                'No personal data is retained beyond your event participation.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          // Link to full privacy policy (in About)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Read how we handle your data'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  // Helper for consistent tile styling (same as Settings)
  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFD93B21).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFFD93B21), size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: trailing ?? const SizedBox.shrink(),
        onTap: onTap,
      ),
    );
  }
}