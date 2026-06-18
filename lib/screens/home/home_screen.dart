import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/job_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/job_status_badge.dart';
import '../../widgets/notification_bell.dart';
import '../artisan/artisan_dashboard_screen.dart';

const _categories = [
  ('Plumbing', Icons.water_drop_outlined),
  ('Electrical', Icons.bolt_outlined),
  ('Carpentry', Icons.handyman_outlined),
  ('Painting', Icons.format_paint_outlined),
  ('Cleaning', Icons.cleaning_services_outlined),
  ('Welding', Icons.construction_outlined),
  ('Tiling', Icons.grid_on_outlined),
  ('Generator', Icons.electrical_services_outlined),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedCategory = '';

  /// Hidden admin entry point. Checks /admins/{uid} (the same source of
  /// truth Firestore security rules and isAdminProvider use) BEFORE ever
  /// showing the PIN dialog, then requires a correct PIN before navigating.
  /// Both checks fail silently/subtly — no UI ever reveals whether the
  /// signed-in account is an admin.
  Future<void> _handleHiddenAdminGesture() async {
    final uid = ref.read(authStateChangesProvider).asData?.value?.uid;
    if (uid == null) return;

    DocumentSnapshot<Map<String, dynamic>> adminDoc;
    try {
      adminDoc = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    } catch (_) {
      // Non-admins get permission-denied here, since /admins read rules
      // require isAdmin() to already be true — that failure IS the "not an
      // admin" signal. Exit silently either way.
      return;
    }
    if (!adminDoc.exists || !mounted) return;

    final enteredPin = await showDialog<String>(
      context: context,
      builder: (_) => const _AdminPinDialog(),
    );
    if (enteredPin == null || !mounted) return; // dialog cancelled

    final storedPin = adminDoc.data()?['pin'] as String?;
    if (storedPin == null || enteredPin != storedPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid'), duration: Duration(seconds: 1)),
      );
      return;
    }

    if (mounted) context.go('/admin');
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    // Route to the artisan dashboard only while activeRole is 'artisan' —
    // dual-role users can switch back and forth without losing either role.
    final user = userAsync.asData?.value;
    if (user != null && user.isArtisan && user.activeRole == 'artisan') {
      return const ArtisanDashboardScreen();
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(userAsync, user),
            _buildCategorySection(),
            _buildRequestButton(user),
            _buildActiveJobsSection(userAsync),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue userAsync, UserModel? user) => SliverToBoxAdapter(
        child: Container(
          color: context.colors.surface,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: userAsync.when(
                      data: (profile) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hidden admin entry point: long-press the greeting.
                          // No visible affordance — non-admins who long-press
                          // this just see nothing happen.
                          GestureDetector(
                            onLongPress: _handleHiddenAdminGesture,
                            child: Text(
                              'Hello, ${profile?.name.split(' ').first ?? 'there'} 👋',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            'What service do you need today?',
                            style: TextStyle(
                              fontSize: 14,
                              color: context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                      loading: () => const SizedBox(height: 40),
                      error: (_, stack) => const Text('Hello'),
                    ),
                  ),
                  if (user != null && user.isArtisan)
                    IconButton(
                      icon: Icon(Icons.handyman_outlined,
                          color: context.colors.textSecondary),
                      tooltip: 'Switch to Artisan View',
                      onPressed: () => ref
                          .read(authServiceProvider)
                          .updateUserProfile(user.uid, {'activeRole': 'artisan'}),
                    ),
                  const NotificationBell(),
                  IconButton(
                    icon: Icon(Icons.settings_outlined,
                        color: context.colors.textSecondary),
                    onPressed: () => context.push('/settings'),
                  ),
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
              const SizedBox(height: 16),
              _SearchBar(
                onSearch: (query) {
                  if (query.isNotEmpty) {
                    context.push('/request?category=$query');
                  }
                },
              ),
            ],
          ),
        ),
      );

  Widget _buildCategorySection() => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Browse by Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemCount: _categories.length,
                itemBuilder: (ctx, i) {
                  final (name, icon) = _categories[i];
                  final selected = _selectedCategory == name;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedCategory = name);
                      context.push('/request?category=$name');
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: selected
                            ? context.colors.primarySurface
                            : context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? context.colors.primary
                              : context.colors.borderLight,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 24,
                            color: selected
                                ? context.colors.primary
                                : context.colors.textSecondary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? context.colors.primary
                                  : context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

  Widget _buildRequestButton(UserModel? user) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: () => context.push('/request'),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Post a New Job'),
              ),
              if (user != null && !user.isArtisan) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/register/artisan'),
                  icon: const Icon(Icons.handyman_outlined),
                  label: const Text('Become an Artisan'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildActiveJobsSection(AsyncValue userAsync) =>
      userAsync.when(
        data: (user) {
          if (user == null) return const SliverToBoxAdapter(child: SizedBox());
          return _ActiveJobsList(userId: user.uid);
        },
        loading: () => const SliverToBoxAdapter(child: SizedBox()),
        error: (_, stack) => const SliverToBoxAdapter(child: SizedBox()),
      );
}

class _ActiveJobsList extends ConsumerWidget {
  final String userId;

  const _ActiveJobsList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(customerJobsProvider(userId));

    return jobsAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => const SliverToBoxAdapter(child: SizedBox()),
      data: (jobs) {
        final active = jobs.where((j) => !j.status.isTerminal).toList();

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      active.isEmpty ? 'Your Jobs' : 'Active Jobs (${active.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    if (jobs.length > 3)
                      TextButton(
                        onPressed: () => context.push('/jobs'),
                        child: const Text('See all'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (active.isEmpty)
                  _emptyJobsCard(context)
                else
                  ...active.take(5).map((j) => _JobTile(job: j)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyJobsCard(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 40, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No active jobs',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Post a job to get matched with artisans',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: () => context.push('/request'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                ),
                child: const Text('Post a Job'),
              ),
            ),
          ],
        ),
      );
}

class _JobTile extends StatelessWidget {
  final JobModel job;

  const _JobTile({required this.job});

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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.build_circle_outlined,
                    color: context.colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.category,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              JobStatusBadge(status: job.status, compact: true),
            ],
          ),
        ),
      );
}

/// Ephemeral PIN entry — the controller and its value live only for the
/// lifetime of this dialog and are disposed the moment it closes. Nothing
/// here is persisted to Riverpod state, SharedPreferences, or any other
/// storage.
class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog();

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin PIN'),
      content: TextField(
        controller: _pinCtrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pinCtrl.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _SearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;

  const _SearchBar({required this.onSearch});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        onSubmitted: widget.onSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search plumbers, electricians…',
          prefixIcon:
              Icon(Icons.search_rounded, color: context.colors.textTertiary),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: context.colors.textTertiary),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {});
                  },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
      );
}
