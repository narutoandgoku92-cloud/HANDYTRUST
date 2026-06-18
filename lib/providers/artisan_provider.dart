import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/safe_firestore.dart';
import '../models/artisan_model.dart';

/// Live stream of a single artisan's profile — reactive to approval/rating changes.
final artisanProfileProvider =
    StreamProvider.family<ArtisanModel?, String>((ref, uid) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('artisans').doc(uid),
    ArtisanModel.fromJson,
    debugLabel: 'artisanProfile:$uid',
  );
});

/// Artisan reviews summary — count + average.
/// Uses the stored rating/totalRatings on the artisan doc (maintained by
/// the atomic transaction in ReviewScreen and Cloud Functions in production)
/// instead of fetching all review docs.
final artisanReviewsProvider =
    StreamProvider.family<({int count, double avg}), String>((ref, artisanId) {
  return FirebaseFirestore.instance
      .collection('artisans')
      .doc(artisanId)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return (count: 0, avg: 0.0);
    final data = snap.data()!;
    final count = (data['totalRatings'] as num?)?.toInt() ?? 0;
    final avg = (data['rating'] as num?)?.toDouble() ?? 0.0;
    return (count: count, avg: avg);
  }).transform(
    StreamTransformer<({int count, double avg}), ({int count, double avg})>.fromHandlers(
      handleError: (Object e, StackTrace st, sink) {
        debugPrint('[artisanReviewsProvider:$artisanId] stream error swallowed: $e');
        sink.add((count: 0, avg: 0.0));
      },
    ),
  );
});
