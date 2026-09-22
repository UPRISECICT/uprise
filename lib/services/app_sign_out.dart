// lib/services/app_sign_out.dart
//
// The one way to end a session.
//
// Signing out used to be `FirebaseAuth.instance.signOut()` written inline at
// roughly fifteen call sites, and only two of them (AuthService.logout /
// AuthService.signOut) also unregistered the device's FCM token. Every button
// a user actually pressed took one of the other thirteen paths, so the token
// stayed in `users/{uid}.fcmTokens` after logout. The next account to log in
// on that device was handed the same token and added it to *their* array, and
// from then on that phone received both accounts' push notifications — with
// no way back, because the token is still valid so the Cloud Function's
// invalid-token pruning never removes it.
//
// Route every sign-out through here. The order is the point: the token has to
// come off the outgoing user's document while that user is still
// authenticated, because the Firestore write is performed as them.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'push_notification_service.dart';

class AppSignOut {
  /// How long to wait for the push cleanup before signing out regardless.
  ///
  /// The cleanup makes two network round trips (getToken, then the Firestore
  /// arrayRemove). Offline or on a bad connection those can hang, and a Log Out
  /// button that appears frozen is worse than a token cleaned up on the next
  /// successful logout — so this is a bound, not a guarantee.
  static const Duration _cleanupTimeout = Duration(seconds: 5);

  /// Unregisters this device for push, then ends the Firebase session.
  ///
  /// Safe to call with no user signed in. Never throws on the cleanup: a push
  /// failure must not strand someone in a half-signed-out state, so the
  /// sign-out itself always runs.
  static Future<void> signOut([FirebaseAuth? auth]) async {
    final instance = auth ?? FirebaseAuth.instance;
    final uid = instance.currentUser?.uid;

    if (uid != null && uid.isNotEmpty) {
      try {
        await PushNotificationService.unregister(
          uid,
        ).timeout(_cleanupTimeout);
      } catch (e) {
        debugPrint('AppSignOut: push unregister failed for $uid: $e');
      }
    }

    await instance.signOut();
  }
}
