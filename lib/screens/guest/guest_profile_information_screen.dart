// lib/screens/guest/guest_profile_information_screen.dart
//
// GUEST PROFILE INFORMATION — view + edit external_requests/{docId}.
// Also lets the guest set a profile photo (stored as a base64 data URI,
// consistent with how images are already stored elsewhere in this app),
// which then shows up on the Digital ID card.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'guest_auth_service.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;
const _kBg = AppColors.background;

class GuestProfileInformationScreen extends StatefulWidget {
  const GuestProfileInformationScreen({super.key});

  @override
  State<GuestProfileInformationScreen> createState() => _GuestProfileInformationScreenState();
}

class _GuestProfileInformationScreenState extends State<GuestProfileInformationScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _photoUrl;
  String _email = '';

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();

  String get _docId => GuestAuthService().docId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _schoolCtrl.dispose();
    _courseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_docId.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('external_requests').doc(_docId).get();
      final data = doc.data() ?? {};
      _firstNameCtrl.text = (data['firstName'] ?? '').toString();
      _lastNameCtrl.text = (data['lastName'] ?? '').toString();
      _phoneCtrl.text = (data['phone'] ?? '').toString();
      _schoolCtrl.text = (data['university'] ?? '').toString();
      _courseCtrl.text = (data['course'] ?? '').toString();
      _email = (data['email'] ?? '').toString();
      _emailCtrl.text = _email;
      _photoUrl = data['photoUrl'] as String?;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      setState(() => _photoUrl = 'data:image/jpeg;base64,$b64');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not select photo: $e', style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fullName = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
      await FirebaseFirestore.instance.collection('external_requests').doc(_docId).update({
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'userName': fullName,
        'phone': _phoneCtrl.text.trim(),
        'university': _schoolCtrl.text.trim(),
        'course': _courseCtrl.text.trim(),
        if (_photoUrl != null) 'photoUrl': _photoUrl,
      });
      // Keep the cached session name in sync (used across guest screens).
      await GuestAuthService.saveSession(docId: _docId, email: _email, fullName: fullName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Profile updated.', style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: _kOrange,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e', style: GoogleFonts.beVietnamPro(fontSize: 13)),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // AppImage.provider over a local decoder: it also reads raw base64 with no
  // data: prefix and the malformed `dataimage...` variant some stored records
  // carry, both of which fell through to NetworkImage here and failed.
  ImageProvider? get _photoProvider => AppImage.provider(_photoUrl ?? '');

  InputDecoration _deco(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: const StudentAppBar(title: 'Profile Information'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Stack(children: [
                          Container(
                            width: 96, height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kOrangeLight,
                              image: _photoProvider != null
                                  ? DecorationImage(image: _photoProvider!, fit: BoxFit.cover)
                                  : null,
                            ),
                            child: _photoProvider == null
                                ? const Icon(Icons.person, size: 44, color: _kOrange)
                                : null,
                          ),
                          Positioned(
                            right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(controller: _firstNameCtrl, decoration: _deco('First Name')),
                    const SizedBox(height: 14),
                    TextField(controller: _lastNameCtrl, decoration: _deco('Last Name')),
                    const SizedBox(height: 14),
                    TextField(
                      enabled: false,
                      controller: _emailCtrl,
                      decoration: _deco('Email (cannot be changed)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: _deco('Phone')),
                    const SizedBox(height: 14),
                    TextField(controller: _schoolCtrl, decoration: _deco('University / Organization')),
                    const SizedBox(height: 14),
                    TextField(controller: _courseCtrl, decoration: _deco('Course / Program')),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Save Changes', style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
    );
  }
}
