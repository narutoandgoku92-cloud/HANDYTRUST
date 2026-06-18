import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'firestore_parsing.dart';

/// Single entry point for "a Firestore problem can never crash this app's
/// UI." Two distinct failure modes, two distinct layers:
///
///  - A document parses badly (missing/malformed field) → [safeDocParse] /
///    [safeQueryParse] skip just that document. These delegate to
///    firestore_parsing.dart, the existing implementation, rather than
///    duplicating the logic under a second name.
///
///  - The query/stream itself fails (missing composite index, a
///    permission-denied, the device going offline mid-listen) → that has
///    nothing to do with document content, and no amount of per-document
///    try/catch helps. [safeStream] / [safeDocStream] wrap .snapshots()
///    itself so a stream-level failure surfaces as an empty list / null
///    instead of an AsyncError, logging the real cause via debugPrint.
///
/// Tradeoff, stated plainly: with [safeStream], a genuine ongoing failure
/// (e.g. an admin's access was revoked mid-session, or a required index
/// really is still missing) looks identical in the UI to "there is
/// genuinely nothing here." That's a deliberate choice for this app's
/// list/admin screens, where a confusing raw Firestore error is worse than
/// an indistinguishable empty state — but it is a real tradeoff, not a free
/// lunch. The debugPrint calls are what keep the actual cause visible
/// during development (and to Crashlytics/console logs in production).

/// Parses one document, returning null instead of throwing if it's
/// malformed or missing.
T? safeDocParse<T>(
  DocumentSnapshot<Map<String, dynamic>> doc,
  T Function(Map<String, dynamic> json) fromJson,
) =>
    parseDocSafely(doc, fromJson);

/// Parses every document in a query snapshot, silently dropping any
/// individual document that fails to parse.
List<T> safeQueryParse<T>(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromJson,
) =>
    parseDocsSafely(snapshot.docs, fromJson);

/// Wraps a Firestore query stream so a stream-level failure never reaches
/// the UI as an AsyncError — it emits an empty list instead. Use this for
/// any StreamProvider backing a list screen (admin tabs, job feeds, etc.).
Stream<List<T>> safeStream<T>(
  Query<Map<String, dynamic>> query,
  T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromJson, {
  String? debugLabel,
}) {
  return query.snapshots().map((snap) => safeQueryParse(snap, fromJson)).transform(
        StreamTransformer<List<T>, List<T>>.fromHandlers(
          handleError: (Object error, StackTrace stackTrace, sink) {
            debugPrint(
              '[safeStream${debugLabel != null ? ":$debugLabel" : ""}] '
              'stream error swallowed, emitting empty list: $error\n$stackTrace',
            );
            sink.add(const []);
          },
        ),
      );
}

/// Same idea for a single-document stream (e.g. a live job or profile
/// doc) — emits null instead of propagating a stream-level error.
Stream<T?> safeDocStream<T>(
  DocumentReference<Map<String, dynamic>> docRef,
  T Function(Map<String, dynamic> json) fromJson, {
  String? debugLabel,
}) {
  return docRef.snapshots().map((doc) => safeDocParse(doc, fromJson)).transform(
        StreamTransformer<T?, T?>.fromHandlers(
          handleError: (Object error, StackTrace stackTrace, sink) {
            debugPrint(
              '[safeDocStream${debugLabel != null ? ":$debugLabel" : ""}] '
              'stream error swallowed, emitting null: $error\n$stackTrace',
            );
            sink.add(null);
          },
        ),
      );
}
