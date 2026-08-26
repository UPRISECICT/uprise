// lib/screens/guest/guest_settings_screen.dart
//
// GUEST SETTINGS — promoted out of guest_profile_screen.dart so it can be
// reached from the new Profile Menu Hub. Adds a voluntary Change Password
// entry on top of the original Notifications/Privacy/Help/About tiles.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'guest_access_gateway_screen.dart' show GuestChangePasswordScreen;
import '../../widgets/shared/app_support.dart';
import '../common/notification_settings_screen.dart';
import '../../services/guest_data_export.dart';
import '../../widgets/common/action_tile.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';

const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;
const _kSuccess = AppColors.success;
const _kSuccessBg = AppColors.successBg;

class GuestSettingsScreen extends StatelessWidget {
  final String fullName;
  final String email;
  final String school;
  final String docId;
  final VoidCallback onLogout;

  const GuestSettingsScreen({
    super.key,
    required this.fullName,
    required this.email,
    required this.school,
    required this.docId,
    required this.onLogout,
  });

  String get _initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : 'G';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Settings'),
      // Same shape as the student Settings screen: a shadowed profile card,
      // then uppercase section labels over runs of kActionTile rows. The old
      // layout was full-bleed white blocks divided by hairlines, which is why
      // the two screens read as different products.
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile card ────────────────────────────────
            Container(
              margin: const EdgeInsets.all(16),
              decoration: kCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kOrangeLight,
                        border: Border.all(color: _kOrange.withAlpha(51), width: 2),
                      ),
                      child: Center(
                        child: Text(_initials,
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 22, fontWeight: FontWeight.w900, color: _kOrange)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
                          const SizedBox(height: 2),
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey[600])),
                          if (school.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(school,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                          ],
                          const SizedBox(height: 6),
                          // Sits where the student card puts its edit button —
                          // a guest has nothing to edit here, but does have a
                          // verification state worth showing.
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: _kSuccessBg, borderRadius: BorderRadius.circular(20)),
                            child: Text('VERIFIED GUEST',
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _kSuccess,
                                    letterSpacing: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Account settings ─────────────────────────────
            kSectionLabel('Account Settings'),
            kActionTile(
              icon: Icons.lock_outline_rounded,
              title: 'Change Password',
              subtitle: 'Update your account password',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GuestChangePasswordScreen(
                    uid: uid,
                    docId: docId,
                    forced: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            kActionTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Choose what reaches you',
              // Was a straight jump to the OS settings, which could only
              // turn the app off wholesale. Approved guests have a
              // users/{uid} doc, so they get the same in-app switch
              // students do — the OS shortcut lives inside it now.
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 8),

            kActionTile(
              icon: Icons.shield_outlined,
              title: 'Privacy & Security',
              subtitle: 'Manage your security preferences',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Reached only from the approved-guest profile, so
                    // this guest does have records to export.
                    builder: (_) => PrivacySecurityScreen(
                      isGuest: true,
                      onExportData: () => exportGuestData(context),
                    ),
                  ),
                );
              },
            ),

            // ── Support ──────────────────────────────────────
            kSectionLabel('Support'),
            kActionTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              subtitle: 'Get assistance and FAQs',
              onTap: () => launchSupportEmail(context, subject: 'UPRISE Support Request'),
            ),
            const SizedBox(height: 8),

            kActionTile(
              icon: Icons.feedback_outlined,
              title: 'Send Feedback',
              subtitle: 'Help us improve the app',
              onTap: () => launchSupportEmail(context, subject: 'UPRISE Feedback'),
              iconColor: Colors.purple,
            ),
            const SizedBox(height: 8),

            kActionTile(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App info & privacy policy',
              // Was a no-op — the row looked tappable but did nothing.
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              trailing: FutureBuilder<String>(
                future: getAppVersionLabel(),
                builder: (context, snap) => Text(
                  snap.data ?? '...',
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Logout ──────────────────────────────────────
            // Student Settings owns its confirm dialog because its logout is
            // direct. Guest's [onLogout] is the profile screen's
            // _confirmLogout, which already asks — so this only adopts the
            // red full-width button, not a second prompt.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // close settings first
                  onLogout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
