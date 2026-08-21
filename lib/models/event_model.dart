import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/helpers.dart' as helpers;

/// Where an event sits relative to now, based on its date + start/end time.
/// The one canonical classification — see [EventModel.timeStatus].
enum EventTimeStatus { upcoming, ongoing, completed }

class EventModel {
  final String id;
  final String title;
  final String description;
  final String location;
  final String category;


  final String otherCategory;
  final bool issuesCertificate;
  final String orgName;
  final String orgId;

  
  final DateTime date;

  /// Time strings (e.g. "7:00 AM" or "19:00")
  final String startTime;
  final String endTime;

  final String audience;
  final String status;
  final bool isPublic;

  final String? proposalId;
  final String? createdFromProposalId;
  final String? logoUrl;
  final String? bannerUrl;

  /// When the event doc was created — null for older records written
  /// before this field existed. Used for feed-card "NEW" badge timing;
  /// not the same as [date], which is when the event itself happens.
  final DateTime? createdAt;

  /// Max registrants, org-set and optional — null (or omitted) means
  /// unlimited slots, matching the org proposal form's default.
  final int? capacity;

  /// Whether to automatically mark attendees as late.
  /// Default: false (for backward compatibility with existing events)
  final bool markLate;

  /// Number of minutes after event start time before marking late.
  /// Only applies when [markLate] is true.
  /// Default: 15 minutes
  final int lateAfterMinutes;

