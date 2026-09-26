import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../student/student_login.dart';
import '../student/student_events_screen.dart';
import '../student/student_feedback_screen.dart';
import '../student/student_certificates_screen.dart';
import '../student/student_notification_settings_screen.dart';
import '../student/student_organization_details_screen.dart';
import '../../widgets/shared/app_support.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/common/action_tile.dart';
import '../../services/app_sign_out.dart';
import '../../utils/download_saver.dart';
import '../../utils/feedback_helper.dart';

// kCardDecoration / kSectionLabel / kIconBadge / kActionTile moved to
// widgets/common/action_tile.dart so the guest screens can share them.
// Re-exported here so this file's existing call sites — and anything
// importing them *from* here — keep resolving.
export '../../widgets/common/action_tile.dart';

// ─────────────────────────────────────────────────────────────
// Shared constants - brand palette
// ─────────────────────────────────────────────────────────────
// Aliases onto AppColors rather than repeated literals: kOrangeLight and kBg
// are byte-identical to primarySoft and background, and were duplicated here
// only because this file predates those tokens.
const kOrange = AppColors.primaryDark;
const kOrangeLight = AppColors.primarySoft;
const kBg = AppColors.background;

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
  // Read off the same organizations/{orgId} doc as orgName (no extra read),
  // for the My Organizations row: the acronym as its title, since the full
  // name ellipsized at phone width, and the org's own logo.
  String orgShortName = '';
  String orgLogoUrl = '';
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
    // Org-tag fields are cleared with FieldValue.delete() by org_profile.dart
    // when a student is removed from a org's roster, so a fresh doc.data()
    // simply won't contain these keys anymore — falling back to the
    // previous in-memory value (like the fields above do) would silently
    // keep the stale org tag forever instead of clearing it.
    orgId = data['orgId'] ?? '';
    orgRole = data['orgRole'] ?? '';
    isOrgOfficer = data['isOrgOfficer'] == true;
    isOrgMember = data['isOrgMember'] == true;
    officerPosition = data['officerPosition'] ?? '';
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
        orgShortName = cachedData['orgShortName'] ?? '';
        orgLogoUrl = cachedData['orgLogoUrl'] ?? '';
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
            final org = orgSnap.data() ?? {};
            orgName = org['orgName'] ?? org['name'] ?? '';
            orgShortName = (org['shortName'] ?? '').toString().trim();
            orgLogoUrl = (org['logoUrl'] ?? '').toString();
          }
        } else {
          // Membership was untagged (orgId now cleared above) — drop the
          // last-known org name too, otherwise the "My Organizations" card
          // keeps rendering it since that card's visibility is gated on
          // orgName.isNotEmpty, not on orgId.
          orgName = '';
          orgShortName = '';
          orgLogoUrl = '';
        }

        await _saveCache(user.uid);

        // `users.fullName` (read by org_profile.dart's Members list) can
        // drift from `students.fullName` — the org side only backfills it
        // the first time a student is tagged (_tagMatchingStudentAccount),
        // and update() below only ever wrote to `students`. Repair the
        // drift here so the org roster picks up the correct name the next
        // time this student opens the app, without needing them to re-save
        // their profile.
        if (fullName.isNotEmpty) {
          final usersRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          final usersSnap = await usersRef.get();
          if (usersSnap.exists &&
              (usersSnap.data()?['fullName'] ?? '') != fullName) {
            await usersRef.set({
              'firstName': firstName,
              'middleName': middleName,
              'lastName': lastName,
              'fullName': fullName,
            }, SetOptions(merge: true));
          }
        }
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
        'orgShortName': orgShortName,
        'orgLogoUrl': orgLogoUrl,
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

      // Keep `users.fullName` in sync — org_profile.dart's Members list
      // reads it directly, and this write path previously only ever
      // touched `students`, letting the two drift apart (see CLAUDE.md:
      // student updates must write to both collections).
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName,
      }, SetOptions(merge: true));

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

