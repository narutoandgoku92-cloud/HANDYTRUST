import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/artisan_registration_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/service_request_screen.dart';
import '../screens/artisan/artisan_list_screen.dart';
import '../screens/artisan/artisan_profile_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/payment/demo_escrow_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../screens/job/job_detail_screen.dart';
import '../screens/job/job_completion_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/dispute/dispute_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/home/all_jobs_screen.dart';
import '../screens/verification/verification_upload_screen.dart';
import '../screens/artisan/bank_details_screen.dart';
import '../screens/artisan/business_profile_screen.dart';
import '../screens/artisan/open_jobs_feed_screen.dart';
import '../screens/artisan/portfolio_manager_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/support/contact_support_screen.dart';
import '../screens/auth/suspended_screen.dart';

class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(Ref ref) {
    ref.listen<AsyncValue<User?>>(
      authStateChangesProvider,
      (previous, next) => notifyListeners(),
      fireImmediately: true,
    );
    // Also re-run the redirect when the profile doc changes (e.g. an admin
    // suspends the account live) so SuspendedScreen kicks in immediately.
    ref.listen(
      currentUserProfileProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

final authChangeNotifierProvider =
    Provider<AuthChangeNotifier>((ref) => AuthChangeNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: ref.watch(authChangeNotifierProvider),
    redirect: (context, state) {
      final authAsync = ref.watch(authStateChangesProvider);

      if (authAsync.isLoading) return null;

      final firebaseUser = authAsync.asData?.value;
      final path = state.uri.path;

      // Strip any anonymous/demo sessions — treat them as signed-out
      final isRealUser = firebaseUser != null && !firebaseUser.isAnonymous;

      const publicPaths = {'/login', '/register', '/register/artisan', '/forgot-password'};
      final isPublic = publicPaths.any((p) => path == p || path.startsWith('$p/'));

      if (!isRealUser) {
        // The isLoading guard above already keeps splash ('/') showing
        // while Firebase resolves. Once auth state is known — including
        // "definitely signed out" — every non-public path, '/' included,
        // must redirect to /login. (Previously '/' was special-cased to
        // never redirect, which parked signed-out users on splash forever.)
        if (!isPublic) return '/login';
        return null;
      }

      // Authenticated but email not verified → gate on verify screen
      if (!firebaseUser.emailVerified && path != '/verify-email') {
        return '/verify-email';
      }

      // Verified user trying to access auth screens → send home
      // Exception: /register/artisan is the artisan step-2 onboarding form —
      // verified artisan users may still need to complete it.
      if (firebaseUser.emailVerified &&
          (path == '/login' ||
              path == '/' ||
              path == '/verify-email' ||
              path == '/register')) {
        return '/home';
      }

      // Suspended accounts are locked out of the entire app except the
      // suspended screen itself (which only offers sign-out).
      final profile = ref.watch(currentUserProfileProvider).asData?.value;
      if (profile != null && profile.isSuspended && path != '/suspended') {
        return '/suspended';
      }
      if ((profile == null || !profile.isSuspended) && path == '/suspended') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, _) => const RegisterScreen()),
      GoRoute(path: '/register/artisan', builder: (context, _) => const ArtisanRegistrationScreen()),
      GoRoute(path: '/verify-email', builder: (context, _) => const VerifyEmailScreen()),
      GoRoute(path: '/forgot-password', builder: (context, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/suspended', builder: (context, _) => const SuspendedScreen()),
      GoRoute(path: '/support', builder: (context, _) => const ContactSupportScreen()),
      GoRoute(path: '/settings', builder: (context, _) => const SettingsScreen()),

      GoRoute(path: '/home', builder: (context, _) => const HomeScreen()),
      GoRoute(path: '/jobs', builder: (context, _) => const AllJobsScreen()),
      GoRoute(path: '/notifications', builder: (context, _) => const NotificationsScreen()),
      GoRoute(
        path: '/request',
        builder: (_, state) => ServiceRequestScreen(
          initialCategory: state.uri.queryParameters['category'],
        ),
      ),

      // Artisan discovery
      GoRoute(
        path: '/artisans/:jobId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ArtisanListScreen(
            jobId: state.pathParameters['jobId']!,
            category: extra['category'] as String? ?? '',
            customerLat: extra['lat'] as double?,
            customerLng: extra['lng'] as double?,
          );
        },
      ),
      GoRoute(
        path: '/artisan/:uid',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ArtisanProfileScreen(
            artisanId: state.pathParameters['uid']!,
            jobId: extra['jobId'] as String?,
          );
        },
      ),

      // Chat
      GoRoute(
        path: '/chat/:jobId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatScreen(
            jobId: state.pathParameters['jobId']!,
            otherUserId: extra['artisanId'] as String? ?? '',
            otherUserName: extra['artisanName'] as String? ?? 'Artisan',
          );
        },
      ),

      // Payment
      GoRoute(
        path: '/payment/:jobId',
        builder: (_, state) => PaymentScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/demo-payment/:jobId',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return DemoEscrowScreen(
            jobId: state.pathParameters['jobId']!,
            autoStart: extra['autoStart'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/payment/:jobId/webview',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PaymentWebviewScreen(
            jobId: state.pathParameters['jobId']!,
            url: extra['url'] as String? ?? '',
            reference: extra['reference'] as String? ?? '',
          );
        },
      ),

      // Job lifecycle
      GoRoute(
        path: '/job/:jobId',
        builder: (_, state) => JobDetailScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/job/:jobId/submit',
        builder: (_, state) => JobCompletionScreen(jobId: state.pathParameters['jobId']!),
      ),

      // Review & dispute
      GoRoute(
        path: '/review/:jobId',
        builder: (_, state) => ReviewScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/dispute/:jobId',
        builder: (_, state) => DisputeScreen(jobId: state.pathParameters['jobId']!),
      ),

      GoRoute(
        path: '/admin',
        builder: (context, _) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/verification',
        builder: (context, _) => const VerificationUploadScreen(),
      ),
      GoRoute(
        path: '/bank-details',
        builder: (context, _) => const BankDetailsScreen(),
      ),
      GoRoute(
        path: '/business-profile',
        builder: (context, _) => const BusinessProfileScreen(),
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, _) => const PortfolioManagerScreen(),
      ),
      GoRoute(
        path: '/open-jobs',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OpenJobsFeedScreen(category: extra['category'] as String? ?? '');
        },
      ),
    ],
  );
});
