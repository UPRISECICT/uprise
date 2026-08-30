// lib/services/proposal_review_log.dart
//
// Append-only history of what happened to an event proposal.
//
// Before this, the whole conversation between an admin and an org lived in
// a single `adminFeedback` string on the proposal document, written by both
// the rejection path and the revision path. A second revision request
// overwrote the first, so an org that had been sent back twice could only
// ever see the most recent note — and the admin had no record of what they
// had already asked for. `adminFeedback` is still written (the org's view
// modal and existing documents depend on it), but it is now the *latest*
// entry rather than the only one.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The actions a proposal's history can record. Stored as plain strings so
/// old entries keep reading if this list grows.
class ProposalReviewAction {
  static const String submitted = 'submitted';
  static const String resubmitted = 'resubmitted';
  static const String revisionRequested = 'revision_requested';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  /// Human label for a stored action value.
  static String label(String action) => switch (action) {
    submitted => 'Submitted',
    resubmitted => 'Resubmitted',
    revisionRequested => 'Revision requested',
    approved => 'Approved',
    rejected => 'Rejected',
    _ => action,
  };
}

class ProposalReviewLog {
  ProposalReviewLog._();

  static CollectionReference<Map<String, dynamic>> _col(String proposalId) =>
      FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .collection('reviews');

  /// Appends one entry. Never throws into the caller — a proposal must
  /// still get approved even if writing its history entry fails, the same
  /// fire-and-forget rule the notification and activity-log calls follow.
  static Future<void> add({
    required String proposalId,
    required String action,
    String? message,
    String? byName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _col(proposalId).add({
        'action': action,
        'message': (message ?? '').trim(),
        'byUid': user?.uid ?? '',
        'byName': byName ?? user?.displayName ?? user?.email ?? 'Unknown',
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }

  /// Oldest first, so the UI reads top-to-bottom as a timeline.
  ///
  /// Ordered client-side: `at` is a server timestamp that is momentarily
  /// null on the writing client, and an `orderBy` would drop those entries
  /// from the list until the server round-trip lands — the org would watch
  /// their own resubmission vanish and reappear.
  static Stream<List<ProposalReviewEntry>> watch(String proposalId) {
    return _col(proposalId).snapshots().map((snap) {
      final entries = snap.docs
          .map((d) => ProposalReviewEntry.fromDoc(d))
          .toList();
      entries.sort((a, b) {
        final at = a.at, bt = b.at;
        if (at == null && bt == null) return 0;
        if (at == null) return 1; // pending write sorts last
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      return entries;
    });
  }
}

class ProposalReviewEntry {
  final String id;
  final String action;
  final String message;
  final String byName;
  final Timestamp? at;

  const ProposalReviewEntry({
    required this.id,
    required this.action,
    required this.message,
    required this.byName,
    required this.at,
  });

  factory ProposalReviewEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ProposalReviewEntry(
      id: doc.id,
      action: (d['action'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      byName: (d['byName'] ?? 'Unknown').toString(),
      at: d['at'] as Timestamp?,
    );
  }

  String get label => ProposalReviewAction.label(action);
}
