import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String jobId;
  final String customerId;
  final String artisanId;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const ReviewModel({
    required this.id,
    required this.jobId,
    required this.customerId,
    required this.artisanId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    final raw = json['createdAt'];
    final createdAt = raw is Timestamp
        ? raw.toDate()
        : DateTime.tryParse(raw as String? ?? '') ?? DateTime.now();

    return ReviewModel(
      id: json['id'] as String,
      jobId: json['jobId'] as String,
      customerId: json['customerId'] as String,
      artisanId: json['artisanId'] as String,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'customerId': customerId,
        'artisanId': artisanId,
        'rating': rating,
        'comment': comment,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
