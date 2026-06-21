import 'package:cloud_firestore/cloud_firestore.dart';

/// Identity verification record — one document per artisan at
/// `verifications/{uid}`. This is the authoritative source of truth for
/// review state; [status] is intentionally a narrower vocabulary than
/// [ArtisanModel.verificationStatus] (which also tracks pre-submission and
/// post-approval trust tiers for badge display).
enum VerificationStatus { pending, approved, rejected, pendingLater }

VerificationStatus _statusFromString(String? v) => switch (v) {
      'approved' => VerificationStatus.approved,
      'rejected' => VerificationStatus.rejected,
      'pending_later' => VerificationStatus.pendingLater,
      _ => VerificationStatus.pending,
    };

extension VerificationStatusJson on VerificationStatus {
  String toJsonValue() => switch (this) {
        VerificationStatus.approved => 'approved',
        VerificationStatus.rejected => 'rejected',
        VerificationStatus.pendingLater => 'pending_later',
        VerificationStatus.pending => 'pending',
      };
}

class VerificationModel {
  final String uid;
  final String selfieUrl;
  final String governmentIdUrl;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewerId;
  final String? rejectionReason;
  final VerificationStatus status;

  const VerificationModel({
    required this.uid,
    required this.selfieUrl,
    required this.governmentIdUrl,
    this.submittedAt,
    this.reviewedAt,
    this.reviewerId,
    this.rejectionReason,
    this.status = VerificationStatus.pending,
  });

  factory VerificationModel.fromJson(Map<String, dynamic> json) =>
      VerificationModel(
        uid: json['uid'] as String,
        selfieUrl: json['selfieUrl'] as String? ?? '',
        governmentIdUrl: json['governmentIdUrl'] as String? ?? '',
        submittedAt: (json['submittedAt'] as Timestamp?)?.toDate(),
        reviewedAt: (json['reviewedAt'] as Timestamp?)?.toDate(),
        reviewerId: json['reviewerId'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        status: _statusFromString(json['status'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'selfieUrl': selfieUrl,
        'governmentIdUrl': governmentIdUrl,
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
        if (reviewerId != null) 'reviewerId': reviewerId,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'status': status.toJsonValue(),
      };
}
