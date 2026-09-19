// lib/services/org_directory.dart
//
// One live index of the `organizations` collection, keyed by document id.
//
// Announcements freeze the org's display name into the doc as `authorName` at
// post time (org_announcements.dart writes it from `shortName ?? name`), so a
// later rename leaves every older post showing the old name. They also never
// write a logo field at all. Both surfaces therefore have to resolve the org
// themselves, and the only stable handle they hold is `orgId` — which is
// exactly what the cache this replaces got wrong: it keyed by lowercased org
// name, so it missed for precisely the renamed orgs whose names were stale.
//
// The collection is small (one doc per campus org) and every announcement feed
// needs it, so this keeps a single process-wide snapshot listener rather than
// a per-screen fetch. `revision` ticks on every change so feeds can rebuild
// when the index first loads or an org edits its profile.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class OrgDirectoryEntry {
  final String name;
  final String logoUrl;

  const OrgDirectoryEntry({required this.name, required this.logoUrl});
}

class OrgDirectory {
  OrgDirectory._();

  static final Map<String, OrgDirectoryEntry> _byId = {};
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Bumps on every change to the index. Feeds that render org names or logos
  /// should rebuild on it — otherwise a card built before the first snapshot
  /// arrives keeps its `authorName` fallback until something else happens to
  /// rebuild it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get isLoaded => _byId.isNotEmpty;

  /// Idempotent — call it from anywhere that's about to show org names.
  static void start() {
    if (_sub != null) return;
    _sub = FirebaseFirestore.instance
        .collection('organizations')
        .snapshots()
        .listen(
          (snap) {
            _byId
              ..clear()
              ..addEntries(
                snap.docs.map(
                  (d) => MapEntry(d.id, _entryFrom(d.data())),
                ),
              );
            revision.value++;
          },
          // A failure here is not fatal: every caller falls back to the name
          // stored on the announcement, which is what shipped before this
          // existed. Losing the listener silently beats losing the feed.
          onError: (_) {},
        );
  }

  static OrgDirectoryEntry _entryFrom(Map<String, dynamic> data) {
    // `name` is what the org profile screen displays, so match it rather than
    // the `shortName ?? name` that announcements froze into `authorName`.
    final name = [
      data['name'],
      data['orgName'],
      data['shortName'],
    ].map((v) => (v ?? '').toString().trim()).firstWhere(
          (v) => v.isNotEmpty,
          orElse: () => '',
        );

    return OrgDirectoryEntry(
      name: name,
      logoUrl: (data['logoUrl'] ?? '').toString().trim(),
    );
  }

  static OrgDirectoryEntry? entryFor(String? orgId) =>
      (orgId == null || orgId.isEmpty) ? null : _byId[orgId];

  /// The org's current display name, or `''` when the org is unknown — the
  /// caller decides what to fall back to (usually the announcement's own
  /// `authorName`, which is all a deleted org leaves behind).
  static String nameFor(String? orgId) => entryFor(orgId)?.name ?? '';

  /// The org's logo, or `''`. Feeds pass this straight to
  /// `AppImage.provider`, which handles both base64 and network sources.
  static String logoFor(String? orgId) => entryFor(orgId)?.logoUrl ?? '';
}
