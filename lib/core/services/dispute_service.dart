import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/audit_log_model.dart';
import '../../models/dispute_model.dart';
import '../../models/job_mutation_context.dart';
import '../utils/safe_firestore.dart';
import 'job_service.dart';
import 'notification_service.dart';

/// Write layer for the dispute domain.
///
/// Raising and resolving a dispute both mutate /jobs (status transition)
/// AND /disputes (the record) — those two writes are delegated to
/// [JobService.raiseDisputeWithRecord] / [resolveDisputeWithRecord] so they
/// commit atomically in a single transaction, preserving JobService as the
/// single writer of job documents. The artisan's response to a dispute does
/// NOT touch /jobs, so it is a direct, narrow Firestore write here — exactly
/// the field whitelist permitted by the disputes security rule.
class DisputeService {
  final FirebaseFirestore _db;
  final JobService _jobService;
  final NotificationService _notifications;

  DisputeService(this._db, this._jobService)
      : _notifications = NotificationService(_db);

  CollectionReference<Map<String, dynamic>> get _disputesCol =>
      _db.collection('disputes');

  /// Pre-allocates a dispute document ID. Callers that need to upload
  /// evidence to Storage first (path includes the dispute ID) should call
  /// this, upload, then pass the same ID into [raiseDispute].
  String newDisputeId() => _disputesCol.doc().id;

  /// Customer raises a dispute against the assigned artisan.
  Future<void> raiseDispute({
    required String disputeId,
    required String jobId,
    required String customerId,
    required String artisanId,
    required String reason,
    List<String> evidenceImageUrls = const [],
  }) async {
    final disputeRef = _disputesCol.doc(disputeId);
    final ctx = JobMutationContext.customer(
      uid: customerId,
      actionType: JobActionType.disputeRaised,
      reason: reason,
    );

    await _jobService.raiseDisputeWithRecord(
      ctx,
      jobId,
      disputeId: disputeRef.id,
      reason: reason,
      againstUserId: artisanId,
      evidenceImageUrls: evidenceImageUrls,
    );

    await _notifications.send(
      userId: artisanId,
      type: 'dispute_raised',
      title: 'A dispute was raised',
      body: 'The customer raised a dispute on a job. Respond with your side within 14 days.',
      jobId: jobId,
    );
  }

  /// Against-party (artisan) responds with their side and evidence.
  /// One-shot — the rule only allows these three fields, and only once
  /// while the dispute is open (a resolved/dismissed dispute is read-only
  /// to non-admins because [resolveDispute] changes its status).
  Future<void> respondToDispute({
    required String disputeId,
    required String responseText,
    List<String> evidenceImageUrls = const [],
  }) async {
    await _disputesCol.doc(disputeId).update({
      'artisanResponseText': responseText,
      'artisanEvidenceUrls': evidenceImageUrls,
      'artisanRespondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin resolves (or dismisses) a dispute.
  Future<void> resolveDispute({
    required String jobId,
    required String disputeId,
    required String adminId,
    required String raisedBy,
    required String againstUserId,
    required String resolution,
    String? adminNote,
    bool dismiss = false,
  }) async {
    final ctx = JobMutationContext.admin(
      uid: adminId,
      actionType: JobActionType.disputeResolved,
      reason: resolution,
    );

    await _jobService.resolveDisputeWithRecord(
      ctx,
      jobId,
      disputeId: disputeId,
      resolution: resolution,
      adminNote: adminNote,
      dismiss: dismiss,
    );

    for (final userId in {raisedBy, againstUserId}) {
      await _notifications.send(
        userId: userId,
        type: 'dispute_resolved',
        title: dismiss ? 'Dispute Dismissed' : 'Dispute Resolved',
        body: resolution,
        jobId: jobId,
      );
    }
  }

  /// The single dispute record for a job, if one exists.
  Stream<DisputeModel?> watchDisputeForJob(String jobId) => safeStream(
        _disputesCol.where('jobId', isEqualTo: jobId).limit(1),
        (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'disputeForJob:$jobId',
      ).map((list) => list.isEmpty ? null : list.first);

  /// All open/under-review disputes — drives the admin Disputes tab.
  Stream<List<DisputeModel>> watchOpenDisputes() => safeStream(
        _disputesCol.where('status', whereIn: ['open', 'underReview']),
        (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'openDisputes',
      ).map((disputes) => disputes..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
}
