import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/verification_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/verification_model.dart';

final verificationServiceProvider = Provider<VerificationService>(
  (ref) => VerificationService(FirebaseFirestore.instance),
);

/// Live verification record for one artisan. Null = not yet submitted.
final verificationStatusProvider =
    StreamProvider.family<VerificationModel?, String>((ref, uid) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('verifications').doc(uid),
    VerificationModel.fromJson,
    debugLabel: 'verificationStatus:$uid',
  );
});

/// Admin Verification Center — all submissions awaiting review, oldest first.
/// where(status) + orderBy(submittedAt) on different fields needs a
/// composite index — sort client-side instead, same pattern as the rest of
/// the admin dashboard's list providers.
final pendingVerificationsProvider =
    StreamProvider<List<VerificationModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance.collection('verifications').where('status', isEqualTo: 'pending'),
    (d) => VerificationModel.fromJson(d.data()),
    debugLabel: 'pendingVerifications',
  ).map((list) => list..sort((a, b) => (a.submittedAt ?? DateTime(0)).compareTo(b.submittedAt ?? DateTime(0))));
});
