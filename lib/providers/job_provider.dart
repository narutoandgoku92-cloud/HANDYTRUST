import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/storage_service.dart';
import '../core/services/firestore_service.dart';
import '../firebase/firestore/firestore_repository.dart';
import '../models/job_model.dart';

class JobRequestState {
  final bool isSubmitting;
  final String? error;
  final String? createdJobId;

  const JobRequestState({
    this.isSubmitting = false,
    this.error,
    this.createdJobId,
  });

  bool get success => createdJobId != null;

  JobRequestState copyWith({
    bool? isSubmitting,
    String? error,
    String? createdJobId,
  }) =>
      JobRequestState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: error,
        createdJobId: createdJobId ?? this.createdJobId,
      );
}

class JobRequestNotifier extends StateNotifier<JobRequestState> {
  final FirestoreRepository _repository;
  final StorageService _storageService;

  JobRequestNotifier(this._repository, this._storageService)
      : super(const JobRequestState());

  Future<void> submitRequest({
    required String customerId,
    required String category,
    required String description,
    required List<Uint8List> images,
    double? customerLat,
    double? customerLng,
    String? customerAddress,
    double? budgetMin,
    double? budgetMax,
    String urgency = 'asap',
    DateTime? scheduledDate,
    Map<String, dynamic>? aiSuggestion,
  }) async {
    state = const JobRequestState(isSubmitting: true);

    try {
      final jobId = _repository.generateJobId();

      // Pass userId so Storage path matches rules: jobs/{jobId}/{userId}/...
      // Each upload is caught individually — Future.wait would otherwise
      // abort the WHOLE submission (and lose every successfully-uploaded
      // photo too) if even one of several images failed transiently. The
      // job is still created with whichever photos made it through; the
      // customer doesn't lose their work over one flaky upload.
      final uploadResults = await Future.wait(
        images.asMap().entries.map((e) async {
          try {
            return await _storageService.uploadJobImageBytes(
              jobId: jobId,
              userId: customerId,
              index: e.key,
              bytes: e.value,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      final urls = uploadResults.whereType<String>().toList();

      final job = JobModel(
        id: jobId,
        customerId: customerId,
        category: category,
        description: description,
        imageUrls: urls,
        status: JobStatus.requested,
        customerLat: customerLat,
        customerLng: customerLng,
        customerAddress: customerAddress,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        urgency: urgency,
        scheduledDate: scheduledDate,
        createdAt: DateTime.now(),
        aiSuggestion: aiSuggestion,
      );

      await _repository.createJob(job);
      state = JobRequestState(createdJobId: jobId);
    } catch (e) {
      state = JobRequestState(error: e.toString());
    }
  }
}

final jobRequestNotifierProvider =
    StateNotifierProvider<JobRequestNotifier, JobRequestState>(
  (ref) => JobRequestNotifier(
    FirestoreRepository(FirestoreService()),
    StorageService(),
  ),
);
