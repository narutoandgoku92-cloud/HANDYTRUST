import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/safe_firestore.dart';
import '../models/review_model.dart';

/// A single job's review, if one has been left. Review docs use the jobId
/// as their document ID (one review per job), so this is a single-doc read.
final jobReviewProvider =
    StreamProvider.family<ReviewModel?, String>((ref, jobId) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('reviews').doc(jobId),
    ReviewModel.fromJson,
    debugLabel: 'jobReview:$jobId',
  );
});

/// All reviews left for a given artisan, newest first. Sorted client-side
/// after a pure equality filter to avoid requiring a composite index.
final artisanReviewListProvider =
    StreamProvider.family<List<ReviewModel>, String>((ref, artisanId) {
  return safeStream(
    FirebaseFirestore.instance.collection('reviews').where('artisanId', isEqualTo: artisanId),
    (d) => ReviewModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'artisanReviews:$artisanId',
  ).map((reviews) => reviews..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// All reviews across the platform, newest first — drives admin moderation.
final allReviewsProvider = StreamProvider<List<ReviewModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance.collection('reviews'),
    (d) => ReviewModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'allReviews',
  ).map((reviews) => reviews..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});
