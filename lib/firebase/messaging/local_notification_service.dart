import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level FCM background handler — must be a top-level function and annotated
/// so the Dart compiler does not tree-shake it in release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages on Android are delivered by FCM natively.
  // On iOS the system shows them automatically.
  debugPrint('[FCM] Background message received: ${message.messageId}');
}

/// Singleton notification service.
/// Call [init] once after Firebase is initialized (before any notifications
/// can be shown), then use the show* helpers to display local notifications.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _fcm = FirebaseMessaging.instance;

  static const _channel = AndroidNotificationChannel(
    'handy_trust_main',
    'HandyTrust',
    description: 'Job updates, messages, and payment notifications.',
    importance: Importance.high,
  );

  static bool _alwaysEnabled() => true;

  bool _foregroundListenerRegistered = false;
  bool Function() _isEnabled = _alwaysEnabled;

  /// Initialise flutter_local_notifications and register the FCM background handler.
  /// Must be called once from main() after WidgetsFlutterBinding.ensureInitialized()
  /// and after Firebase.initializeApp().
  Future<void> init() async {
    // Register background handler before any other FCM setup
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Create the Android notification channel
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }
  }

  /// Request OS-level notification permission (iOS + Android 13+).
  /// Returns true if granted or provisional.
  Future<bool> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[FCM] requestPermission failed: $e');
      return false;
    }
  }

  /// Returns the current FCM registration token, or null if unavailable.
  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  /// Returns a stream that fires whenever the FCM token is refreshed.
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  /// Start listening for foreground FCM messages and show local notifications.
  /// Safe to call multiple times — only registers the listener once.
  /// [isEnabled] is re-checked on every message so a live preference change
  /// (toggled mid-session) takes effect without re-registering the listener.
  void startForegroundListener({bool Function() isEnabled = _alwaysEnabled}) {
    _isEnabled = isEnabled;
    if (_foregroundListenerRegistered) return;
    _foregroundListenerRegistered = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!_isEnabled()) return;
      final notification = message.notification;
      if (notification == null) return;
      _show(
        id: message.hashCode,
        title: notification.title ?? 'HandyTrust',
        body: notification.body ?? '',
        payload: message.data['route'] as String?,
      );
    });
  }

  /// Show a local notification for a new chat message.
  Future<void> showMessageNotification({
    required String senderName,
    required String preview,
    required String jobId,
  }) =>
      _show(
        id: jobId.hashCode ^ 0x01,
        title: 'New message from $senderName',
        body: preview,
        payload: '/chat/$jobId',
      );

  /// Show a local notification for a job status change.
  Future<void> showJobStatusNotification({
    required String jobId,
    required String title,
    required String body,
  }) =>
      _show(
        id: jobId.hashCode ^ 0x02,
        title: title,
        body: body,
        payload: '/job/$jobId',
      );

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[LocalNotif] show failed: $e');
    }
  }
}
