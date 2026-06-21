import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/storage_service.dart';
import '../core/services/firestore_service.dart';
import '../firebase/firestore/firestore_repository.dart';
import '../models/job_model.dart';

class JobRequestState {
  final bool isSubmitting;
  final String? error;
  final String? createdJobId;
  /// Number of attached photos that failed to upload — the job is still
  /// created successfully with whichever photos made it through, but this
  /// must be surfaced to the customer rather than silently dropped.
  final int failedImageCount;

  const JobRequestState({
    this.isSubmitting = false,
    this.error,
    this.createdJobId,
    this.failedImageCount = 0,
  });

  bool get success => createdJobId != null;

  JobRequestState copyWith({
    bool? isSubmitting,
    String? error,
    String? createdJobId,
    int? failedImageCount,
  }) =>
      JobRequestState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: error,
        createdJobId: createdJobId ?? this.createdJobId,
        failedImageCount: failedImageCount ?? this.failedImageCount,
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
      debugPrint('[JobRequest] submission started: jobId=$jobId, images=${images.length}');

      // Pass userId so Storage path matches rules: jobs/{jobId}/{userId}/...
      // Each upload is caught individually — Future.wait would otherwise
      // abort the WHOLE submission (and lose every successfully-uploaded
      // photo too) if even one of several images failed transiently. The
      // job is still created with whichever photos made it through; the
      // customer doesn't lose their work over one flaky upload, but the
      // failure is logged and counted (not silently dropped).
      debugPrint('[JobRequest] image upload started: jobId=$jobId');
      final uploadResults = await Future.wait(
        images.asMap().entries.map((e) async {
          try {
            return await _storageService.uploadJobImageBytes(
              jobId: jobId,
              userId: customerId,
              index: e.key,
              bytes: e.value,
            );
          } catch (err) {
            debugPrint('[JobRequest] image ${e.key} upload failed for jobId=$jobId: $err');
            return null;
          }
        }),
      );
      final urls = uploadResults.whereType<String>().toList();
      final failedCount = uploadResults.length - urls.length;
      debugPrint('[JobRequest] image upload completed: jobId=$jobId, '
          'succeeded=${urls.length}, failed=$failedCount');

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

      debugPrint('[JobRequest] firestore write started: jobId=$jobId');
      await _repository.createJob(job);
      debugPrint('[JobRequest] firestore write completed: jobId=$jobId');
      state = JobRequestState(createdJobId: jobId, failedImageCount: failedCount);
    } catch (e) {
      debugPrint('[JobRequest] submission failed: $e');
      state = JobRequestState(
        error: 'Could not submit your job request. Check your connection and try again.',
      );
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
