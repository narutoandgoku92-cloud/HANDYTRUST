import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Parses each Firestore doc with [fromJson], skipping any single document
/// that fails to parse instead of letting one malformed/incomplete doc
/// throw and abort the entire list — a bad doc elsewhere in a collection
/// should never hide every other valid one in admin lists, job feeds, etc.
List<T> parseDocsSafely<T>(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromJson,
) {
  final result = <T>[];
  for (final d in docs) {
    try {
      result.add(fromJson(d));
    } catch (e) {
      debugPrint('[parseDocsSafely] skipped malformed doc ${d.id}: $e');
    }
  }
  return result;
}

/// Same idea for a single-document read — returns null instead of throwing
/// if the doc exists but fails to parse.
T? parseDocSafely<T>(
  DocumentSnapshot<Map<String, dynamic>> doc,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (!doc.exists) return null;
  try {
    return fromJson({...doc.data()!, 'id': doc.id});
  } catch (e) {
    debugPrint('[parseDocSafely] skipped malformed doc ${doc.id}: $e');
    return null;
  }
}
