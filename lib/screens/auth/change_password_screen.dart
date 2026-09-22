import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/theme.dart';
import '../../widgets/common/terms_and_conditions.dart';
import '../web/org/org_login.dart';
import '../web/admin/admin_login.dart';
import '../../services/app_sign_out.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String userId;
  final bool isFirstLogin;

  const ChangePasswordScreen({
    super.key,
    required this.userId,
    this.isFirstLogin = false,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;

    final newPass = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (newPass.isEmpty || confirm.isEmpty) {
      _showError('Please fill in both password fields.');
      return;
    }

    if (newPass.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    if (newPass != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    if (widget.isFirstLogin && !_agreedToTerms) {
      _showError('Please agree to the Terms and Conditions to continue.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user');

      await user.updatePassword(newPass);
      print('Password updated for uid=${user.uid}');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
            'isFirstLogin': false,
            'mustChangePassword': false,
            'needsPasswordChange': false,
            'firstLogin': false,
          });
      print('Firestore password flags cleared for uid=${widget.userId}');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final role = (userDoc.data()?['role'] as String?)?.toLowerCase() ?? '';
      print('ChangePassword success uid=${widget.userId} role=$role');

      await AppSignOut.signOut();

      if (!mounted) return;
      if (role == 'org') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OrganizationLogin()),
        );
        return;
      }
      if (role == 'admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminLogin()),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OrganizationLogin()),
      );
    } on FirebaseAuthException catch (e) {
      print('ChangePassword error: ${e.code} ${e.message}');
      if (e.code == 'requires-recent-login') {
        _showError('Please sign in again and retry password change.');
      } else {
        _showError(e.message ?? 'Failed to change password.');
      }
    } catch (e, st) {
      print('ChangePassword unexpected error: $e\n$st');
      _showError('Failed to change password. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password'), elevation: 0),
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: primaryOrange,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Change Your Password',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This account is using a temporary password. Update it now to continue to the organization portal.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _newCtrl,
                    obscureText: !_showNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showNewPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey[600],
                        ),
                        onPressed: () => setState(
                          () => _showNewPassword = !_showNewPassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: !_showConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey[600],
                        ),
                        onPressed: () => setState(
                          () => _showConfirmPassword = !_showConfirmPassword,
                        ),
                      ),
                    ),
                  ),
                  if (widget.isFirstLogin) ...[
                    const SizedBox(height: 20),
                    TermsAgreementCheckbox(
                      value: _agreedToTerms,
                      onChanged: (v) => setState(() => _agreedToTerms = v),
                      accent: const Color(0xFF2563EB),
                      textColor: Colors.grey[700]!,
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (widget.isFirstLogin && !_agreedToTerms)
                          ? null
                          : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Text('Save New Password'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'After changing your password, you will be signed out and redirected back to the login page. Use your new password to sign in.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
