import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/role_router.dart';
import '../student/student_login.dart';
import '../student/student_events_screen.dart';
import '../student/student_feedback_screen.dart';
import '../student/student_certificates_screen.dart';
import '../student/student_organization_details_screen.dart';
import '../../models/profile_model.dart';
import '../../widgets/shared/app_support.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/student/app_image.dart';

// ─────────────────────────────────────────────────────────────
// Shared constants - brand palette
// ─────────────────────────────────────────────────────────────
const kOrange = AppColors.primaryDark;
const kOrangeLight = Color(0xFFF5E3D9);
const kBg = Color(0xFFF5F5F5);

// ─────────────────────────────────────────────────────────────
// Shared style helpers — keeps the Profile tab visually aligned
// with the Settings screen (cards, shadows, section labels).
// ─────────────────────────────────────────────────────────────
BoxDecoration kCardDecoration({double radius = 16}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.grey.withOpacity(0.06),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

Widget kSectionLabel(String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Colors.grey[500],
      ),
    ),
  );
}

Widget kIconBadge(IconData icon, {Color color = kOrange, double size = 20}) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: color, size: size),
  );
}

// ─────────────────────────────────────────────────────────────
// ProfileModel — single source of truth
// ─────────────────────────────────────────────────────────────
class ProfileModel extends ChangeNotifier {
  String firstName = '';
  String middleName = '';
  String lastName = '';

  // Admin-created accounts (student_accounts.dart, both the single-add form
  // and batch import) only ever write a single `fullName` field to the
  // `students` doc — firstName/middleName/lastName don't exist there until
  // the student edits their own profile on mobile. Without this fallback,
  // fullName below would stay empty (and the header would keep showing the
  // static "Student Name" placeholder) for every student who hasn't done
  // that yet, which in practice is almost everyone right after account
  // creation.
  String rawFullName = '';

  String get fullName {
    final parts = [
      firstName,
      middleName,
      lastName,
    ].where((p) => p.trim().isNotEmpty);
    final joined = parts.join(' ');
    return joined.isNotEmpty ? joined : rawFullName;
  }

  String get fullNameLastFirst {
    if (lastName.trim().isEmpty) return fullName;
    final first = [
      firstName,
      middleName,
    ].where((p) => p.trim().isNotEmpty).join(' ');
    return first.isEmpty ? lastName : '$lastName, $first';
  }

  String studentId = '';
  String email = '';
  String mobile = '';
  String address = '';
  String photoUrl = '';
  String course = '';
  String major = '';
  String yearLevel = '';
  String department = '';
  String campus = '';
  String orgId = '';
  String orgName = '';
  // Set by org_profile.dart when an org tags this student as an officer or
  // member (org_profile.dart's _tagMatchingStudentAccount writes these same
  // fields onto both `users` and `students`, so they're already sitting in
  // the same doc this screen already fetches — no extra read needed).
  String orgRole = '';
  bool isOrgOfficer = false;
  bool isOrgMember = false;
  String officerPosition = '';

  ProfileModel() {
    _loadUserData();
  }

  String _cacheKey(String uid) => 'profile_cache_$uid';

  void _applyFields(Map<String, dynamic> data) {
    firstName = data['firstName'] ?? firstName;
    middleName = data['middleName'] ?? middleName;
    lastName = data['lastName'] ?? lastName;
    rawFullName = data['fullName'] ?? rawFullName;
    studentId = data['studentId'] ?? studentId;
    mobile = data['mobile'] ?? mobile;
    address = data['address'] ?? address;
    photoUrl = data['photoUrl'] ?? photoUrl;
    course = data['course'] ?? course;
    major = data['major'] ?? major;
    yearLevel = data['yearLevel'] ?? yearLevel;
    department = data['department'] ?? department;
    campus = data['campus'] ?? campus;
    orgId = data['orgId'] ?? orgId;
    orgRole = data['orgRole'] ?? orgRole;
    isOrgOfficer = data['isOrgOfficer'] == true;
    isOrgMember = data['isOrgMember'] == true;
    officerPosition = data['officerPosition'] ?? officerPosition;
  }

