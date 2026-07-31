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
    _tabController = TabController(length: 2, vsync: this);
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
        const SizedBox(height: 20),

        // ── Tab bar (rounded pill, smooth sliding indicator) ──
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E6EA)),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: UpriseColors.primaryDark,
                borderRadius: BorderRadius.circular(9),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(9),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(height: 38, text: 'Profile'),
                Tab(height: 38, text: 'Security'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

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
              _SecurityTab(orgId: widget.orgId),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Tab
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF9AA5B4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : '—',
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: const Color(0xFF1A202C),
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
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
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
                _infoRow('Organization Name', orgName),
                _infoRow('Short Name', orgShortName),
                _infoRow('Email Address', orgEmail),
              ],
            ),
          ),
          _GcashSettingsCard(orgId: orgId),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GCash Settings — the GCash number/name students are told to pay to during
// merchandise checkout. There's no payment gateway behind this (PayMongo
// requires business docs/Blaze billing the org doesn't have); the org just
// publishes where to send money and manually verifies each order's
// reference number in org_merchandise.dart before fulfilling it.
// ─────────────────────────────────────────────────────────────────────────────
class _GcashSettingsCard extends StatefulWidget {
  final String orgId;
  const _GcashSettingsCard({required this.orgId});

  @override
  State<_GcashSettingsCard> createState() => _GcashSettingsCardState();
}

class _GcashSettingsCardState extends State<_GcashSettingsCard> {
  final _numberCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      final d = doc.data() ?? {};
      _numberCtrl.text = (d['gcashNumber'] as String?) ?? '';
      _nameCtrl.text = (d['gcashName'] as String?) ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final number = _numberCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a GCash number.'),
          backgroundColor: UpriseColors.error,
        ),
      );
      return;
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid 11-digit GCash number (e.g., 09171234567).',
          ),
          backgroundColor: UpriseColors.error,
        ),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the GCash account name.'),
          backgroundColor: UpriseColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .update({'gcashNumber': number, 'gcashName': name});
      await activity_log.ActivityLogger.log(
        action: 'update_gcash_settings',
        module: 'settings',
        details: {'orgId': widget.orgId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash details saved'),
            backgroundColor: UpriseColors.success,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'GCash Payment Details',
            style: GoogleFonts.beVietnamPro(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Shown to students at merchandise checkout so they know where to send GCash payments. You confirm each payment manually in Merchandise > Orders.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            TextFormField(
              controller: _numberCtrl,
              decoration: _DS.inputDecoration(
                'GCash Number',
                hint: 'e.g. 0917xxxxxxx',
                icon: Icons.phone_iphone_rounded,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameCtrl,
              decoration: _DS.inputDecoration(
                'GCash Account Name',
                hint: 'e.g. Juan Dela Cruz',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: UpriseColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Save',
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Security Tab
// ─────────────────────────────────────────────────────────────────────────────
class _SecurityTab extends StatefulWidget {
  final String orgId;
  const _SecurityTab({required this.orgId});

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

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
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
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
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
                      return const Center(child: CircularProgressIndicator());
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
    );
  }
}
