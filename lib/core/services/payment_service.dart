import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/audit_log_model.dart';
import '../../models/job_mutation_context.dart';
import '../../models/payment_model.dart';
import 'job_service.dart';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final JobService _job = JobService(_firestore);

  /// Simulates a Paystack payment and locks escrow on the job.
  /// In production the Paystack webhook calls a Cloud Function that does this;
  /// the escrow lock uses a system context because it originates from a webhook,
  /// not a direct user action.
  Future<PaymentModel> simulatePayment({
    required String jobId,
    required String payerId,
    required String artisanId,
    required double amount,
  }) async {
    final id = _firestore.collection('payments').doc().id;

    final payment = PaymentModel(
      id: id,
      jobId: jobId,
      payerId: payerId,
      artisanId: artisanId,
      amount: amount,
      status: PaymentStatus.escrowHeld,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('payments').doc(id).set(payment.toJson());

    await _job.lockEscrow(
      JobMutationContext.system(JobActionType.escrowLocked),
      jobId,
      'DEMO-$id',
    );

    return payment;
  }
}
