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

  // ── Tap handling ──
  //
  // Set by main.dart (mobile) to open the tapped notification. Deliberately
  // a callback rather than importing the student screens here: this file is
  // also imported by main_web.dart and auth_service.dart, and the student
  // screen chain pulls in `dart:io` (student_events_screen.dart), which does
  // not compile for web. The web entry simply never sets this and taps stay
  // a no-op there, which is correct — web pushes are org/admin surfaces.
  static void Function(String notificationId)? onNotificationTap;

  static void _handleTap(RemoteMessage message) {
    final id = (message.data['notificationId'] ?? '').toString();
    if (id.isEmpty) return;
    onNotificationTap?.call(id);
  }

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
      // App alive in the background, student taps the push in the tray.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
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

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // Claim the uid only once a token is actually on file. Setting it up
      // front meant a single denied permission prompt turned register() into
      // a permanent no-op: the user could grant notifications in OS settings
      // afterwards and still never get a token until the process restarted.
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = kIsWeb
          ? await messaging.getToken(
              vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey,
            )
          : await messaging.getToken();
      if (token == null) return;

      await _saveToken(uid, token);
      _registeredUid = uid;

      messaging.onTokenRefresh.listen((refreshed) => _saveToken(uid, refreshed));

      // Cold start: the app was fully closed and launched BY the tap, so
      // onMessageOpenedApp never fires and the message is waiting here
      // instead. Handled in register() rather than initialize() because
      // register() runs from RoleRouter once a uid exists, by which point
      // there is a Navigator to push onto and an auth user to load the
      // notification for.
      if (!kIsWeb) {
        final initial = await messaging.getInitialMessage();
        if (initial != null) _handleTap(initial);
      }
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
  //
  // Do not call this directly from a screen — use AppSignOut.signOut(), which
  // guarantees it runs before FirebaseAuth.signOut(). Removing the token from
  // users/{uid} needs the outgoing user's own auth context, so the order
  // matters, and a logout that skips this step leaves the device registered to
  // that account forever.
  static Future<void> unregister(String uid) async {
    if (uid.isEmpty) return;
    _registeredUid = null;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = kIsWeb
          ? await messaging.getToken(
              vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey,
            )
          : await messaging.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));

      // Drop the token itself, not just this user's reference to it. Without
      // this the next account to log in on this device is handed the SAME
      // token, so one stale entry left behind anywhere re-links the two
      // accounts. getToken() mints a fresh one on the next register().
      await messaging.deleteToken();
    } catch (e) {
      // Surfaced rather than swallowed: a failed arrayRemove is exactly how a
      // device ends up receiving a previous user's notifications, and silence
      // made that invisible.
      debugPrint('PushNotificationService.unregister failed for $uid: $e');
    }
  }
}
