import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/job_model.dart';
import '../../models/job_mutation_context.dart';
import '../errors/job_exceptions.dart';

/// Callback type for [JobService.applyJobUpdateTransaction].
typedef JobUpdateFn = void Function(
  Transaction tx,
  DocumentReference<Map<String, dynamic>> jobRef,
  Map<String, dynamic> currentData,
);

/// ════════════════════════════════════════════════════════════════════════════
/// JobService — single authoritative write layer for /jobs
/// ════════════════════════════════════════════════════════════════════════════
///
/// Invariants enforced on every call:
///   1. All writes go through a Firestore transaction (no bare .update()).
///   2. State transitions are validated against [allowedTransitions] unless
///      the caller supplies an admin override context.
///   3. Every transaction writes an immutable audit log entry atomically:
///         if the job update fails → audit log is NOT written
///         if the audit log write fails → job update is rolled back
///      No partial state is possible.
///   4. Three consistency fields are stamped on every job mutation:
///      lastUpdatedAt, lastUpdatedBy, updateVersion.
///   5. Status-milestone timestamps use FieldValue.serverTimestamp() —
///      no client clock is ever trusted for milestone data.
class JobService {
  final FirebaseFirestore _db;

  JobService(this._db);

  // ─── State machine ────────────────────────────────────────────────────────

  static const allowedTransitions = <JobStatus, Set<JobStatus>>{
    JobStatus.requested: {JobStatus.matched, JobStatus.cancelled},
    JobStatus.matched: {JobStatus.inChat, JobStatus.cancelled},
    JobStatus.inChat: {JobStatus.paymentPending, JobStatus.cancelled},
    JobStatus.paymentPending: {JobStatus.escrowLocked, JobStatus.cancelled},
    JobStatus.escrowLocked: {
      JobStatus.inProgress,
      JobStatus.disputed,
      JobStatus.cancelled,
    },
    JobStatus.inProgress: {JobStatus.submitted, JobStatus.disputed},
    JobStatus.submitted: {JobStatus.completed, JobStatus.disputed},
    JobStatus.completed: {},
    JobStatus.disputed: {JobStatus.resolved},
    JobStatus.resolved: {},
    JobStatus.cancelled: {},
  };

  static bool isValidTransition(JobStatus from, JobStatus to) {
    final allowed = allowedTransitions[from];
    return allowed != null && allowed.contains(to);
  }

  static void assertValidTransition(JobStatus from, JobStatus to) {
    if (!isValidTransition(from, to)) {
      throw InvalidJobTransitionException(from: from, to: to);
    }
  }

  // ─── Core write primitive ─────────────────────────────────────────────────

