// lib/screens/web/org/org_settings.dart
//
// NOTE: Embedded inside OrgDashboard's IndexedStack.
// No extra Scaffold or outer padding — dashboard provides background + topbar.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../theme/org_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors merchandise & student accounts)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: const Color(0xFF9AA5B4))
          : null,
      suffixIcon: suffix,
      labelStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF64748B),
      ),
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF9AA5B4),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main embedded screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgSettingsScreen extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgShortName;
  final String orgEmail;

  const OrgSettingsScreen({
    super.key,
    required this.orgId,
    required this.orgName,
    required this.orgShortName,
    required this.orgEmail,
  });

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 720 ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tab bar — plain underline style, matching admin/settings.dart
        // instead of the rounded-pill look this used before.
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: UpriseColors.primaryDark,
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: UpriseColors.primaryDark,
              indicatorWeight: 2.5,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Notifications'),
                Tab(text: 'Security'),
              ],
            ),
          ),
        ),

        // ── Tab views ────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ProfileTab(
                orgId: widget.orgId,
                orgName: widget.orgName,
                orgShortName: widget.orgShortName,
                orgEmail: widget.orgEmail,
              ),
              _NotificationsTab(orgId: widget.orgId),
              _SecurityTab(orgId: widget.orgId, orgName: widget.orgName),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Tab
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final String orgId;
  final String orgName, orgShortName, orgEmail;
  const _ProfileTab({
    required this.orgId,
    required this.orgName,
    required this.orgShortName,
    required this.orgEmail,
  });

  // Was a bare label-above-value text stack, no icon or background — the
  // one plain part of this tab next to the card that frames it. Matches
  // the icon-tagged detail-row pattern (OrgDetailItem) used everywhere
  // else this info-display shape appears in the app.
  Widget _infoRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(28),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 13, color: UpriseColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9AA5B4),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isNotEmpty ? value : '—',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 720 ? 16.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Organization Settings',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Your organization's basic account information.",
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organization Information',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'To update your logo, cover photo, or description, use the Profile page.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _infoRow(
                      'Organization Name',
                      orgName,
                      Icons.apartment_outlined,
                    ),
                    _infoRow(
                      'Short Name',
                      orgShortName,
                      Icons.short_text_rounded,
                    ),
                    _infoRow('Email Address', orgEmail, Icons.email_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Tab
// ─────────────────────────────────────────────────────────────────────────────
// NotificationService already gates every send (registrations, proposal
// decisions, letter requests, broadcasts, etc.) behind
// users/{uid}/settings/notifications#push_notifications — but until now no
// screen anywhere wrote to that doc, so orgs had no way to actually mute it.
class _NotificationsTab extends StatefulWidget {
  final String orgId;
  const _NotificationsTab({required this.orgId});

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _prefsDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications');
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      await _prefsDoc.set({
        'push_notifications': value,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 720 ? 16.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Control what this account gets notified about.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'In-App Notifications',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Control the in-app notifications this account receives — '
                      'new registrations, proposal decisions, letter requests, '
                      'student broadcasts, and more.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 20),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _prefsDoc.snapshots(),
                      builder: (context, snap) {
                        final enabled =
                            (snap.data?.data()?['push_notifications']
                                as bool?) ??
                            true;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE8ECF0)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                enabled
                                    ? Icons.notifications_active_outlined
                                    : Icons.notifications_off_outlined,
                                size: 20,
                                color: enabled
                                    ? UpriseColors.primaryDark
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'In-app notifications',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF1A202C),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      enabled
                                          ? 'You\'ll be notified of new activity involving your organization.'
                                          : 'Notifications are muted for this account.',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_saving)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Switch(
                                  value: enabled,
                                  activeThumbColor: UpriseColors.primaryDark,
                                  onChanged: _setEnabled,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Security Tab
// ─────────────────────────────────────────────────────────────────────────────
class _SecurityTab extends StatefulWidget {
  final String orgId;
  final String orgName;
  const _SecurityTab({required this.orgId, required this.orgName});

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _isUpdating = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final _emailFormKey = GlobalKey<FormState>();
  final _newEmailCtrl = TextEditingController();
  final _emailPasswordCtrl = TextEditingController();
  bool _obscureEmailPassword = true;
  bool _isChangingEmail = false;

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _newEmailCtrl.dispose();
    _emailPasswordCtrl.dispose();
    super.dispose();
  }

  // Sensitive Firebase Auth operations (password/email changes) fail with
  // requires-recent-login if the session is more than a few minutes old —
  // reauthenticating up front means the form succeeds on the first try
  // instead of failing partway through with a cryptic error.
  Future<void> _reauthenticate(String currentPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-current-email',
        message: 'No email on this account to reauthenticate with.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect.';
      case 'requires-recent-login':
        return 'Please sign out and sign back in, then try again.';
      case 'email-already-in-use':
        return 'That email is already in use by another account.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return e.message ?? 'Something went wrong (${e.code}).';
    }
  }

  // Uses verifyBeforeUpdateEmail (not the deprecated updateEmail) — Firebase
  // requires the new address to be verified via an emailed link before the
  // login email actually changes, so the auth email and the address typed
  // here diverge until that link is clicked. The `users` doc's email mirror
  // is deliberately left untouched until then, matching the admin flow.
  Future<void> _changeEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final newEmail = _newEmailCtrl.text.trim();
    setState(() => _isChangingEmail = true);
    try {
      await _reauthenticate(_emailPasswordCtrl.text.trim());
      await FirebaseAuth.instance.currentUser!.verifyBeforeUpdateEmail(
        newEmail,
      );
      await activity_log.ActivityLogger.log(
        action: 'request_email_change',
        module: 'settings',
        severity: 'security',
        details: {'orgId': widget.orgId, 'newEmail': newEmail},
      );
      if (mounted) {
        _newEmailCtrl.clear();
        _emailPasswordCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification link sent to $newEmail. Your login email '
              'updates once you confirm it there.',
            ),
            backgroundColor: UpriseColors.success,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_authErrorMessage(e)),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingEmail = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordCtrl.text.trim(),
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordCtrl.text.trim());
      await activity_log.ActivityLogger.log(
        action: 'change_password',
        module: 'settings',
        severity: 'security',
        details: {'orgId': widget.orgId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully'),
            backgroundColor: UpriseColors.success,
          ),
        );
        _currentPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 720 ? 16.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account Security',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Keep your login credentials current and protected.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),

              // Account identity card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: UpriseColors.primaryDark.withAlpha(20),
                        border: Border.all(
                          color: UpriseColors.primaryDark.withAlpha(60),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        size: 26,
                        color: UpriseColors.primaryDark.withAlpha(160),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.orgName.isNotEmpty
                                ? widget.orgName
                                : 'Organization',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A202C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            FirebaseAuth.instance.currentUser?.email ?? '—',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Password change card
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password & Security',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update your password regularly to keep your account secure.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _currentPasswordCtrl,
                            obscureText: _obscureCurrent,
                            decoration: _DS.inputDecoration(
                              'Current Password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureCurrent
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                                tooltip: _obscureCurrent
                                    ? 'Show Password'
                                    : 'Hide Password',
                                onPressed: () => setState(
                                  () => _obscureCurrent = !_obscureCurrent,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _newPasswordCtrl,
                            obscureText: _obscureNew,
                            decoration: _DS.inputDecoration(
                              'New Password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureNew
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                                tooltip: _obscureNew
                                    ? 'Show Password'
                                    : 'Hide Password',
                                onPressed: () =>
                                    setState(() => _obscureNew = !_obscureNew),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (v.length < 6) {
                                return 'Must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordCtrl,
                            obscureText: _obscureConfirm,
                            decoration: _DS.inputDecoration(
                              'Confirm New Password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                                tooltip: _obscureConfirm
                                    ? 'Show Password'
                                    : 'Hide Password',
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            validator: (v) => v != _newPasswordCtrl.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isUpdating ? null : _updatePassword,
                              icon: _isUpdating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline, size: 16),
                              label: Text(
                                'Update Password',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: UpriseColors.primaryDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
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

              // Change email card
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Login Email',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current: ${FirebaseAuth.instance.currentUser?.email ?? '—'}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _emailFormKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _newEmailCtrl,
                            decoration: _DS.inputDecoration('New Email'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final ok = RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(v.trim());
                              return ok ? null : 'Enter a valid email address';
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailPasswordCtrl,
                            obscureText: _obscureEmailPassword,
                            decoration: _DS.inputDecoration(
                              'Current Password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureEmailPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                                tooltip: _obscureEmailPassword
                                    ? 'Show Password'
                                    : 'Hide Password',
                                onPressed: () => setState(
                                  () => _obscureEmailPassword =
                                      !_obscureEmailPassword,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We\'ll email a verification link to the new address — '
                            'your login email only updates once you confirm it there.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11.5,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isChangingEmail ? null : _changeEmail,
                              icon: _isChangingEmail
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.mail_outline_rounded,
                                      size: 16,
                                    ),
                              label: Text(
                                'Change Email',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: UpriseColors.primaryDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
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

              // Recent security activity card
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Security Activity',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot>(
                      // Filtered by orgId (matches the existing orgId+timestamp
                      // composite index) instead of user+severity, which has no
                      // index and previously made this query fail silently and
                      // spin forever.
                      stream: FirebaseFirestore.instance
                          .collection('activity_logs')
                          .where('orgId', isEqualTo: widget.orgId)
                          .orderBy('timestamp', descending: true)
                          .limit(50)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Could not load security activity',
                                style: GoogleFonts.beVietnamPro(
                                  color: UpriseColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final currentEmail =
                            FirebaseAuth.instance.currentUser?.email ?? '';
                        final docs = snap.data!.docs
                            .where((d) {
                              final data = d.data() as Map<String, dynamic>;
                              return data['user'] == currentEmail &&
                                  data['severity'] == 'security';
                            })
                            .take(10)
                            .toList();
                        if (docs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No security activity recorded',
                                style: GoogleFonts.beVietnamPro(
                                  color: const Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final data = docs[i].data() as Map<String, dynamic>;
                            final action = data['action'] ?? 'Unknown action';
                            final timestamp =
                                (data['timestamp'] as Timestamp?)?.toDate() ??
                                DateTime.now();
                            final details =
                                data['details'] as Map<String, dynamic>?;
                            final location =
                                details?['location'] ?? 'Unknown location';
                            return ListTile(
                              leading: const Icon(
                                Icons.security,
                                color: UpriseColors.info,
                                size: 20,
                              ),
                              title: Text(
                                action,
                                style: GoogleFonts.beVietnamPro(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                '$location • ${DateFormat('MMM dd, yyyy h:mm a').format(timestamp)}',
                                style: GoogleFonts.beVietnamPro(fontSize: 11),
                              ),
                              trailing: const Icon(
                                Icons.devices,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
