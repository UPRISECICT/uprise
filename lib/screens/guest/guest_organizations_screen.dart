// lib/screens/guest/guest_organizations_screen.dart
//
// Organizations, as a guest sees them.
//
// This is deliberately a thin wrapper, not a fork. The list, the merged
// events+announcements feed, the avatar rail, the media grid and the 4-tab org
// profile are all the same widgets students use — sharing them is why those
// screens take an [OrgBrowsingConfig] instead of reaching for `students/{uid}`
// and the student detail screens directly.
//
// What the config changes for a guest:
//
//   • no membership — no Member/Officer pill, and no org pinned to the top
//     of the feed or the directory
//   • no broadcasts — that's a member-only channel, and a guest belongs to
//     no org, so the avatar rail always opens the org profile
//   • CICT-Only / Members-Only events are filtered out everywhere, and
//     announcements are limited to targetAudience == 'Public'
//   • events, announcements and merch open the *guest* screens, so a guest can
//     never reach a view offering student-only actions
//
// A visitor (no approved account) gets exactly the same read-only browse as
// an approved guest — the feed spans every organization either way, and
// neither has a membership to pin.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/membership_store.dart';
import '../../services/guest_event_registration.dart';
import '../../widgets/common/org_browsing_config.dart';
import '../student/student_organizations_screen.dart';
import 'guest_events_screen.dart';
import 'guest_merchandise_screen.dart';
import 'guest_announcement_detail_screen.dart';

/// How a guest of the given [classification] browses organizations.
///
/// Top-level rather than built inline in the screen below, because guest Home
/// opens org profiles from its "Organizations for you" rail too. That call
/// site used to pass no config at all and silently fell back to
/// `OrgBrowsingConfig.student`, which handed a guest the member-only broadcast
/// icon and unfiltered CICT-Only / Members-Only content.
OrgBrowsingConfig guestOrgBrowsingConfig(String classification) {
  return OrgBrowsingConfig(
    membershipStore: const GuestMembershipStore(),
    showMembership: false,
    enableBroadcast: false,
    publicAnnouncementsOnly: true,
    audienceFilter: (audience) =>
        classificationAllowsAudience(audience, classification),
    onOpenEvent: openGuestEventById,
    onOpenAnnouncement: openGuestAnnouncementById,
    onOpenMerch: (ctx) => Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const GuestMerchandiseScreen()),
    ),
  );
}

/// Loads the event and opens the guest detail screen — which enforces the
/// same audience rule again at its register button.
Future<void> openGuestEventById(BuildContext context, String eventId) async {
  final doc = await _guestFetch(context, 'events', eventId, 'event');
  if (doc == null || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          GuestEventDetailScreen(event: FirestoreEvent.fromDoc(doc)),
    ),
  );
}

Future<void> openGuestAnnouncementById(
  BuildContext context,
  String announcementId,
) async {
  final doc = await _guestFetch(
    context,
    'announcements',
    announcementId,
    'announcement',
  );
  if (doc == null || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GuestAnnouncementDetailScreen(
        data: doc.data() as Map<String, dynamic>,
      ),
    ),
  );
}

/// Shared fetch-with-spinner, mirroring openEventById's shape on the
/// student side. Returns null when the doc is gone or the read failed.
Future<DocumentSnapshot?> _guestFetch(
  BuildContext context,
  String collection,
  String id,
  String label,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
  );
  try {
    final doc = await FirebaseFirestore.instance
        .collection(collection)
        .doc(id)
        .get();
    if (!context.mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();
    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('This $label is no longer available.')),
      );
      return null;
    }
    return doc;
  } catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open $label: $e')));
    return null;
  }
}

class GuestOrganizationsScreen extends StatefulWidget {
  const GuestOrganizationsScreen({super.key});

  @override
  State<GuestOrganizationsScreen> createState() =>
      _GuestOrganizationsScreenState();
}

class _GuestOrganizationsScreenState extends State<GuestOrganizationsScreen> {
  // Resolved once. Until it lands, assume the most restrictive tier so a
  // BulSUan-only event can't flash into view for an Outsider mid-load.
  String _classification = 'Outsider';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identity = await resolveGuestIdentity();
    if (!mounted) return;
    setState(() {
      _classification = identity?.classification ?? 'Outsider';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilding with a different config once the classification resolves
    // would re-run the feed query, so hold the first frame instead.
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StudentOrganizationsScreen(
      config: guestOrgBrowsingConfig(_classification),
    );
  }
}
