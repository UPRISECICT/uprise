import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/models/event_model.dart';

void main() {
  group('Event audience access', () {
    test('allows everyone to access a Public event', () {
      final result = EventModel.audienceAllowsMember(
        audience: 'Public',
        eventOrgId: 'org-001',
        userData: null,
      );

      expect(result, isTrue);
    });

    test('allows a CICT student to access a CICT Only event', () {
      final result = EventModel.audienceAllowsMember(
        audience: 'CICT Only',
        eventOrgId: 'org-001',
        userData: null,
        course: 'BSIT',
      );

      expect(result, isTrue);
    });

    test('allows an organization member to access a Members Only event', () {
      final result = EventModel.audienceAllowsMember(
        audience: 'Members Only',
        eventOrgId: 'org-001',
        userData: {
          'orgId': 'org-001',
          'orgRole': 'member',
        },
      );

      expect(result, isTrue);
    });

    test('blocks a non-member from a Members Only event', () {
      final result = EventModel.audienceAllowsMember(
        audience: 'Members Only',
        eventOrgId: 'org-001',
        userData: {
          'orgId': 'org-002',
          'orgRole': 'member',
        },
      );

      expect(result, isFalse);
    });
    });
  });
}