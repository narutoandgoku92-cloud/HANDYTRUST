import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    debugPrint('[SplashScreen] build authState=$authState');

    // SplashScreen is shown while determining auth state
    // Once auth state is known, router will redirect to /login or /home
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Center(
        child: authState.when(
          data: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Color(0xFF1A56DB)),
              SizedBox(height: 20),
              Text(
                'HandyTrust',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A56DB),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          loading: () => Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Color(0xFF1A56DB)),
              SizedBox(height: 20),
              Text(
                'HandyTrust',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A56DB),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to initialize app',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
