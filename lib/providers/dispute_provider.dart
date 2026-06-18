import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/dispute_service.dart';
import '../models/dispute_model.dart';
import 'job_service_provider.dart';

final disputeServiceProvider = Provider<DisputeService>(
  (ref) => DisputeService(FirebaseFirestore.instance, ref.watch(jobServiceProvider)),
);

/// The dispute record for a job — drives the Dispute Thread section on
/// JobDetailScreen once a job reaches 'disputed' or 'resolved'.
final disputeForJobProvider = StreamProvider.family<DisputeModel?, String>(
  (ref, jobId) => ref.watch(disputeServiceProvider).watchDisputeForJob(jobId),
);

/// All open/under-review disputes — drives the admin Disputes tab.
final openDisputesProvider = StreamProvider<List<DisputeModel>>(
  (ref) => ref.watch(disputeServiceProvider).watchOpenDisputes(),
);
