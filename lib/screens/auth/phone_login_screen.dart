import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Replaced by LoginScreen (email+password). Kept to avoid broken imports.
class PhoneLoginScreen extends StatelessWidget {
  const PhoneLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/login');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
