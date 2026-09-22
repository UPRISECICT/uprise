// Shared helpers for the mobile change-password screens (guest + student).
//
// Firebase treats updatePassword as a sensitive operation: it rejects the
// call with `requires-recent-login` unless the ID token came from a sign-in
// within roughly the last five minutes. That holds for a freshly issued
// token only, so the forced first-login screens succeed while the voluntary
// "change my password" entries from Settings — reached on a session that is
// hours or days old — always failed.
//
// The web settings screens (org_settings.dart, admin/settings.dart) already
// solve this by reauthenticating with the current password first. These
// helpers carry that same pattern to mobile without a third copy of it.

import 'package:firebase_auth/firebase_auth.dart';

/// Reauthenticates [user] with [currentPassword], then sets [newPassword].
///
/// Only needed on the voluntary path — the forced first-login screens run
/// seconds after sign-in, where the token is still recent and the user has
/// nothing but the admin-issued temp password to offer anyway.
///
/// Throws [FirebaseAuthException] with code `no-current-email` when the
/// account has no email to build an [EmailAuthProvider] credential from.
Future<void> reauthenticateAndUpdatePassword({
  required User user,
  required String currentPassword,
  required String newPassword,
}) async {
  final email = user.email;
  if (email == null || email.isEmpty) {
    throw FirebaseAuthException(
      code: 'no-current-email',
      message: 'No email on this account to confirm your identity with.',
    );
  }
  await user.reauthenticateWithCredential(
    EmailAuthProvider.credential(email: email, password: currentPassword),
  );
  await user.updatePassword(newPassword);
}

/// Maps a [FirebaseAuthException] to something a student or guest can act on.
///
/// Firebase's own `message` is written for developers — the raw
/// `requires-recent-login` text ("This operation is sensitive and requires
/// recent authentication...") tells a user nothing they can do.
String passwordChangeErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'requires-recent-login':
      return 'For your security, please sign out and sign in again, then '
          'change your password.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Current password is incorrect.';
    case 'weak-password':
      return 'That password is too weak. Please choose a stronger one.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'network-request-failed':
      return 'No connection. Check your internet and try again.';
    case 'no-current-email':
      return 'This account has no email address, so your password cannot be '
          'changed here. Please contact the CICT admin.';
    case 'user-mismatch':
      return 'Those credentials belong to a different account.';
    default:
      return e.message ?? 'Failed to change password (${e.code}).';
  }
}
