// lib/models/letter_type.dart
//
// The kinds of letter an organization can request, and what each one needs.
//
// `letterType` already existed on every `letter_requests` document, but it
// was hardcoded to 'General' at the single point of creation and never read
// as anything else — so there was no request taxonomy, and an admin opening
// the queue could not tell an endorsement from a venue permit without
// opening the attachment. Reviving the field costs nothing at the data
// layer: existing documents already carry 'General', which is kept below as
// a valid (if unlisted) fallback.
//
// [requiresAttachment] is the other half of the change. The old form
// refused to submit without a file, which forced the org to write the
// letter itself before it could ask for one — backwards for the request
// types where the whole point is that the admin's office drafts it.
class LetterType {
  final String id;
  final String label;
  final String description;
  final bool requiresAttachment;

  const LetterType({
    required this.id,
    required this.label,
    required this.description,
    this.requiresAttachment = false,
  });

  static const List<LetterType> all = [
    LetterType(
      id: 'Endorsement',
      label: 'Endorsement',
      description: 'Endorsing the org or its members to an outside party.',
    ),
    LetterType(
      id: 'Permit to Use Venue',
      label: 'Permit to Use Venue',
      description: 'Requesting the use of a campus facility.',
    ),
    LetterType(
      id: 'Excuse Letter',
      label: 'Excuse Letter',
      description: 'Excusing members from classes for an approved activity.',
    ),
    LetterType(
      id: 'Solicitation',
      label: 'Solicitation',
      description: 'Seeking sponsorship or donations for an activity.',
    ),
    LetterType(
      id: 'Invitation',
      label: 'Invitation',
      description: 'Inviting a guest, speaker or judge to an event.',
    ),
    LetterType(
      id: 'Certification',
      label: 'Certification',
      description: 'Certifying membership, standing or participation.',
    ),
    LetterType(
      id: 'Other',
      label: 'Other',
      // The only type that still demands a file: if it fits none of the
      // categories above, the admin needs the org's own draft to work from.
      description: 'Anything else — attach your draft.',
      requiresAttachment: true,
    ),
  ];

  /// Lookup that never returns null. Unknown or legacy values (notably the
  /// old hardcoded 'General') resolve to 'Other', which is the safe answer:
  /// it is the type that keeps requiring an attachment, exactly as every
  /// pre-existing request already had one.
  static LetterType byId(String? id) {
    return all.firstWhere(
      (t) => t.id == id,
      orElse: () => all.firstWhere((t) => t.id == 'Other'),
    );
  }

  static bool needsAttachment(String? id) => byId(id).requiresAttachment;

  static List<String> get ids => [for (final t in all) t.id];
}
