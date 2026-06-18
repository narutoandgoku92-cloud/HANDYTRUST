import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/artisan_model.dart';

/// Returns up to 5 ranked artisans for a job:
///   3 experienced (highest match score)
///   2 rising professionals (< 10 jobs, fairness layer)
/// Only returns artisans with approvalStatus == 'approved' AND a verified
/// identity (verificationStatus in id_verified/trusted) — unverified
/// artisans must not be publicly discoverable.
class MatchingService {
  final FirebaseFirestore _db;

  MatchingService(this._db);

  Future<List<ArtisanModel>> findMatches({
    required String category,
    double? customerLat,
    double? customerLng,
  }) async {
    final snap = await _db
        .collection('artisans')
        .where('category', isEqualTo: category)
        .where('isAvailable', isEqualTo: true)
        .where('approvalStatus', isEqualTo: 'approved')
        .where('verificationStatus', whereIn: ['id_verified', 'trusted'])
        .limit(100)
        .get();

    final all = snap.docs
        .map((d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}))
        .toList();

    return _rank(all, customerLat: customerLat, customerLng: customerLng);
  }

  List<ArtisanModel> _rank(
    List<ArtisanModel> artisans, {
    double? customerLat,
    double? customerLng,
  }) {
    final experienced = <ArtisanModel>[];
    final rising = <ArtisanModel>[];

    for (final a in artisans) {
      if (a.isRising) {
        rising.add(a);
      } else {
        experienced.add(a);
      }
    }

    experienced.sort((a, b) => _score(b, customerLat, customerLng)
        .compareTo(_score(a, customerLat, customerLng)));
    rising.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final result = <ArtisanModel>[
      ...experienced.take(3),
      ...rising.take(2),
    ];

    final seen = <String>{};
    return result.where((a) => seen.add(a.uid)).toList();
  }

  double _score(ArtisanModel a, double? lat, double? lng) {
    var score = a.matchScore;

    if (lat != null && lng != null && a.latitude != null && a.longitude != null) {
      final distKm = _haversineKm(lat, lng, a.latitude!, a.longitude!);
      final proximityBonus = (1.0 - (distKm / 50.0).clamp(0.0, 1.0)) * 0.10;
      score += proximityBonus;
    }

    return score.clamp(0.0, 1.1);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  double _rad(double deg) => deg * math.pi / 180;
}
