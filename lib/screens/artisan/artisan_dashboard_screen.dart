import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/artisan_model.dart';
import '../../models/job_model.dart';
import '../../models/verification_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/verification_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/job_status_badge.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/trust_score_card.dart';

class ArtisanDashboardScreen extends ConsumerWidget {
  const ArtisanDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProfileProvider);

    return userAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('Profile not found')));
        }
        final artisanAsync = ref.watch(artisanProfileProvider(user.uid));
        return artisanAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (artisan) {
            if (artisan == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go('/register/artisan');
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return _DashboardBody(userId: user.uid, artisan: artisan);
          },
        );
      },
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final String userId;
  final ArtisanModel artisan;

  const _DashboardBody({required this.userId, required this.artisan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(artisanJobsProvider(userId));

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(context, ref),
            if (artisan.approvalStatus == 'pending') _buildPendingBanner(context),
            if (artisan.approvalStatus == 'approved') _buildAvailabilityToggle(context, ref),
            _buildVerificationCard(context, ref),
            _buildProfileActions(context),
            _buildStatsRow(context),
            _buildJobsSection(context, jobsAsync),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAvailability(WidgetRef ref, bool current) async {
    final firestore = FirebaseFirestore.instance;
    await Future.wait([
      firestore.collection('artisans').doc(userId).update({
        'isAvailable': !current,
      }),
      firestore.collection('users').doc(userId).update({
        'isAvailable': !current,
      }),
    ]);
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) =>
      SliverToBoxAdapter(
        child: Container(
          color: context.colors.surface,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.primarySurface,
                backgroundImage: artisan.profileImageUrl != null
                    ? NetworkImage(artisan.profileImageUrl!)
                    : null,
                child: artisan.profileImageUrl == null
                    ? Text(
                        artisan.name.isNotEmpty
                            ? artisan.name[0].toUpperCase()
                            : 'A',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.colors.primary,
                          fontFamily: 'Inter',
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${artisan.name.split(' ').first} 👋',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    Text(
                      artisan.category ?? 'Artisan',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.swap_horiz_rounded,
                    color: context.colors.textSecondary),
                tooltip: 'Switch to Customer View',
                onPressed: () => ref.read(authServiceProvider).updateUserProfile(
                  userId,
                  // Customer access needs no approval — arrayUnion grants the
                  // role on first switch and is a no-op on later ones.
                  {
                    'roles': FieldValue.arrayUnion(['customer']),
                    'activeRole': 'customer',
                  },
                ),
              ),
              const NotificationBell(),
              IconButton(
                icon: Icon(Icons.help_outline_rounded,
                    color: context.colors.textSecondary),
                onPressed: () => context.push('/support'),
              ),
              IconButton(
                icon: Icon(Icons.logout_outlined,
                    color: context.colors.textSecondary),
                onPressed: () =>
                    ref.read(authNotifierProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      );

  Widget _buildPendingBanner(BuildContext context) => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.warningSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded,
                  color: context.colors.warning, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your profile is under review. You will appear in search results once approved (24–48 hours).',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildAvailabilityToggle(BuildContext context, WidgetRef ref) => SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderLight),
          ),
          child: Row(
            children: [
              Icon(
                artisan.isAvailable
                    ? Icons.circle
                    : Icons.circle_outlined,
                color: artisan.isAvailable
                    ? context.colors.accent
                    : context.colors.textTertiary,
                size: 12,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  artisan.isAvailable
                      ? 'Available for new jobs'
                      : 'Not accepting new jobs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: artisan.isAvailable
                        ? context.colors.accent
                        : context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              Switch(
                value: artisan.isAvailable,
                onChanged: (_) => _toggleAvailability(ref, artisan.isAvailable),
                activeThumbColor: context.colors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      );

  Widget _buildVerificationCard(BuildContext context, WidgetRef ref) {
    final verificationAsync = ref.watch(verificationStatusProvider(userId));

    return verificationAsync.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox()),
      error: (e, _) => const SliverToBoxAdapter(child: SizedBox()),
      data: (verification) {
        final _VerificationCardSpec spec = switch (verification?.status) {
          null => _VerificationCardSpec(
              icon: Icons.verified_user_outlined,
              color: context.colors.warning,
              surface: context.colors.warningSurface,
              title: 'Verify Your Identity',
              subtitle: 'Upload your selfie and ID to earn the Verified badge.',
              actionLabel: 'Verify',
            ),
          VerificationStatus.pending => _VerificationCardSpec(
              icon: Icons.hourglass_top_rounded,
              color: context.colors.accent,
              surface: context.colors.accentSurface,
              title: 'Verification Under Review',
              subtitle: 'Your documents are being reviewed (24–48 hours).',
            ),
          VerificationStatus.approved => _VerificationCardSpec(
              icon: Icons.verified_rounded,
              color: context.colors.accent,
              surface: context.colors.accentSurface,
              title: 'Identity Verified',
              subtitle: 'You now appear with the Verified badge.',
            ),
          VerificationStatus.rejected => _VerificationCardSpec(
              icon: Icons.cancel_outlined,
              color: context.colors.error,
              surface: context.colors.errorSurface,
              title: 'Verification Rejected',
              subtitle: verification?.rejectionReason?.isNotEmpty == true
                  ? verification!.rejectionReason!
                  : 'Please resubmit with clearer photos.',
              actionLabel: 'Resubmit',
            ),
        };

        return SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: spec.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: spec.color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(spec.icon, color: spec.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                if (spec.actionLabel != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => context.push('/verification'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(
                      spec.actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileActions(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              // Only an approved + verified artisan can submit quotes —
              // mirrors the Firestore isArtisanEligible() gate on /quotes.
              if (artisan.approvalStatus == 'approved' &&
                  (artisan.verificationStatus == 'id_verified' ||
                      artisan.verificationStatus == 'trusted')) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/open-jobs',
                      extra: {'category': artisan.category ?? ''},
                    ),
                    icon: const Icon(Icons.work_outline_rounded, size: 18),
                    label: const Text('Browse Open Jobs'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: context.colors.textInverse,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/bank-details'),
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: const Text('Manage Payout Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side: BorderSide(color: context.colors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/portfolio'),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Manage Portfolio'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side: BorderSide(color: context.colors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/business-profile'),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Business Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side: BorderSide(color: context.colors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildStatsRow(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _StatCard(
                label: 'Rating',
                value: artisan.rating == 0
                    ? 'New'
                    : artisan.rating.toStringAsFixed(1),
                icon: Icons.star_rounded,
                color: context.colors.ratingGold,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Completed',
                value: '${artisan.completedJobs}',
                icon: Icons.check_circle_outline_rounded,
                color: context.colors.accent,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Trust Score',
                value: '${artisan.trustScore.toInt()}',
                icon: Icons.verified_outlined,
                color: context.colors.primary,
                onTap: () => showTrustScoreSheet(context, artisan),
              ),
            ],
          ),
        ),
      );

  Widget _buildJobsSection(
    BuildContext context,
    AsyncValue<List<JobModel>> jobsAsync,
  ) =>
      jobsAsync.when(
        loading: () => const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (e, _) => const SliverToBoxAdapter(child: SizedBox()),
        data: (jobs) {
          final active = jobs.where((j) => !j.status.isTerminal).toList();
          final recent =
              jobs.where((j) => j.status.isTerminal).take(5).toList();

          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (active.isNotEmpty) ...[
                    Text(
                      'Active Jobs (${active.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...active.map((j) => _ArtisanJobTile(job: j)),
                    const SizedBox(height: 20),
                  ],
                  if (recent.isNotEmpty) ...[
                    Text(
                      'Recent Jobs',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...recent.map((j) => _ArtisanJobTile(job: j)),
                  ],
                  if (jobs.isEmpty) _emptyState(context),
                ],
              ),
            ),
          );
        },
      );

  Widget _emptyState(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          children: [
            Icon(Icons.work_outline_rounded,
                size: 40, color: context.colors.textTertiary),
            SizedBox(height: 12),
            Text(
              'No jobs yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Once your profile is approved, customers will find and hire you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
}

class _VerificationCardSpec {
  final IconData icon;
  final Color color;
  final Color surface;
  final String title;
  final String subtitle;
  final String? actionLabel;

  const _VerificationCardSpec({
    required this.icon,
    required this.color,
    required this.surface,
    required this.title,
    required this.subtitle,
    this.actionLabel,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderLight),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textTertiary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ArtisanJobTile extends StatelessWidget {
  final JobModel job;

  const _ArtisanJobTile({required this.job});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.push('/job/${job.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderLight),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.category,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.description.length > 60
                          ? '${job.description.substring(0, 60)}…'
                          : job.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('dd MMM yyyy').format(job.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              JobStatusBadge(status: job.status),
            ],
          ),
        ),
      );
}
