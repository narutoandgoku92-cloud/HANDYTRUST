import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/audit_log_model.dart';
import '../../models/job_model.dart';
import '../../models/job_mutation_context.dart';
import 'job_service.dart';

/// Demo-only simulated escrow payment service.
///
/// All job-document writes route through [JobService] — the status
/// transition (paymentPending → escrowLocked) is validated against the
/// state machine and produces an audit log entry, exactly like the real
/// Paystack path. Even the cosmetic display fields (escrow.status,
/// payment.*) go through JobService's transaction primitives, so there is
/// no write to /jobs anywhere in this file that bypasses the audit trail.
class DemoEscrowService {
  final FirebaseFirestore _db;
  late final JobService _job = JobService(_db);

  DemoEscrowService(this._db);

  static const _jobs = 'jobs';

  /// Full demo payment simulation:
  ///   Phase 1 → escrow.status = "processing"
  ///   Delay    → 2–4 seconds (simulates gateway round-trip)
  ///   Phase 2  → status → escrowLocked (validated + audited) with
  ///              escrow.status = "success" written in the same transaction
  Future<void> startDemoEscrowPayment(
    String jobId, {
    required String payerUid,
  }) async {
    final ref = _db.collection(_jobs).doc(jobId);

    final snap = await ref.get();
    if (!snap.exists) throw Exception('Job $jobId not found');

    // Guard: don't double-process
    final data = snap.data()!;
    final existing = (data['escrow'] as Map<String, dynamic>?)?['status'];
    if (existing == 'processing' || existing == 'success') return;

    // Phase 1: mark as processing — display-only flag, no status change.
    await _job.applyJobUpdateTransaction(jobId, (tx, jobRef, _) {
      tx.update(jobRef, {'escrow.status': 'processing'});
    });

    // Simulate payment gateway delay
    final delaySecs = 2 + Random().nextInt(3); // 2, 3, or 4 seconds
    await Future.delayed(Duration(seconds: delaySecs));

    // Phase 2: validated transition to escrowLocked. Display fields ride
    // along in the same transaction as the status write and the audit log.
    final reference = 'DEMO_${DateTime.now().millisecondsSinceEpoch}';
    await _job.updateJobStatus(
      JobMutationContext.customer(
        uid: payerUid,
        actionType: JobActionType.escrowLocked,
      ),
      jobId,
      JobStatus.escrowLocked,
      extra: {
        'paymentReference': reference,
        'escrow.status': 'success',
        'payment.method': 'demo_gateway',
        'payment.reference': reference,
        'payment.paidAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Real-time raw stream of the job document.
  /// Used by the demo payment screen to react to escrow sub-field changes.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchJobRaw(String jobId) =>
      _db.collection(_jobs).doc(jobId).snapshots();
}
