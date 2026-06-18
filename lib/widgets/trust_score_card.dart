import 'package:flutter/material.dart';
import '../core/services/trust_score_service.dart';
import '../models/artisan_model.dart';
import '../theme/app_theme.dart';

/// Small pill badge for an artisan's trust tier. Returns null for
/// 'standard' tier — only 'trusted'/'elite' artisans are called out, to
/// avoid clutter for brand-new artisans whose score is still neutral.
Widget? trustTierBadge(BuildContext context, String tier, {double fontSize = 10}) {
  late final Color fg;
  late final Color bg;
  late final String label;
  switch (tier) {
    case 'elite':
      fg = context.colors.trustElite;
      bg = context.colors.trustEliteSurface;
      label = 'Elite Pro';
      break;
    case 'trusted':
      fg = context.colors.trustTrusted;
      bg = context.colors.trustTrustedSurface;
      label = 'Trusted';
      break;
    default:
      return null;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: fg,
        fontFamily: 'Inter',
      ),
    ),
  );
}

/// Trust score breakdown card — shows the overall score, tier label/badge,
/// and a bar per TrustScoreService.breakdown component. Display-only; the
/// score itself is always computed and written by Cloud Functions.
class TrustScoreCard extends StatelessWidget {
  final ArtisanModel artisan;

  const TrustScoreCard({super.key, required this.artisan});

  @override
  Widget build(BuildContext context) {
    final badge = trustTierBadge(context, artisan.trustTier, fontSize: 11);
    final tierLabel = TrustScoreService.tierLabel(artisan.trustScore);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  size: 20, color: context.colors.primary),
              const SizedBox(width: 8),
              Text(
                'Trust Score',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              Text(
                '${artisan.trustScore.toStringAsFixed(0)}/100',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              tierLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: 10),
            badge,
          ],
          const SizedBox(height: 16),
          ...TrustScoreService.breakdown(artisan).map((c) => _componentRow(context, c)),
        ],
      ),
    );
  }

  Widget _componentRow(BuildContext context, TrustComponent c) {
    final fraction = c.maxScore == 0 ? 0.0 : (c.score / c.maxScore).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                c.label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                '${c.score.toStringAsFixed(1)} / ${c.maxScore.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: context.colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [TrustScoreCard] in a bottom sheet — used for the artisan's own
/// self-view from the dashboard stat card.
Future<void> showTrustScoreSheet(BuildContext context, ArtisanModel artisan) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: TrustScoreCard(artisan: artisan),
    ),
  );
}
