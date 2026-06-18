import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/quote_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/job_model.dart';
import '../models/quote_model.dart';
import 'job_service_provider.dart';

final quoteServiceProvider = Provider<QuoteService>(
  (ref) => QuoteService(FirebaseFirestore.instance, ref.watch(jobServiceProvider)),
);

/// All quotes for a job — drives the customer's Quote Inbox.
final jobQuotesProvider = StreamProvider.family<List<QuoteModel>, String>(
  (ref, jobId) => ref.watch(quoteServiceProvider).watchJobQuotes(jobId),
);

class ArtisanJobQuoteKey {
  final String jobId;
  final String artisanId;
  const ArtisanJobQuoteKey(this.jobId, this.artisanId);

  @override
  bool operator ==(Object other) =>
      other is ArtisanJobQuoteKey && other.jobId == jobId && other.artisanId == artisanId;

  @override
  int get hashCode => Object.hash(jobId, artisanId);
}

/// This artisan's own quote (if any) for a job — drives submit/edit/withdraw UI.
final artisanQuoteForJobProvider =
    StreamProvider.family<QuoteModel?, ArtisanJobQuoteKey>(
  (ref, key) => ref.watch(quoteServiceProvider).watchArtisanQuote(key.jobId, key.artisanId),
);

/// Open Jobs Feed — jobs still in 'requested' status matching the artisan's
/// category. Sorted newest-first on the client, mirroring
/// [customerJobsProvider]/[artisanJobsProvider] in escrow_provider.dart.
final openJobsFeedProvider = StreamProvider.family<List<JobModel>, String>(
  (ref, category) {
    return safeStream(
      FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'requested')
          .where('category', isEqualTo: category),
      (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
      debugLabel: 'openJobsFeed:$category',
    ).map((jobs) => jobs..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  },
);
