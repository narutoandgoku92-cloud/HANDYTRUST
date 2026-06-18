import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Poll Firebase every 4 seconds to detect email verification
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified() async {
    if (_checking) return;
    _checking = true;
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      // No manual navigation here. authStateChangesProvider is backed by
      // userChanges() (see AuthService.authStateChanges), which emits after
      // reload() — so this triggers AuthChangeNotifier, which triggers the
      // router's refreshListenable, which re-runs redirect and sends a
      // verified user from /verify-email to /home on its own. GoRouter's
      // redirect is the single source of truth for navigation; this screen
      // only needs to confirm verification, not decide where to go.
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    await ref.read(authNotifierProvider.notifier).resendVerificationEmail();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verification email sent. Check your inbox.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.mark_email_unread_outlined, size: 72, color: context.colors.primary),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n$email\n\nOpen your email and tap the link to activate your account.',
                style: TextStyle(color: context.colors.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _resend,
                child: const Text('Resend verification email'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _checkVerified,
                child: const Text("I've verified — continue"),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  // Router redirect handles navigation after signOut
                },
                child: Text(
                  'Use a different account',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
