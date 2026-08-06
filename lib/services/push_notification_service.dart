import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// Registers this device for real OS/browser-level push (phone notification
// tray on mobile, browser notification on web) and stores the FCM token on
// `users/{uid}.fcmTokens`. The `sendPushForNotification` Cloud Function
// (functions/index.js) triggers on every `notifications` doc that
// NotificationService already writes and delivers a push to those tokens —
// no change needed to NotificationService itself, this only wires up where
// the push actually gets sent to.
//
// iOS is intentionally left out for now: real APNs delivery needs an Apple
// Developer Program membership and an APNs key uploaded in Firebase Console,
// neither of which exist yet. iOS falls through to requestPermission()
// returning denied/not-determined and this becomes a no-op there.
class PushNotificationService {
  // Web Push certificate key pair, from Firebase Console → Project Settings
  // → Cloud Messaging → Web Push certificates.
  static const String _webVapidKey =
      'BIJQbpd6E_WwV55OlGEaSI0-AMLy7a9sahbAZrza0YvJBY1mk9EqMKZVwtvLO_L2QXVC-C5snpoShhwX54aSMEI';

  static String? _registeredUid;

  static Future<void> register(String uid) async {
    if (uid.isEmpty || _registeredUid == uid) return;
    _registeredUid = uid;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = kIsWeb
          ? await messaging.getToken(
              vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey,
            )
          : await messaging.getToken();
      if (token != null) await _saveToken(uid, token);

      messaging.onTokenRefresh.listen((refreshed) => _saveToken(uid, refreshed));
    } catch (e) {
      debugPrint('PushNotificationService.register failed: $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  // Called on sign-out so a shared/borrowed device stops receiving the
  // previous user's pushes once they log out.
  static Future<void> unregister(String uid) async {
    if (uid.isEmpty) return;
    _registeredUid = null;
    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey,
            )
          : await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
