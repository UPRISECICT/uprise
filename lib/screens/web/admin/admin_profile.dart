// lib/screens/web/admin/admin_profile.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/file_validation.dart';
import '../../../services/activity_logger.dart' as activity_log;

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
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
                    style: labelTextStyle.copyWith(color: UpriseColors.error),
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
        borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1.5),
      ),
    );
  }
}

Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: UpriseColors.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: UpriseColors.primaryDark,
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
// Main Widget — the admin's own profile (name, email, photo). Previously
// this was just the first tab of AdminSettings, but "My Profile" and
// "Settings" in the top-right menu both opened the exact same screen (the
// menu item literally called the same _selectTab(-1) for both) — this is
// now a real, separate destination.
// ─────────────────────────────────────────────────────────────────────────────
class AdminProfile extends StatefulWidget {
  final VoidCallback? onProfileUpdated;
  const AdminProfile({super.key, this.onProfileUpdated});

  @override
  State<AdminProfile> createState() => _AdminProfileState();
}

class _AdminProfileState extends State<AdminProfile> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _profileFormKey = GlobalKey<FormState>();
  bool _isLoading = false;
  User? _currentUser;
  String? _profileImageBase64;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _loadUserData();
    _loadProfileImage();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (_currentUser != null) {
      _fullNameController.text = _currentUser!.displayName ?? '';
      _emailController.text = _currentUser!.email ?? '';
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser?.uid)
        .get();
    if (doc.exists) {
      final data = doc.data();
      if (data != null) {
        _fullNameController.text = data['fullName'] ?? _fullNameController.text;
        _emailController.text = data['email'] ?? _emailController.text;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadProfileImage() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser?.uid)
        .get();
    if (doc.exists) {
      final data = doc.data();
      if (data != null && data['photoBase64'] != null) {
        setState(() => _profileImageBase64 = data['photoBase64']);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final validationError = FileValidation.validateImageBytes(bytes);
    if (validationError != null) {
      _showSnack(validationError, success: false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final base64String = base64Encode(bytes);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set({'photoBase64': base64String}, SetOptions(merge: true));
      setState(() => _profileImageBase64 = base64String);
      await activity_log.ActivityLogger.log(
        action: 'Updated profile picture',
        module: 'My Profile',
      );
      widget.onProfileUpdated?.call();
      _showSnack('Profile picture updated', success: true);
    } catch (e) {
      _showSnack('Error saving picture: $e', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // If email changed, attempt to update the auth user's email as well.
      final newEmail = _emailController.text.trim();
      if (newEmail.isNotEmpty && newEmail != (_currentUser?.email ?? '')) {
        try {
          await _currentUser!.updateEmail(newEmail);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            _showSnack('Please re-login to change your email', success: false);
            setState(() => _isLoading = false);
            return;
          }
          rethrow;
        }
      }
      await _currentUser!.updateDisplayName(_fullNameController.text.trim());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set({
            'fullName': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await activity_log.ActivityLogger.log(
        action: 'Updated profile name to ${_fullNameController.text.trim()}',
        module: 'My Profile',
      );
      widget.onProfileUpdated?.call();
      _showSnack('Profile updated successfully', success: true);
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
        backgroundColor: success ? const Color(0xFF059669) : UpriseColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty) {
      imageProvider = MemoryImage(base64Decode(_profileImageBase64!));
    }

    return Container(
      color: const Color(0xFFFBFCFE),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Profile',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your personal information and photo.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_DS.radiusLg),
                    border: Border.all(color: const Color(0xFFE8ECF0)),
                    boxShadow: _DS.cardShadow,
                  ),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: UpriseColors.primaryDark.withAlpha(38),
                                width: 3,
                              ),
                              boxShadow: _DS.cardShadow,
                            ),
                            child: ClipOval(
                              child: imageProvider != null
                                  ? Image(
                                      image: imageProvider,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: UpriseColors.primaryDark.withAlpha(
                                        20,
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
                                        size: 48,
                                        color: UpriseColors.primaryDark
                                            .withAlpha(100),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: MouseRegion(
                              cursor: _isLoading
                                  ? MouseCursor.defer
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _isLoading ? null : _pickAndUploadImage,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: UpriseColors.primaryDark,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _fullNameController.text.isNotEmpty
                            ? _fullNameController.text
                            : 'Admin User',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _emailController.text,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: UpriseColors.primaryDark.withAlpha(20),
                          borderRadius: BorderRadius.circular(_DS.radiusPill),
                        ),
                        child: Text(
                          'System Administrator',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: UpriseColors.primaryDark,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap the camera icon to change your photo',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: const Color(0xFF9AA5B4),
                        ),
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
                    key: _profileFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(
                          'Personal Information',
                          icon: Icons.badge_outlined,
                        ),
                        TextFormField(
                          controller: _fullNameController,
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                          decoration: _DS.inputDecoration(
                            'Full Name',
                            hint: 'e.g., Juan dela Cruz',
                            icon: Icons.person_outline_rounded,
                            required: true,
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                          decoration: _DS.inputDecoration(
                            'Email Address',
                            icon: Icons.email_outlined,
                            required: true,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Required';
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _updateProfile,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 16),
                          label: Text(
                            'Save Changes',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UpriseColors.primaryDark,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
