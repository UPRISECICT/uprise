import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // ⭐ IDAGDAG ITO
import 'role_router.dart'; // RoleRouter handles login vs home
import 'utils/theme.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'screens/student/student_notifications_screen.dart';
import 'providers/event_provider.dart'; // ⭐ IDAGDAG ITO

/// Lets PushNotificationService push a route from outside the widget tree
/// when a student taps a notification in the tray.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Background/terminated-app FCM handler. Must be a top-level function and
/// must be registered before runApp, or the plugin drops background messages
/// entirely. The body stays empty on purpose: the OS already draws
/// notification-type messages, and the `notifications` doc is the source of
/// truth once the app is opened — registering the handler is the point.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Deliberately no Firebase.initializeApp() here: this isolate does no
  // Firestore work, and initializing it on every background push is wasted
  // startup cost.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TEMPORARY DIAGNOSTIC — remove once the RenderFlex overflow is tracked
  // down. Flutter prints the first exception in full and abbreviates every
  // repeat to "Another exception was thrown: ...", which drops the widget
  // and file:line. forceReport defeats that so each occurrence prints the
  // full block, including "The relevant error-causing widget was:".
  if (kDebugMode) {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kIsWeb) {
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: false);
    } else {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
    // Must be registered before runApp.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Tapping a push opens the notification list with that notification
    // already actioned, so push taps reuse the in-app tap routing rather
    // than duplicating it.
    PushNotificationService.onNotificationTap = (notificationId) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) =>
              StudentNotificationsScreen(initialNotificationId: notificationId),
        ),
      );
    };

    // Not awaited: displaying pushes must never delay first frame.
    PushNotificationService.initialize();
    print('✅ Firebase initialized!');
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      print('⚠️ Firebase already initialized, continuing...');
    } else {
      print('❌ Firebase error: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider( // ⭐ I-WRAP ANG APP SA MultiProvider
      providers: [
        ChangeNotifierProvider(create: (_) => EventProvider()), // ⭐ IDAGDAG ITO
        // Add other providers here if needed
      ],
      child: MaterialApp(
        title: 'UPRISE',
        navigatorKey: rootNavigatorKey,
        theme: appTheme,
        builder: (context, child) {
          // This sits above the root Navigator, so the shared web dialog
          // theme also reaches screens opened through Navigator.push.
          // Mobile keeps its current dialog presentation unchanged.
          if (!kIsWeb || child == null) return child ?? const SizedBox();
          return Theme(
            data: Theme.of(context).copyWith(dialogTheme: upriseWebDialogTheme),
            child: child,
          );
        },
        debugShowCheckedModeBanner: false,
        home: const RoleRouter(), // ✅ Always start here
      ),
    );
  }
}
