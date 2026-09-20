import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/file_validation.dart';
import '../../../widgets/app_toast.dart';
import 'admin_login.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Activity Logger
// ─────────────────────────────────────────────────────────────────────────────
class ActivityLogger {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<void> log({
    required String action,
    required String module,
    String severity = 'info',
    Map<String, dynamic>? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email ?? 'Unknown User';
    await _firestore.collection('activity_logs').add({
      'user': userName,
      'action': action,
      'module': module,
      'severity': severity,
      'timestamp': FieldValue.serverTimestamp(),
      'ipAddress': '',
      'details': details,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

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
    bool enabled = true,
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
                    style: labelTextStyle.copyWith(color: AdminColors.error),
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
      fillColor: enabled ? const Color(0xFFF8F9FB) : const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE8ECF0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: AdminColors.error, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Severity badge (reused from activity logs)
// ─────────────────────────────────────────────────────────────────────────────
class _SeverityBadge extends StatelessWidget {
  final String severity;
  const _SeverityBadge(this.severity);

  @override
  Widget build(BuildContext context) {
    final Map<String, _BadgeStyle> styles = {
      'info': _BadgeStyle(
        const Color(0xFFEFF6FF),
        const Color(0xFF2563EB),
        'INFO',
      ),
      'warning': _BadgeStyle(
        const Color(0xFFFFFBEB),
        const Color(0xFFFB923C),
        'WARNING',
      ),
      'error': _BadgeStyle(
        const Color(0xFFFEF2F2),
        const Color(0xFFDC2626),
        'ERROR',
      ),
      'critical': _BadgeStyle(
        const Color(0xFFFDF2F8),
        const Color(0xFF9333EA),
        'CRITICAL',
      ),
    };
    final s =
        styles[severity.toLowerCase()] ??
        _BadgeStyle(
          const Color(0xFFF3F4F6),
          const Color(0xFF6B7280),
          severity.toUpperCase(),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: s.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: s.fg,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Module badge — colored per module so the audit table is scannable at a
// glance instead of every row reading the same neutral gray.
// ─────────────────────────────────────────────────────────────────────────────
class _ModuleBadge extends StatelessWidget {
  final String module;
  const _ModuleBadge(this.module);

  static const Map<String, _BadgeStyle> _styles = {
    'User Directory': _BadgeStyle(
      Color(0xFFEFF6FF),
      Color(0xFF2563EB),
      'User Directory',
    ),
    'Admin Settings': _BadgeStyle(
      Color(0xFFF5F3FF),
      Color(0xFF7C3AED),
      'Admin Settings',
    ),
    'Reports': _BadgeStyle(Color(0xFFECFDF5), Color(0xFF059669), 'Reports'),
    'Organizations': _BadgeStyle(
      Color(0xFFEEF2FF),
      Color(0xFF4F46E5),
      'Organizations',
    ),
    'Letter Request': _BadgeStyle(
      Color(0xFFFFFBEB),
      Color(0xFFD97706),
      'Letter Request',
    ),
    'External Account': _BadgeStyle(
      Color(0xFFECFEFF),
      Color(0xFF0891B2),
      'External Account',
    ),
    'Adviser Roles': _BadgeStyle(
      Color(0xFFFAF5FF),
      Color(0xFF9333EA),
      'Adviser Roles',
    ),
    'Event Management': _BadgeStyle(
      Color(0xFFFDF2F8),
      Color(0xFFDB2777),
      'Event Management',
    ),
    'My Profile': _BadgeStyle(
      Color(0xFFFFF7ED),
      Color(0xFFEA580C),
      'My Profile',
    ),
    'Authentication': _BadgeStyle(
      Color(0xFFF3F4F6),
      Color(0xFF4B5563),
      'Authentication',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final s =
        _styles[module] ??
        _BadgeStyle(const Color(0xFFF3F4F6), const Color(0xFF6B7280), module);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(_DS.radiusSm),
      ),
      child: Text(
        s.label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.fg,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account overview stat chip (member since / last sign-in)
// ─────────────────────────────────────────────────────────────────────────────
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
          Icon(icon, size: 15, color: AdminColors.primaryDark.withAlpha(160)),
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
// Section label helper
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AdminColors.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE2E6EA), thickness: 1)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Signatory model - NO PLACEHOLDER KEY
// ─────────────────────────────────────────────────────────────────────────────
class SignatoryEntry {
  final String id;
  final String fullName;
  final String title;
  final String? signatureBase64;

  const SignatoryEntry({
    required this.id,
    required this.fullName,
    required this.title,
    this.signatureBase64,
  });

  factory SignatoryEntry.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return SignatoryEntry(
      id: doc.id,
      fullName: (d['fullName'] ?? '').toString(),
      title: (d['title'] ?? '').toString(),
      signatureBase64: d['signatureBase64'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'fullName': fullName.trim(),
    'title': title.trim(),
    if (signatureBase64 != null) 'signatureBase64': signatureBase64,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────
class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});

  @override
  _AdminSettingsState createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _passwordFormKey = GlobalKey<FormState>();
  bool _isLoading = false;
  User? _currentUser;

  // Password
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  // Email
  final _emailFormKey = GlobalKey<FormState>();
  final _newEmailController = TextEditingController();
  final _emailCurrentPasswordController = TextEditingController();
  bool _showEmailCurrentPassword = false;
  bool _isChangingEmail = false;

  // Account overview header
  String _accountFullName = '';
  String? _accountPhotoBase64;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentUser = FirebaseAuth.instance.currentUser;
    _loadAccountOverview();
  }

  Future<void> _loadAccountOverview() async {
    if (_currentUser == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .get();
    if (!mounted) return;
    final data = doc.data();
    setState(() {
      _accountFullName =
          (data?['fullName'] as String?)?.trim().isNotEmpty == true
          ? data!['fullName'] as String
          : (_currentUser!.displayName ?? 'Admin User');
      _accountPhotoBase64 = data?['photoBase64'] as String?;
    });
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Unknown';
    return DateFormat('MMM d, y').format(dt);
  }

  Future<List<Map<String, dynamic>>> _fetchUserAuditLogs(String email) async {
    final col = FirebaseFirestore.instance.collection('activity_logs');
    try {
      final qs = await col
          .where('user', isEqualTo: email)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      return qs.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        final tsField = m['timestamp'];
        DateTime? ts;
        if (tsField is Timestamp)
          ts = tsField.toDate();
        else if (tsField is DateTime)
          ts = tsField;
        m['_ts'] = ts;
        m['_id'] = d.id;
        return m;
      }).toList();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('requires an index') ||
          msg.contains('failed-precondition')) {
        final qs = await col.where('user', isEqualTo: email).limit(50).get();
        final list = qs.docs.map((d) {
          final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
          final tsField = m['timestamp'];
          DateTime? ts;
          if (tsField is Timestamp)
            ts = tsField.toDate();
          else if (tsField is DateTime)
            ts = tsField;
          m['_ts'] = ts;
          m['_id'] = d.id;
          return m;
        }).toList();
        list.sort((a, b) {
          final at = a['_ts'] as DateTime?;
          final bt = b['_ts'] as DateTime?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        return list.take(20).toList();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newEmailController.dispose();
    _emailCurrentPasswordController.dispose();
    super.dispose();
  }

  // Both password and email changes are "sensitive" operations that Firebase
  // rejects with `requires-recent-login` if the session is more than a few
  // minutes old — reauthenticating with the current password up front means
  // the form actually succeeds on the first try instead of failing opaquely
  // partway through.
  Future<void> _reauthenticate(String currentPassword) async {
    final email = _currentUser?.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-current-email',
        message: 'No email on this account to reauthenticate with.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await _currentUser!.reauthenticateWithCredential(credential);
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

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _reauthenticate(_currentPasswordController.text);
      await _currentUser!.updatePassword(_newPasswordController.text);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      await ActivityLogger.log(
        action: 'Changed account password',
        module: 'Admin Settings',
      );
      _showSnack('Password changed successfully', success: true);
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e), success: false);
    } catch (e) {
      _showSnack('Error: $e', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Uses verifyBeforeUpdateEmail (not the deprecated updateEmail) — Firebase
  // now requires the new address to be verified via an emailed link before
  // the account's email actually changes, so the auth email and the address
  // typed here diverge until that link is clicked. Firestore's `users.email`
  // mirror is deliberately left untouched until then, to avoid it pointing
  // at an email the auth record doesn't actually have yet.
  Future<void> _changeEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final newEmail = _newEmailController.text.trim();
    setState(() => _isChangingEmail = true);
    try {
      await _reauthenticate(_emailCurrentPasswordController.text);
      await _currentUser!.verifyBeforeUpdateEmail(newEmail);
      _emailCurrentPasswordController.clear();
      _newEmailController.clear();
      await ActivityLogger.log(
        action: 'Requested email change to $newEmail',
        module: 'Admin Settings',
      );
      _showSnack(
        'Verification link sent to $newEmail. Your login email updates once you confirm it there.',
        success: true,
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e), success: false);
    } catch (e) {
      _showSnack('Error: $e', success: false);
    } finally {
      if (mounted) setState(() => _isChangingEmail = false);
    }
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    if (success) {
      AppToast.success(context, message);
    } else {
      AppToast.error(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFBFCFE),
      child: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSecurityTab(),
                _buildAuditLogsTab(),
                const _SignatoriesTab(),
                const _HelpTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        tabs: const [
          Tab(text: 'Security'),
          Tab(text: 'Audit Logs'),
          Tab(text: 'Signatories'),
          Tab(text: 'Help'),
        ],
        labelColor: AdminColors.primaryDark,
        unselectedLabelColor: const Color(0xFF64748B),
        indicatorColor: AdminColors.primaryDark,
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
      ),
    );
  }

  Widget _notificationTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        border: Border.all(
          color: value
              ? AdminColors.primaryDark.withAlpha(77)
              : const Color(0xFFE2E6EA),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: value
                  ? AdminColors.primaryDark.withAlpha(26)
                  : const Color(0xFFE8ECF0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? AdminColors.primaryDark : const Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AdminColors.primaryDark,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    ImageProvider? imageProvider;
    if (_accountPhotoBase64 != null && _accountPhotoBase64!.isNotEmpty) {
      imageProvider = MemoryImage(base64Decode(_accountPhotoBase64!));
    }
    final metadata = _currentUser?.metadata;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AdminColors.primaryDark.withAlpha(60),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: imageProvider != null
                                ? Image(image: imageProvider, fit: BoxFit.cover)
                                : Container(
                                    color: AdminColors.primaryDark.withAlpha(
                                      20,
                                    ),
                                    child: Icon(
                                      Icons.person_rounded,
                                      size: 26,
                                      color: AdminColors.primaryDark.withAlpha(
                                        100,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _accountFullName.isNotEmpty
                                    ? _accountFullName
                                    : 'Admin User',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A202C),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _currentUser?.email ?? '—',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12.5,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AdminColors.primaryDark.withAlpha(20),
                            borderRadius: BorderRadius.circular(_DS.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 13,
                                color: AdminColors.primaryDark,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'System Administrator',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AdminColors.primaryDark,
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
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Form(
                  key: _emailFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                        'Change Email',
                        icon: Icons.alternate_email_rounded,
                      ),
                      Container(
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
                                'Current email: ${_currentUser?.email ?? '—'}. '
                                'We\'ll send a verification link to the new '
                                'address — your login email only changes '
                                'once you confirm it there.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: const Color(0xFF1D4ED8),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS.inputDecoration(
                          'New Email',
                          hint: 'e.g., admin@cict.edu.ph',
                          icon: Icons.alternate_email_rounded,
                          required: true,
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Required';
                          if (!RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(value)) {
                            return 'Enter a valid email address';
                          }
                          if (value.toLowerCase() ==
                              (_currentUser?.email ?? '').toLowerCase()) {
                            return 'This is already your current email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCurrentPasswordController,
                        obscureText: !_showEmailCurrentPassword,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS
                            .inputDecoration(
                              'Current Password',
                              icon: Icons.password_rounded,
                              required: true,
                            )
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showEmailCurrentPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF9AA5B4),
                                ),
                                tooltip: _showEmailCurrentPassword
                                    ? 'Hide Password'
                                    : 'Show Password',
                                onPressed: () => setState(
                                  () => _showEmailCurrentPassword =
                                      !_showEmailCurrentPassword,
                                ),
                              ),
                            ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _isChangingEmail ? null : _changeEmail,
                        icon: _isChangingEmail
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          'Send Verification Link',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_DS.radiusSm),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                        'Change Password',
                        icon: Icons.lock_outline_rounded,
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F6FF),
                          borderRadius: BorderRadius.circular(_DS.radiusSm),
                          border: Border.all(color: const Color(0xFFBFD7FF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Regularly updating your password keeps your account secure.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: const Color(0xFF1D4ED8),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: !_showCurrentPassword,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS
                            .inputDecoration(
                              'Current Password',
                              icon: Icons.password_rounded,
                              required: true,
                            )
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showCurrentPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF9AA5B4),
                                ),
                                tooltip: _showCurrentPassword
                                    ? 'Hide Password'
                                    : 'Show Password',
                                onPressed: () => setState(
                                  () => _showCurrentPassword =
                                      !_showCurrentPassword,
                                ),
                              ),
                            ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: !_showNewPassword,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS
                            .inputDecoration(
                              'New Password',
                              icon: Icons.lock_outline_rounded,
                              required: true,
                            )
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showNewPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF9AA5B4),
                                ),
                                tooltip: _showNewPassword
                                    ? 'Hide Password'
                                    : 'Show Password',
                                onPressed: () => setState(
                                  () => _showNewPassword = !_showNewPassword,
                                ),
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_showConfirmPassword,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS
                            .inputDecoration(
                              'Confirm New Password',
                              icon: Icons.lock_outline_rounded,
                              required: true,
                            )
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: const Color(0xFF9AA5B4),
                                ),
                                tooltip: _showConfirmPassword
                                    ? 'Hide Password'
                                    : 'Show Password',
                                onPressed: () => setState(
                                  () => _showConfirmPassword =
                                      !_showConfirmPassword,
                                ),
                              ),
                            ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _changePassword,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.update_rounded, size: 16),
                        label: Text(
                          'Update Password',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_DS.radiusSm),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Two-Factor Authentication removed per user request.
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                  boxShadow: _DS.cardShadow,
                ),
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
                        Expanded(
                          child: Divider(
                            color: const Color(0xFFFCA5A5),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const AdminLogin(),
                            ),
                            (_) => false,
                          );
                        }
                      },
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    final email = _currentUser?.email ?? '';
    if (email.isEmpty) {
      return const Center(child: Text('Unable to load logs: user not found'));
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchUserAuditLogs(email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 32,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Error loading logs',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }

        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    size: 40,
                    color: Color(0xFF9AA5B4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No recent activity',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Actions you perform will appear here.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.primaryDark.withAlpha(20),
                      borderRadius: BorderRadius.circular(_DS.radiusPill),
                    ),
                    child: Text(
                      '${logs.length} entries',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
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
                          final data = logs[i] as Map<String, dynamic>;
                          final ts = data['_ts'] as DateTime?;
                          final severity = (data['severity'] ?? 'info')
                              .toString();
                          final module = (data['module'] ?? 'System')
                              .toString();
                          final action = (data['action'] ?? '—').toString();
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
                                    child: _ModuleBadge(module),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _SeverityBadge(severity),
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
                        'Showing your last ${logs.length} actions. Visit Activity Logs for the full audit trail.',
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

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SIGNATORIES TAB - NO PLACEHOLDER KEY
// ─────────────────────────────────────────────────────────────────────────────
class _SignatoriesTab extends StatefulWidget {
  const _SignatoriesTab();

  @override
  State<_SignatoriesTab> createState() => _SignatoriesTabState();
}

class _SignatoriesTabState extends State<_SignatoriesTab> {
  final CollectionReference _col = FirebaseFirestore.instance.collection(
    'signatories',
  );

  void _openForm({SignatoryEntry? existing}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SignatoryFormDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(SignatoryEntry s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Delete Signatory',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Delete "${s.fullName}"? This will remove them from the signatory list.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Delete',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    await _col.doc(s.id).delete();
    await ActivityLogger.log(
      action: 'Deleted signatory ${s.fullName}',
      module: 'Admin Settings',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Certificate Signatories',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      'Add Signatory',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_DS.radiusSm),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Signatories added here can be auto-inserted into any certificate template in the Certificates module.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              StreamBuilder<QuerySnapshot>(
                stream: _col.orderBy('fullName').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_DS.radiusLg),
                        border: Border.all(color: const Color(0xFFE8ECF0)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.draw_outlined,
                            size: 36,
                            color: const Color(0xFF9AA5B4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No signatories yet',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add one to make it available in the Certificates module.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: const Color(0xFF9AA5B4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final entries = docs
                      .map((d) => SignatoryEntry.fromDoc(d))
                      .toList();
                  return Column(
                    children: entries
                        .map(
                          (s) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(_DS.radiusMd),
                              border: Border.all(
                                color: const Color(0xFFE8ECF0),
                              ),
                              boxShadow: _DS.cardShadow,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FB),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE2E6EA),
                                    ),
                                  ),
                                  child: s.signatureBase64 != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                          child: Image.memory(
                                            base64Decode(s.signatureBase64!),
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.draw_outlined,
                                          size: 20,
                                          color: Color(0xFF9AA5B4),
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.fullName.isEmpty
                                            ? '(No name)'
                                            : s.fullName,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1A202C),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.title.isEmpty ? '—' : s.title,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Color(0xFF64748B),
                                  ),
                                  tooltip: 'Edit',
                                  onPressed: () => _openForm(existing: s),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Color(0xFFDC2626),
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(s),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Add/Edit signatory dialog - NO PLACEHOLDER KEY
class _SignatoryFormDialog extends StatefulWidget {
  final SignatoryEntry? existing;
  const _SignatoryFormDialog({this.existing});

  @override
  State<_SignatoryFormDialog> createState() => _SignatoryFormDialogState();
}

class _SignatoryFormDialogState extends State<_SignatoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _titleCtrl;
  String? _signatureBase64;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.fullName ?? '');
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _signatureBase64 = e?.signatureBase64;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSignature() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final validationError = FileValidation.validateImageBytes(bytes);
    if (validationError != null) {
      if (mounted) {
        AppToast.error(context, validationError);
      }
      return;
    }
    setState(() => _signatureBase64 = base64Encode(bytes));
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);
    try {
      final entry = SignatoryEntry(
        id: widget.existing?.id ?? '',
        fullName: _nameCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        signatureBase64: _signatureBase64,
      );
      final col = FirebaseFirestore.instance.collection('signatories');
      if (widget.existing != null) {
        await col
            .doc(widget.existing!.id)
            .set(entry.toMap(), SetOptions(merge: true));
        await ActivityLogger.log(
          action: 'Updated signatory ${entry.fullName}',
          module: 'Admin Settings',
        );
      } else {
        await col.add({
          ...entry.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        await ActivityLogger.log(
          action: 'Added signatory ${entry.fullName}',
          module: 'Admin Settings',
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── HEADER ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AdminColors.primaryDark,
                      AdminColors.primaryDark.withAlpha(225),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.draw_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isEdit ? 'Edit Signatory' : 'Add Signatory',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ─── BODY ────────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _pickSignature,
                            child: Container(
                              width: 140,
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE2E6EA),
                                ),
                              ),
                              child: _signatureBase64 != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.memory(
                                        base64Decode(_signatureBase64!),
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.upload_rounded,
                                          size: 20,
                                          color: const Color(0xFF9AA5B4),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Upload signature',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            color: const Color(0xFF9AA5B4),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _nameCtrl,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS.inputDecoration(
                          'Full Name',
                          hint: 'e.g., Dr. Maria Santos',
                          icon: Icons.person_outline_rounded,
                          required: true,
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Required';
                          if (!RegExp(
                            r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*(?: [A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'.-]*)+$",
                          ).hasMatch(value)) {
                            return 'Enter a full name (first and last)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _titleCtrl,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _DS.inputDecoration(
                          'Position / Title',
                          hint: 'e.g., College Dean',
                          icon: Icons.badge_outlined,
                          required: true,
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Required';
                          if (value.length < 2) return 'Enter a valid title';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ─── FOOTER ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E6EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
// Help tab — navigation guide, FAQs, Terms & Conditions
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

class _HelpTab extends StatelessWidget {
  const _HelpTab();

  static const _navGuide = [
    _NavGuideEntry(
      Icons.dashboard_outlined,
      'Dashboard',
      'At-a-glance stats — org standings, pending proposals, upcoming events, '
          'and overdue reports, each exportable straight from its panel.',
    ),
    _NavGuideEntry(
      Icons.groups_outlined,
      'Organization Management',
      'Approve org profiles, set their status, and assign advisers.',
    ),
    _NavGuideEntry(
      Icons.people_outline,
      'Student Accounts',
      'Create, edit, or archive individual students, or batch-import a whole '
          'section at once using the provided Excel template.',
    ),
    _NavGuideEntry(
      Icons.school_outlined,
      'Adviser Roles',
      'Manage adviser contact details and which organization(s) they oversee.',
    ),
    _NavGuideEntry(
      Icons.pending_actions_outlined,
      'Event Proposals',
      'Review org-submitted proposals — approve or reject them. Once '
          'approved, the organization itself publishes the event to students.',
    ),
    _NavGuideEntry(
      Icons.calendar_today_outlined,
      'College Event Calendar',
      'A combined calendar of every approved event across all organizations.',
    ),
    _NavGuideEntry(
      Icons.mail_outline,
      'Letter Request',
      'Process official letter requests submitted by organizations.',
    ),
    _NavGuideEntry(
      Icons.link_outlined,
      'External Account',
      'Review and manage access requests from outside the student directory.',
    ),
    _NavGuideEntry(
      Icons.assessment_outlined,
      'Reports & Analytics',
      'Generate and export financial, accomplishment, and submission-'
          'tracking reports for the current semester.',
    ),
    _NavGuideEntry(
      Icons.history_outlined,
      'Activity Logs',
      'A full audit trail of every significant action across the admin and '
          'org portals — searchable and exportable.',
    ),
    _NavGuideEntry(
      Icons.settings_outlined,
      'Settings',
      'Security, audit logs, signatories, and this Help section all live here.',
    ),
  ];

  static const _faqs = [
    _FaqEntry(
      'Who approves an event proposal — admin or the organization?',
      'Admins review a proposal and approve or reject it. Once approved, the '
          'organization itself publishes the event to students; admins don\'t '
          'publish events directly, only approve, reject, or archive them.',
    ),
    _FaqEntry(
      'How do I add students in bulk?',
      'Go to Student Accounts and click "Batch Import" to download the Excel '
          'template. Fill it out and re-upload — every row is validated '
          'before saving, with row-by-row error messages for anything that '
          'fails instead of silently skipping it.',
    ),
    _FaqEntry(
      'I changed my email in Settings but it still shows the old one.',
      'That\'s expected. Changing your email requires clicking the '
          'verification link sent to the new address first — your login '
          'email only updates once that link is confirmed, so this page '
          'correctly keeps showing your current, still-active email until '
          'then.',
    ),
    _FaqEntry(
      'How do I export a table to Excel or PDF?',
      'Every data table has an Export button in its toolbar — choose Excel '
          'or PDF and the file downloads immediately, styled with the CICT '
          'brand colors.',
    ),
    _FaqEntry(
      'How are certificates issued?',
      'Certificates aren\'t generated automatically at QR check-in. On the '
          'Certificates page, an organization issues them per event once an '
          'attendee has submitted feedback for it — each certificate gets a '
          'unique code that anyone can check at the public verification page.',
    ),
    _FaqEntry(
      'How are report deadlines calculated?',
      'Deadlines follow the academic semester: 1st Semester (Aug–Jan), 2nd '
          'Semester (Feb–Jun), and Summer (Jun–Aug). Reports & Analytics '
          'computes the active range automatically — no manual date entry.',
    ),
    _FaqEntry(
      'Where can I see who changed what, and when?',
      'The Activity Logs tab lists every logged action together with the '
          'user, module, and timestamp involved, and can be filtered and '
          'exported like any other table.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Help & Resources',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How to get around the admin portal, answers to common '
                'questions, and the terms governing this system.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(
                      'Navigating the Admin Portal',
                      icon: Icons.explore_outlined,
                    ),
                    for (var i = 0; i < _navGuide.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _NavGuideRow(entry: _navGuide[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(
                      'Frequently Asked Questions',
                      icon: Icons.help_outline_rounded,
                    ),
                    for (var i = 0; i < _faqs.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _FaqTile(entry: _faqs[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_DS.radiusLg),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(
                      'Terms & Conditions',
                      icon: Icons.gavel_outlined,
                    ),
                    Text(
                      'This portal handles student, organization, and event '
                      'records. By signing in as an administrator, you agree '
                      'to use it only for official CICT organization-'
                      'management purposes and to keep student data '
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
                        builder: (_) => const _TermsDialog(),
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
                        foregroundColor: AdminColors.primaryDark,
                        side: BorderSide(
                          color: AdminColors.primaryDark.withAlpha(90),
                        ),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_DS.radiusSm),
                        ),
                      ),
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
            color: AdminColors.primaryDark.withAlpha(15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(entry.icon, size: 17, color: AdminColors.primaryDark),
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
          color: _expanded
              ? AdminColors.primaryDark.withAlpha(70)
              : const Color(0xFFE8ECF0),
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
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AdminColors.primaryDark,
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

class _TermsSection {
  final String title;
  final String body;
  const _TermsSection(this.title, this.body);
}

class _TermsDialog extends StatelessWidget {
  const _TermsDialog();

  static const _sections = [
    _TermsSection(
      '1. Acceptance of Use',
      'Access to this system is granted only to authorized CICT '
          'administrators. Signing in constitutes agreement to use it solely '
          'for official organization-management duties within the college.',
    ),
    _TermsSection(
      '2. Account Responsibility',
      'You are responsible for keeping your login credentials confidential '
          'and for all actions taken under your account. Report a '
          'compromised account immediately and change your password from '
          'the Security tab.',
    ),
    _TermsSection(
      '3. Data Privacy & Confidentiality',
      'Student, organization, and event records accessed here are '
          'confidential and handled in line with the Data Privacy Act of '
          '2012 (Republic Act No. 10173). Records may only be viewed, '
          'exported, or shared for legitimate administrative purposes — '
          'never for personal use or disclosed to unauthorized parties.',
    ),
    _TermsSection(
      '4. Activity Logging',
      'Significant actions taken in this portal — approvals, edits, '
          'exports, deletions — are recorded in the Activity Logs audit '
          'trail together with the acting user, timestamp, and affected '
          'module.',
    ),
    _TermsSection(
      '5. Certificates & Verification',
      'Certificates issued through this system carry a unique '
          'verification code checkable at the public verification page. '
          'Do not issue or alter certificates outside the intended '
          'attendance-and-feedback workflow.',
    ),
    _TermsSection(
      '6. Prohibited Actions',
      'Do not use exported data for purposes outside official college '
          'business, attempt to bypass access controls, or share admin '
          'credentials with students, organizations, or other staff.',
    ),
    _TermsSection(
      '7. Changes to These Terms',
      'These terms may be updated as the system evolves. Continued use '
          'after an update constitutes acceptance of the revised terms.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Dialog centers on the full window by default, but AdminDashboard keeps
    // a persistent 256px sidebar to the left on screens >= 900px wide (see
    // _sidebarBreakpoint in admin_dashboard.dart) — centering on the whole
    // window there leaves the dialog looking shifted left of the actual
    // content pane. Padding only the left inset by the sidebar's width
    // re-centers it within the visible content area instead. Below the
    // breakpoint the sidebar becomes a Drawer (no persistent width taken),
    // so the normal symmetric inset applies.
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
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: const Color(0xFFE8ECF0)),
                ),
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
                      'internal reference within the admin portal.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF9AA5B4),
                      ),
                    ),
                    for (final s in _sections) ...[
                      const SizedBox(height: 18),
                      Text(
                        s.title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.primaryDark,
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
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: const Color(0xFFE8ECF0))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primaryDark,
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
