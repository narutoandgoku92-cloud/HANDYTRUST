import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notification_model.dart';
import '../utils/safe_firestore.dart';

/// Single write layer for `notifications/{autoId}`.
///
/// Previously DisputeService, QuoteService, and VerificationService each
/// wrote this collection independently (3 duplicate inline writers with an
/// identical field shape). This service consolidates that into one place;
/// the other services now call [send] (or [payload] + [newRef] when the
/// write must happen inside one of their own transactions) instead of
/// constructing the map themselves.
class NotificationService {
  final FirebaseFirestore _db;

  NotificationService(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('notifications');

  /// Pre-allocates a notification doc ref — used when the write must happen
  /// inside a caller's own `runTransaction` (e.g. VerificationService).
  DocumentReference<Map<String, dynamic>> newRef() => _col.doc();

  /// Builds the canonical notification payload. Pass the id from [newRef].
  Map<String, dynamic> payload({
    required String id,
    required String userId,
    required String type,
    required String title,
    required String body,
    String? jobId,
  }) =>
      {
        'id': id,
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'jobId': ?jobId,
      };

  /// Writes a notification directly (outside any transaction).
  Future<void> send({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? jobId,
  }) async {
    final ref = newRef();
    await ref.set(payload(
      id: ref.id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      jobId: jobId,
    ));
  }

  Future<void> markRead(String notificationId) => _col.doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });

  Future<void> markAllRead(String userId) async {
    final unread = await _col
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  /// All notifications for a user, newest first. Sorted client-side (not
  /// via orderBy) to avoid requiring a composite index, matching the
  /// precedent set in DisputeService.watchOpenDisputes.
  Stream<List<NotificationModel>> watchForUser(String userId) => safeStream(
        _col.where('userId', isEqualTo: userId).limit(100),
        (d) => NotificationModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'notifications:$userId',
      ).map((notifications) => notifications..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Stream<int> watchUnreadCount(String userId) => _col
      .where('userId', isEqualTo: userId)
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);
}
