import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/activity_logger.dart' as activity_log;
import '../../widgets/common/app_intro.dart';
import '../../widgets/common/terms_and_conditions.dart';
import '../../widgets/student/app_colors.dart';
import 'student_login.dart';

class StudentChangePasswordScreen extends StatefulWidget {
  const StudentChangePasswordScreen({super.key});

  @override
  State<StudentChangePasswordScreen> createState() =>
      _StudentChangePasswordScreenState();
}

class _StudentChangePasswordScreenState
    extends State<StudentChangePasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _agreedToTerms = false;

  // This screen is only ever reached once per account (mustChangePassword
  // flips to false permanently after the first successful change), so a
  // short "what is UPRISE" guide shown as the first step here naturally
  // runs exactly once per student without needing a persisted flag.
  bool _showIntro = true;

  // UI-only state — does not affect the change-password logic below.
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }
    if (newPassword.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }
    if (!_agreedToTerms) {
      _showError('Please agree to the Terms and Conditions to continue');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await user.updatePassword(newPassword);

      final uid = user.uid;
      final futures = <Future>[
        // Clear flag in users collection (read by auth_service.needsPasswordChange)
        FirebaseFirestore.instance.collection('users').doc(uid).update({
          'mustChangePassword': false,
        }),
        // Clear temp password and flag in students collection — doc ID is
        // the uid itself, so this is a direct lookup, not a query.
        FirebaseFirestore.instance.collection('students').doc(uid).get().then((
          doc,
        ) {
          if (doc.exists) {
            return doc.reference.update({
              'mustChangePassword': false,
              'tempPassword': FieldValue.delete(),
            });
          }
          return Future.value();
        }),
      ];
      await Future.wait(futures);

      await activity_log.ActivityLogger.log(
        action: 'Student changed password',
        module: 'Authentication',
        severity: 'security',
        details: {'uid': uid},
      );

      // ✅ Sign out and go back to login
      await FirebaseAuth.instance.signOut();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password changed! Please login with your new password.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const StudentLogin()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF6B6B70), fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 20),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: const Color(0xFF9A9A9E),
          size: 20,
        ),
        onPressed: onToggle,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: border(const Color(0xFFE7E7E9)),
      enabledBorder: border(const Color(0xFFE7E7E9)),
      focusedBorder: border(AppColors.primaryDark, width: 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro) {
      return AppIntroScreen(
        slides: kStudentIntroSlides,
        onDone: () => setState(() => _showIntro = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Color(0xFF1B1B1D),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE7E7E9)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // ── Centered logo ──
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE7E7E9),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.school,
                      color: AppColors.primaryDark,
                      size: 36,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Set a New Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B1B1D),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Please create a new password to secure your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 32),

              // ── Form card ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: _fieldDecoration(
                        label: 'New Password',
                        icon: Icons.lock_outline,
                        obscure: _obscureNew,
                        onToggle: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: _fieldDecoration(
                        label: 'Confirm Password',
                        icon: Icons.lock_outline,
                        obscure: _obscureConfirm,
                        onToggle: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Must be at least 6 characters.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              TermsAgreementCheckbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v),
                accent: AppColors.primaryDark,
                textColor: Colors.grey.shade700,
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_agreedToTerms)
                      ? null
                      : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    disabledBackgroundColor: AppColors.primaryDark.withOpacity(
                      0.6,
                    ),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text(
                          'Save New Password',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
