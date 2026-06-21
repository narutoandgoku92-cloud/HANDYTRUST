import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/trust_score_service.dart';
import '../../models/artisan_model.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/review_model.dart';
import '../../models/support_ticket_model.dart';
import '../../models/user_model.dart';
import '../../models/verification_model.dart';
import '../../core/utils/safe_firestore.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/quote_provider.dart';
import '../../providers/review_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../../providers/verification_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/job_status_badge.dart';
import '../../widgets/review_tile.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => UserModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'allUsers',
  );
});

/// All jobs, newest-first — drives the admin Jobs tab. isAdmin() already
/// grants full /jobs read access (see firestore.rules); no rule change
/// needed. No orderBy+where combo, same composite-index-avoidance pattern
/// as every other admin list provider.
final _allJobsProvider = StreamProvider<List<JobModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('jobs')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'allJobs',
  );
});

/// Resolves display names for a batch of user/artisan uids (both live in
/// /users — even artisans get a /users doc at signup), for the Jobs tab's
/// "Customer"/"Assigned artisan" columns and name search. Keyed by a sorted,
/// comma-joined string (not the raw List) so Riverpod actually caches
/// repeat lookups for the same set of ids instead of refetching on every
/// snapshot tick.
final _jobPeopleNamesProvider =
    FutureProvider.family<Map<String, String>, String>((ref, idsKey) async {
      if (idsKey.isEmpty) return const {};
      final ids = idsKey.split(',');
      final result = <String, String>{};
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(
          i,
          (i + 30 > ids.length) ? ids.length : i + 30,
        );
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = (doc.data()['name'] as String?) ?? '';
        }
      }
      return result;
    });

final _pendingArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) {
  // No orderBy on the query itself: where(approvalStatus) + orderBy(createdAt)
  // on different fields requires a Firestore composite index that was never
  // deployed for this project. Sorting client-side avoids needing one at
  // all — same pattern already used by every other admin/job list provider.
  // safeStream is still the right wrapper on top: it protects against any
  // OTHER stream-level failure (permission, offline), not just this one.
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .where('approvalStatus', isEqualTo: 'pending'),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'pendingArtisans',
  ).map(
    (artisans) => artisans..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate: only accounts with a doc at /admins/{uid} may access this screen
    // — the same check Firestore security rules use for every query below,
    // so reaching this screen guarantees the dashboard's reads will work.
    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () => Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: context.colors.primary),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Text(
            'Error checking admin access: $e',
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ),
      data: (isAdmin) {
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin')),
            body: Center(
              child: Text(
                'Access denied. Admin privileges required.',
                style: TextStyle(color: context.colors.error),
              ),
            ),
          );
        }
        return const _AdminDashboardBody();
      },
    );
  }
}

class _AdminDashboardBody extends ConsumerWidget {
  const _AdminDashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(_pendingArtisansProvider);

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: const Text(
            'Admin Dashboard',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
          ),
          backgroundColor: context.colors.surface,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_outlined),
              onPressed: () =>
                  ref.read(authNotifierProvider.notifier).signOut(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending Approval'),
              Tab(text: 'All Artisans'),
              Tab(text: 'Verification Center'),
              Tab(text: 'Disputes'),
              Tab(text: 'Users'),
              Tab(text: 'Support'),
              Tab(text: 'Reviews'),
              Tab(text: 'Jobs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PendingArtisansTab(pendingAsync: pendingAsync),
            const _AllArtisansTab(),
            const _VerificationCenterTab(),
            const _DisputesTab(),
            const _UsersTab(),
            const _SupportTicketsTab(),
            const _ReviewsTab(),
            const _JobsTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared friendly states — used by every tab so admins never see a raw
// Firestore exception string, and every empty list gets a consistent,
// non-blank treatment.
// ---------------------------------------------------------------------------

class _AdminErrorState extends StatelessWidget {
  const _AdminErrorState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load this data. Check your connection and try again.",
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
}

class _AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _AdminEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.colors.accent),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pending tab
// ---------------------------------------------------------------------------

class _PendingArtisansTab extends StatelessWidget {
  final AsyncValue<List<ArtisanModel>> pendingAsync;

  const _PendingArtisansTab({required this.pendingAsync});

  @override
  Widget build(BuildContext context) {
    return pendingAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (artisans) {
        if (artisans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No pending applications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All artisan applications have been reviewed.',
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

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: artisans.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _ArtisanApplicationCard(artisan: artisans[i]),
        );
      },
    );
  }
}

