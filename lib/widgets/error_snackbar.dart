import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// [onRetry] is optional — when given, the snackbar shows a "Retry" action
/// instead of leaving a failed operation as a dead end.
void showErrorSnackbar(BuildContext context, String message, {VoidCallback? onRetry}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: context.colors.error,
      action: onRetry == null
          ? null
          : SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: onRetry),
    ),
  );
}