/// The one settings-style row used by both SettingsScreen and the profile
/// page's Edit Profile / Digital ID / Certificates actions. Lifted out of
/// _SettingsScreenState so the two can't drift apart.
Widget kActionTile({
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
          color: Colors.grey.withAlpha(10),
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
          color: (iconColor ?? kOrange).withAlpha(31),
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

  // Cached once — this whole screen is wrapped in an AnimatedBuilder tied
  // to _profile, which rebuilds on every notifyListeners() (cache load, then
  // network load, then any profile edit). A future created in build() would
  // re-run the activity queries on each of those.
  late final Future<_ActivityStats?> _activityFuture = _loadActivityStats();

  /// Events › My Events. The home shell passes a callback that switches tabs
  /// in place; standalone, the Events screen is pushed on its My Events tab.
  void _openMyEvents() {
    final onView = widget.onViewAllRegistrations;
    if (onView != null) {
      onView();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StudentEventsScreen(initialTabIndex: 2),
      ),
    );
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

                // ── Quick actions: Personal Information / Digital ID /
                // Certificates. Stacked settings-style rows, sharing
                // kActionTile with the Settings screen. ──
                const SizedBox(height: 14),
                kActionTile(
                  icon: Icons.person_outline,
                  title: 'Personal Information',
                  // Read-only now, so no "Update info" promise.
                  subtitle: 'Your details on record',
                  iconColor: kOrange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(profile: _profile),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                kActionTile(
                  icon: Icons.credit_card,
                  title: 'Digital ID',
                  subtitle: 'View & download',
                  iconColor: const Color(0xFF2196F3),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonalIdentityScreen(profile: _profile),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                kActionTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Certificates',
                  subtitle: 'Your awards',
                  iconColor: const Color(0xFF16A34A),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentCertificatesScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // The permanent way into Event Feedback — the post-event popup
                // stops reappearing once dismissed, and notifications scroll
                // away. Beside Certificates since feedback gates them.
                kActionTile(
                  icon: Icons.rate_review_outlined,
                  title: 'Event Feedback',
                  subtitle: 'Rate events you\'ve attended',
                  iconColor: Colors.purple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentFeedbackScreen(),
                    ),
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
                        child: _MyOrgRow(
                          name: _profile.orgName,
                          shortName: _profile.orgShortName,
                          logoUrl: _profile.orgLogoUrl,
                          role: _profile.isOrgOfficer
                              ? (_profile.officerPosition.isNotEmpty
                                    ? _profile.officerPosition.toUpperCase()
                                    : 'OFFICER')
                              : (_profile.isOrgMember ? 'MEMBER' : null),
                        ),
                      ),
                    ),
                  ),
                ],

                // ── My Activity ──
                kSectionLabel('My Activity'),
                _MyActivitySection(
                  future: _activityFuture,
                  onOpenEvents: _openMyEvents,
                  onOpenCertificates: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentCertificatesScreen(),
                    ),
                  ),
                  onOpenFeedback: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentFeedbackScreen(),
                    ),
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

// ── My Activity ──
// Replaces the old "Events Registered" list, which repeated Events › My
// Events three rows at a time — usually three PAST events behind grey
// calendar placeholders. A profile reads better as a summary of what the
// student has done, plus the one thing they can act on.

class _ActivityStats {
  final int registered;
  final int attended;
  final int certificates;

  /// Attended events with no review yet — these hold up certificates.
  final int needsFeedback;

  const _ActivityStats({
    required this.registered,
    required this.attended,
    required this.certificates,
    required this.needsFeedback,
  });
}

