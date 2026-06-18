import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/notification_service.dart';
import '../firebase/messaging/local_notification_service.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FirebaseFirestore.instance),
);

/// In-app notification inbox for the current user — drives NotificationsScreen.
final userNotificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  // Stream.empty() closes without emitting, leaving a StreamProvider stuck
  // in AsyncLoading forever — same bug class as currentUserProfileProvider
  // had. Emit an explicit empty list so signed-out callers resolve cleanly.
  if (user == null) return Stream.value(const []);
  return ref.watch(notificationServiceProvider).watchForUser(user.uid);
});

/// Unread count — drives the bell-icon badge.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  if (user == null) return Stream.value(0);
  return ref.watch(notificationServiceProvider).watchUnreadCount(user.uid);
});

/// Writes the current FCM token to `fcm_tokens/{uid}` — the collection
/// Cloud Functions' `_sendNotification` already reads from (functions/index.js).
/// Previously this wrote to `users/{uid}.fcmToken`, a field the existing
/// Cloud Functions never look at, so server-sent pushes silently never had
/// a token to deliver to. Writing to the collection Cloud Functions already
/// expect makes the existing push infrastructure functional without
/// modifying any Cloud Function (preserves "no new backend services" scope).
Future<void> _saveFcmToken(FirebaseFirestore db, String uid, String token) =>
    db.collection('fcm_tokens').doc(uid).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });

/// Bootstraps push notifications and FCM token registration.
/// Watch this provider in the root widget (_HandyTrustRouterApp) to keep it
/// alive for the entire session. It is a no-op when the user is signed out.
final notificationInitProvider = Provider<void>((ref) {
  final authAsync = ref.watch(authStateChangesProvider);
  final user = authAsync.asData?.value;

  if (user == null || user.isAnonymous) return;

  final service = LocalNotificationService.instance;
  final firestore = FirebaseFirestore.instance;

  // Start listening for foreground messages (idempotent). Skipped if the
  // user has turned off notifications in their preferences.
  service.startForegroundListener(
    isEnabled: () => ref.read(currentUserProvider).asData?.value?.notificationsEnabled ?? true,
  );

  // Request permission + register FCM token — fire and forget
  Future<void> register() async {
    try {
      await service.requestPermission();
      final token = await service.getToken();
      if (token != null) {
        await _saveFcmToken(firestore, user.uid, token);
      }
    } catch (e) {
      debugPrint('[notificationInitProvider] token registration failed: $e');
    }
  }

  register();

  // Re-register whenever the FCM token rotates
  final sub = service.onTokenRefresh.listen((newToken) {
    _saveFcmToken(firestore, user.uid, newToken).catchError(
      (e) => debugPrint('[notificationInitProvider] token refresh save failed: $e'),
    );
  });

  ref.onDispose(sub.cancel);
});
