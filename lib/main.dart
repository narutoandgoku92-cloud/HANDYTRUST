import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/firebase/firebase_initializer.dart';
import 'firebase/messaging/local_notification_service.dart';
import 'providers/init_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be fully initialized before any Firebase service is
  // touched. LocalNotificationService's constructor reads
  // FirebaseMessaging.instance and its init() calls
  // FirebaseMessaging.onBackgroundMessage — both throw [core/no-app] if
  // Firebase.initializeApp() hasn't completed yet.
  try {
    await initializeFirebase();
  } catch (e) {
    // Swallowed here — firebaseInitializationProvider retries this same
    // call inside the widget tree and surfaces the existing "Failed to
    // initialize the app" error screen if it fails again.
    debugPrint('[main] initial Firebase init failed, deferring to firebaseInitializationProvider: $e');
  }

  // Background FCM handler + local-notifications plugin setup. Must run
  // after Firebase is initialized, before runApp().
  try {
    await LocalNotificationService.instance.init();
  } catch (e) {
    debugPrint('[main] LocalNotificationService.init failed: $e');
  }

  runApp(const ProviderScope(child: HandyTrustApp()));
}

class HandyTrustApp extends ConsumerWidget {
  const HandyTrustApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialization = ref.watch(firebaseInitializationProvider);

    return initialization.when(
      data: (_) => const _HandyTrustRouterApp(),
      loading: () => const MaterialApp(home: _InitializationScreen()),
      error: (error, stack) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to initialize the app. $error', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

class _HandyTrustRouterApp extends ConsumerWidget {
  const _HandyTrustRouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(notificationInitProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'HandyTrust',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class _InitializationScreen extends StatelessWidget {
  const _InitializationScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 20),
            Text(
              'HandyTrust',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}