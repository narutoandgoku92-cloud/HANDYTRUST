import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/matching_service.dart';
import '../models/artisan_model.dart';

final matchingServiceProvider = Provider<MatchingService>(
  (ref) => MatchingService(FirebaseFirestore.instance),
);

final matchingProvider = FutureProvider.family<List<ArtisanModel>, MatchingParams>(
  (ref, params) => ref.read(matchingServiceProvider).findMatches(
        category: params.category,
        customerLat: params.lat,
        customerLng: params.lng,
      ),
);

class MatchingParams {
  final String category;
  final double? lat;
  final double? lng;

  const MatchingParams({required this.category, this.lat, this.lng});

  @override
  bool operator ==(Object other) =>
      other is MatchingParams &&
      other.category == category &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(category, lat, lng);
}
