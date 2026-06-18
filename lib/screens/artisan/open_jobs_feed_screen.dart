import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/job_model.dart';
import '../../models/quote_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/quote_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';

/// Artisan-side Open Jobs Feed — browse jobs still in 'requested' status
/// within the artisan's own category and submit a quote.
class OpenJobsFeedScreen extends ConsumerWidget {
  final String category;

  const OpenJobsFeedScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(openJobsFeedProvider(category));
    final userAsync = ref.watch(currentUserProfileProvider);
    final artisanId = userAsync.value?.uid;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Open Jobs')),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.work_off_outlined,
                      size: 56,
                      color: context.colors.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No open $category jobs right now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'New job requests will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (artisanId == null) return const SizedBox.shrink();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) =>
                _OpenJobCard(job: jobs[i], artisanId: artisanId),
          );
        },
      ),
    );
  }
}

class _OpenJobCard extends ConsumerWidget {
  final JobModel job;
  final String artisanId;

  const _OpenJobCard({required this.job, required this.artisanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myQuoteAsync = ref.watch(
      artisanQuoteForJobProvider(ArtisanJobQuoteKey(job.id, artisanId)),
    );
    final myQuote = myQuoteAsync.value;
    final hasActiveQuote =
        myQuote != null && (myQuote.status == QuoteStatus.pending);

    return Container(
      padding: const EdgeInsets.all(16),
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
                  job.category,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              _UrgencyChip(urgency: job.urgency),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            job.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
          if (job.budgetMin != null || job.budgetMax != null) ...[
            const SizedBox(height: 8),
            Text(
              'Budget: ₦${NumberFormat('#,##0').format(job.budgetMin ?? 0)} – ₦${NumberFormat('#,##0').format(job.budgetMax ?? job.budgetMin ?? 0)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.primary,
                fontFamily: 'Inter',
              ),
            ),
          ],
          if (job.customerAddress != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: context.colors.textTertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    job.customerAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Chat Customer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: hasActiveQuote
                    ? OutlinedButton(
                        onPressed: () =>
                            _openQuoteSheet(context, ref, existing: myQuote),
                        child: Text(
                          'Edit Quote (₦${NumberFormat('#,##0').format(myQuote.amount)})',
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () =>
                            _openQuoteSheet(context, ref, existing: null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          foregroundColor: context.colors.textInverse,
                        ),
                        child: const Text("I'm Interested"),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Opens (or creates, on first message) the job's chat thread between this
  // artisan and the customer — same /jobs/{jobId}/messages used by the
  // post-match chat screen, just reached before a quote is accepted.
  // No customer-name lookup: /users/{uid} is owner/admin-only by design
  // (protects customer PII from browsing artisans), so this mirrors the
  // existing 'Artisan'-fallback pattern used the other direction.
  void _openChat(BuildContext context) {
    context.push(
      '/chat/${job.id}',
      extra: {'artisanId': job.customerId, 'artisanName': 'Customer'},
    );
  }

  void _openQuoteSheet(
    BuildContext context,
    WidgetRef ref, {
    QuoteModel? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubmitQuoteSheet(
        jobId: job.id,
        artisanId: artisanId,
        existing: existing,
      ),
    );
  }
}

class _UrgencyChip extends StatelessWidget {
  final String urgency;
  const _UrgencyChip({required this.urgency});

  @override
  Widget build(BuildContext context) {
    final isAsap = urgency == 'asap';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAsap
            ? context.colors.warningSurface
            : context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isAsap ? 'ASAP' : 'Scheduled',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isAsap ? context.colors.warning : context.colors.textSecondary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class _SubmitQuoteSheet extends ConsumerStatefulWidget {
  final String jobId;
  final String artisanId;
  final QuoteModel? existing;

  const _SubmitQuoteSheet({
    required this.jobId,
    required this.artisanId,
    this.existing,
  });

  @override
  ConsumerState<_SubmitQuoteSheet> createState() => _SubmitQuoteSheetState();
}

class _SubmitQuoteSheetState extends ConsumerState<_SubmitQuoteSheet> {
  late final _amountController = TextEditingController(
    text: widget.existing?.amount.toStringAsFixed(0) ?? '',
  );
  late final _durationController = TextEditingController(
    text: widget.existing?.durationDays.toString() ?? '1',
  );
  late final _notesController = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  bool _submitting = false;
  bool _withdrawing = false;

  @override
  void dispose() {
    _amountController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    if (amount == null || amount <= 0) {
      showErrorSnackbar(context, 'Enter a valid quote amount.');
      return;
    }
    if (duration == null || duration <= 0) {
      showErrorSnackbar(context, 'Enter a valid duration in days.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(quoteServiceProvider)
          .submitQuote(
            jobId: widget.jobId,
            artisanId: widget.artisanId,
            amount: amount,
            durationDays: duration,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not submit quote: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _withdrawing = true);
    try {
      await ref
          .read(quoteServiceProvider)
          .withdrawQuote(jobId: widget.jobId, artisanId: widget.artisanId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not withdraw quote: $e');
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Edit Your Quote' : 'Submit a Quote',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quote Amount (₦)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimated Duration (days)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting || _withdrawing ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.textInverse,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isEdit ? 'Update Quote' : 'Submit Quote'),
              ),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _submitting || _withdrawing ? null : _withdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _withdrawing
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.error,
                          ),
                        )
                      : const Text('Withdraw Quote'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
