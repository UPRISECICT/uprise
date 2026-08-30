// lib/models/adviser_rank.dart
//
// What an adviser at each rank is actually responsible for.
//
// The app models an adviser as contact metadata attached to an
// organization: a name, an email, a phone number and a rank. They have no
// login and no authority anywhere in the system — the only place an adviser
// is functionally in the loop is `functions/index.js`, which emails the
// *organization's* credentials to `adviserEmail` so the adviser can share
// the org account. So "adviser roles" named a rank and nothing else; what
// the rank obliged anyone to do was never written down.
//
// This is that missing half. It is deliberately descriptive, not
// enforcing: nothing here grants a permission, because advisers still have
// no account to hold one. It gives the org, the admin and the student-facing
// org page one agreed answer to "what does our adviser actually do?", and
// gives the endorsement recorded on an event proposal something to mean.
class AdviserRank {
  final String id;
  final String label;
  final List<String> responsibilities;

  const AdviserRank({
    required this.id,
    required this.label,
    required this.responsibilities,
  });

  /// The five ranks the Adviser Roles form already offers. Kept in this
  /// order so the existing dropdown is unchanged.
  static const List<AdviserRank> all = [
    AdviserRank(
      id: 'Dean',
      label: 'Dean',
      responsibilities: [
        'Approves college-wide activities and their budgets',
        'Signs endorsements addressed outside the university',
        'Resolves matters escalated by program chairs',
      ],
    ),
    AdviserRank(
      id: 'Program Chair',
      label: 'Program Chair',
      responsibilities: [
        'Endorses event proposals before they reach the admin office',
        'Reviews financial and accomplishment reports each semester',
        'Confirms the officer roster at the start of every term',
      ],
    ),
    AdviserRank(
      id: 'Department Head',
      label: 'Department Head',
      responsibilities: [
        'Endorses event proposals for department-level activities',
        'Coordinates schedules and venues with other departments',
        'Reviews accomplishment reports before submission',
      ],
    ),
    AdviserRank(
      id: 'Coordinator',
      label: 'Coordinator',
      responsibilities: [
        'Guides officers through planning and logistics',
        'Checks event requirements before a proposal is submitted',
        'Attends activities as the organization representative',
      ],
    ),
    AdviserRank(
      id: 'Faculty',
      label: 'Faculty',
      responsibilities: [
        'Advises officers on day-to-day activities',
        'Reviews event proposals before submission',
        'Serves as the first point of contact for members',
      ],
    ),
  ];

  /// Lookup that never returns null. Falls back to Faculty, which is what
  /// the row list already defaults to — note the view dialog used to
  /// default to 'Instructor', a value that is not in the dropdown at all.
  static AdviserRank byId(String? id) {
    return all.firstWhere(
      (r) => r.id == id,
      orElse: () => all.firstWhere((r) => r.id == 'Faculty'),
    );
  }

  static List<String> get ids => [for (final r in all) r.id];

  static List<String> responsibilitiesFor(String? id) =>
      byId(id).responsibilities;
}
