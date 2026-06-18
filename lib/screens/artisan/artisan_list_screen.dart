import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/artisan_model.dart';
import '../../providers/matching_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artisan_card.dart';

class ArtisanListScreen extends ConsumerWidget {
  final String jobId;
  final String category;
  final double? customerLat;
  final double? customerLng;

  const ArtisanListScreen({
    super.key,
    required this.jobId,
    required this.category,
    this.customerLat,
    this.customerLng,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = MatchingParams(
      category: category,
      lat: customerLat,
      lng: customerLng,
    );
    final matchAsync = ref.watch(matchingProvider(params));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Choose an Artisan'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderLight),
        ),
      ),
      body: matchAsync.when(
        loading: () => _loadingGrid(context),
        error: (e, _) => _errorState(context, e.toString()),
        data: (artisans) {
          if (artisans.isEmpty) return _emptyState(context, category);

          final experienced = artisans.where((a) => !a.isRising).toList();
          final rising = artisans.where((a) => a.isRising).toList();

          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (experienced.isNotEmpty) ...[
                _sectionHeader(context, 'Top Professionals', icon: Icons.verified_rounded),
                _artisanGrid(context, experienced),
              ],
              if (rising.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                _sectionHeader(
                  context,
                  'Rising Professionals',
                  icon: Icons.trending_up_rounded,
                  iconColor: context.colors.risingBadge,
                  subtitle: 'Fresh talent — eager, available, and affordable',
                ),
                _artisanGrid(context, rising),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    required IconData icon,
    Color? iconColor,
    String? subtitle,
  }) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: iconColor ?? context.colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _artisanGrid(BuildContext context, List<ArtisanModel> list) =>
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => ArtisanCard(
              artisan: list[i],
              onTap: () => context.push(
                '/artisan/${list[i].uid}',
                extra: {'jobId': jobId},
              ),
            ),
            childCount: list.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
        ),
      );

  Widget _loadingGrid(BuildContext context) => Shimmer.fromColors(
        baseColor: context.colors.shimmerBase,
        highlightColor: context.colors.shimmerHighlight,
        child: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(16),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.75,
          children: List.generate(
            4,
            (_) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      );

  Widget _emptyState(BuildContext context, String category) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64, color: context.colors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'No $category artisans available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try a different category or check back later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorState(BuildContext context, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: context.colors.error),
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textSecondary)),
            ],
          ),
        ),
      );
}
