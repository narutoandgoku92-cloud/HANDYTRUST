import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/artisan_model.dart';
import '../../models/job_mutation_context.dart';
import '../../models/quote_model.dart';
import '../utils/safe_firestore.dart';
import 'job_service.dart';
import 'notification_service.dart';

/// Write layer for the quote marketplace domain.
///
/// Quote documents (`jobs/{jobId}/quotes/{artisanId}`) are owned here for
/// submit/edit/withdraw — none of those touch the job document, so they
/// don't need JobService. Accepting a quote DOES mutate the job (requested
/// → matched), so that path is delegated to [JobService.acceptQuote],
/// preserving JobService as the single writer for job documents.
class QuoteService {
  final FirebaseFirestore _db;
  final JobService _jobService;
  final NotificationService _notifications;

  QuoteService(this._db, this._jobService) : _notifications = NotificationService(_db);

  CollectionReference<Map<String, dynamic>> _quotesCol(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('quotes');

  DocumentReference<Map<String, dynamic>> _quoteRef(String jobId, String artisanId) =>
      _quotesCol(jobId).doc(artisanId);

  /// Submits a new quote, or edits an existing pending one (same doc ID).
  Future<void> submitQuote({
    required String jobId,
    required String artisanId,
    required double amount,
    required int durationDays,
    String? notes,
  }) async {
    final artisanSnap = await _db.collection('artisans').doc(artisanId).get();
    if (!artisanSnap.exists) {
      throw StateError('Artisan profile not found for $artisanId');
    }
    final artisan = ArtisanModel.fromJson({...artisanSnap.data()!, 'uid': artisanId});
    final isVerified = artisan.verificationStatus == 'id_verified' ||
        artisan.verificationStatus == 'trusted';

    final ref = _quoteRef(jobId, artisanId);
    final existing = await ref.get();
    final isNew = !existing.exists;

    await ref.set({
      'id': artisanId,
      'jobId': jobId,
      'artisanId': artisanId,
      'amount': amount,
      'durationDays': durationDays,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'status': 'pending',
      'createdAt': isNew ? FieldValue.serverTimestamp() : existing.data()!['createdAt'],
      'updatedAt': FieldValue.serverTimestamp(),
      'artisanName': artisan.displayName,
      'artisanRating': artisan.rating,
      'artisanTrustTier': artisan.trustTier,
      'artisanVerified': isVerified,
      if (artisan.profileImageUrl != null) 'artisanProfileImageUrl': artisan.profileImageUrl,
    });

    if (isNew) {
      final jobSnap = await _db.collection('jobs').doc(jobId).get();
      final customerId = jobSnap.data()?['customerId'] as String?;
      if (customerId != null) {
        await _notifications.send(
          userId: customerId,
          type: 'quote_received',
          title: 'New Quote Received',
          body: '${artisan.displayName} sent a quote for ₦${amount.toStringAsFixed(0)}.',
          jobId: jobId,
        );
      }
    }
  }

  /// Withdraws a still-pending quote. No job mutation — quote-only write.
  Future<void> withdrawQuote({required String jobId, required String artisanId}) async {
    final ref = _quoteRef(jobId, artisanId);
    final snap = await ref.get();
    if (!snap.exists) return;
    if (snap.data()!['status'] != 'pending') {
      throw StateError('Only a pending quote can be withdrawn.');
    }
    await ref.update({'status': 'withdrawn', 'updatedAt': FieldValue.serverTimestamp()});

    final jobSnap = await _db.collection('jobs').doc(jobId).get();
    final customerId = jobSnap.data()?['customerId'] as String?;
    if (customerId != null) {
      await _notifications.send(
        userId: customerId,
        type: 'quote_withdrawn',
        title: 'Quote Withdrawn',
        body: 'An artisan withdrew their quote for your job.',
        jobId: jobId,
      );
    }
  }

  /// Customer rejects a single quote without accepting another.
  Future<void> rejectQuote({
    required String jobId,
    required String artisanId,
  }) async {
    final ref = _quoteRef(jobId, artisanId);
    final snap = await ref.get();
    if (!snap.exists || snap.data()!['status'] != 'pending') {
      throw StateError('Quote is not pending.');
    }
    await ref.update({'status': 'rejected', 'updatedAt': FieldValue.serverTimestamp()});
    await _notifications.send(
      userId: artisanId,
      type: 'quote_rejected',
      title: 'Quote Declined',
      body: 'Your quote was declined for a job.',
      jobId: jobId,
    );
  }

  /// Accepts a quote: closes every competing quote and matches the job —
  /// the job mutation itself is delegated to [JobService.acceptQuote].
  Future<void> acceptQuote(
    JobMutationContext ctx, {
    required String jobId,
    required String artisanId,
  }) async {
    final pending = await _quotesCol(jobId).where('status', isEqualTo: 'pending').get();
    final competingIds = pending.docs.map((d) => d.id).toList();
    if (!competingIds.contains(artisanId)) competingIds.add(artisanId);

    await _jobService.acceptQuote(
      ctx,
      jobId,
      quoteId: artisanId,
      artisanId: artisanId,
      competingQuoteIds: competingIds,
    );

    await _notifications.send(
      userId: artisanId,
      type: 'quote_accepted',
      title: 'Quote Accepted!',
      body: 'Your quote was accepted. You can now chat with the customer.',
      jobId: jobId,
    );
  }

  Stream<List<QuoteModel>> watchJobQuotes(String jobId) {
    return safeStream(
      _quotesCol(jobId),
      (d) => QuoteModel.fromJson(d.data()),
      debugLabel: 'jobQuotes:$jobId',
    ).map((quotes) => quotes
      ..sort((a, b) =>
          (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now())));
  }

  Stream<QuoteModel?> watchArtisanQuote(String jobId, String artisanId) {
    return safeDocStream(
      _quoteRef(jobId, artisanId),
      QuoteModel.fromJson,
      debugLabel: 'artisanQuote:$jobId:$artisanId',
    );
  }

}
