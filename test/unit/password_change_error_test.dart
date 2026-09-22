import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/services/password_change_service.dart';

FirebaseAuthException err(String code, [String? message]) =>
    FirebaseAuthException(code: code, message: message);

void main() {
  // The bug this guards: the guest/student change-password screens passed
  // FirebaseAuthException.message straight to the snackbar, so a stale
  // session surfaced Firebase's raw "This operation is sensitive and
  // requires recent authentication..." string instead of an instruction
  // the user can act on.
  test('requires-recent-login never leaks the raw Firebase wording', () {
    final message = passwordChangeErrorMessage(
      err(
        'requires-recent-login',
        'This operation is sensitive and requires recent authentication. '
            'Log in again before retrying this request.',
      ),
    );
    expect(message, isNot(contains('sensitive')));
    expect(message, isNot(contains('retrying this request')));
    expect(message.toLowerCase(), contains('sign in again'));
  });

  test('a bad current password reads as a current-password problem', () {
    for (final code in ['wrong-password', 'invalid-credential']) {
      expect(
        passwordChangeErrorMessage(err(code)),
        'Current password is incorrect.',
        reason: 'code $code should map to the current-password message',
      );
    }
  });

  test('weak-password points at the new password, not the old one', () {
    final message = passwordChangeErrorMessage(err('weak-password'));
    expect(message.toLowerCase(), contains('password is too weak'));
    expect(message, isNot(contains('Current password')));
  });

  test('throttling and offline states get their own guidance', () {
    expect(
      passwordChangeErrorMessage(err('too-many-requests')).toLowerCase(),
      contains('too many attempts'),
    );
    expect(
      passwordChangeErrorMessage(err('network-request-failed')).toLowerCase(),
      contains('connection'),
    );
  });

  test('an account with no email explains why reauth is impossible', () {
    expect(
      passwordChangeErrorMessage(err('no-current-email')).toLowerCase(),
      contains('email'),
    );
  });

  test('unmapped codes fall back to the Firebase message', () {
    expect(
      passwordChangeErrorMessage(err('some-new-code', 'Something specific.')),
      'Something specific.',
    );
  });

  test('unmapped codes with no message still produce something readable', () {
    final message = passwordChangeErrorMessage(err('some-new-code'));
    expect(message, isNotEmpty);
    expect(message, contains('some-new-code'));
  });
}
