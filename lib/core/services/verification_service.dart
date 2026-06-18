import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'notification_service.dart';

/// Single write layer for the artisan identity verification pipeline.
///
/// Mirrors [JobService]'s invariants for this narrower domain: every state
/// change is transactional and stamps who/when/why. `verifications/{uid}`
/// is the authoritative review record; `artisans/{uid}.verificationStatus`
/// is a derived, coarser field kept in sync for badge/discoverability checks
/// (and is the field Firestore rules and [MatchingService] gate on).
class VerificationService {
  final FirebaseFirestore _db;
  final NotificationService _notifications;

  VerificationService(this._db) : _notifications = NotificationService(_db);

  DocumentReference<Map<String, dynamic>> _verificationRef(String uid) =>
      _db.collection('verifications').doc(uid);

  /// Artisan submits (or resubmits after rejection) selfie + government ID.
  Future<void> submit({
    required String uid,
    required String selfieUrl,
    required String governmentIdUrl,
  }) async {
    final ref = _verificationRef(uid);
    final artisanRef = _db.collection('artisans').doc(uid);
    final userRef = _db.collection('users').doc(uid);

    debugPrint('[VerificationService] firestore write started for $uid');

    final batch = _db.batch();
    batch.set(ref, {
      'uid': uid,
      'selfieUrl': selfieUrl,
      'governmentIdUrl': governmentIdUrl,
      'submittedAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewerId': null,
      'rejectionReason': null,
      'status': 'pending',
    });
    // set(merge:true) instead of update() — update() throws if the target
    // doc doesn't exist yet, which would fail the WHOLE batch atomically
    // (a batch is all-or-nothing) even though the verification doc itself
    // was perfectly valid. merge-set is a no-op-equivalent to update() when
    // the doc already exists, and degrades gracefully (creates it with just
    // this field) instead of throwing when it doesn't.
    batch.set(artisanRef, {'verificationStatus': 'id_submitted'}, SetOptions(merge: true));
    batch.set(userRef, {'verificationStatus': 'id_submitted'}, SetOptions(merge: true));
    await batch.commit();

    debugPrint('[VerificationService] firestore write completed for $uid');
  }

  /// Admin approves — verification record + artisan's coarse status move
  /// together, atomically, and a notification is queued for the artisan.
  Future<void> approve({
    required String uid,
    required String reviewerId,
  }) async {
    final ref = _verificationRef(uid);
    final artisanRef = _db.collection('artisans').doc(uid);
    final userRef = _db.collection('users').doc(uid);
    final notifRef = _notifications.newRef();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('No verification submission found for $uid');
      }

      tx.update(ref, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewerId': reviewerId,
        'rejectionReason': null,
      });
      tx.update(artisanRef, {'verificationStatus': 'id_verified'});
      tx.update(userRef, {'verificationStatus': 'id_verified'});
      tx.set(notifRef, _notifications.payload(
        id: notifRef.id,
        userId: uid,
        type: 'verification_approved',
        title: 'Identity Verified',
        body: 'Your identity has been verified. You now appear with the Verified badge.',
      ));
    });
  }

  /// Admin rejects (or requests resubmission — same mechanism, [reason]
  /// communicates what to fix). Reverting verificationStatus to 'unverified'
  /// allows the artisan to resubmit; Firestore rules only allow the artisan
  /// to update their own `verifications/{uid}` doc while status == 'rejected'.
  Future<void> reject({
    required String uid,
    required String reviewerId,
    required String reason,
  }) async {
    final ref = _verificationRef(uid);
    final artisanRef = _db.collection('artisans').doc(uid);
    final userRef = _db.collection('users').doc(uid);
    final notifRef = _notifications.newRef();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('No verification submission found for $uid');
      }

      tx.update(ref, {
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewerId': reviewerId,
        'rejectionReason': reason,
      });
      tx.update(artisanRef, {'verificationStatus': 'unverified'});
      tx.update(userRef, {'verificationStatus': 'unverified'});
      tx.set(notifRef, _notifications.payload(
        id: notifRef.id,
        userId: uid,
        type: 'verification_rejected',
        title: 'Verification Needs Attention',
        body: reason,
      ));
    });
  }
}
