import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  // ── Foreground display ──
  //
  // Android does NOT show an FCM notification while the app is open — the
  // message is handed to FirebaseMessaging.onMessage and dropped unless the
  // app draws it itself. Backgrounded/closed apps are fine (the OS shows it),
  // but anyone testing with UPRISE open saw nothing. This re-posts foreground
  // messages as local notifications on the same channel the Cloud Function
  // targets.
  static const String channelId = 'uprise_notifications';
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Call once at startup, after Firebase.initializeApp(). Mobile only — the
  /// browser shows web pushes through the service worker.
  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      // High importance is what makes Android show a heads-up banner rather
      // than filing the notification silently in the tray. Channels are
      // immutable once created, so this id must stay stable.
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              'UPRISE notifications',
              description: 'Announcements, events, messages and reminders',
              importance: Importance.high,
            ),
          );

      FirebaseMessaging.onMessage.listen(_showForeground);
    } catch (e) {
      debugPrint('PushNotificationService.initialize failed: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      // Stable per notification doc, so a redelivered message replaces its
      // earlier banner instead of stacking a duplicate.
      id: (message.data['notificationId'] ?? message.messageId ?? '').hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'UPRISE notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

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