/// One pass over the student's registrations, attendance, certificates and
/// reviews. Each part fails on its own, so an unreadable certificates query
/// shows "—" there instead of blanking the whole section.
Future<_ActivityStats?> _loadActivityStats() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final db = FirebaseFirestore.instance;

  final regSnap = await db
      .collection('registrations')
      .where('userId', isEqualTo: uid)
      .get();
  final registeredIds = {
    for (final d in regSnap.docs)
      if ((d.data()['eventId'] ?? '').toString().isNotEmpty)
        d.data()['eventId'].toString(),
  };

  // Attendance: one collection-group query (the one My Events uses). If that
  // index isn't available, read this student's attendance doc under each
  // registered event instead — every check-in writer keys it by UID.
  Set<String> attended = {};
  try {
    final attSnap = await db
        .collectionGroup('attendances')
        .where('studentId', isEqualTo: uid)
        .get();
    for (final doc in attSnap.docs) {
      final status = (doc.data()['status'] ?? '').toString();
      if (status != 'present' && status != 'late') continue;
      final eventId = doc.reference.parent.parent?.id;
      if (eventId != null) attended.add(eventId);
    }
  } catch (_) {
    final docs = await Future.wait(
      registeredIds.map(
        (id) => db
            .collection('events')
            .doc(id)
            .collection('attendances')
            .doc(uid)
            .get()
            .then<DocumentSnapshot<Map<String, dynamic>>?>((d) => d)
            .catchError((_) => null),
      ),
    );
    for (final doc in docs) {
      final status = (doc?.data()?['status'] ?? '').toString();
      if (doc != null && (status == 'present' || status == 'late')) {
        attended.add(doc.reference.parent.parent!.id);
      }
    }
  }

  // Same rule as the Event Feedback screen: only events that still exist and
  // are approved count. A deleted event leaves its `attendances` subcollection
  // behind, which the collection-group query above still finds — that's how
  // this once said "3 need feedback" where the Feedback screen listed 2.
  if (attended.isNotEmpty) {
    final ids = attended.toList();
    final live = <String>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      try {
        final snap = await db
            .collection('events')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          if (doc.data()['status'] == 'approved') live.add(doc.id);
        }
      } catch (_) {
        // Unreadable chunk: leave those out rather than over-count.
      }
    }
    attended = live;
  }

  final results = await Future.wait<Object?>([
    // An aggregate count — the certificate documents themselves aren't needed.
    db
        .collection('certificates')
        .where('recipientUid', isEqualTo: uid)
        .count()
        .get()
        .then<Object?>((s) => s.count ?? 0)
        .catchError((_) => null),
    FeedbackHelper.ratedEventIds(
      uid,
    ).then<Object?>((ids) => ids).catchError((_) => <String>{}),
  ]);

  final rated = results[1] as Set<String>;
  return _ActivityStats(
    registered: registeredIds.length,
    attended: attended.length,
    certificates: (results[0] as int?) ?? -1,
    needsFeedback: attended.where((id) => !rated.contains(id)).length,
  );
}

class _MyActivitySection extends StatelessWidget {
  final Future<_ActivityStats?> future;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenCertificates;
  final VoidCallback onOpenFeedback;