  /// Race-safe registration counter maintained transactionally alongside
  /// the `registrations` writes (see EventDetailScreen._registerForEvent) —
  /// used for "Most Popular" sorting. Not included in [toMap] since it's
  /// server/transaction-owned, not something a client should overwrite.
  final int registeredCount;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.category,
    this.otherCategory = '',
    this.issuesCertificate = false,
    required this.orgName,
    required this.orgId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.audience,
    required this.status,
    required this.isPublic,
    this.proposalId,
    this.createdFromProposalId,
    this.logoUrl,
    this.bannerUrl,
    this.createdAt,
    this.capacity,
    this.markLate = false,
    this.lateAfterMinutes = 15,
    this.registeredCount = 0,
  });

  /// Combines the event date and start time
  DateTime get fullDateTime => helpers.combineDateAndTime(date, startTime);

  /// Combines the event date and end time — defaults to 23:59 same day when
  /// [endTime] is blank, so an event with no stated end time still counts
  /// as "over" only after its whole day has passed.
  DateTime get endDateTime => endTime.trim().isEmpty
      ? DateTime(date.year, date.month, date.day, 23, 59)
      : helpers.combineDateAndTime(date, endTime);

  /// The one canonical upcoming/ongoing/completed classification, replacing
  /// several hand-rolled copies of this same start/end comparison that used
  /// to live in individual screens.
  EventTimeStatus get timeStatus {
    final now = DateTime.now();
    if (now.isBefore(fullDateTime)) return EventTimeStatus.upcoming;
    if (now.isAfter(endDateTime)) return EventTimeStatus.completed;
    return EventTimeStatus.ongoing;
  }

  /// Getter para sa image URL na may fallback placeholder
  String get imageUrl {
    if (bannerUrl != null && bannerUrl!.isNotEmpty) {
      return bannerUrl!;
    }
    // Return default placeholder image (orange background with "No Image" text)
    // This will show a placeholder in the EventImage widget
    return '';
  }

  /// Check kung may image
  bool get hasImage => bannerUrl != null && bannerUrl!.isNotEmpty;

  /// The org's custom label when they picked "Other" and typed one in,
  /// otherwise just [category] — this is what should actually be shown to
  /// students instead of a generic "OTHER" badge.
  String get displayCategory => category == 'Other' && otherCategory.isNotEmpty
      ? otherCategory
      : category;

  /// The org proposal form's audience chips treat 'Public' as exclusive of
  /// the other three (selecting it clears/locks the rest), so a normal
  /// event only ever has EITHER 'Public' alone OR one-to-three of
  /// 'CICT Only' / 'Members Only' / 'BulSUan' combined. Combined non-public
  /// audiences use AND logic — "CICT Only, Members Only" means the student
  /// must satisfy both, not either. A legacy/manually-edited record that
  /// still has 'Public' alongside other values is treated as unrestricted
  /// (matches the org form's own rule and keeps old records from becoming
  /// accidentally inaccessible) rather than evaluated against the rest.
  /// [userData] is the signed-in student's own `users/{uid}` doc (for org
  /// membership + email); [course] is their `students/{uid}.course`
  /// (for the CICT check) — both already-existing fields, nothing new.
  static bool audienceAllowsMember({
    required String audience,
    required String eventOrgId,
    required Map<String, dynamic>? userData,
    String? course,
  }) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (values.isEmpty || values.contains('Public')) return true;

    bool isCictStudent() {
      const cictCourses = {'BSIT', 'BSIS', 'BLIS'};
      return course != null && cictCourses.contains(course.toUpperCase());
    }

    bool isMemberOfEventOrg() {
      if (userData == null) return false;
      final userOrgId = (userData['orgId'] ?? '').toString();
      if (userOrgId.isEmpty || userOrgId != eventOrgId) return false;
      final role = (userData['orgRole'] ?? '').toString();
      return role == 'member' ||
          role == 'officer' ||
          userData['isOrgMember'] == true ||
          userData['isOrgOfficer'] == true;
    }

    bool isBulsuan() {
      final email = (userData?['email'] ?? '').toString().toLowerCase();
      return email.endsWith('@ms.bulsu.edu.ph');
    }

    bool singleAllowed(String v) {
      switch (v) {
        case 'CICT Only':
          return isCictStudent();
        case 'Members Only':
          return isMemberOfEventOrg();
        case 'BulSUan':
          return isBulsuan();
        default:
          // Unrecognized/legacy label — don't block eligibility on it.
          return true;
      }
    }

    return values.every(singleAllowed);
  }

  /// Session-less variant of [audienceAllowsMember] for a viewer with no
  /// account context at all (e.g. a visitor guest) — blocks anything
  /// requiring membership/CICT/BulSUan verification, allows everything else.
  static bool audienceAllowsPublic(String audience) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (values.isEmpty) return true;

    bool singleAllowed(String v) {
      switch (v) {
        case 'CICT Only':
        case 'Members Only':
        case 'BulSUan':
          return false;
        default:
          return true;
      }
    }

    return values.any(singleAllowed);
  }

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    final rawDate = d['date'];

    final parsedDate = rawDate is Timestamp
        ? rawDate.toDate()
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

    return EventModel(
      id: doc.id,
      title: (d['title'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      location: (d['location'] ?? '').toString(),
      category: (d['category'] ?? 'Other').toString(),
      otherCategory: (d['otherCategory'] ?? '').toString(),
      issuesCertificate: d['issuesCertificate'] == true,
      orgName: (d['orgName'] ?? '').toString(),
      orgId: (d['orgId'] ?? '').toString(),
      date: parsedDate,
      startTime: (d['startTime'] ?? '').toString(),
      endTime: (d['endTime'] ?? '').toString(),
      audience: (d['audience'] ?? 'Public').toString(),
      status: (d['status'] ?? 'approved').toString(),
      isPublic: d['isPublic'] == true,
      proposalId: d['proposalId'] as String?,
      createdFromProposalId: d['createdFromProposalId'] as String?,
      logoUrl: d['logoUrl'] as String?,
      bannerUrl: d['bannerUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      capacity: (d['capacity'] as num?)?.toInt(),
      markLate: d['markLate'] == true,
      lateAfterMinutes: (d['lateAfterMinutes'] as num?)?.toInt() ?? 15,
      registeredCount: (d['registeredCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'location': location,
    'category': category,
    'otherCategory': otherCategory,
    'issuesCertificate': issuesCertificate,
    'orgName': orgName,
    'orgId': orgId,
    'date': Timestamp.fromDate(date),
    'startTime': startTime,
    'endTime': endTime,
    'audience': audience,
    'status': status,
    'isPublic': isPublic,
    'proposalId': proposalId,
    'createdFromProposalId': createdFromProposalId,
    'logoUrl': logoUrl,
    'bannerUrl': bannerUrl,
    'capacity': capacity,
    'markLate': markLate,
    'lateAfterMinutes': lateAfterMinutes,
  };

  /// Uses full date + start time
  bool get isPast => fullDateTime.isBefore(DateTime.now());

  String get formattedDate => DateFormat('MMMM dd, yyyy').format(date);

  String get formattedTime {
    if (startTime.isNotEmpty && endTime.isNotEmpty) {
      return '$startTime – $endTime';
    }
    if (startTime.isNotEmpty) {
      return startTime;
    }
    return '—';
  }
}
