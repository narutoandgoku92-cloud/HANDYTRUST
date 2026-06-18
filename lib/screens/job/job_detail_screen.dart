import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import '../../core/services/storage_service.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/job_mutation_context.dart';
import '../../models/audit_log_model.dart';
import '../../models/quote_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/quote_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/job_timeline_widget.dart';

class JobDetailScreen extends ConsumerWidget {
  final String jobId;

  const JobDetailScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(jobId));
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Job Details')),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (job) {
          if (job == null) {
            return const Center(child: Text('Job not found'));
          }
          final isCustomer = userAsync.value?.isCustomer ?? true;
          return _JobDetailBody(
            job: job,
            isCustomer: isCustomer,
            currentUserId: userAsync.value?.uid,
          );
        },
      ),
    );
  }
}

class _JobDetailBody extends ConsumerWidget {
  final JobModel job;
  final bool isCustomer;
  final String? currentUserId;

  const _JobDetailBody({
    required this.job,
    required this.isCustomer,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final escrow = ref.watch(escrowNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobTimelineWidget(job: job),
          const SizedBox(height: 20),
          if (job.status == JobStatus.requested &&
              isCustomer &&
              currentUserId != null) ...[
            _QuoteInboxSection(job: job, customerId: currentUserId!),
            const SizedBox(height: 20),
          ],
          if (job.status == JobStatus.submitted) ...[
            _DisputeCountdownBanner(job: job),
            const SizedBox(height: 20),
          ],
          if ((job.status == JobStatus.disputed ||
                  job.status == JobStatus.resolved) &&
              currentUserId != null) ...[
            _DisputeThreadSection(job: job, currentUserId: currentUserId!),
            const SizedBox(height: 20),
          ],
          _detailSection(context, 'Service Category', job.category),
          const SizedBox(height: 16),
          _detailSection(context, 'Description', job.description),
          if (job.agreedAmount != null) ...[
            const SizedBox(height: 16),
            _detailSection(
              context,
              'Agreed Amount',
              '₦${NumberFormat('#,##0').format(job.agreedAmount!)}',
            ),
          ],
          if (job.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _imageSection(context, 'Before Photos', job.imageUrls),
          ],
          if (job.completionImageUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _imageSection(
              context,
              'Completion Photos',
              job.completionImageUrls,
            ),
          ],
          if (job.artisanNotes != null) ...[
            const SizedBox(height: 16),
            _detailSection(context, 'Artisan Notes', job.artisanNotes!),
          ],
          if (job.artisanId.isNotEmpty) ...[
            const SizedBox(height: 20),
            _artisanSection(context, ref),
          ],
          const SizedBox(height: 28),
          _actionButtons(context, ref, escrow),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _detailSection(BuildContext context, String title, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
              height: 1.5,
            ),
          ),
        ],
      );

