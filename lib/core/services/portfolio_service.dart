import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'storage_service.dart';

/// Single write layer for artisan portfolio data (`artisans.portfolioImageUrls`)
/// and portfolio view analytics (`portfolio_analytics/{artisanId}`).
/// Mirrors the precedent set by QuoteService/DisputeService: a dedicated
/// service owns writes to its own collection scope, while JobService remains
/// the sole writer for `/jobs`.
class PortfolioService {
  final FirebaseFirestore _db;
  final StorageService _storage;

  PortfolioService(this._db, this._storage);

  static const int maxImages = 10;

  DocumentReference<Map<String, dynamic>> _artisanRef(String artisanId) =>
      _db.collection('artisans').doc(artisanId);

  Future<void> addImage({
    required String artisanId,
    required Uint8List bytes,
  }) async {
    final snapshot = await _artisanRef(artisanId).get();
    final current =
        List<String>.from(snapshot.data()?['portfolioImageUrls'] ?? []);
    if (current.length >= maxImages) {
      throw Exception('Portfolio is limited to $maxImages photos.');
    }
    final url = await _storage.uploadPortfolioImage(
      artisanId: artisanId,
      index: DateTime.now().millisecondsSinceEpoch,
      bytes: bytes,
    );
    await _artisanRef(artisanId).update({
      'portfolioImageUrls': FieldValue.arrayUnion([url]),
    });
  }

  Future<void> removeImage({
    required String artisanId,
    required String url,
  }) async {
    await _artisanRef(artisanId).update({
      'portfolioImageUrls': FieldValue.arrayRemove([url]),
    });
    try {
      await _storage.deletePortfolioImage(url);
    } catch (_) {
      // Storage object may already be gone — Firestore is the source of truth.
    }
  }

  Future<void> reorder({
    required String artisanId,
    required List<String> orderedUrls,
  }) =>
      _artisanRef(artisanId).update({'portfolioImageUrls': orderedUrls});

  Future<void> recordView(String artisanId) =>
      _db.collection('portfolio_analytics').doc(artisanId).set({
        'viewCount': FieldValue.increment(1),
        'lastViewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<int> watchViewCount(String artisanId) => _db
      .collection('portfolio_analytics')
      .doc(artisanId)
      .snapshots()
      .map((doc) => (doc.data()?['viewCount'] as num?)?.toInt() ?? 0);
}