  // Cache-first: a fresh ProfileModel is created every time the student
  // switches to the Profile tab (student_home_screen.dart rebuilds
  // `_screens` from scratch on every tab change, so State isn't preserved
  // across tabs) — without a local cache, that meant a Firestore round trip
  // and a blank "Student Name / No student ID / No email" flash on every
  // single visit, not just right after login.
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    email = user.email ?? '';

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _cacheKey(user.uid);

    // 1. Show cached values immediately, before the network round trip.
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final cachedData = jsonDecode(cached) as Map<String, dynamic>;
        _applyFields(cachedData);
        orgName = cachedData['orgName'] ?? '';
        notifyListeners();
      } catch (_) {
        // Corrupt/old cache shape — ignore and fall through to the fetch.
      }
    }

    // 2. Refresh from Firestore in the background and re-cache the result.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _applyFields(data);

        if (orgId.isNotEmpty) {
          final orgSnap = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(orgId)
              .get();
          if (orgSnap.exists) {
            orgName =
                orgSnap.data()?['orgName'] ?? orgSnap.data()?['name'] ?? '';
          }
        }

        await _saveCache(user.uid);
      }
    } catch (_) {
      // Offline or the fetch failed — whatever the cache already applied
      // above (if any) stays on screen instead of reverting to blank.
    }

    notifyListeners();
  }

  Future<void> _saveCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(uid),
      jsonEncode({
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': rawFullName,
        'studentId': studentId,
        'mobile': mobile,
        'address': address,
        'photoUrl': photoUrl,
        'course': course,
        'major': major,
        'yearLevel': yearLevel,
        'department': department,
        'campus': campus,
        'orgId': orgId,
        'orgName': orgName,
        'orgRole': orgRole,
        'isOrgOfficer': isOrgOfficer,
        'isOrgMember': isOrgMember,
        'officerPosition': officerPosition,
      }),
    );
  }

  Future<void> update({
    required String firstName,
    required String middleName,
    required String lastName,
    required String email,
    required String mobile,
    required String address,
    String? photoUrl,
    String? course,
    String? major,
    String? yearLevel,
    String? department,
    String? campus,
  }) async {
    this.firstName = firstName;
    this.middleName = middleName;
    this.lastName = lastName;
    rawFullName = fullName; // keep the fallback in sync too
    this.email = email;
    this.mobile = mobile;
    this.address = address;
    if (photoUrl != null) this.photoUrl = photoUrl;
    if (course != null) this.course = course;
    if (major != null) this.major = major;
    if (yearLevel != null) this.yearLevel = yearLevel;
    if (department != null) this.department = department;
    if (campus != null) this.campus = campus;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final docRef = doc.reference;
        await docRef.set({
          'firstName': firstName,
          'middleName': middleName,
          'lastName': lastName,
          'fullName': fullName, // Update the fullName field too
          'studentId': studentId,
          'email': email,
          'mobile': mobile,
          'address': address,
          'photoUrl': this.photoUrl,
          'course': this.course,
          'major': this.major,
          'yearLevel': this.yearLevel,
          'department': this.department,
          'campus': this.campus,
        }, SetOptions(merge: true));
      }
      await _saveCache(user.uid);
    }

    // 🔥 Update all registrations with the new name (automatic sync)
    await updateAllRegistrationsWithName();

    notifyListeners();
  }

  Future<void> updatePhotoUrl(String url) async {
    photoUrl = url;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docRef = FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid);
      if ((await docRef.get()).exists) {
        await docRef.set({'photoUrl': url}, SetOptions(merge: true));
      }
      await _saveCache(user.uid);
    }

    notifyListeners();
  }

  // Update all registrations for the current user (called automatically on profile save)
  Future<void> updateAllRegistrationsWithName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Only update THIS user's registrations (not all students)
      final registrationsSnapshot = await FirebaseFirestore.instance
          .collection('registrations')
          .where('userId', isEqualTo: user.uid)
          .get();

      if (registrationsSnapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in registrationsSnapshot.docs) {
        batch.update(doc.reference, {
          'studentName': fullName,
          'firstName': firstName,
          'lastName': lastName,
          'fullName': fullName,
          'studentId': studentId,
        });
      }

      await batch.commit();
      print(
        '✅ Updated ${registrationsSnapshot.docs.length} registrations with new name: $fullName',
      );
    } catch (e) {
      print('❌ Error updating registrations: $e');
    }
  }

  // ⚠️ ADMIN ONLY – do not expose to students. Moved out of student-facing code.
  // Future<void> fixAllRegistrationsManually() { ... }  // Removed – dangerous bulk update
}

