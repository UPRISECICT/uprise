// lib/screens/web/org/org_settings.dart
//
// NOTE: Embedded inside OrgDashboard's IndexedStack.
// No extra Scaffold or outer padding — dashboard provides background + topbar.
//
// Mirrors admin/settings.dart's layout and flow (Security → Audit Logs → …
// → Help), in the org palette. Signatories stays admin-only; Notifications
// is org-specific because NotificationService actually honors its toggle.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../theme/org_theme.dart';
import '../../../widgets/app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors admin/settings.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const Color brand = UpriseColors.primaryDark;
  static const Color error = UpriseColors.error;

  static const double radiusSm = 8;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration card({Color border = const Color(0xFFE8ECF0)}) =>
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: border),
        boxShadow: cardShadow,
      );

  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    bool required = false,
  }) {
    final labelTextStyle = GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF64748B),
    );
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: labelTextStyle,
                children: [
                  TextSpan(
                    text: ' *',
                    style: labelTextStyle.copyWith(color: error),
                  ),
                ],
              ),
            )
          : null,
      labelText: required ? null : label,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: const Color(0xFF9AA5B4))
          : null,
      labelStyle: labelTextStyle,
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF9AA5B4),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: _DS.brand),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _DS.brand,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

Widget _pageHeader(String title, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: GoogleFonts.beVietnamPro(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A202C),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          color: const Color(0xFF64748B),
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}

Widget _infoBanner(String text) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F6FF),
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      border: Border.all(color: const Color(0xFFBFD7FF)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: Color(0xFF2563EB),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF1D4ED8),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Centered, max-680 scrolling column shared by every tab.
class _TabScaffold extends StatelessWidget {
  final List<Widget> children;
  const _TabScaffold({required this.children});

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
            children: children,
          ),
        ),
      ),
    );
  }
}

