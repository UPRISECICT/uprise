// lib/services/membership_store.dart
//
// Where a viewer's org membership lives, and how it's read.
//
// Formerly follow_store.dart, which modelled an opt-in `followedOrgIds` array
// on top of membership. Following is gone: the org feed now shows every active
// organization with no exclusion, and a student's own org is simply pinned to
// the top of it. What remains is the membership question — "is this viewer a
// member of this org, and are they an officer?" — which only students can
// answer yes to:
//
//   student  →  students/{uid}   .orgId / .isOrgOfficer
//   guest    →  nothing          (guests are never members)
//
// The org screens are shared between both roles, so they take a
// MembershipStore rather than reaching for `students/{uid}` directly. That was
// the only student-specific coupling in ~3,400 lines of otherwise generic feed
// code, and it stays that way.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Who the viewer is, org-wise. `orgId` is a formal membership — students
/// only. Never null: a viewer with no membership still browses the full feed,
/// they just get no pinned block.
class MyOrgInfo {
  final String? orgId;
  final bool isOfficer;

  const MyOrgInfo({this.orgId, this.isOfficer = false});

  bool get hasMembership => orgId != null && orgId!.isNotEmpty;

  /// 'Officer' / 'Member' / null — the label every membership pill renders.
  String? get membershipLabel =>
      hasMembership ? (isOfficer ? 'Officer' : 'Member') : null;
}

abstract class MembershipStore {
  const MembershipStore();

  /// Current membership. Implementations swallow their own errors and return
  /// an empty [MyOrgInfo] rather than throwing — the feed degrades to "no
  /// pinned block", which is the correct fallback for both roles.
  Future<MyOrgInfo> load();
}

/// students/{uid}
class StudentMembershipStore extends MembershipStore {
  const StudentMembershipStore();

  @override
  Future<MyOrgInfo> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const MyOrgInfo();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .get();
      final data = doc.data();
      final orgId = (data?['orgId'] ?? '').toString();
      return MyOrgInfo(
        orgId: orgId.isEmpty ? null : orgId,
        isOfficer: data?['isOrgOfficer'] == true,
      );
    } catch (_) {
      return const MyOrgInfo();
    }
  }
}

/// Guests have no formal membership, so this reads nothing at all — no
/// Firestore round trip, and every membership affordance in the shared org
/// screens hides itself because `hasMembership` stays false.
class GuestMembershipStore extends MembershipStore {
  const GuestMembershipStore();

  @override
  Future<MyOrgInfo> load() async => const MyOrgInfo();
}
