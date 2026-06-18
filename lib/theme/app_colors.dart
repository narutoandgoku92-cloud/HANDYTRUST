import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary — Trust Blue
  static const Color primary = Color(0xFF1A56DB);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primarySurface = Color(0xFFEFF6FF);

  // Accent — Calm Green (success, verified, escrow locked)
  static const Color accent = Color(0xFF0CA678);
  static const Color accentLight = Color(0xFF34D399);
  static const Color accentSurface = Color(0xFFECFDF5);

  // Escrow-specific
  static const Color escrowLocked = Color(0xFF0CA678);
  static const Color escrowPending = Color(0xFFFF8A00);
  static const Color escrowReleased = Color(0xFF1A56DB);

  // Semantic
  static const Color error = Color(0xFFE02424);
  static const Color errorSurface = Color(0xFFFEF2F2);
  static const Color warning = Color(0xFFFF8A00);
  static const Color warningSurface = Color(0xFFFFFBEB);
  static const Color success = Color(0xFF0CA678);

  // Neutrals
  static const Color background = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);

  // Text
  static const Color textPrimary = Color(0xFF111928);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Chat bubbles
  static const Color bubbleSent = Color(0xFF1A56DB);
  static const Color bubbleReceived = Color(0xFFF3F4F6);

  // Status chips
  static const Color statusRequested = Color(0xFF6B7280);
  static const Color statusMatched = Color(0xFF7C3AED);
  static const Color statusInChat = Color(0xFF2563EB);
  static const Color statusEscrowLocked = Color(0xFF0CA678);
  static const Color statusInProgress = Color(0xFFFF8A00);
  static const Color statusSubmitted = Color(0xFF1A56DB);
  static const Color statusCompleted = Color(0xFF0CA678);
  static const Color statusDisputed = Color(0xFFE02424);
  static const Color statusResolved = Color(0xFF6B7280);

  // Rating
  static const Color ratingGold = Color(0xFFFBBF24);

  // Shimmer
  static const Color shimmerBase = Color(0xFFE5E7EB);
  static const Color shimmerHighlight = Color(0xFFF9FAFB);

  // Rising Professional badge
  static const Color risingBadge = Color(0xFF7C3AED);
  static const Color risingBadgeSurface = Color(0xFFF5F3FF);

  // Trust tier badges (Trust System)
  static const Color trustElite = Color(0xFFB45309);
  static const Color trustEliteSurface = Color(0xFFFFFBEB);
  static const Color trustTrusted = Color(0xFF1A56DB);
  static const Color trustTrustedSurface = Color(0xFFEFF6FF);

  // Gradient — used on onboarding / hero cards
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A56DB), Color(0xFF1E40AF)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0CA678), Color(0xFF059669)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xCC000000)],
  );
}