// ─────────────────────────────────────────────────────────────
// Pick & upload photo helper
// ─────────────────────────────────────────────────────────────
Future<void> _pickAndUploadPhoto(
  BuildContext context,
  ProfileModel profile,
) async {
  XFile? picked;
  try {
    final picker = ImagePicker();
    picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 400,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
    }
    return;
  }
  if (picked == null) return;

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: kOrange)),
  );

  try {
    final Uint8List bytes = await picked.readAsBytes();

    if (bytes.lengthInBytes > 400 * 1024) {
      throw Exception('That photo is too large. Please pick a smaller image.');
    }

    final String dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    await profile.updatePhotoUrl(dataUrl);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated!'),
          backgroundColor: kOrange,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Profile image helpers
// ─────────────────────────────────────────────────────────────
class _ProfileImage extends StatelessWidget {
  final String photoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  const _ProfileImage({
    required this.photoUrl,
    required this.errorBuilder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return AppImage(
      source: photoUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = kOrange,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: kCardDecoration(),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 19),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: Colors.grey[300],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Student Profile Screen — redesigned to match Settings' visual
// language: gradient hero, shadowed cards, uppercase section labels.
// ─────────────────────────────────────────────────────────────
class StudentProfileScreen extends StatefulWidget {
  final VoidCallback? onViewAllRegistrations;

  const StudentProfileScreen({super.key, this.onViewAllRegistrations});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final ProfileModel _profile = ProfileModel();

  Future<List<QueryDocumentSnapshot>> _fetchEventsByIds(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return [];

    final chunks = <List<String>>[];
    for (var i = 0; i < eventIds.length; i += 10) {
      chunks.add(
        eventIds.sublist(
          i,
          i + 10 > eventIds.length ? eventIds.length : i + 10,
        ),
      );
    }

    final results = <QueryDocumentSnapshot>[];
    for (final chunk in chunks) {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs);
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _profile,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: kBg,
          appBar: StudentAppBar(
            title: 'Profile',
            leading: const SizedBox.shrink(),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: kOrange),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(profile: _profile),
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile header — plain card, avatar/name/ID/email.
                // Orange is used only as an accent (edit-badge, icon) per
                // the redesign's "amber accent, not a dominant fill" rule.
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: kCardDecoration(radius: 18),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kOrangeLight,
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: ClipOval(
                              child: _profile.photoUrl.isNotEmpty
                                  ? _ProfileImage(
                                      photoUrl: _profile.photoUrl,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person,
                                        size: 46,
                                        color: kOrange,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person,
                                      size: 46,
                                      color: kOrange,
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () =>
                                  _pickAndUploadPhoto(context, _profile),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: kOrange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _profile.fullName.isNotEmpty
                            ? _profile.fullName
                            : 'Student Name',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _profile.studentId.isNotEmpty
                            ? _profile.studentId
                            : 'No student ID',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _profile.email.isNotEmpty ? _profile.email : 'No email',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),

                // ── Quick actions: Edit Profile / Digital ID / Certificates ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      _QuickActionCard(
                        icon: Icons.edit_outlined,
                        title: 'Edit Profile',
                        subtitle: 'Update info',
                        color: kOrange,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EditProfileScreen(profile: _profile),
                            ),
                          );
                          if (result != null && result is String) {
                            _profile._loadUserData();
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      _QuickActionCard(
                        icon: Icons.credit_card,
                        title: 'Digital ID',
                        subtitle: 'View & download',
                        color: const Color(0xFF2196F3),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PersonalIdentityScreen(profile: _profile),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _QuickActionCard(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Certificates',
                        subtitle: 'Your awards',
                        color: const Color(0xFF16A34A),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StudentCertificatesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── My Organizations — membership is a single orgId on
                // students/{uid} today, not an array, so this renders it as
                // a 0-1 item list (same pattern as Home and the
                // Organizations tab) rather than assuming one fixed org.
                if (_profile.orgName.isNotEmpty) ...[
                  kSectionLabel('My Organizations'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _profile.orgId.isEmpty
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    StudentOrganizationsDetailsScreen(
                                      orgId: _profile.orgId,
                                    ),
                              ),
                            ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: kCardDecoration(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kOrange.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.groups,
                                color: kOrange,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _profile.orgName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (_profile.isOrgOfficer ||
                                _profile.isOrgMember) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: kOrange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _profile.isOrgOfficer
                                      ? (_profile.officerPosition.isNotEmpty
                                            ? _profile.officerPosition
                                                  .toUpperCase()
                                            : 'OFFICER')
                                      : 'MEMBER',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: kOrange,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: Colors.grey[300],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Account Information ──
                kSectionLabel('Account Information'),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: kCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Your details',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditProfileScreen(profile: _profile),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: kOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ContactRow(
                        icon: Icons.school_outlined,
                        label: 'COURSE / PROGRAM',
                        value: _profile.course,
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),
                      _ContactRow(
                        icon: Icons.workspace_premium_outlined,
                        label: 'MAJOR',
                        value: _profile.major,
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),
                      _ContactRow(
                        icon: Icons.stairs_outlined,
                        label: 'YEAR LEVEL',
                        value: _profile.yearLevel,
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),
                      _ContactRow(
                        icon: Icons.account_balance_outlined,
                        label: 'COLLEGE / DEPARTMENT',
                        value: _profile.department,
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),
                      _ContactRow(
                        icon: Icons.location_city_outlined,
                        label: 'CAMPUS',
                        value: _profile.campus,
                      ),
                    ],
                  ),
                ),

                // ── Events Registered ──
                kSectionLabel('Events Registered'),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: kCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent registrations',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (widget.onViewAllRegistrations != null) {
                                widget.onViewAllRegistrations!();
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StudentEventsScreen(
                                      initialTabIndex: 1,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              'See All',
                              style: TextStyle(
                                color: kOrange,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('registrations')
                            .where(
                              'userId',
                              isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                            )
                            .snapshots(),
                        builder: (context, regSnapshot) {
                          if (regSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  color: kOrange,
                                ),
                              ),
                            );
                          }

                          if (!regSnapshot.hasData ||
                              regSnapshot.data!.docs.isEmpty) {
                            return _EmptyEventsState();
                          }

                          final registrations = regSnapshot.data!.docs;
                          final eventIds = registrations
                              .map((doc) => doc['eventId'] as String)
                              .toList();

                          if (eventIds.isEmpty) {
                            return _EmptyEventsState();
                          }

                          return FutureBuilder<List<QueryDocumentSnapshot>>(
                            future: _fetchEventsByIds(eventIds),
                            builder: (context, eventSnapshot) {
                              if (eventSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      color: kOrange,
                                    ),
                                  ),
                                );
                              }

                              final events = eventSnapshot.data ?? [];

                              if (events.isEmpty) {
                                return _EmptyEventsState();
                              }

                              final displayEvents = events.take(3).toList();

                              return Column(
                                children: displayEvents.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final doc = entry.value;
                                  final eventData =
                                      doc.data() as Map<String, dynamic>;

                                  final eventDate =
                                      eventData['date'] is Timestamp
                                      ? (eventData['date'] as Timestamp)
                                            .toDate()
                                      : DateTime.tryParse(
                                          eventData['date']?.toString() ?? '',
                                        );
                                  final isUpcoming =
                                      eventDate != null &&
                                      eventDate.isAfter(DateTime.now());
                                  final badgeText = isUpcoming
                                      ? 'UPCOMING'
                                      : 'PAST';
                                  final badgeColor = isUpcoming
                                      ? const Color(0xFF2196F3)
                                      : Colors.grey;

                                  String displayDate = '';
                                  if (eventDate != null) {
                                    if (isUpcoming &&
                                        eventDate
                                                .difference(DateTime.now())
                                                .inDays ==
                                            1) {
                                      displayDate =
                                          'Tomorrow • ${eventData['startTime'] ?? '9:00 AM'}';
                                    } else {
                                      displayDate =
                                          '${DateFormat('MMM d, yyyy').format(eventDate)} • ${eventData['startTime'] ?? '9:00 AM'}';
                                    }
                                  }

                                  return Column(
                                    children: [
                                      _EventCard(
                                        title:
                                            eventData['title'] ??
                                            'Untitled Event',
                                        subtitle: displayDate,
                                        badge: badgeText,
                                        badgeColor: badgeColor,
                                        imageUrl: eventData['bannerUrl'] ?? '',
                                      ),
                                      if (index < displayEvents.length - 1)
                                        Divider(
                                          height: 1,
                                          color: Colors.grey.shade100,
                                        ),
                                    ],
                                  );
                                }).toList(),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // ❌ Removed the Log Out button from here (duplicate).
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyEventsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy_outlined, size: 34, color: Colors.grey[300]),
            const SizedBox(height: 8),
            const Text(
              'No registered events yet',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Personal Identity Screen
// ─────────────────────────────────────────────────────────────
class PersonalIdentityScreen extends StatelessWidget {
  final ProfileModel profile;
  const PersonalIdentityScreen({super.key, required this.profile});

  void _showDownloadPreview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IdDownloadPreviewSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profile,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: kBg,
          appBar: const StudentAppBar(title: 'Personal Identity'),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _IdCardLabel(text: 'FRONT'),
                const SizedBox(height: 8),
                _IdCard1(profile: profile),
                const SizedBox(height: 20),
                _IdCardLabel(text: 'BACK'),
                const SizedBox(height: 8),
                _IdCard2(profile: profile),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showDownloadPreview(context),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    label: const Text(
                      'Download ID',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IdCardLabel extends StatelessWidget {
  final String text;
  const _IdCardLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

// ── Download Preview Bottom Sheet ──
class _IdDownloadPreviewSheet extends StatefulWidget {
  final ProfileModel profile;
  const _IdDownloadPreviewSheet({required this.profile});

  @override
  State<_IdDownloadPreviewSheet> createState() =>
      _IdDownloadPreviewSheetState();
}

class _IdDownloadPreviewSheetState extends State<_IdDownloadPreviewSheet> {
  final GlobalKey _frontKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();
  bool _isGenerating = false;

  Future<Uint8List?> _captureCard(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  Future<void> _downloadAsPdf() async {
    setState(() => _isGenerating = true);

    try {
      final frontBytes = await _captureCard(_frontKey);
      final backBytes = await _captureCard(_backKey);

      if (frontBytes == null || backBytes == null) {
        throw Exception('Could not capture the ID card.');
      }

      final frontImage = pw.MemoryImage(frontBytes);
      final backImage = pw.MemoryImage(backBytes);

      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'FRONT',
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: PdfColors.grey500,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(child: pw.Image(frontImage, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 20),
              pw.Text(
                'BACK',
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: PdfColors.grey500,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(child: pw.Image(backImage, fit: pw.BoxFit.contain)),
            ],
          ),
        ),
      );

      final pdfBytes = await doc.save();

      final studentId = widget.profile.studentId.isNotEmpty
          ? widget.profile.studentId
          : 'student';
      final fileName = 'BSU_ID_$studentId.pdf';

      if (!mounted) return;
      setState(() => _isGenerating = false);
      Navigator.pop(context);

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate ID PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE8E8E8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _IdCardLabel(text: 'FRONT'),
            const SizedBox(height: 8),
            RepaintBoundary(
              key: _frontKey,
              child: _IdCard1(profile: widget.profile),
            ),
            const SizedBox(height: 20),
            _IdCardLabel(text: 'BACK'),
            const SizedBox(height: 8),
            RepaintBoundary(
              key: _backKey,
              child: _IdCard2(profile: widget.profile),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGenerating ? null : _downloadAsPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: kOrange.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isGenerating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Download',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
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

// ─────────────────────────────────────────────────────────────
// _HeaderBadge
// ─────────────────────────────────────────────────────────────
class _HeaderBadge extends StatelessWidget {
  final String assetPath;
  final IconData icon;
  final double size;
  final double imageSize;

  const _HeaderBadge({
    required this.assetPath,
    required this.icon,
    this.size = 36,
    this.imageSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(icon, color: kOrange, size: size * 0.5),
        ),
      ),
    );
  }
}

// ── FRONT of ID ──
class _IdCard1 extends StatelessWidget {
  final ProfileModel profile;
  const _IdCard1({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEAEA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                _HeaderBadge(
                  assetPath: 'assets/images/bsu_logo.png',
                  icon: Icons.school,
                  size: 36,
                  imageSize: 36,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'BULACAN STATE UNIVERSITY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'OFFICIAL STUDENT IDENTIFICATION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                          fontSize: 8,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _HeaderBadge(
                  assetPath: 'assets/images/logo.png',
                  icon: Icons.local_fire_department,
                  size: 36,
                  imageSize: 52,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: profile.photoUrl.isNotEmpty
                      ? _ProfileImage(
                          photoUrl: profile.photoUrl,
                          width: 86,
                          height: 108,
                          errorBuilder: (_, __, ___) => _PhotoPlaceholder(),
                        )
                      : _PhotoPlaceholder(),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'LAST NAME',
                              value: profile.lastName.isNotEmpty
                                  ? profile.lastName.toUpperCase()
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'STUDENT NO.',
                              value: profile.studentId.isNotEmpty
                                  ? profile.studentId
                                  : '—',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'FIRST NAME',
                              value: profile.firstName.isNotEmpty
                                  ? profile.firstName.toUpperCase()
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'PROGRAM',
                              value: profile.course.isNotEmpty
                                  ? profile.course.toUpperCase()
                                  : '—',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'MIDDLE NAME',
                              value: profile.middleName.isNotEmpty
                                  ? profile.middleName.toUpperCase()
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _IdFieldWidget(
                              label: 'MAJOR',
                              value: profile.major.isNotEmpty
                                  ? profile.major.toUpperCase()
                                  : '—',
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
        ],
      ),
    );
  }
}

// ── BACK of ID ──
class _IdCard2 extends StatelessWidget {
  final ProfileModel profile;
  const _IdCard2({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEAEA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ACADEMIC INFORMATION',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IdFieldWidget(
                        label: 'YEAR LEVEL',
                        value: profile.yearLevel.isNotEmpty
                            ? profile.yearLevel.toUpperCase()
                            : '—',
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 14),
                      _IdFieldWidget(
                        label: 'COLLEGE / DEPARTMENT',
                        value: profile.department.isNotEmpty
                            ? profile.department.toUpperCase()
                            : '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Container(
                  width: 140,
                  height: 140,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: QrImageView(
                    data: FirebaseAuth.instance.currentUser?.uid ?? '',
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    size: 120,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'VALID FOR A.Y. ${_currentAcademicYear()} · NON-TRANSFERABLE',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.3,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Image.asset(
                  'assets/images/bsu_logo.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.school, size: 18, color: Colors.grey[400]),
                ),
                const SizedBox(width: 4),
                Image.asset(
                  'assets/images/logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.local_fire_department,
                    size: 18,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _currentAcademicYear() {
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable small widgets
// ─────────────────────────────────────────────────────────────

class _PhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 108,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.person, size: 40, color: Colors.grey[400]),
    );
  }
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool readOnly;
  final TextInputType keyboardType;
  final bool isPassword;
  final bool showPassword;
  final VoidCallback? onTogglePassword;

  const _EditField({
    required this.label,
    required this.controller,
    required this.icon,
    this.readOnly = false,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.showPassword = false,
    this.onTogglePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          obscureText: isPassword && !showPassword,
          style: TextStyle(
            fontSize: 14,
            color: readOnly ? Colors.grey : Colors.black87,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: Colors.grey),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onPressed: onTogglePassword,
                  )
                : null,
            filled: true,
            fillColor: readOnly ? const Color(0xFFF8F8F8) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kOrange),
            ),
          ),
        ),
      ],
    );
  }
}

class _MajorDropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String hint;

  const _MajorDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = 'Select major',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: Colors.grey),
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kOrange),
            ),
          ),
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IdFieldWidget extends StatelessWidget {
  final String label;
  final String value;
  const _IdFieldWidget({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey[400],
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        kIconBadge(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.isNotEmpty ? value : '—',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final String imageUrl;

  const _EventCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          imageUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event, color: Colors.grey),
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {},
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Edit Profile Screen
// ─────────────────────────────────────────────────────────────
class EditProfileScreen extends StatefulWidget {
  final ProfileModel profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const List<String> kMajorOptions = ['WMAD', 'DBA', 'Infrastructure'];
  static const List<String> kCollegeOptions = [
    'College of Information and Communications Technology (CICT)',
  ];
  static const List<String> kCampusOptions = [
    'Bulacan State University – Main Campus',
    'Bulacan State University – Bustos Campus',
    'Bulacan State University – Sarmiento Campus',
    'Bulacan State University – Meneses Campus',
    'Bulacan State University – Hagonoy Campus',
    'Bulacan State University – San Rafael Campus',
  ];

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _courseCtrl;
  late final TextEditingController _yearLevelCtrl;
  String? _selectedMajor;
  String? _selectedDepartment;
  String? _selectedCampus;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    // Admin-created accounts only ever have a combined `fullName` on file
    // (see student_accounts.dart) — firstName/middleName/lastName stay
    // empty until the student edits here. Pre-fill a best-effort split of
    // rawFullName so opening this form the first time doesn't present a
    // blank slate for a name that's already on record.
    String first = p.firstName;
    String middle = p.middleName;
    String last = p.lastName;
    if (first.isEmpty && last.isEmpty && p.rawFullName.trim().isNotEmpty) {
      final parts = p.rawFullName.trim().split(RegExp(r'\s+'));
      first = parts.first;
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    _firstNameCtrl = TextEditingController(text: first);
    _middleNameCtrl = TextEditingController(text: middle);
    _lastNameCtrl = TextEditingController(text: last);
    _emailCtrl = TextEditingController(text: widget.profile.email);
    _mobileCtrl = TextEditingController(text: widget.profile.mobile);
    _addressCtrl = TextEditingController(text: widget.profile.address);
    _courseCtrl = TextEditingController(text: widget.profile.course);
    _yearLevelCtrl = TextEditingController(text: widget.profile.yearLevel);
    _selectedMajor = kMajorOptions.contains(widget.profile.major)
        ? widget.profile.major
        : null;
    // Only one real college exists in this app today, so default to it
    // instead of leaving a single-option dropdown sitting on a blank hint.
    _selectedDepartment = kCollegeOptions.contains(widget.profile.department)
        ? widget.profile.department
        : kCollegeOptions.first;
    _selectedCampus = kCampusOptions.contains(widget.profile.campus)
        ? widget.profile.campus
        : null;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _courseCtrl.dispose();
    _yearLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newFirst = _firstNameCtrl.text.trim();
    final newMiddle = _middleNameCtrl.text.trim();
    final newLast = _lastNameCtrl.text.trim();

    try {
      await widget.profile.update(
        firstName: newFirst,
        middleName: newMiddle,
        lastName: newLast,
        email: _emailCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        course: _courseCtrl.text.trim(),
        major: _selectedMajor ?? '',
        yearLevel: _yearLevelCtrl.text.trim(),
        department: _selectedDepartment ?? '',
        campus: _selectedCampus ?? '',
      );

      // The update() method now automatically updates all registrations
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final displayName = [
        newFirst,
        newMiddle,
        newLast,
      ].where((p) => p.isNotEmpty).join(' ');
      await user.updateDisplayName(displayName);
    }
    if (!mounted) return;

    // Show success message with info about registrations update
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Profile updated successfully! All registrations have been updated.',
        ),
        backgroundColor: kOrange,
        duration: Duration(seconds: 3),
      ),
    );

    Navigator.pop(context, widget.profile.fullName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: const StudentAppBar(title: 'Profile'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AnimatedBuilder(
              animation: widget.profile,
              builder: (_, __) => Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF5C8A0),
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: ClipOval(
                            child: widget.profile.photoUrl.isNotEmpty
                                ? _ProfileImage(
                                    photoUrl: widget.profile.photoUrl,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () =>
                                _pickAndUploadPhoto(context, widget.profile),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: kOrange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.profile.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.profile.studentId,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.profile.email,
                      style: const TextStyle(fontSize: 12, color: kOrange),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _EditField(
                    label: 'First Name',
                    controller: _firstNameCtrl,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Middle Name',
                    controller: _middleNameCtrl,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Last Name',
                    controller: _lastNameCtrl,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Student ID',
                    controller: TextEditingController(
                      text: widget.profile.studentId,
                    ),
                    icon: Icons.badge_outlined,
                    readOnly: true,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Email Address',
                    controller: _emailCtrl,
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ID Information',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _EditField(
                    label: 'Course / Program',
                    controller: _courseCtrl,
                    icon: Icons.school_outlined,
                  ),
                  const SizedBox(height: 14),
                  _MajorDropdownField(
                    label: 'Major',
                    icon: Icons.workspace_premium_outlined,
                    value: _selectedMajor,
                    options: kMajorOptions,
                    onChanged: (value) {
                      setState(() => _selectedMajor = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Year Level',
                    controller: _yearLevelCtrl,
                    icon: Icons.stairs_outlined,
                  ),
                  const SizedBox(height: 14),
                  _MajorDropdownField(
                    label: 'College / Department',
                    icon: Icons.account_balance_outlined,
                    value: _selectedDepartment,
                    options: kCollegeOptions,
                    hint: 'Select college / department',
                    onChanged: (value) {
                      setState(() => _selectedDepartment = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _MajorDropdownField(
                    label: 'Campus',
                    icon: Icons.location_city_outlined,
                    value: _selectedCampus,
                    options: kCampusOptions,
                    hint: 'Select campus',
                    onChanged: (value) {
                      setState(() => _selectedCampus = value);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Update Profile',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Settings Screen — cleaned up
// ─────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  final ProfileModel profile;

  const SettingsScreen({super.key, required this.profile});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? kOrange).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor ?? kOrange, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing:
            trailing ??
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: StudentAppBar(title: 'Settings'),
      body: AnimatedBuilder(
        animation: widget.profile,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile Card ──
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kOrangeLight,
                            border: Border.all(
                              color: kOrange.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: widget.profile.photoUrl.isNotEmpty
                                ? _ProfileImage(
                                    photoUrl: widget.profile.photoUrl,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      size: 32,
                                      color: kOrange,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 32,
                                    color: kOrange,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.profile.fullName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.profile.email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.profile.studentId.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${widget.profile.studentId}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: kOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            color: kOrange,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditProfileScreen(
                                    profile: widget.profile,
                                  ),
                                ),
                              );
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Account Settings ──
                _buildSectionHeader('ACCOUNT SETTINGS'),
                _buildSettingsTile(
                  icon: Icons.person_outline,
                  title: 'Edit Profile',
                  subtitle: 'Update your personal information',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            EditProfileScreen(profile: widget.profile),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                _buildSettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Privacy & Security',
                  subtitle: 'Manage your security preferences',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PrivacySecurityScreen(isGuest: false),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Previously the only way in here was a one-time popup right
                // after attending an event (which stops reappearing once
                // dismissed) or tapping a notification — dismiss "Maybe
                // Later" once and there was no way back in. This is the
                // permanent way to reach it.
                _buildSettingsTile(
                  icon: Icons.rate_review_outlined,
                  title: 'Event Feedback',
                  subtitle: 'Rate events you\'ve attended',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StudentFeedbackScreen(),
                      ),
                    );
                  },
                ),
                // ❌ Removed "Fix Registrations" tile – admin only.
                // ❌ Removed "Change Password" inline form – moved to PrivacySecurityScreen.
                // ❌ Removed "Notifications" tile – placeholder, not implemented.

                // ── Support ──
                _buildSectionHeader('SUPPORT'),
                _buildSettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'Get assistance and FAQs',
                  onTap: () => launchSupportEmail(
                    context,
                    subject: 'UPRISE Support Request',
                  ),
                ),
                const SizedBox(height: 8),

                _buildSettingsTile(
                  icon: Icons.feedback_outlined,
                  title: 'Send Feedback',
                  subtitle: 'Help us improve the app',
                  onTap: () =>
                      launchSupportEmail(context, subject: 'UPRISE Feedback'),
                  iconColor: Colors.purple,
                ),
                const SizedBox(height: 8),

                _buildSettingsTile(
                  icon: Icons.info_outline,
                  title: 'About',
                  subtitle: 'App info & privacy policy',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // ── Logout (only here now) ──
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Text('Logout'),
                          content: const Text(
                            'Are you sure you want to logout?',
                            style: TextStyle(fontSize: 14),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );

                      if (confirm != true) return;

                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const StudentLogin(),
                          ),
                          (route) => false,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}
