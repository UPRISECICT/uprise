import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/file_validation.dart';
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
      color: Colors.black.withOpacity(0.06),
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
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUser = FirebaseAuth.instance.currentUser;
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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _currentUser!.updatePassword(_newPasswordController.text);
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      await ActivityLogger.log(
        action: 'Changed account password',
        module: 'Admin Settings',
      );
      _showSnack('Password changed successfully', success: true);
    } catch (e) {
      _showSnack('Error: $e', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: success ? const Color(0xFF059669) : AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
              ? AdminColors.primaryDark.withOpacity(0.3)
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
                  ? AdminColors.primaryDark.withOpacity(0.10)
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      color: AdminColors.primaryDark.withOpacity(0.08),
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
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AdminColors.primaryDark
                                          .withOpacity(0.07),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      module,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AdminColors.primaryDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: _SeverityBadge(severity),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            backgroundColor: AdminColors.error,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AdminColors.error,
          ),
        );
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
                        color: Colors.white.withOpacity(0.15),
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
