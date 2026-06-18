import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/firestore_service.dart';
import '../../models/job_model.dart';
import 'collections.dart';

class FirestoreRepository {
  FirestoreRepository(this._service);

  final FirestoreService _service;

  String generateJobId() {
    return _service.collection(Collections.jobs).doc().id;
  }

  Future<void> createJob(JobModel job) async {
    final ref = _service.collection(Collections.jobs).doc(job.id);
    await ref.set({
      ...job.toJson(),
      // Seed consistency fields so every doc has them from creation.
      // JobService.updateJobStatus will increment updateVersion on each mutation.
      'updateVersion': 0,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedBy': 'customer',
    });
  }

  Stream<List<JobModel>> watchCustomerJobs(String customerId) {
    return _service
        .collection(Collections.jobs)
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snapshot) {
          final jobs = snapshot.docs
              .map((doc) => JobModel.fromJson({...doc.data(), 'id': doc.id}))
              .toList();
          jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return jobs;
        });
  }
}