  const _MyActivitySection({
    required this.future,
    required this.onOpenEvents,
    required this.onOpenCertificates,
    required this.onOpenFeedback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ActivityStats?>(
      future: future,
      builder: (context, snap) {
        final stats = snap.data;
        final loading = snap.connectionState != ConnectionState.done;

        if (!loading && stats != null && stats.registered == 0) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: kCardDecoration(),
            child: Column(
              children: [
                const Text(
                  'No activity yet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Events you register for, attend and get certificates '
                  'from will add up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        String value(int? n) =>
            loading || n == null || n < 0 ? '—' : n.toString();

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: kCardDecoration(),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActivityStat(
                      value: value(stats?.registered),
                      label: 'Registered',
                      accent: kOrange,
                      onTap: onOpenEvents,
                    ),
                    const _ActivityDivider(),
                    _ActivityStat(
                      value: value(stats?.attended),
                      label: 'Attended',
                      accent: const Color(0xFF059669),
                      onTap: onOpenFeedback,
                    ),
                    const _ActivityDivider(),
                    _ActivityStat(
                      value: value(stats?.certificates),
                      label: 'Certificates',
                      accent: const Color(0xFF2563EB),
                      onTap: onOpenCertificates,
                    ),
                  ],
                ),
              ),
            ),
            // Only when there is something to do, so it reads as a nudge
            // rather than a permanent fixture.
            if (!loading && stats != null && stats.needsFeedback > 0) ...[
              const SizedBox(height: 10),
              _NeedsFeedbackBanner(
                count: stats.needsFeedback,
                onTap: onOpenFeedback,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityStat extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ActivityStat({
    required this.value,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
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

class _ActivityDivider extends StatelessWidget {
  const _ActivityDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: VerticalDivider(width: 1, color: Colors.grey.shade200),
    );
  }
}

class _NeedsFeedbackBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NeedsFeedbackBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD97706);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: const Color(0xFFFFFBEB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: amber.withAlpha(70)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: amber.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        count == 1
                            ? '1 event needs your feedback'
                            : '$count events need your feedback',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rate them so organizations can issue your '
                        'certificates.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[700],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: amber,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of My Organizations: logo, acronym, full name, role.
///
/// The acronym is the title because the full name used to be the only line
/// and ellipsized at phone width ("CICT Student Innov…"). The full name still
/// sits underneath, small and allowed two lines, since an acronym alone
/// doesn't tell a newer student which org it is. With no acronym on record,
/// the full name is the title and isn't repeated.
class _MyOrgRow extends StatelessWidget {
  final String name;
  final String shortName;
  final String logoUrl;

  /// Badge text — "MEMBER", or the officer's position. Null hides it.
  final String? role;

  const _MyOrgRow({
    required this.name,
    required this.shortName,
    required this.logoUrl,
    required this.role,
  });

  String get _initials {
    final source = shortName.isNotEmpty ? shortName : name;
    final words = source.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length >= 2) {
      return words.take(2).map((w) => w[0]).join().toUpperCase();
    }
    if (source.isEmpty) return '?';
    return source.substring(0, source.length < 2 ? 1 : 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasShort = shortName.isNotEmpty && shortName != name;
    final initials = Center(
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: kOrange,
        ),
      ),
    );

    return Row(
      children: [
        // The org's own logo; its initials on the brand tint when it has none
        // (or it fails to load) rather than a generic people icon.
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: kOrange.withAlpha(26),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          clipBehavior: Clip.antiAlias,
          child: logoUrl.isEmpty
              ? initials
              : AppImage(
                  source: logoUrl,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  showLoadingIndicator: false,
                  placeholder: initials,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasShort ? shortName : name,
                maxLines: hasShort ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              if (hasShort) ...[
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (role != null) ...[
          const SizedBox(width: 8),
          // Capped so a long officer title can't squeeze the name column.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: kOrange.withAlpha(26),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: kOrange,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey[300]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Personal Identity Screen
// ─────────────────────────────────────────────────────────────
class PersonalIdentityScreen extends StatefulWidget {
  final ProfileModel profile;
  const PersonalIdentityScreen({super.key, required this.profile});

  @override
  State<PersonalIdentityScreen> createState() => _PersonalIdentityScreenState();
}

class _PersonalIdentityScreenState extends State<PersonalIdentityScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isDownloading = false;

  /// True for the one frame the card is captured for the PDF: it swaps the
  /// on-screen "Tap to enlarge" caption for "Scan to verify", which is what a
  /// printed ID should say.
  bool _capturing = false;

  ProfileModel get profile => widget.profile;

  /// A page, not a dialog — same as the guest Digital ID, so the QR gets the
  /// whole screen and event staff can scan it from a distance.
  void _openFullscreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenQrScreen(
          fullName: profile.fullName.trim().isNotEmpty
              ? profile.fullName.trim()
              : (profile.rawFullName.trim().isNotEmpty
                    ? profile.rawFullName.trim()
                    : 'Student'),
        ),
      ),
    );
  }

  Future<Uint8List?> _captureCard() async {
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final cardBytes = await _captureCard();
      if (cardBytes == null) {
        throw Exception('Could not capture the ID card.');
      }

      final doc = pw.Document()
        ..addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            build: (context) => pw.Center(
              child: pw.Image(
                pw.MemoryImage(cardBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        );
      final pdfBytes = await doc.save();

      final studentId = profile.studentId.isNotEmpty
          ? profile.studentId
          : 'student';
      // Straight to Downloads — no share sheet.
      final saved = await saveToDownloads(pdfBytes, 'BSU_ID_$studentId.pdf');
      await announceDownload(messenger, saved);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to download ID: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
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
                RepaintBoundary(
                  key: _cardKey,
                  child: _StudentIdCard(
                    profile: profile,
                    onFullscreen: _capturing ? null : _openFullscreen,
                  ),
                ),
                const SizedBox(height: 14),

                // Second, more discoverable route to the same screen —
                // the 100px QR on the card is a small tap target to find
                // on its own.
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openFullscreen,
                    child: const SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Text(
                          'Tap to show full-screen QR for easy scanning',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _download,
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kOrange.withAlpha(153),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    label: Text(
                      _isDownloading ? 'Downloading…' : 'Download ID',
                      style: const TextStyle(
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
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STUDENT DIGITAL ID
//
// One card, built on the guest Digital ID's design
// (lib/screens/guest/guest_digital_id_screen.dart, _DigitalIdCard):
// gradient header band, UPRISE branding, name + status chip, avatar,
// dashed divider, detail rows beside the QR, gradient footer.
//
// The information is the student's: photo, full name, student number,
// program, year level, the UID QR and the A.Y. validity line. Major and
// College/Department are deliberately not shown.
//
// The guest file's _DetailRow/_DashedDivider are private to it, so the
// equivalents below are local rather than editing the guest screen.
// ─────────────────────────────────────────────────────────────
class _StudentIdCard extends StatelessWidget {
  final ProfileModel profile;

  /// Opens the full-screen QR. Null while the card is being captured for the
  /// PDF, where there is nothing to tap and the "Tap to enlarge" caption would
  /// be baked into the downloaded ID.
  final VoidCallback? onFullscreen;

  const _StudentIdCard({required this.profile, this.onFullscreen});

  String get _initials {
    final f = profile.firstName.trim();
    final l = profile.lastName.trim();
    if (f.isEmpty && l.isEmpty) {
      final raw = profile.rawFullName.trim();
      return raw.isEmpty ? '?' : raw[0].toUpperCase();
    }
    return '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'
        .toUpperCase();
  }

  String _currentAcademicYear() {
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final name = profile.fullName.trim().isNotEmpty
        ? profile.fullName.trim()
        : (profile.rawFullName.trim().isNotEmpty
              ? profile.rawFullName.trim()
              : 'Student');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: kOrange.withAlpha(15),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header band ──
          Container(
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kOrange, Color(0xFFD47A00)]),
            ),
          ),

          // ── Branding + name + avatar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'UPRISE',
                            style: TextStyle(
                              color: kOrange,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'BULACAN STATE UNIVERSITY',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          letterSpacing: 0.3,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF059669).withAlpha(77),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 10,
                              color: Color(0xFF059669),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'VERIFIED STUDENT',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (profile.email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFAAAAAA),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5E3D9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kOrange.withAlpha(64), width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: profile.photoUrl.isNotEmpty
                      ? _ProfileImage(
                          photoUrl: profile.photoUrl,
                          width: 70,
                          height: 70,
                          errorBuilder: (_, __, ___) => _IdInitials(_initials),
                        )
                      : _IdInitials(_initials),
                ),
              ],
            ),
          ),

          const _IdDashedDivider(),

          // ── Details + QR ──
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IdDetailRow(
                        label: 'STUDENT NO.',
                        value: profile.studentId,
                      ),
                      const SizedBox(height: 6),
                      _IdDetailRow(label: 'PROGRAM', value: profile.course),
                      const SizedBox(height: 6),
                      _IdDetailRow(
                        label: 'YEAR LEVEL',
                        value: profile.yearLevel,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A.Y. ${_currentAcademicYear()} · NON-TRANSFERABLE',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: onFullscreen,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: uid,
                          version: QrVersions.auto,
                          size: 100,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF1A1A2E),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        onFullscreen == null
                            ? 'Scan to verify'
                            : 'Tap to enlarge',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom strip ──
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kOrange, Color(0xFFD47A00)]),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdInitials extends StatelessWidget {
  final String initials;
  const _IdInitials(this.initials);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: kOrange,
        ),
      ),
    );
  }
}

/// Label-over-value row on the ID card.
class _IdDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _IdDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: Color(0xFFAAAAAA),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value.trim().isNotEmpty ? value.toUpperCase() : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _IdDashedDivider extends StatelessWidget {
  const _IdDashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _IdDashedLinePainter(),
      ),
    );
  }
}

