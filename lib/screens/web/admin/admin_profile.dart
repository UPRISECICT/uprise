// lib/screens/web/admin/admin_profile.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
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
  bool _avatarHovering = false;
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
      // Auth is the source of truth for the login email — Firestore's
      // mirror only exists for convenience and goes stale the moment a
      // verifyBeforeUpdateEmail link is confirmed (that happens outside the
      // app, so nothing else writes the new address back to Firestore).
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
        final firestoreEmail = data['email'] as String?;
        final authEmail = _currentUser?.email;
        if (authEmail != null &&
            authEmail.isNotEmpty &&
            firestoreEmail != authEmail) {
          // Self-heal: a pending email change was verified since the mirror
          // was last written. Bring Firestore back in sync silently.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUser!.uid)
              .set({'email': authEmail}, SetOptions(merge: true));
        }
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

  // Email is intentionally read-only on this page. Changing it is a
  // sensitive operation that Firebase requires a recent re-authentication
  // for — that flow (password confirmation + verifyBeforeUpdateEmail) already
  // exists on the Settings screen, so it's surfaced here as a pointer rather
  // than duplicated (and previously silently failing) here.
  Future<void> _updateProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final newName = _fullNameController.text.trim();
      await _currentUser!.updateDisplayName(newName);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set({
            'fullName': newName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await activity_log.ActivityLogger.log(
        action: 'Updated profile name to $newName',
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
        backgroundColor: success ? const Color(0xFF059669) : AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Unknown';
    return DateFormat('MMM d, y').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty) {
      imageProvider = MemoryImage(base64Decode(_profileImageBase64!));
    }

    final metadata = _currentUser?.metadata;

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
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_DS.radiusLg),
                    border: Border.all(color: const Color(0xFFE8ECF0)),
                    boxShadow: _DS.cardShadow,
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 88,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AdminColors.primaryDark,
                              AdminColors.primaryLight,
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                        child: Column(
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -48),
                              child: Stack(
                                children: [
                                  MouseRegion(
                                    cursor: _isLoading
                                        ? MouseCursor.defer
                                        : SystemMouseCursors.click,
                                    onEnter: (_) =>
                                        setState(() => _avatarHovering = true),
                                    onExit: (_) =>
                                        setState(() => _avatarHovering = false),
                                    child: GestureDetector(
                                      onTap: _isLoading
                                          ? null
                                          : _pickAndUploadImage,
                                      child: Container(
                                        width: 96,
                                        height: 96,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 4,
                                          ),
                                          boxShadow: _DS.cardShadow,
                                        ),
                                        child: ClipOval(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              imageProvider != null
                                                  ? Image(
                                                      image: imageProvider,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Container(
                                                      color: AdminColors
                                                          .primaryDark
                                                          .withAlpha(20),
                                                      child: Icon(
                                                        Icons.person_rounded,
                                                        size: 48,
                                                        color: AdminColors
                                                            .primaryDark
                                                            .withAlpha(100),
                                                      ),
                                                    ),
                                              // Hover reveal — "Change
                                              // Photo" overlay, so the whole
                                              // avatar (not just the small
                                              // camera badge) reads as
                                              // clickable on hover.
                                              if (_avatarHovering)
                                                Container(
                                                  color: Colors.black.withAlpha(
                                                    140,
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .camera_alt_rounded,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'Change\nPhoto',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style:
                                                            GoogleFonts.beVietnamPro(
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  Colors.white,
                                                              height: 1.2,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
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
                                        onTap: _isLoading
                                            ? null
                                            : _pickAndUploadImage,
                                        child: Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: AdminColors.primaryDark,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const Padding(
                                                  padding: EdgeInsets.all(6),
                                                  child:
                                                      CircularProgressIndicator(
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
                            ),
                            Transform.translate(
                              offset: const Offset(0, -32),
                              child: Column(
                                children: [
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
                                      color: AdminColors.primaryDark.withAlpha(
                                        20,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        _DS.radiusPill,
                                      ),
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
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatChip(
                                    icon: Icons.calendar_today_rounded,
                                    label: 'Member since',
                                    value: _formatDate(metadata?.creationTime),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatChip(
                                    icon: Icons.login_rounded,
                                    label: 'Last sign-in',
                                    value: _formatDate(
                                      metadata?.lastSignInTime,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                          enabled: false,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: const Color(0xFF9AA5B4),
                          ),
                          decoration: _DS.inputDecoration(
                            'Email Address',
                            icon: Icons.lock_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your email is tied to account sign-in and can only be changed from Settings, where it goes through password confirmation and a verification link.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11.5,
                            color: const Color(0xFF9AA5B4),
                            height: 1.4,
                          ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
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
