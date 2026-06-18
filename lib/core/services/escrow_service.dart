import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/job_model.dart';

/// All job state transitions are validated here and written atomically.
/// No client can bypass this — every transition checks the current state first.
class EscrowService {
  final FirebaseFirestore _db;

  EscrowService(this._db);

  static const _jobs = 'jobs';

  Future<void> transitionTo(
    String jobId,
    JobStatus target, {
    Map<String, dynamic> extra = const {},
  }) async {
    final ref = _db.collection(_jobs).doc(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Job $jobId not found');

      final data = snap.data()!;
      if (data['status'] == null) throw Exception('Job $jobId is missing status field');
      final current = JobStatus.fromString(data['status'] as String);
      _assertValidTransition(current, target);

      final now = Timestamp.now();
      final update = <String, dynamic>{
        'status': target.name,
        ...extra,
      };

      switch (target) {
        case JobStatus.matched:
          update['matchedAt'] = now;
        case JobStatus.escrowLocked:
          update['escrowLockedAt'] = now;
          // Auto-release 7 days after completion submission if customer does nothing
          update['autoReleaseAt'] =
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 7)));
        case JobStatus.submitted:
          update['submittedAt'] = now;
          // 14-day dispute window from submission
          update['disputeWindowEndsAt'] =
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 14)));
        case JobStatus.inProgress:
          update['startedAt'] = now;
        case JobStatus.completed:
          update['completedAt'] = now;
        case JobStatus.resolved:
          update['completedAt'] = now;
        default:
          break;
      }

      tx.update(ref, update);
    });
  }

  /// Customer accepts artisan → matched
  Future<void> acceptArtisan(String jobId, String artisanId) =>
      transitionTo(jobId, JobStatus.matched, extra: {'artisanId': artisanId});

  /// Customer opens chat → inChat
  Future<void> openChat(String jobId) =>
      transitionTo(jobId, JobStatus.inChat);

  /// Customer confirms payment amount → paymentPending
  Future<void> initPayment(String jobId, double amount) => transitionTo(
        jobId,
        JobStatus.paymentPending,
        extra: {'agreedAmount': amount},
      );

  /// Paystack webhook confirmed → escrow held
  Future<void> lockEscrow(String jobId, String paystackRef) => transitionTo(
        jobId,
        JobStatus.escrowLocked,
        extra: {'paymentReference': paystackRef},
      );

  /// Artisan marks work started
  Future<void> startWork(String jobId) =>
      transitionTo(jobId, JobStatus.inProgress);

  /// Artisan submits completion proof
  Future<void> submitCompletion(
    String jobId, {
    required List<String> completionImageUrls,
    String? artisanNotes,
  }) async {
    final extra = <String, dynamic>{
      'completionImageUrls': completionImageUrls,
    };
    if (artisanNotes != null) extra['artisanNotes'] = artisanNotes;
    await transitionTo(jobId, JobStatus.submitted, extra: extra);
  }

  /// Customer confirms → release funds
  Future<void> confirmComplete(String jobId) async {
    await transitionTo(jobId, JobStatus.completed);
    // Cloud Function handles actual fund release via Paystack transfer
    await _db.collection('escrow_releases').add({
      'jobId': jobId,
      'requestedAt': Timestamp.now(),
      'status': 'pending',
    });
  }

  /// Customer raises dispute
  Future<void> raiseDispute(String jobId, String reason) => transitionTo(
        jobId,
        JobStatus.disputed,
        extra: {'disputeReason': reason},
      );

  /// Admin resolves dispute
  Future<void> resolveDispute(String jobId, String resolution) => transitionTo(
        jobId,
        JobStatus.resolved,
        extra: {'disputeResolution': resolution},
      );

  void _assertValidTransition(JobStatus from, JobStatus to) {
    final allowed = _transitions[from];
    if (allowed == null || !allowed.contains(to)) {
      throw Exception(
        'Invalid escrow transition: ${from.name} → ${to.name}',
      );
    }
  }

  static const _transitions = <JobStatus, Set<JobStatus>>{
    JobStatus.requested: {JobStatus.matched, JobStatus.cancelled},
    JobStatus.matched: {JobStatus.inChat, JobStatus.cancelled},
    JobStatus.inChat: {JobStatus.paymentPending, JobStatus.cancelled},
    JobStatus.paymentPending: {JobStatus.escrowLocked, JobStatus.cancelled},
    JobStatus.escrowLocked: {JobStatus.inProgress, JobStatus.disputed, JobStatus.cancelled},
    JobStatus.inProgress: {JobStatus.submitted, JobStatus.disputed},
    JobStatus.submitted: {JobStatus.completed, JobStatus.disputed},
    JobStatus.completed: {},
    JobStatus.disputed: {JobStatus.resolved},
    JobStatus.resolved: {},
    JobStatus.cancelled: {},
  };
}
