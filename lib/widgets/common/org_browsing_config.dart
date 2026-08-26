// lib/widgets/common/org_browsing_config.dart
//
// How a given role browses organizations.
//
// The organizations list and the org profile screen are shared between
// students and guests. Almost all of that code is role-agnostic — the feed,
// the avatar rail, the tabs, the cards. What differs is a small, fixed set of
// decisions: where membership is read from, what content is visible, which
// detail screens open, and whether member-only affordances appear at all.
//
// Passing those as eight loose constructor arguments meant threading every
// one of them through leaf widgets. Bundling them means the leaves forward a
// single value and new knobs don't ripple.

import 'package:flutter/material.dart';

import '../../services/membership_store.dart';

class OrgBrowsingConfig {
  /// Where the viewer's org membership is read from.
  final MembershipStore membershipStore;

  /// Whether to surface membership affordances (the Member/Officer pill, and
  /// pinning the viewer's own org to the top of the feed and the directory).
  /// Guests are never members.
  final bool showMembership;

  /// Whether the broadcast thread is reachable. Broadcasts are a member-only
  /// channel, so guests get the org profile instead.
  final bool enableBroadcast;

  /// Extra visibility gate on events. Null means no additional filtering
  /// (students see whatever any org publishes); guests pass
  /// `classificationAllowsAudience` so CICT-Only and Members-Only events
  /// never surface anywhere in the feed.
  final bool Function(String audience)? audienceFilter;

  /// Restricts announcements to `targetAudience == 'Public'`.
  final bool publicAnnouncementsOnly;

  /// Detail-screen navigation. Null falls back to the student screens.
  /// Guests override all three so they can never reach a screen that offers
  /// student-only actions.
  final void Function(BuildContext context, String eventId)? onOpenEvent;
  final void Function(BuildContext context, String announcementId)?
  onOpenAnnouncement;
  final void Function(BuildContext context)? onOpenMerch;

  const OrgBrowsingConfig({
    this.membershipStore = const StudentMembershipStore(),
    this.showMembership = true,
    this.enableBroadcast = true,
    this.audienceFilter,
    this.publicAnnouncementsOnly = false,
    this.onOpenEvent,
    this.onOpenAnnouncement,
    this.onOpenMerch,
  });

  /// The student defaults — full access, student record, student screens.
  static const student = OrgBrowsingConfig();

  bool allowsEventAudience(String audience) =>
      audienceFilter == null || audienceFilter!(audience);

  bool allowsAnnouncement(Map<String, dynamic> data) =>
      !publicAnnouncementsOnly ||
      (data['targetAudience'] ?? 'Public').toString() == 'Public';
}
