import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/job_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/audit_log_model.dart';
import '../models/job_model.dart';
import '../models/job_mutation_context.dart';
import '../models/payment_model.dart';
import 'auth_provider.dart';
import 'job_service_provider.dart';

// ─── Job streams (read-only — not part of the write layer) ──────────────────

/// Real-time stream of a single job document. Drives all status-aware UI.
final jobStreamProvider = StreamProvider.family<JobModel?, String>((ref, jobId) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('jobs').doc(jobId),
    JobModel.fromJson,
    debugLabel: 'job:$jobId',
  );
});

/// All jobs for a customer — sorted newest-first on the client to avoid a
/// composite Firestore index on (customerId, createdAt).
final customerJobsProvider =
    StreamProvider.family<List<JobModel>, String>((ref, customerId) {
  return safeStream(
    FirebaseFirestore.instance.collection('jobs').where('customerId', isEqualTo: customerId),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'customerJobs:$customerId',
  ).map((jobs) => jobs..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// All jobs for an artisan — sorted newest-first on the client.
final artisanJobsProvider =
    StreamProvider.family<List<JobModel>, String>((ref, artisanId) {
  return safeStream(
    FirebaseFirestore.instance.collection('jobs').where('artisanId', isEqualTo: artisanId),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'artisanJobs:$artisanId',
  ).map((jobs) => jobs..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// Payment record for a job — used by the payment screen.
final jobPaymentProvider =
    FutureProvider.family<PaymentModel?, String>((ref, jobId) async {
  final snap = await FirebaseFirestore.instance
      .collection('payments')
      .where('jobId', isEqualTo: jobId)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  final d = snap.docs.first;
  return PaymentModel.fromJson({...d.data(), 'id': d.id});
});

// ─── Write notifier ──────────────────────────────────────────────────────────

/// All job lifecycle mutations go through [JobService] — no direct Firestore
/// writes are made here. Every method is atomic via runTransaction and writes
/// an audit log entry in the same commit.
class EscrowNotifier extends StateNotifier<AsyncValue<void>> {
  final JobService _job;
  final String _uid;

  EscrowNotifier(this._job, this._uid) : super(const AsyncData(null));

  // ─── Role assignments per action ─────────────────────────────────────────
  // Role is determined by the action: customers book/accept/pay/confirm;
  // artisans start/submit. Ambiguous actions (cancel/dispute) require the
  // caller to pass the role explicitly.

  JobMutationContext _customerCtx(JobActionType action, {String? reason}) =>
      JobMutationContext.customer(uid: _uid, actionType: action, reason: reason);

  JobMutationContext _artisanCtx(JobActionType action, {String? reason}) =>
      JobMutationContext.artisan(uid: _uid, actionType: action, reason: reason);

  JobMutationContext _ctxFor(ActorRole role, JobActionType action, {String? reason}) =>
      JobMutationContext(
        actorId: _uid,
        actorRole: role,
        actionType: action,
        reason: reason,
      );

  // ─── Customer actions ─────────────────────────────────────────────────────

  Future<void> acceptArtisan(String jobId, String artisanId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.acceptArtisan(
          _customerCtx(JobActionType.statusTransition),
          jobId,
          artisanId,
        ));
  }

  Future<void> openChat(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.openChat(_customerCtx(JobActionType.statusTransition), jobId));
  }

  Future<void> initPayment(String jobId, double amount) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.initPayment(_customerCtx(JobActionType.statusTransition), jobId, amount));
  }

  Future<void> lockEscrow(String jobId, String ref) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.lockEscrow(_customerCtx(JobActionType.escrowLocked), jobId, ref));
  }

  Future<void> confirmComplete(String jobId) async {
    state = const AsyncLoading();
    // Both the job→completed update and the escrow_releases entry are written
    // in a single Firestore transaction. Partial completion is impossible.
    state = await AsyncValue.guard(
        () => _job.confirmComplete(_customerCtx(JobActionType.jobCompleted), jobId));
  }

  // ─── Artisan actions ──────────────────────────────────────────────────────

  Future<void> startWork(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.startWork(_artisanCtx(JobActionType.workStarted), jobId));
  }

  Future<void> submitCompletion(
    String jobId, {
    required List<String> imageUrls,
    String? notes,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.submitCompletion(
          _artisanCtx(JobActionType.workSubmitted),
          jobId,
          completionImageUrls: imageUrls,
          artisanNotes: notes,
        ));
  }

  // ─── Either-party actions (role passed by caller) ─────────────────────────
  // Note: raising/resolving a dispute is NOT exposed here — those mutate
  // both /jobs and /disputes atomically and live in DisputeService, which
  // delegates the job half of the write to JobService.raiseDisputeWithRecord
  // / resolveDisputeWithRecord (see dispute_service.dart).

  Future<void> cancelJob(String jobId, {required ActorRole callerRole}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.cancelJob(
          _ctxFor(callerRole, JobActionType.jobCancelled),
          jobId,
        ));
  }
}

final escrowNotifierProvider =
    StateNotifierProvider<EscrowNotifier, AsyncValue<void>>((ref) {
  final uid = ref.watch(authStateChangesProvider).asData?.value?.uid ?? 'unknown';
  return EscrowNotifier(ref.watch(jobServiceProvider), uid);
});
