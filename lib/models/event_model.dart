import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EventModel {
  final String id;
  final String title;
  final String description;
  final String location;
  final String category;
  final String orgName;
  final String orgId;

  /// Date only (from Firestore)
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

  /// Max registrants, org-set and optional — null (or omitted) means
  /// unlimited slots, matching the org proposal form's default.
  final int? capacity;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.category,
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
    this.capacity,
  });

  /// Combines the event date and start time
  DateTime get fullDateTime {
    try {
      int hour = 0;
      int minute = 0;

      if (startTime.isNotEmpty) {
        if (startTime.toLowerCase().contains('am') ||
            startTime.toLowerCase().contains('pm')) {
          // Example: 7:30 PM
          final cleanTime = startTime
              .replaceAll(RegExp(r'[AP]M', caseSensitive: false), '')
              .trim();

          final parts = cleanTime.split(':');
          hour = int.parse(parts[0]);
          minute = int.parse(parts[1]);

          if (startTime.toLowerCase().contains('pm') && hour < 12) {
            hour += 12;
          }

          if (startTime.toLowerCase().contains('am') && hour == 12) {
            hour = 0;
          }
        } else {
          // Example: 19:30
          final parts = startTime.split(':');
          hour = int.parse(parts[0]);
          minute = int.parse(
            parts.length > 1 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : '0',
          );
        }
      }

      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return date;
    }
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

  /// Mirrors guest_events_screen.dart's `_audienceAllowed` — an event can
  /// target more than one audience at once (comma-joined in the same
  /// field), and passes if ANY one of them would allow this student. Only
  /// 'Members Only' is actually enforced here: 'CICT Only'/'BulSUan' have
  /// no equivalent student classification data to check against, so they
  /// fall through as allowed on the student side (same as they always have).
  /// [userData] is the signed-in student's own `users/{uid}` doc.
  static bool audienceAllowsMember({
    required String audience,
    required String eventOrgId,
    required Map<String, dynamic>? userData,
  }) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (values.isEmpty) return true;

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

    return values.any((v) => v == 'Members Only' ? isMemberOfEventOrg() : true);
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
      capacity: (d['capacity'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'location': location,
    'category': category,
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