class _IdDashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEEEEEE)
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────
// FULL-SCREEN QR
//
// Ported from the guest Digital ID's _FullscreenQrScreen so both roles get
// the same scanning experience. The card's 100px code is fine to look at but
// not to scan across a registration table; this gives it the whole screen on
// a dark ground for maximum contrast.
//
// The payload stays the bare Firebase uid — org_attendance_qr.dart routes
// anything that isn't prefixed `UPRISE|GUEST|` to the student lookup, so
// wrapping or prefixing it here would break check-in.
//
// Styled with plain TextStyle rather than GoogleFonts, matching
// _StudentIdCard above (the guest copy uses beVietnamPro because its whole
// file does).
// ─────────────────────────────────────────────────────────────
class _FullscreenQrScreen extends StatelessWidget {
  final String fullName;

  const _FullscreenQrScreen({required this.fullName});

  static const Color _dark = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Student ID — Scan QR',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              fullName.toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'VERIFIED STUDENT',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF059669),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: kOrange.withAlpha(64),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: QrImageView(
              data: uid,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: _dark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: _dark,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: kOrange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Show to event staff for scanning',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable small widgets
// ─────────────────────────────────────────────────────────────

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
  // Every field here is read-only: the organization supplies a student's
  // details when it creates the account, and corrections go through the web
  // admin. The photo is the one thing the student still owns, and it writes
  // straight through ProfileModel.updatePhotoUrl() rather than a form save.
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _courseCtrl;
  late final TextEditingController _yearLevelCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    // Admin-created accounts only ever have a combined `fullName` on file
    // (see student_accounts.dart), so firstName/middleName/lastName can be
    // empty. Fall back to a best-effort split of rawFullName so the form
    // shows the name that's actually on record.
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
    _emailCtrl = TextEditingController(text: p.email);
    _courseCtrl = TextEditingController(text: p.course);
    _yearLevelCtrl = TextEditingController(text: p.yearLevel);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _courseCtrl.dispose();
    _yearLevelCtrl.dispose();
    super.dispose();
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
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'These details are maintained by your organization. '
                          'Contact them or the CICT admin to have anything '
                          'corrected.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _EditField(
                    label: 'First Name',
                    controller: _firstNameCtrl,
                    icon: Icons.person_outline,
                    readOnly: true,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Middle Name',
                    controller: _middleNameCtrl,
                    icon: Icons.person_outline,
                    readOnly: true,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Last Name',
                    controller: _lastNameCtrl,
                    icon: Icons.person_outline,
                    readOnly: true,
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
                    readOnly: true,
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
                    readOnly: true,
                  ),
                  const SizedBox(height: 14),
                  _EditField(
                    label: 'Year Level',
                    controller: _yearLevelCtrl,
                    icon: Icons.stairs_outlined,
                    readOnly: true,
                  ),
                ],
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
  /// Delegates to the file-level [kSectionLabel], the same way
  /// [_buildSettingsTile] delegates to [kActionTile] — this used to be a
  /// near-copy differing only in padding, and the guest Settings screen now
  /// renders the shared one.
  Widget _buildSectionHeader(String title) => kSectionLabel(title);

  /// Delegates to the file-level [kActionTile] so the profile page's action
  /// rows and these settings rows share one definition.
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) => kActionTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    iconColor: iconColor,
    trailing: trailing,
  );

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
                      ],
                    ),
                  ),
                ),

                // ── Account Settings ──
                // No profile entry here, and no edit affordance on the card
                // above: Personal Information lives on the profile page, and
                // it's read-only, so a "settings" entry for it would be
                // misleading and a pencil icon doubly so.
                _buildSectionHeader('ACCOUNT SETTINGS'),
                _buildSettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Choose what reaches you',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const StudentNotificationSettingsScreen(),
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

                      await AppSignOut.signOut();
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