class _AccountStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AccountStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _DS.brand.withAlpha(160)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10,
                    color: const Color(0xFF9AA5B4),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
  final String? orgLogoUrl;

  /// Runs the dashboard's own confirm-and-sign-out flow, so the Danger Zone
  /// button behaves exactly like the profile menu's "Sign Out".
  final VoidCallback? onSignOut;

  const OrgSettingsScreen({
    super.key,
    required this.orgId,
    required this.orgName,
    required this.orgShortName,
    required this.orgEmail,
    this.orgLogoUrl,
    this.onSignOut,
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
    _tabController = TabController(length: 4, vsync: this);
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
              labelColor: _DS.brand,
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: _DS.brand,
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
                Tab(text: 'Security'),
                Tab(text: 'Audit Logs'),
                Tab(text: 'Notifications'),
                Tab(text: 'Help'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SecurityTab(
                orgId: widget.orgId,
                orgName: widget.orgName,
                orgShortName: widget.orgShortName,
                orgEmail: widget.orgEmail,
                orgLogoUrl: widget.orgLogoUrl,
                onSignOut: widget.onSignOut,
              ),
              _AuditLogsTab(orgId: widget.orgId),
              _NotificationsTab(orgId: widget.orgId),
              const _HelpTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Security Tab
// ─────────────────────────────────────────────────────────────────────────────
class _SecurityTab extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String orgShortName;
  final String orgEmail;
  final String? orgLogoUrl;
  final VoidCallback? onSignOut;

  const _SecurityTab({
    required this.orgId,
    required this.orgName,
    required this.orgShortName,
    required this.orgEmail,
    this.orgLogoUrl,
    this.onSignOut,
  });

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

  // The login email lives on the Firebase Auth record; the organizations
  // doc's `email` field is often blank (which is why the old Profile tab
  // showed "—"), so it's only a fallback.
  String get _loginEmail {
    final authEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (authEmail.isNotEmpty) return authEmail;
    return widget.orgEmail.isNotEmpty ? widget.orgEmail : '—';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Unknown';
    return DateFormat('MMM d, y').format(dt);
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
        AppToast.success(
          context,
          'Verification link sent to $newEmail. Your login email updates once you confirm it there.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) AppToast.error(context, _authErrorMessage(e));
    } catch (e) {
      if (mounted) AppToast.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isChangingEmail = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isUpdating = true);
    try {
      await _reauthenticate(_currentPasswordCtrl.text.trim());
      await FirebaseAuth.instance.currentUser!.updatePassword(
        _newPasswordCtrl.text.trim(),
      );
      await activity_log.ActivityLogger.log(
        action: 'change_password',
        module: 'settings',
        severity: 'security',
        details: {'orgId': widget.orgId},
      );
      if (mounted) {
        AppToast.success(context, 'Password updated successfully');
        _currentPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) AppToast.error(context, _authErrorMessage(e));
    } catch (e) {
      if (mounted) AppToast.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _visibilityToggle(bool obscured, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: const Color(0xFF9AA5B4),
      ),
      tooltip: obscured ? 'Show Password' : 'Hide Password',
      onPressed: onPressed,
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _DS.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  Widget _logoFallback() {
    return Container(
      color: _DS.brand.withAlpha(20),
      alignment: Alignment.center,
      child: widget.orgShortName.isNotEmpty
          ? Text(
              widget.orgShortName[0].toUpperCase(),
              style: GoogleFonts.beVietnamPro(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _DS.brand,
              ),
            )
          : Icon(
              Icons.groups_rounded,
              size: 26,
              color: _DS.brand.withAlpha(160),
            ),
    );
  }

  Widget _buildAccountCard() {
    final metadata = FirebaseAuth.instance.currentUser?.metadata;
    final logoUrl = widget.orgLogoUrl;
    final shortName = widget.orgShortName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _DS.card(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _DS.brand.withAlpha(60), width: 2),
                ),
                child: ClipOval(
                  child: logoUrl != null && logoUrl.isNotEmpty
                      ? Image.network(
                          logoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _logoFallback(),
                        )
                      : _logoFallback(),
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
                      _loginEmail,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _DS.brand.withAlpha(20),
                  borderRadius: BorderRadius.circular(_DS.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 13,
                      color: _DS.brand,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      shortName.isNotEmpty ? shortName : 'Organization',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _DS.brand,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AccountStatChip(
                  icon: Icons.calendar_today_rounded,
                  label: 'Member since',
                  value: _formatDate(metadata?.creationTime),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AccountStatChip(
                  icon: Icons.login_rounded,
                  label: 'Last sign-in',
                  value: _formatDate(metadata?.lastSignInTime),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'To update your logo, cover photo, or description, use My Profile '
            'from the account menu.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11.5,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _DS.card(),
      child: Form(
        key: _emailFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Change Email', icon: Icons.alternate_email_rounded),
            _infoBanner(
              'Current email: $_loginEmail. We\'ll send a verification link '
              'to the new address — your login email only changes once you '
              'confirm it there.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _DS.inputDecoration(
                'New Email',
                hint: 'e.g., org@cict.edu.ph',
                icon: Icons.alternate_email_rounded,
                required: true,
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Required';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                  return 'Enter a valid email address';
                }
                final current = FirebaseAuth.instance.currentUser?.email ?? '';
                if (value.toLowerCase() == current.toLowerCase()) {
                  return 'This is already your current email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailPasswordCtrl,
              obscureText: _obscureEmailPassword,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _DS
                  .inputDecoration(
                    'Current Password',
                    icon: Icons.password_rounded,
                    required: true,
                  )
                  .copyWith(
                    suffixIcon: _visibilityToggle(
                      _obscureEmailPassword,
                      () => setState(
                        () => _obscureEmailPassword = !_obscureEmailPassword,
                      ),
                    ),
                  ),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            _primaryButton(
              label: 'Send Verification Link',
              icon: Icons.send_rounded,
              busy: _isChangingEmail,
              onPressed: _changeEmail,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _DS.card(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Change Password', icon: Icons.lock_outline_rounded),
            _infoBanner(
              'Regularly updating your password keeps your account secure.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currentPasswordCtrl,
              obscureText: _obscureCurrent,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _DS
                  .inputDecoration(
                    'Current Password',
                    icon: Icons.password_rounded,
                    required: true,
                  )
                  .copyWith(
                    suffixIcon: _visibilityToggle(
                      _obscureCurrent,
                      () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPasswordCtrl,
              obscureText: _obscureNew,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _DS
                  .inputDecoration(
                    'New Password',
                    icon: Icons.lock_outline_rounded,
                    required: true,
                  )
                  .copyWith(
                    suffixIcon: _visibilityToggle(
                      _obscureNew,
                      () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 6) return 'Must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirm,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: _DS
                  .inputDecoration(
                    'Confirm New Password',
                    icon: Icons.lock_outline_rounded,
                    required: true,
                  )
                  .copyWith(
                    suffixIcon: _visibilityToggle(
                      _obscureConfirm,
                      () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v != _newPasswordCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 20),
            _primaryButton(
              label: 'Update Password',
              icon: Icons.update_rounded,
              busy: _isUpdating,
              onPressed: _updatePassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _DS.card(border: const Color(0xFFFCA5A5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(width: 8),
              Text(
                'Danger Zone',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Divider(color: Color(0xFFFCA5A5), thickness: 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: Text(
              'Sign Out',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_DS.radiusSm),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TabScaffold(
      children: [
        _pageHeader(
          'Account Security',
          'Keep your login credentials current and protected.',
        ),
        _buildAccountCard(),
        const SizedBox(height: 20),
        _buildEmailCard(),
        const SizedBox(height: 20),
        _buildPasswordCard(),
        if (widget.onSignOut != null) ...[
          const SizedBox(height: 20),
          _buildDangerZone(),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audit Logs Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AuditLogsTab extends StatelessWidget {
  final String orgId;
  const _AuditLogsTab({required this.orgId});

  static const Map<String, (Color, Color)> _severityStyles = {
    'info': (Color(0xFFEFF6FF), Color(0xFF2563EB)),
    'security': (Color(0xFFFFF7ED), Color(0xFFC2410C)),
    'warning': (Color(0xFFFFFBEB), Color(0xFFFB923C)),
    'error': (Color(0xFFFEF2F2), Color(0xFFDC2626)),
    'critical': (Color(0xFFFDF2F8), Color(0xFF9333EA)),
  };

  // Org-side logs use snake_case action keys (e.g. "change_password");
  // show them as readable sentences without changing what gets stored.
  static String _humanize(String raw) {
    if (!raw.contains('_') || raw.contains(' ')) return raw;
    final words = raw.split('_').where((w) => w.isNotEmpty).join(' ');
    return words.isEmpty ? raw : words[0].toUpperCase() + words.substring(1);
  }

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _pill(String text, Color bg, Color fg, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          dot ? _DS.radiusPill : _DS.radiusSm,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.beVietnamPro(
                fontSize: dot ? 10 : 11,
                fontWeight: dot ? FontWeight.w700 : FontWeight.w600,
                color: fg,
                letterSpacing: dot ? 0.6 : 0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String subtitle, {
    bool isError = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 36,
                color: isError
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF9AA5B4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final width = MediaQuery.of(context).size.width;
    final hPad = width < 720 ? 16.0 : 28.0;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // orgId + timestamp is an existing composite index; filtering by the
      // acting user happens client-side so no new index is needed.
      stream: FirebaseFirestore.instance
          .collection('activity_logs')
          .where('orgId', isEqualTo: orgId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _emptyState(
            Icons.error_outline_rounded,
            'Error loading logs',
            '${snap.error}',
            isError: true,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snap.data!.docs
            .map((d) => d.data())
            .where((d) => d['user'] == email)
            .take(20)
            .toList();

        if (logs.isEmpty) {
          return _emptyState(
            Icons.history_rounded,
            'No recent activity',
            'Actions you perform will appear here.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 12),
              child: Row(
                children: [
                  Text(
                    'Your Recent Actions',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _pill(
                    '${logs.length} entries',
                    _DS.brand.withAlpha(20),
                    _DS.brand,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: hPad),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE8ECF0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: _headerCell('ACTION')),
                          Expanded(flex: 3, child: _headerCell('MODULE')),
                          Expanded(flex: 2, child: _headerCell('SEVERITY')),
                          Expanded(flex: 3, child: _headerCell('TIMESTAMP')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final data = logs[i];
                          final ts = (data['timestamp'] as Timestamp?)
                              ?.toDate();
                          final severity = (data['severity'] ?? 'info')
                              .toString()
                              .toLowerCase();
                          final module = _humanize(
                            (data['module'] ?? 'System').toString(),
                          );
                          final action = _humanize(
                            (data['action'] ?? '—').toString(),
                          );
                          final sev =
                              _severityStyles[severity] ??
                              (
                                const Color(0xFFF3F4F6),
                                const Color(0xFF6B7280),
                              );
                          final isLast = i == logs.length - 1;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : const Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFF1F5F9),
                                      ),
                                    ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    action,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      color: const Color(0xFF374151),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _pill(
                                      module,
                                      const Color(0xFFF3F4F6),
                                      const Color(0xFF4B5563),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _pill(
                                      severity.toUpperCase(),
                                      sev.$1,
                                      sev.$2,
                                      dot: true,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: ts != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat(
                                                'MMM dd, yyyy',
                                              ).format(ts),
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF374151),
                                              ),
                                            ),
                                            Text(
                                              DateFormat('hh:mm a').format(ts),
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11,
                                                color: const Color(0xFF9AA5B4),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          '—',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 12,
                                            color: const Color(0xFF9AA5B4),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFE8ECF0)),
                        ),
                        color: Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Showing your last ${logs.length} actions on this account.',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: const Color(0xFF9AA5B4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Tab
// ─────────────────────────────────────────────────────────────────────────────
// NotificationService gates every send (registrations, proposal decisions,
// letter requests, broadcasts, etc.) behind
// users/{uid}/settings/notifications#push_notifications — turning this off
// makes the service skip creating notifications for this account.
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
      if (mounted) AppToast.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TabScaffold(
      children: [
        _pageHeader(
          'Notifications',
          'Control what this account gets notified about.',
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: _DS.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'In-App Notifications',
                icon: Icons.notifications_none_rounded,
              ),
              _infoBanner(
                'Covers new registrations, proposal decisions, letter '
                'requests, student messages, and more. When muted, new '
                'notifications for this account are not created — '
                'existing ones stay in your inbox.',
              ),
              const SizedBox(height: 16),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _prefsDoc.snapshots(),
                builder: (context, snap) {
                  final enabled =
                      (snap.data?.data()?['push_notifications'] as bool?) ??
                      true;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      border: Border.all(
                        color: enabled
                            ? _DS.brand.withAlpha(77)
                            : const Color(0xFFE2E6EA),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: enabled
                                ? _DS.brand.withAlpha(26)
                                : const Color(0xFFE8ECF0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            enabled
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_off_outlined,
                            size: 18,
                            color: enabled
                                ? _DS.brand
                                : const Color(0xFF9AA5B4),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'In-app notifications',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
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
                                  fontSize: 11,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Switch(
                            value: enabled,
                            activeThumbColor: _DS.brand,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Help Tab
// ─────────────────────────────────────────────────────────────────────────────
class _NavGuideEntry {
  final IconData icon;
  final String title;
  final String description;
  const _NavGuideEntry(this.icon, this.title, this.description);
}

class _FaqEntry {
  final String question;
  final String answer;
  const _FaqEntry(this.question, this.answer);
}

class _TermsSection {
  final String title;
  final String body;
  const _TermsSection(this.title, this.body);
}

class _HelpTab extends StatelessWidget {
  const _HelpTab();

  static const _navGuide = [
    _NavGuideEntry(
      Icons.dashboard_outlined,
      'Dashboard',
      'At-a-glance stats for your organization — events, pending proposals, '
          'upcoming events, and merchandise, each exportable from its panel.',
    ),
    _NavGuideEntry(
      Icons.forum_outlined,
      'Communication',
      'Post announcements to students and reply to their private messages.',
    ),
    _NavGuideEntry(
      Icons.event_note_outlined,
      'Events & Requests',
      'Submit event proposals, publish approved events, build registration '
          'forms, and send official letter requests to the admin.',
    ),
    _NavGuideEntry(
      Icons.bar_chart_outlined,
      'Event Analytics',
      'Registration, attendance, and feedback trends across your events.',
    ),
    _NavGuideEntry(
      Icons.summarize_outlined,
      'Reports',
      'Upload the financial and accomplishment report for each event '
          'before the semester deadline.',
    ),
    _NavGuideEntry(
      Icons.fact_check_outlined,
      'Attendance & Certificates',
      'Scan attendee QR codes at the event, then issue certificates to '
          'attendees who have submitted feedback.',
    ),
    _NavGuideEntry(
      Icons.storefront_outlined,
      'Finance & Merch',
      'Track your organization\'s finances and manage the merchandise '
          'catalog students see.',
    ),
    _NavGuideEntry(
      Icons.settings_outlined,
      'Settings',
      'Security, your audit log, notification preferences, and this Help '
          'section all live here.',
    ),
  ];

  static const _faqs = [
    _FaqEntry(
      'How does an event go from proposal to published?',
      'Submit it under Event Proposals. Once the admin approves it, open '
          'Events & Schedules and publish it — only then do students see it '
          'and can register.',
    ),
    _FaqEntry(
      'Why can\'t I issue a certificate to some attendees yet?',
      'Certificates aren\'t generated automatically at QR check-in. An '
          'attendee must first submit their feedback for that event; after '
          'that, you can issue their certificate from the Certificates page. '
          'Each one gets a unique code anyone can check at the public '
          'verification page.',
    ),
    _FaqEntry(
      'I changed my email in Settings but it still shows the old one.',
      'That\'s expected. Your login email only changes after you click the '
          'verification link sent to the new address — until then, this '
          'page keeps showing your current, still-active email.',
    ),
    _FaqEntry(
      'How do I change our logo, cover photo, or description?',
      'Open the account menu at the top right and choose My Profile. '
          'Settings only covers login and account security.',
    ),
    _FaqEntry(
      'I muted notifications — will I miss anything?',
      'While muted, new in-app notifications for this account aren\'t '
          'created, so you won\'t see them later either. Turn them back on '
          'under the Notifications tab anytime.',
    ),
    _FaqEntry(
      'When are reports due?',
      'Deadlines follow the academic semester — 1st Semester (Aug–Jan), '
          '2nd Semester (Feb–Jun), and Summer (Jun–Aug) — and are set by the '
          'admin. Check the Reports page for the current deadlines.',
    ),
    _FaqEntry(
      'I forgot my password or my account is locked.',
      'Contact the CICT admin office. They manage organization accounts '
          'and can help you regain access.',
    ),
  ];

  static const _terms = [
    _TermsSection(
      '1. Acceptance of Use',
      'This portal is provided to recognized CICT student organizations. '
          'Signing in means you agree to use it only for official '
          'organization activities within the college.',
    ),
    _TermsSection(
      '2. Account Responsibility',
      'The organization account is shared by its officers, and they are '
          'responsible for keeping its credentials confidential and for all '
          'actions taken under it. Change the password from the Security tab '
          'when officers turn over or if the account may be compromised.',
    ),
    _TermsSection(
      '3. Data Privacy & Confidentiality',
      'Student information you access here — registrations, attendance, '
          'feedback, messages — is handled in line with the Data Privacy Act '
          'of 2012 (Republic Act No. 10173). Use it only for your '
          'organization\'s legitimate activities, and never share it with '
          'unauthorized parties.',
    ),
    _TermsSection(
      '4. Activity Logging',
      'Significant actions in this portal are recorded in the audit trail '
          'with the acting account, timestamp, and module, and are visible '
          'to CICT administrators.',
    ),
    _TermsSection(
      '5. Events, Reports & Certificates',
      'Publish only events that have been approved, submit accurate '
          'financial and accomplishment reports, and issue certificates only '
          'through the attendance-and-feedback workflow.',
    ),
    _TermsSection(
      '6. Changes to These Terms',
      'These terms may be updated as the system evolves. Continued use '
          'after an update means you accept the revised terms.',
    ),
  ];

  Widget _card(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: _DS.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return _TabScaffold(
      children: [
        _pageHeader(
          'Help & Resources',
          'How to get around the organization portal, answers to common '
              'questions, and the terms governing this system.',
        ),
        _card([
          _sectionLabel(
            'Navigating the Organization Portal',
            icon: Icons.explore_outlined,
          ),
          for (var i = 0; i < _navGuide.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _NavGuideRow(entry: _navGuide[i]),
          ],
        ]),
        const SizedBox(height: 20),
        _card([
          _sectionLabel(
            'Frequently Asked Questions',
            icon: Icons.help_outline_rounded,
          ),
          for (var i = 0; i < _faqs.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _FaqTile(entry: _faqs[i]),
          ],
        ]),
        const SizedBox(height: 20),
        _card([
          _sectionLabel('Terms & Conditions', icon: Icons.gavel_outlined),
          Text(
            'This portal handles your organization\'s events and your '
            'members\' data. By signing in, you agree to use it only for '
            'official organization purposes and to keep student data '
            'confidential.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: const Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _TermsDialog(sections: _terms),
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(
              'View Full Terms & Conditions',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _DS.brand,
              side: BorderSide(color: _DS.brand.withAlpha(90)),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_DS.radiusSm),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

class _NavGuideRow extends StatelessWidget {
  final _NavGuideEntry entry;
  const _NavGuideRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _DS.brand.withAlpha(15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(entry.icon, size: 17, color: _DS.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.description,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final _FaqEntry entry;
  const _FaqTile({required this.entry});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(
          color: _expanded ? _DS.brand.withAlpha(70) : const Color(0xFFE8ECF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entry.question,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: _DS.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.entry.answer,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _TermsDialog extends StatelessWidget {
  final List<_TermsSection> sections;
  const _TermsDialog({required this.sections});

  @override
  Widget build(BuildContext context) {
    // Re-centers within the content pane when the dashboard's persistent
    // sidebar is showing (same approach as admin/settings.dart).
    final hasPersistentSidebar = MediaQuery.of(context).size.width >= 900;
    final insetPadding = hasPersistentSidebar
        ? const EdgeInsets.only(left: 296, right: 40, top: 24, bottom: 24)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24);

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_DS.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Terms & Conditions',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: const Color(0xFF64748B),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CICT Organization Management System — provided for '
                      'internal reference within the organization portal.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                    for (final s in sections) ...[
                      const SizedBox(height: 18),
                      Text(
                        s.title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _DS.brand,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.body,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          color: const Color(0xFF374151),
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _DS.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