  Widget _imageSection(BuildContext context, String title, List<String> urls) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  urls[i],
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, stack) => Container(
                    width: 120,
                    height: 120,
                    color: context.colors.surfaceVariant,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _artisanSection(BuildContext context, WidgetRef ref) {
    final artisanAsync = ref.watch(artisanProfileProvider(job.artisanId));

    return artisanAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, stack) => const SizedBox.shrink(),
      data: (artisan) {
        if (artisan == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => context.push('/artisan/${artisan.uid}'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderLight),
            ),
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
                          artisan.displayName.isNotEmpty
                              ? artisan.displayName[0].toUpperCase()
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
                        artisan.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'Artisan',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionButtons(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<void> escrow,
  ) {
    final loading = escrow.isLoading;

    return switch (job.status) {
      JobStatus.inChat => Column(
        children: [
          ElevatedButton(
            onPressed: loading
                ? null
                : () => context.push('/payment/${job.id}'),
            child: const Text('Proceed to Payment'),
          ),
        ],
      ),
      JobStatus.escrowLocked =>
        isCustomer
            ? const SizedBox.shrink()
            : ElevatedButton(
                onPressed: loading
                    ? null
                    : () => ref
                          .read(escrowNotifierProvider.notifier)
                          .startWork(job.id),
                child: const Text('Start Work'),
              ),
      JobStatus.inProgress =>
        isCustomer
            ? const SizedBox.shrink()
            : ElevatedButton(
                onPressed: loading
                    ? null
                    : () => context.push('/job/${job.id}/submit'),
                child: const Text('Submit Completion'),
              ),
      JobStatus.submitted =>
        isCustomer
            ? Column(
                children: [
                  ElevatedButton(
                    onPressed: loading
                        ? null
                        : () async {
                            await ref
                                .read(escrowNotifierProvider.notifier)
                                .confirmComplete(job.id);
                            if (context.mounted) {
                              context.push('/review/${job.id}');
                            }
                          },
                    child: const Text('Confirm & Release Payment'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: loading
                        ? null
                        : () => context.push('/dispute/${job.id}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                    ),
                    child: const Text('Raise Dispute'),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      JobStatus.completed =>
        isCustomer
            ? Consumer(
                builder: (context, ref, _) {
                  final reviewAsync = ref.watch(jobReviewProvider(job.id));
                  final alreadyReviewed = reviewAsync.asData?.value != null;
                  return OutlinedButton(
                    onPressed: () => context.push('/review/${job.id}'),
                    child: Text(
                      alreadyReviewed ? 'View My Review' : 'Leave a Review',
                    ),
                  );
                },
              )
            : const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Customer-side Quote Inbox — shown while the job is still 'requested'.
/// Lists every quote with price/duration/rating/trust tier/verification
/// badge; accepting routes through QuoteService.acceptQuote, which
/// delegates the job mutation to JobService (single write layer).
class _QuoteInboxSection extends ConsumerStatefulWidget {
  final JobModel job;
  final String customerId;

  const _QuoteInboxSection({required this.job, required this.customerId});

  @override
  ConsumerState<_QuoteInboxSection> createState() => _QuoteInboxSectionState();
}

class _QuoteInboxSectionState extends ConsumerState<_QuoteInboxSection> {
  String? _actingOnArtisanId;

  Future<void> _accept(QuoteModel quote) async {
    setState(() => _actingOnArtisanId = quote.artisanId);
    try {
      final ctx = JobMutationContext.customer(
        uid: widget.customerId,
        actionType: JobActionType.quoteAccepted,
        reason: 'Accepted quote from ${quote.artisanName}',
      );
      await ref
          .read(quoteServiceProvider)
          .acceptQuote(ctx, jobId: widget.job.id, artisanId: quote.artisanId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not accept quote: $e');
    } finally {
      if (mounted) setState(() => _actingOnArtisanId = null);
    }
  }

  Future<void> _reject(QuoteModel quote) async {
    setState(() => _actingOnArtisanId = quote.artisanId);
    try {
      await ref
          .read(quoteServiceProvider)
          .rejectQuote(jobId: widget.job.id, artisanId: quote.artisanId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not reject quote: $e');
    } finally {
      if (mounted) setState(() => _actingOnArtisanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(jobQuotesProvider(widget.job.id));

    return quotesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
      data: (quotes) {
        final pending =
            quotes.where((q) => q.status == QuoteStatus.pending).toList()
              ..sort((a, b) => a.amount.compareTo(b.amount));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quotes Received (${pending.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            if (pending.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Waiting for artisans to submit quotes for this job.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              ...pending.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuoteCard(
                    quote: q,
                    busy: _actingOnArtisanId == q.artisanId,
                    onAccept: () => _accept(q),
                    onReject: () => _reject(q),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Shown while a job is 'submitted' — counts down the 14-day window during
/// which the customer may raise a dispute before the job would otherwise
/// auto-complete. Purely informational; the actual auto-completion and
/// dispute-window enforcement live server-side (JobService writes
/// disputeWindowEndsAt when the job is submitted).
class _DisputeCountdownBanner extends StatefulWidget {
  final JobModel job;

  const _DisputeCountdownBanner({required this.job});

  @override
  State<_DisputeCountdownBanner> createState() =>
      _DisputeCountdownBannerState();
}

class _DisputeCountdownBannerState extends State<_DisputeCountdownBanner> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    final endsAt = widget.job.disputeWindowEndsAt;
    final remaining = endsAt == null
        ? Duration.zero
        : endsAt.difference(DateTime.now());
    if (mounted) {
      setState(
        () => _remaining = remaining.isNegative ? Duration.zero : remaining,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.job.disputeWindowEndsAt == null) return const SizedBox.shrink();
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.warningSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.colors.warning.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: context.colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _remaining == Duration.zero
                  ? 'Dispute window has closed.'
                  : 'You have $days day${days == 1 ? '' : 's'} $hours hr${hours == 1 ? '' : 's'} left to raise a dispute before this job auto-completes.',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dispute Thread — shown once a job is 'disputed' or 'resolved'. Displays
/// the customer's original complaint + evidence, the artisan's response
/// (if any), an inline response form for the artisan while still open, and
/// the admin's resolution once the dispute is closed. Reads via
/// [disputeForJobProvider]; the artisan response write goes straight through
/// DisputeService.respondToDispute (status-transition writes still go
/// through JobService — see Section 4 dispute_service.dart).
class _DisputeThreadSection extends ConsumerStatefulWidget {
  final JobModel job;
  final String currentUserId;

  const _DisputeThreadSection({required this.job, required this.currentUserId});

  @override
  ConsumerState<_DisputeThreadSection> createState() =>
      _DisputeThreadSectionState();
}

class _DisputeThreadSectionState extends ConsumerState<_DisputeThreadSection> {
  final _responseController = TextEditingController();
  final List<Uint8List> _evidenceImages = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        quality: 70,
      );
      bytes = Uint8List.fromList(compressed);
    }
    setState(() => _evidenceImages.add(bytes));
  }

  Future<void> _respond(DisputeModel dispute) async {
    if (_responseController.text.trim().isEmpty) {
      setState(() => _error = 'Please describe your side of the dispute.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final storage = StorageService();
      final evidenceUrls = <String>[];
      for (int i = 0; i < _evidenceImages.length; i++) {
        final url = await storage.uploadDisputeEvidence(
          disputeId: dispute.id,
          userId: widget.currentUserId,
          index: i,
          bytes: _evidenceImages[i],
        );
        evidenceUrls.add(url);
      }
      await ref
          .read(disputeServiceProvider)
          .respondToDispute(
            disputeId: dispute.id,
            responseText: _responseController.text.trim(),
            evidenceImageUrls: evidenceUrls,
          );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disputeAsync = ref.watch(disputeForJobProvider(widget.job.id));

    return disputeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
      data: (dispute) {
        if (dispute == null) return const SizedBox.shrink();
        final isAgainstParty = dispute.againstUserId == widget.currentUserId;
        final canRespond =
            isAgainstParty &&
            dispute.artisanRespondedAt == null &&
            dispute.status == DisputeStatus.open;

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
                  Icon(
                    Icons.gavel_rounded,
                    color: context.colors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dispute',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          dispute.status == DisputeStatus.resolved ||
                              dispute.status == DisputeStatus.dismissed
                          ? context.colors.accentSurface
                          : context.colors.errorSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dispute.status.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                        color:
                            dispute.status == DisputeStatus.resolved ||
                                dispute.status == DisputeStatus.dismissed
                            ? context.colors.accent
                            : context.colors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _threadEntry(
                'Customer',
                dispute.reason,
                dispute.evidenceImageUrls,
              ),
              if (dispute.artisanRespondedAt != null) ...[
                const SizedBox(height: 12),
                _threadEntry(
                  'Artisan Response',
                  dispute.artisanResponseText ?? '',
                  dispute.artisanEvidenceUrls,
                ),
              ],
              if (widget.job.status == JobStatus.resolved &&
                  dispute.resolution != null) ...[
                const SizedBox(height: 12),
                _threadEntry('Admin Resolution', dispute.resolution!, const []),
              ],
              if (canRespond) ...[
                const SizedBox(height: 16),
                Text(
                  'Respond to this dispute',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _responseController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Describe your side of the dispute...',
                  ),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _evidenceImages.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == _evidenceImages.length) {
                      return GestureDetector(
                        onTap: _pickEvidence,
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: context.colors.textTertiary,
                              size: 22,
                            ),
                          ),
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _evidenceImages[i],
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: context.colors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _submitting ? null : () => _respond(dispute),
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Response'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _threadEntry(String label, String text, List<String> imageUrls) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                separatorBuilder: (_, index) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrls[i],
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

class _QuoteCard extends StatelessWidget {
  final QuoteModel quote;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _QuoteCard({
    required this.quote,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
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
          // Full numeric trust score + breakdown already exists on the
          // artisan's own profile (TrustScoreCard) — reuse it instead of
          // denormalizing the score onto the quote doc.
          GestureDetector(
            onTap: () => context.push('/artisan/${quote.artisanId}'),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.primarySurface,
                  backgroundImage: quote.artisanProfileImageUrl != null
                      ? NetworkImage(quote.artisanProfileImageUrl!)
                      : null,
                  child: quote.artisanProfileImageUrl == null
                      ? Text(
                          quote.artisanName.isNotEmpty
                              ? quote.artisanName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              quote.artisanName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Inter',
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          if (quote.artisanVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: context.colors.accent,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: context.colors.ratingGold,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            quote.artisanRating == 0
                                ? 'New'
                                : quote.artisanRating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.primarySurface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              quote.artisanTrustTier,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.colors.primary,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '₦${NumberFormat('#,##0').format(quote.amount)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${quote.durationDays} day${quote.durationDays == 1 ? '' : 's'} estimated',
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          if (quote.notes != null && quote.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              quote.notes!,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                '/chat/${quote.jobId}',
                extra: {
                  'artisanId': quote.artisanId,
                  'artisanName': quote.artisanName,
                },
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text('Chat'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: context.colors.textInverse,
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
