import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Replaced by RegisterScreen. Kept to avoid broken imports from older screens.
class CustomerRegistrationScreen extends StatelessWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Immediately redirect legacy deep-links to the new registration flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/register');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