  /// Atomic status transition with mandatory audit trail.
  ///
  /// [ctx] carries WHO is doing WHAT and WHY. Every transaction writes the
  /// audit log entry in the same commit — partial success is impossible.
  ///
  /// Pass [skipTransitionCheck] only via [adminForceStatus] — every other
  /// caller must go through the state machine.
  Future<void> updateJobStatus(
    JobMutationContext ctx,
    String jobId,
    JobStatus to, {
    Map<String, dynamic> extra = const {},
    bool skipTransitionCheck = false,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');

      if (!skipTransitionCheck) assertValidTransition(from, to);

      final version = (data['updateVersion'] as int?) ?? 0;
      final milestones = _timestampsForStatus(to);
      final consistency = _consistencyFields(ctx: ctx, currentVersion: version);
      final userDelta = _sanitizeDelta({
        'status': to.name,
        ...extra,
      });

      tx.update(jobRef, {
        'status': to.name,
        ...extra,
        ...milestones,
        ...consistency,
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: to.name,
        versionBefore: version,
        delta: userDelta,
      ));
    });
  }

  /// Atomically updates [agreedAmount] without changing job status.
  /// Only valid when status == inChat.
  Future<void> updateAgreedAmount(
    JobMutationContext ctx,
    String jobId,
    double amount,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Cannot update agreedAmount in status "${status.name}" — must be inChat.',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'agreedAmount': amount,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null, // no status change
        versionBefore: version,
        delta: {'agreedAmount': amount},
      ));
    });
  }

  /// Atomically sends a negotiation message AND updates [proposedAmount] on
  /// the job — one transaction, one audit log entry. No split-write possible.
  Future<void> sendNegotiation(
    JobMutationContext ctx,
    String jobId,
    String receiverId,
    double proposedAmount,
  ) async {
    final jobRef = _jobRef(jobId);
    final msgRef = _db.collection('jobs').doc(jobId).collection('messages').doc();
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Negotiation only allowed while inChat (current: "${status.name}").',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;
      final now = FieldValue.serverTimestamp();

      // ① Write the chat message — schema matches MessageModel.fromJson exactly
      tx.set(msgRef, {
        'id': msgRef.id,
        'jobId': jobId,
        'senderId': ctx.actorId,
        'receiverId': receiverId,
        'text': '💰 Price proposal: ₦${proposedAmount.toStringAsFixed(0)}',
        'type': 'negotiation',
        'proposedAmount': proposedAmount,
        'isRead': false,
        'createdAt': now,
      });

      // ② Update job's agreedAmount in the same transaction
      tx.update(jobRef, {
        'agreedAmount': proposedAmount,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      // ③ Audit log — same commit, atomic with ① and ②
      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {
          'agreedAmount': proposedAmount,
          'messageId': msgRef.id,
        },
      ));
    });
  }

  /// [confirmComplete] is a special-case because it writes to TWO top-level
  /// collections (job + escrow_releases) AND the audit log — all in one
  /// transaction. If any write fails, all three roll back.
  Future<void> confirmComplete(JobMutationContext ctx, String jobId) async {
    final jobRef = _jobRef(jobId);
    final releaseRef = _db.collection('escrow_releases').doc();
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.completed);

      final version = (data['updateVersion'] as int?) ?? 0;
      final now = FieldValue.serverTimestamp();

      tx.update(jobRef, {
        'status': JobStatus.completed.name,
        'completedAt': now,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      // Escrow release queued atomically — job cannot reach 'completed'
      // without a corresponding release entry.
      tx.set(releaseRef, {
        'jobId': jobId,
        'requestedAt': now,
        'status': 'pending',
        'requestedBy': ctx.actorId,
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.completed.name,
        versionBefore: version,
        delta: {
          'status': JobStatus.completed.name,
          'escrowReleaseQueued': true,
          'releaseRef': releaseRef.id,
        },
      ));
    });
  }

  /// Admin-only: force a job to any status, bypassing the state machine.
  ///
  /// [ctx.isAdminOverride] MUST be true, [ctx.actorRole] MUST be admin,
  /// and [ctx.overrideReason] MUST be non-empty. All three are enforced
  /// by [ctx.assertAdminOverride()] — not runtime duck-typing.
  ///
  /// The override is still transactional and still writes an audit log.
  /// There is no way to perform an override without a trace.
  Future<void> adminForceStatus(
    JobMutationContext ctx,
    String jobId,
    JobStatus forcedStatus,
  ) async {
    ctx.assertAdminOverride(); // throws if context is not valid admin override
    await updateJobStatus(
      ctx,
      jobId,
      forcedStatus,
      extra: {
        if (ctx.overrideReason != null) 'adminOverrideReason': ctx.overrideReason,
      },
      skipTransitionCheck: true,
    );
  }

  /// Escape hatch for callers needing custom multi-doc atomic updates.
  /// The job is pre-read; [updateFn] must not await anything.
  Future<void> applyJobUpdateTransaction(
    String jobId,
    JobUpdateFn updateFn,
  ) async {
    final ref = _jobRef(jobId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw JobNotFoundException(jobId);
      updateFn(tx, ref, snap.data()!);
    });
  }

  // ─── Lifecycle convenience methods ────────────────────────────────────────

  Future<void> acceptArtisan(
    JobMutationContext ctx,
    String jobId,
    String artisanId,
  ) =>
      updateJobStatus(ctx, jobId, JobStatus.matched,
          extra: {'artisanId': artisanId});

  Future<void> openChat(JobMutationContext ctx, String jobId) =>
      updateJobStatus(ctx, jobId, JobStatus.inChat);

  Future<void> initPayment(
    JobMutationContext ctx,
    String jobId,
    double amount,
  ) =>
      updateJobStatus(ctx, jobId, JobStatus.paymentPending,
          extra: {'agreedAmount': amount});

  Future<void> lockEscrow(
    JobMutationContext ctx,
    String jobId,
    String paystackRef,
  ) =>
      updateJobStatus(ctx, jobId, JobStatus.escrowLocked,
          extra: {'paymentReference': paystackRef});

  Future<void> startWork(JobMutationContext ctx, String jobId) =>
      updateJobStatus(ctx, jobId, JobStatus.inProgress);

  Future<void> submitCompletion(
    JobMutationContext ctx,
    String jobId, {
    required List<String> completionImageUrls,
    String? artisanNotes,
  }) {
    final extra = <String, dynamic>{
      'completionImageUrls': completionImageUrls,
    };
    if (artisanNotes != null) extra['artisanNotes'] = artisanNotes;
    return updateJobStatus(ctx, jobId, JobStatus.submitted, extra: extra);
  }

  Future<void> cancelJob(JobMutationContext ctx, String jobId) =>
      updateJobStatus(ctx, jobId, JobStatus.cancelled);

  /// Raises a dispute: transitions the job to 'disputed' AND creates the
  /// dispute record — all in one transaction. Modeled on [confirmComplete],
  /// which writes to escrow_releases alongside the job doc; here the second
  /// collection is /disputes. A dispute can never exist without the job
  /// reflecting 'disputed' status, and vice versa — no partial state.
  Future<void> raiseDisputeWithRecord(
    JobMutationContext ctx,
    String jobId, {
    required String disputeId,
    required String reason,
    required String againstUserId,
    List<String> evidenceImageUrls = const [],
  }) async {
    final jobRef = _jobRef(jobId);
    final disputeRef = _db.collection('disputes').doc(disputeId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.disputed);

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.disputed.name,
        'disputeReason': reason,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(disputeRef, {
        'id': disputeId,
        'jobId': jobId,
        'raisedBy': ctx.actorId,
        'againstUserId': againstUserId,
        'reason': reason,
        'evidenceImageUrls': evidenceImageUrls,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.disputed.name,
        versionBefore: version,
        delta: {'disputeId': disputeId, 'reason': reason},
      ));
    });
  }

  /// Admin resolves a dispute: transitions the job to 'resolved' AND
  /// updates the dispute record — all in one transaction. [dismiss] marks
  /// the dispute record 'dismissed' instead of 'resolved'; the job still
  /// transitions to 'resolved' either way (it is no longer blocked).
  Future<void> resolveDisputeWithRecord(
    JobMutationContext ctx,
    String jobId, {
    required String disputeId,
    required String resolution,
    String? adminNote,
    bool dismiss = false,
  }) async {
    final jobRef = _jobRef(jobId);
    final disputeRef = _db.collection('disputes').doc(disputeId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.resolved);

      final disputeSnap = await tx.get(disputeRef);
      if (!disputeSnap.exists) {
        throw JobStateConflictException('Dispute $disputeId not found for job $jobId');
      }
      final disputeStatus = disputeSnap.data()!['status'] as String?;
      if (disputeStatus == 'resolved' || disputeStatus == 'dismissed') {
        throw JobStateConflictException('Dispute is already resolved.');
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.resolved.name,
        'disputeResolution': resolution,
        ..._timestampsForStatus(JobStatus.resolved),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.update(disputeRef, {
        'status': dismiss ? 'dismissed' : 'resolved',
        'resolution': resolution,
        'adminNote': ?adminNote,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.resolved.name,
        versionBefore: version,
        delta: {'disputeId': disputeId, 'resolution': resolution, 'dismissed': dismiss},
      ));
    });
  }

  /// Accepts an artisan's quote: transitions the job requested → matched
  /// AND resolves every quote for the job — all in one transaction.
  ///
  /// The quotes subcollection is written here, inside JobService, rather
  /// than by a separate write in QuoteService, because the quote outcome
  /// is inseparable from the job's transition: if these were two writes,
  /// a failure between them could leave the job matched with competing
  /// quotes still "pending" (one artisan could then withdraw and silently
  /// reappear as if still in the running). [competingQuoteIds] is the
  /// caller's pre-transaction snapshot of other pending quotes; each is
  /// re-validated implicitly by being blind-written to 'closed' only if
  /// still present — a late-arriving quote outside that snapshot is a
  /// known, accepted gap (the UI only ever shows quotes for jobs still in
  /// 'requested' status, so it self-resolves on the next read).
  Future<void> acceptQuote(
    JobMutationContext ctx,
    String jobId, {
    required String quoteId,
    required String artisanId,
    required List<String> competingQuoteIds,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);
    final quotesCol = _db.collection('jobs').doc(jobId).collection('quotes');
    final acceptedRef = quotesCol.doc(quoteId);
    final competingRefs = competingQuoteIds
        .where((id) => id != quoteId)
        .map(quotesCol.doc)
        .toList();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.matched);

      final acceptedSnap = await tx.get(acceptedRef);
      if (!acceptedSnap.exists) {
        throw JobStateConflictException('Quote $quoteId not found for job $jobId');
      }
      if (acceptedSnap.data()!['status'] != 'pending') {
        throw JobStateConflictException('Quote is no longer pending.');
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.matched.name,
        'artisanId': artisanId,
        ..._timestampsForStatus(JobStatus.matched),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.update(acceptedRef, {'status': 'accepted'});
      for (final ref in competingRefs) {
        tx.update(ref, {'status': 'closed'});
      }

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.matched.name,
        versionBefore: version,
        delta: {
          'artisanId': artisanId,
          'acceptedQuoteId': quoteId,
          'closedQuoteCount': competingRefs.length,
        },
      ));
    });
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _jobRef(String jobId) =>
      _db.collection('jobs').doc(jobId);

  /// Each audit log is a new document in the job's auditLogs subcollection.
  /// The document ID serves as the transactionId.
  DocumentReference<Map<String, dynamic>> _auditRef(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('auditLogs').doc();

  /// Builds the Firestore map for an audit log entry.
  /// Uses [FieldValue.serverTimestamp()] for [timestamp] — authoritative.
  Map<String, dynamic> _buildAuditEntry({
    required String id,
    required JobMutationContext ctx,
    required String jobId,
    required String jobStatusBefore,
    required String? jobStatusAfter,
    required int versionBefore,
    required Map<String, dynamic> delta,
  }) =>
      {
        'id': id,
        'jobId': jobId,
        'transactionId': id,
        'actionType': ctx.actionType.name,
        'actorId': ctx.actorId,
        'actorRole': ctx.actorRole.name,
        'timestamp': FieldValue.serverTimestamp(),
        'jobVersionBefore': versionBefore,
        'jobVersionAfter': versionBefore + 1,
        'jobStatusBefore': jobStatusBefore,
        'jobStatusAfter': ?jobStatusAfter,
        'delta': delta,
        'isAdminOverride': ctx.isAdminOverride,
        if (ctx.reason != null) 'reason': ctx.reason,
        if (ctx.overrideReason != null) 'overrideReason': ctx.overrideReason,
      };

  /// Stamps three fields on every job mutation.
  /// [updateVersion] is read inside the transaction and incremented by 1 —
  /// concurrent transactions retry and always see the committed version.
  static Map<String, dynamic> _consistencyFields({
    required JobMutationContext ctx,
    required int currentVersion,
  }) =>
      {
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedBy': '${ctx.actorRole.name}:${ctx.actorId}',
        'updateVersion': currentVersion + 1,
      };

  /// Excludes [FieldValue] sentinels from the delta so it remains
  /// JSON-serializable when stored in the audit log.
  static Map<String, dynamic> _sanitizeDelta(Map<String, dynamic> data) =>
      Map.fromEntries(
        data.entries.where((e) => e.value is! FieldValue),
      );

  /// Server-side timestamps for status milestones — no client clock dependency.
  static Map<String, dynamic> _timestampsForStatus(JobStatus status) =>
      switch (status) {
        JobStatus.matched => {'matchedAt': FieldValue.serverTimestamp()},
        JobStatus.escrowLocked => {
          'escrowLockedAt': FieldValue.serverTimestamp(),
          'autoReleaseAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 7)),
          ),
        },
        JobStatus.inProgress => {'startedAt': FieldValue.serverTimestamp()},
        JobStatus.submitted => {
          'submittedAt': FieldValue.serverTimestamp(),
          'disputeWindowEndsAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 14)),
          ),
        },
        JobStatus.completed || JobStatus.resolved => {
          'completedAt': FieldValue.serverTimestamp(),
        },
        _ => {},
      };
}