class _ArtisanApplicationCard extends StatefulWidget {
  final ArtisanModel artisan;

  const _ArtisanApplicationCard({required this.artisan});

  @override
  State<_ArtisanApplicationCard> createState() =>
      _ArtisanApplicationCardState();
}

class _ArtisanApplicationCardState extends State<_ArtisanApplicationCard> {
  bool _loading = false;
  String? _error;

  Future<void> _updateStatus(String status) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final artisanRef = FirebaseFirestore.instance
          .collection('artisans')
          .doc(widget.artisan.uid);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.artisan.uid);

      final updates = {
        'approvalStatus': status,
        'isAvailable': status == 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // set(merge:true) instead of update() — update() throws if either
      // doc doesn't exist, which would abort the WHOLE batch (a batch is
      // all-or-nothing) and leave the application stuck un-reviewed with a
      // raw Firestore error as the only feedback.
      batch.set(artisanRef, updates, SetOptions(merge: true));
      batch.set(userRef, {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      debugPrint('[AdminDashboard] artisan approval update failed: $e');
      if (mounted) {
        setState(() => _error = 'Failed to update application: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(String action, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$action Artisan?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to $action ${widget.artisan.name}\'s application?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: status == 'approved'
                  ? context.colors.accent
                  : context.colors.error,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed == true) await _updateStatus(status);
  }

  @override
  Widget build(BuildContext context) {
    final artisan = widget.artisan;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _avatar(artisan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'General',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (artisan.location != null)
                        Text(
                          artisan.location!,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF856404),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bio
          if (artisan.bio != null && artisan.bio!.isNotEmpty) ...[
            Divider(height: 1, color: context.colors.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'About',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                artisan.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
            ),
          ],

          // Skills
          if (artisan.skills.isNotEmpty) ...[
            Divider(height: 1, color: context.colors.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Skills',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: artisan.skills
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.colors.error,
                  fontSize: 12,
                  fontFamily: 'Inter',
                ),
              ),
            ),

          // Action buttons
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirm('Reject', 'rejected'),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.colors.error,
                          ),
                          label: Text(
                            'Reject',
                            style: TextStyle(
                              color: context.colors.error,
                              fontFamily: 'Inter',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _confirm('Approve', 'approved'),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text(
                            'Approve',
                            style: TextStyle(fontFamily: 'Inter'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(ArtisanModel artisan) {
    if (artisan.profileImageUrl != null) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: NetworkImage(artisan.profileImageUrl!),
        backgroundColor: context.colors.primarySurface,
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: context.colors.primarySurface,
      child: Text(
        artisan.name.isNotEmpty ? artisan.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All artisans tab (searchable list with status filters)
// ---------------------------------------------------------------------------

final _allArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'allArtisans',
  );
});

class _AllArtisansTab extends ConsumerStatefulWidget {
  const _AllArtisansTab();

  @override
  ConsumerState<_AllArtisansTab> createState() => _AllArtisansTabState();
}

class _AllArtisansTabState extends ConsumerState<_AllArtisansTab> {
  String _filter = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(_allArtisansProvider);

    return Column(
      children: [
        // Search + filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search by name or category…',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: allAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
            error: (e, st) {
              // Admin sees a friendly message; the real Firestore error (e.g. a
              // missing composite index) is logged for debugging instead of
              // being silently swallowed.
              debugPrint('[AdminDashboard] stream error: $e\n$st');
              return const _AdminErrorState();
            },
            data: (artisans) {
              final filtered = artisans.where((a) {
                final matchesFilter =
                    _filter == 'all' || a.approvalStatus == _filter;
                final matchesSearch =
                    _search.isEmpty ||
                    a.name.toLowerCase().contains(_search) ||
                    (a.category?.toLowerCase().contains(_search) ?? false);
                return matchesFilter && matchesSearch;
              }).toList();

              if (filtered.isEmpty) {
                return const _AdminEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No artisans found',
                  subtitle: 'Try a different search or filter.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _ArtisanListTile(artisan: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArtisanListTile extends StatelessWidget {
  final ArtisanModel artisan;

  const _ArtisanListTile({required this.artisan});

  Color _statusColor(BuildContext context) {
    switch (artisan.approvalStatus) {
      case 'approved':
        return context.colors.accent;
      case 'rejected':
        return context.colors.error;
      default:
        return const Color(0xFFE6A817);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/artisan/${artisan.uid}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                              : '?',
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
                        artisan.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'General',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    artisan.approvalStatus,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(context),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.colors.borderLight),
            const SizedBox(height: 10),
            // Admin-visible trust signals — read-only, no new permissions.
            Row(
              children: [
                _adminStat(
                  context,
                  Icons.verified_outlined,
                  '${artisan.trustScore.toStringAsFixed(0)}/100 '
                  '(${TrustScoreService.tierLabel(artisan.trustScore)})',
                ),
                const SizedBox(width: 14),
                _adminStat(
                  context,
                  Icons.star_rounded,
                  artisan.totalRatings > 0
                      ? artisan.rating.toStringAsFixed(1)
                      : 'New',
                ),
                const SizedBox(width: 14),
                _adminStat(
                  context,
                  Icons.check_circle_outline_rounded,
                  '${artisan.completedJobs} jobs',
                ),
              ],
            ),
            const SizedBox(height: 6),
            _adminStat(
              context,
              Icons.fingerprint_rounded,
              'Verification: ${artisan.verificationStatus}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminStat(BuildContext context, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: context.colors.textTertiary),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Verification Center tab — review selfie + government ID submissions
// ---------------------------------------------------------------------------

class _VerificationCenterTab extends ConsumerWidget {
  const _VerificationCenterTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingVerificationsProvider);

    return pendingAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (verifications) {
        if (verifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No pending verifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: verifications.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _VerificationReviewCard(verification: verifications[i]),
        );
      },
    );
  }
}

class _VerificationReviewCard extends ConsumerStatefulWidget {
  final VerificationModel verification;

  const _VerificationReviewCard({required this.verification});

  @override
  ConsumerState<_VerificationReviewCard> createState() =>
      _VerificationReviewCardState();
}

class _VerificationReviewCardState
    extends ConsumerState<_VerificationReviewCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final reviewerId = ref.read(currentUserProvider).asData?.value?.uid;
    if (reviewerId == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(verificationServiceProvider)
          .approve(uid: widget.verification.uid, reviewerId: reviewerId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Approve failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final reviewerId = ref.read(currentUserProvider).asData?.value?.uid;
    if (reviewerId == null) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reject Verification',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason (e.g. "ID photo is blurry, please resubmit")',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(reasonController.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(verificationServiceProvider)
          .reject(
            uid: widget.verification.uid,
            reviewerId: reviewerId,
            reason: reason,
          );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Reject failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) {
              debugPrint('[AdminVerification] full-screen image load failed for $url: $error');
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verification;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              v.uid,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _VerificationThumb(
                    label: 'Selfie',
                    url: v.selfieUrl,
                    onTap: () => _openImage(v.selfieUrl),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VerificationThumb(
                    label: 'Government ID',
                    url: v.governmentIdUrl,
                    onTap: () => _openImage(v.governmentIdUrl),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _reject,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.colors.error,
                          ),
                          label: Text(
                            'Reject',
                            style: TextStyle(
                              color: context.colors.error,
                              fontFamily: 'Inter',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _approve,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text(
                            'Approve',
                            style: TextStyle(fontFamily: 'Inter'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disputes tab — review evidence from both parties, resolve or dismiss
// ---------------------------------------------------------------------------

class _DisputesTab extends ConsumerWidget {
  const _DisputesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(openDisputesProvider);

    return disputesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (disputes) {
        if (disputes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gavel_outlined,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No open disputes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: disputes.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) => _DisputeReviewCard(dispute: disputes[i]),
        );
      },
    );
  }
}

class _DisputeReviewCard extends ConsumerStatefulWidget {
  final DisputeModel dispute;

  const _DisputeReviewCard({required this.dispute});

  @override
  ConsumerState<_DisputeReviewCard> createState() => _DisputeReviewCardState();
}

class _DisputeReviewCardState extends ConsumerState<_DisputeReviewCard> {
  bool _loading = false;

  Future<void> _resolve({required bool dismiss}) async {
    final adminId = ref.read(currentUserProvider).asData?.value?.uid;
    if (adminId == null) return;

    final resolutionController = TextEditingController();
    final resolution = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          dismiss ? 'Dismiss Dispute' : 'Resolve Dispute',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: resolutionController,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: dismiss
                ? 'Reason for dismissal (shown to both parties)'
                : 'Resolution outcome (shown to both parties)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(resolutionController.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: dismiss
                  ? context.colors.textSecondary
                  : context.colors.accent,
            ),
            child: Text(dismiss ? 'Dismiss' : 'Resolve'),
          ),
        ],
      ),
    );

    if (resolution == null || resolution.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(disputeServiceProvider)
          .resolveDispute(
            jobId: widget.dispute.jobId,
            disputeId: widget.dispute.id,
            adminId: adminId,
            raisedBy: widget.dispute.raisedBy,
            againstUserId: widget.dispute.againstUserId,
            resolution: resolution,
            dismiss: dismiss,
          );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Resolution failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _evidenceRow(List<String> urls) => urls.isEmpty
      ? const SizedBox.shrink()
      : SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, index) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _openImage(urls[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  urls[i],
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Job ${d.jobId}',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Customer Complaint',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              d.reason,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
          if (d.evidenceImageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _evidenceRow(d.evidenceImageUrls),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Artisan Response',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              d.artisanResponseText ?? 'No response yet.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
          if (d.artisanEvidenceUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _evidenceRow(d.artisanEvidenceUrls),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _resolve(dismiss: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            side: BorderSide(color: context.colors.border),
                          ),
                          child: const Text('Dismiss'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _resolve(dismiss: false),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                          ),
                          child: const Text('Resolve'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users tab — search/filter all accounts, suspend/reactivate
// ---------------------------------------------------------------------------

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  String _filter = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(_allUsersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search by name or email…',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'customer', child: Text('Customers')),
                  DropdownMenuItem(value: 'artisan', child: Text('Artisans')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: usersAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
            error: (e, st) {
              // Admin sees a friendly message; the real Firestore error (e.g. a
              // missing composite index) is logged for debugging instead of
              // being silently swallowed.
              debugPrint('[AdminDashboard] stream error: $e\n$st');
              return const _AdminErrorState();
            },
            data: (users) {
              final filtered = users.where((u) {
                final matchesFilter =
                    _filter == 'all' ||
                    (_filter == 'suspended' && u.isSuspended) ||
                    (_filter == 'customer' && u.isCustomer) ||
                    (_filter == 'artisan' && u.isArtisan);
                final matchesSearch =
                    _search.isEmpty ||
                    u.name.toLowerCase().contains(_search) ||
                    (u.email?.toLowerCase().contains(_search) ?? false);
                return matchesFilter && matchesSearch;
              }).toList();

              if (filtered.isEmpty) {
                return const _AdminEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No users found',
                  subtitle: 'Try a different search or filter.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _UserListTile(user: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserListTile extends ConsumerStatefulWidget {
  final UserModel user;

  const _UserListTile({required this.user});

  @override
  ConsumerState<_UserListTile> createState() => _UserListTileState();
}

class _UserListTileState extends ConsumerState<_UserListTile> {
  bool _loading = false;
  bool _deleting = false;

  Future<void> _deleteUser() async {
    final user = widget.user;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete User?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently deletes ${user.name}\'s account data'
          '${user.isArtisan ? " and artisan profile" : ""}. This cannot be undone.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.delete(db.collection('users').doc(user.uid));
      if (user.isArtisan) {
        batch.delete(db.collection('artisans').doc(user.uid));
      }
      await batch.commit();
      debugPrint('[AdminDashboard] deleted ${user.uid} from Firestore');

      // Best-effort: disable the Auth account via Cloud Function. The
      // Firestore deletion above already succeeded either way — the Auth
      // side being unreachable (function not deployed yet, network) must
      // not look like the whole delete failed.
      try {
        await FirebaseFunctions.instance
            .httpsCallable('adminDeleteUser')
            .call({'uid': user.uid});
        debugPrint('[AdminDashboard] disabled Auth account for ${user.uid}');
      } catch (e) {
        debugPrint('[AdminDashboard] Auth disable failed for ${user.uid}: $e');
        if (mounted) {
          showErrorSnackbar(
            context,
            '${user.name} was removed, but their sign-in could not be disabled: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboard] deleteUser failed for ${user.uid}: $e');
      if (mounted) showErrorSnackbar(context, 'Failed to delete user: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _toggleSuspension() async {
    final user = widget.user;
    final newStatus = user.isSuspended ? 'active' : 'suspended';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          user.isSuspended ? 'Reactivate Account?' : 'Suspend Account?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          user.isSuspended
              ? '${user.name} will regain access to the app.'
              : '${user.name} will be signed out and locked out of the app.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: user.isSuspended
                  ? context.colors.accent
                  : context.colors.error,
            ),
            child: Text(user.isSuspended ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
        {'accountStatus': newStatus},
        SetOptions(merge: true),
      );
      if (user.isArtisan) {
        batch.set(
          FirebaseFirestore.instance.collection('artisans').doc(user.uid),
          {'accountStatus': newStatus},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[AdminDashboard] account status update failed: $e');
      if (mounted) showErrorSnackbar(context, 'Failed to update account: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Restructured from a single Row packing avatar + name/email + a fixed-
  // width action button into one line — on narrower screens (and once a
  // second action button was needed for delete) that Row overflowed,
  // which renders as Flutter's diagonal-striped "RenderFlex overflowed"
  // bar. Splitting into stacked rows (identity → chips → actions) keeps
  // every element within the available width regardless of screen size.
  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final artisan =
        user.isArtisan ? ref.watch(artisanProfileProvider(user.uid)).value : null;
    final busy = _loading || _deleting;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.primarySurface,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.email ?? '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (user.isSuspended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colors.errorSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Suspended',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final role in user.roles) _chip(context, role),
              if (artisan != null) ...[
                _chip(
                  context,
                  '${artisan.trustScore.toStringAsFixed(0)}/100 trust',
                  icon: Icons.verified_outlined,
                ),
                _chip(
                  context,
                  'Verification: ${artisan.verificationStatus}',
                  icon: Icons.fingerprint_rounded,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.colors.borderLight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _toggleSuspension,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: user.isSuspended
                        ? context.colors.accent
                        : context.colors.error,
                    side: BorderSide(
                      color: user.isSuspended
                          ? context.colors.accent
                          : context.colors.error,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(user.isSuspended ? 'Reactivate' : 'Suspend'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _deleteUser,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                  child: _deleting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.error),
                        )
                      : const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: context.colors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Support tab — review and respond to support tickets
// ---------------------------------------------------------------------------

class _SupportTicketsTab extends ConsumerWidget {
  const _SupportTicketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(allTicketsProvider);

    return ticketsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (tickets) {
        if (tickets.isEmpty) {
          return const _AdminEmptyState(
            icon: Icons.support_agent_outlined,
            title: 'No support tickets',
            subtitle: 'Customer and artisan tickets will appear here.',
          );
        }

        final open = tickets.where((t) => t.status == 'open').toList();
        final resolved = tickets.where((t) => t.status != 'open').toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (open.isNotEmpty) ...[
              Text(
                'Open (${open.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              ...open.map((t) => _TicketReviewCard(ticket: t)),
              const SizedBox(height: 20),
            ],
            if (resolved.isNotEmpty) ...[
              const Text(
                'Resolved',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              ...resolved.map((t) => _TicketReviewCard(ticket: t)),
            ],
          ],
        );
      },
    );
  }
}

class _TicketReviewCard extends ConsumerStatefulWidget {
  final SupportTicketModel ticket;

  const _TicketReviewCard({required this.ticket});

  @override
  ConsumerState<_TicketReviewCard> createState() => _TicketReviewCardState();
}

class _TicketReviewCardState extends ConsumerState<_TicketReviewCard> {
  bool _loading = false;

  Future<void> _respond() async {
    final responseController = TextEditingController();
    final response = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Respond & Resolve',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: responseController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Your response to the user',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(responseController.text.trim()),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );

    if (response == null || response.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(supportTicketServiceProvider)
          .resolveTicket(ticketId: widget.ticket.id, adminResponse: response);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Resolve failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final resolved = t.status != 'open';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.subject,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              Text(
                t.userName,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.message,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          if (t.adminResponse != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.accentSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Response: ${t.adminResponse}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.accent,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
          if (!resolved) ...[
            const SizedBox(height: 10),
            _loading
                ? const Center(
                    child: SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _respond,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.accent,
                      ),
                      child: const Text('Respond & Resolve'),
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reviews tab — moderate reviews, with rating-aggregate cleanup on delete
// ---------------------------------------------------------------------------

class _ReviewsTab extends ConsumerWidget {
  const _ReviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(allReviewsProvider);

    return reviewsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (reviews) {
        if (reviews.isEmpty) {
          return const _AdminEmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No reviews yet',
            subtitle: 'Reviews appear here once customers rate completed jobs.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reviews.length,
          itemBuilder: (ctx, i) => _AdminReviewCard(review: reviews[i]),
        );
      },
    );
  }
}

class _AdminReviewCard extends ConsumerStatefulWidget {
  final ReviewModel review;

  const _AdminReviewCard({required this.review});

  @override
  ConsumerState<_AdminReviewCard> createState() => _AdminReviewCardState();
}

class _AdminReviewCardState extends ConsumerState<_AdminReviewCard> {
  bool _loading = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Review?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This permanently removes the review and recalculates the artisan\'s rating.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final review = widget.review;

      // Recompute the artisan's rating/totalRatings from the remaining
      // reviews so deleting one never leaves a stale aggregate behind.
      final otherDocs = await db
          .collection('reviews')
          .where('artisanId', isEqualTo: review.artisanId)
          .get();
      final remaining = otherDocs.docs
          .where((d) => d.id != review.id)
          .map((d) => (d.data()['rating'] as num).toDouble())
          .toList();

      final newCount = remaining.length;
      final newRating = newCount == 0
          ? 0.0
          : double.parse(
              (remaining.reduce((a, b) => a + b) / newCount).toStringAsFixed(2),
            );

      final batch = db.batch();
      batch.delete(db.collection('reviews').doc(review.id));
      // set(merge:true) instead of update() — the artisan doc may no longer
      // exist if an admin deleted that account, which would otherwise abort
      // this whole batch (including the review delete itself).
      batch.set(db.collection('artisans').doc(review.artisanId), {
        'rating': newRating,
        'totalRatings': newCount,
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReviewTile(
      review: widget.review,
      trailing: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: context.colors.error,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _delete,
            ),
    );
  }
}

class _VerificationThumb extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onTap;

  const _VerificationThumb({
    required this.label,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.colors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 1,
              child: url.isEmpty
                  ? Container(color: context.colors.borderLight)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) {
                        debugPrint('[AdminVerification] image load failed for $url: $error');
                        return Container(
                          color: context.colors.borderLight,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: context.colors.textTertiary,
                            size: 20,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jobs tab — read-only, real-time view of every job request. Job editing
// stays out of scope here; mutations remain JobService's exclusively.
// ---------------------------------------------------------------------------

class _JobsTab extends ConsumerStatefulWidget {
  const _JobsTab();

  @override
  ConsumerState<_JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends ConsumerState<_JobsTab> {
  String _filter = 'all';
  String _search = '';

  static const _statusFilters = [
    ('all', 'All'),
    ('requested', 'Requested'),
    ('matched', 'Assigned'),
    ('inProgress', 'In Progress'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
    ('disputed', 'Disputed'),
  ];

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(_allJobsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: const InputDecoration(
                    hintText:
                        'Search by job ID, category, customer or artisan…',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: _statusFilters
                    .map(
                      (f) => DropdownMenuItem(value: f.$1, child: Text(f.$2)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: jobsAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
            error: (e, st) {
              debugPrint('[AdminDashboard] stream error: $e\n$st');
              return const _AdminErrorState();
            },
            data: (jobs) {
              // Resolve customer/artisan names for every job currently in
              // view — keyed by a stable, sorted id string so repeat
              // lookups for the same set of people are cached, not refetched
              // on every snapshot tick.
              final ids = <String>{};
              for (final j in jobs) {
                if (j.customerId.isNotEmpty) ids.add(j.customerId);
                if (j.artisanId.isNotEmpty) ids.add(j.artisanId);
              }
              final idsKey = (ids.toList()..sort()).join(',');
              final names =
                  ref.watch(_jobPeopleNamesProvider(idsKey)).value ?? const {};

              final filtered = jobs.where((j) {
                final matchesFilter =
                    _filter == 'all' || j.status.name == _filter;
                if (!matchesFilter) return false;
                if (_search.isEmpty) return true;
                final customerName = (names[j.customerId] ?? '').toLowerCase();
                final artisanName = (names[j.artisanId] ?? '').toLowerCase();
                return j.id.toLowerCase().contains(_search) ||
                    j.category.toLowerCase().contains(_search) ||
                    customerName.contains(_search) ||
                    artisanName.contains(_search);
              }).toList();

              if (filtered.isEmpty) {
                return const _AdminEmptyState(
                  icon: Icons.work_off_outlined,
                  title: 'No jobs found',
                  subtitle: 'Try a different search or filter.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _JobListTile(
                  job: filtered[i],
                  customerName: names[filtered[i].customerId],
                  artisanName: names[filtered[i].artisanId],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _JobListTile extends ConsumerWidget {
  final JobModel job;
  final String? customerName;
  final String? artisanName;

  const _JobListTile({
    required this.job,
    required this.customerName,
    required this.artisanName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(jobQuotesProvider(job.id));
    final quoteCount = quotesAsync.value?.length;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _JobDetailSheet(
          job: job,
          customerName: customerName,
          artisanName: artisanName,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.category,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                JobStatusBadge(status: job.status, compact: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '#${job.id}',
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              job.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _infoChip(
                  context,
                  Icons.person_outline_rounded,
                  customerName?.isNotEmpty == true ? customerName! : 'Customer',
                ),
                _infoChip(
                  context,
                  Icons.handyman_outlined,
                  job.artisanId.isEmpty
                      ? 'Not accepted yet'
                      : 'Accepted by: ${artisanName?.isNotEmpty == true ? artisanName! : job.artisanId}',
                ),
                if (job.budgetMin != null || job.budgetMax != null)
                  _infoChip(
                    context,
                    Icons.payments_outlined,
                    '₦${(job.budgetMin ?? 0).toStringAsFixed(0)}–₦${(job.budgetMax ?? job.budgetMin ?? 0).toStringAsFixed(0)}',
                  ),
                if (job.customerAddress != null)
                  _infoChip(
                    context,
                    Icons.location_on_outlined,
                    job.customerAddress!,
                  ),
                if (quoteCount != null && quoteCount > 0)
                  _infoChip(
                    context,
                    Icons.request_quote_outlined,
                    '$quoteCount quote${quoteCount == 1 ? '' : 's'}',
                  ),
                _infoChip(
                  context,
                  Icons.calendar_today_outlined,
                  DateFormat('d MMM yyyy').format(job.createdAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: context.colors.textTertiary),
      const SizedBox(width: 3),
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
        ),
      ),
    ],
  );
}

/// Read-only job detail sheet — view-only by design (no status/edit
/// controls); mutations remain exclusively JobService's. Links out to the
/// artisan's existing profile screen and surfaces quotes/dispute inline via
/// already-existing providers rather than duplicating their UI.
class _JobDetailSheet extends ConsumerStatefulWidget {
  final JobModel job;
  final String? customerName;
  final String? artisanName;

  const _JobDetailSheet({
    required this.job,
    required this.customerName,
    required this.artisanName,
  });

  @override
  ConsumerState<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends ConsumerState<_JobDetailSheet> {
  bool _deleting = false;

  // Hard delete — distinct from every other mutation here, which goes
  // through JobService's state machine. Reserved for spam/fake job
  // requests an admin wants gone entirely, not a status transition.
  // Firestore rules already grant isAdmin() delete on /jobs; messages are
  // cleaned up best-effort (rules now allow isAdmin() to delete them too)
  // since deleting the job doc does not cascade-delete its subcollections.
  Future<void> _deleteJob() async {
    final job = widget.job;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Job Request?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This permanently deletes the job and its chat history. Use this '
          'only for spam or fake requests — this cannot be undone.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final db = FirebaseFirestore.instance;
      final jobRef = db.collection('jobs').doc(job.id);

      final messages = await jobRef.collection('messages').get();
      if (messages.docs.isNotEmpty) {
        final msgBatch = db.batch();
        for (final doc in messages.docs) {
          msgBatch.delete(doc.reference);
        }
        await msgBatch.commit();
      }

      await jobRef.delete();
      debugPrint('[AdminDashboard] deleted job ${job.id}');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[AdminDashboard] deleteJob failed for ${job.id}: $e');
      if (mounted) showErrorSnackbar(context, 'Failed to delete job: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final customerName = widget.customerName;
    final artisanName = widget.artisanName;
    final quotesAsync = ref.watch(jobQuotesProvider(job.id));
    final disputeAsync = ref.watch(disputeForJobProvider(job.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.category,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                JobStatusBadge(status: job.status),
              ],
            ),
            Text(
              'Job ID: ${job.id}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 16),
            _section(context, 'Description', job.description),
            const SizedBox(height: 14),
            _section(
              context,
              'Budget',
              (job.budgetMin == null && job.budgetMax == null)
                  ? 'Not specified'
                  : '₦${(job.budgetMin ?? 0).toStringAsFixed(0)} – ₦${(job.budgetMax ?? job.budgetMin ?? 0).toStringAsFixed(0)}',
            ),
            const SizedBox(height: 14),
            _section(
              context,
              'Created',
              DateFormat('d MMM yyyy, h:mm a').format(job.createdAt),
            ),
            if (job.customerAddress != null) ...[
              const SizedBox(height: 14),
              _section(context, 'Location', job.customerAddress!),
            ],
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            // Customer — no dedicated admin customer-profile screen exists
            // yet; the existing Users tab (searchable) covers deeper detail.
            Text(
              'Customer',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              customerName?.isNotEmpty == true ? customerName! : job.customerId,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Assigned Artisan',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            if (job.artisanId.isEmpty)
              Text(
                'None yet',
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/artisan/${job.artisanId}');
                },
                child: Row(
                  children: [
                    Text(
                      artisanName?.isNotEmpty == true
                          ? artisanName!
                          : job.artisanId,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: context.colors.primary,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            Text(
              'Quotes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            quotesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const _AdminErrorState(),
              data: (quotes) {
                if (quotes.isEmpty) {
                  return Text(
                    'No quotes submitted yet.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  );
                }
                return Column(
                  children: quotes
                      .map(
                        (q) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${q.artisanName} — ₦${q.amount.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.colors.textPrimary,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                ),
                                Text(
                                  q.status.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.textSecondary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            Text(
              'Dispute',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            disputeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const _AdminErrorState(),
              data: (dispute) {
                if (dispute == null) {
                  return Text(
                    'No dispute on this job.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.errorSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dispute.status.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.colors.error,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dispute.reason,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Review and resolve from the Disputes tab.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleting ? null : _deleteJob,
                icon: _deleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.error),
                      )
                    : Icon(Icons.delete_outline_rounded, color: context.colors.error),
                label: Text(
                  _deleting ? 'Deleting…' : 'Delete Job Request',
                  style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only for spam or fake job requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textTertiary,
          fontFamily: 'Inter',
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      ),
    ],
  );
}
