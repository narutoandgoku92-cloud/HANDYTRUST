import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/portfolio_service.dart';
import '../core/services/storage_service.dart';

final portfolioServiceProvider = Provider<PortfolioService>(
  (ref) => PortfolioService(FirebaseFirestore.instance, StorageService()),
);

/// Live portfolio view count — drives the analytics readout in
/// PortfolioManagerScreen.
final portfolioViewCountProvider =
    StreamProvider.family<int, String>((ref, artisanId) {
  return ref.watch(portfolioServiceProvider).watchViewCount(artisanId);
});
