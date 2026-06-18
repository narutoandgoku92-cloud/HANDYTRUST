import 'package:cloud_firestore/cloud_firestore.dart';

enum DisputeStatus { open, underReview, resolved, dismissed }

class DisputeModel {
  final String id;
  final String jobId;
  final String raisedBy;
  final String againstUserId;
  final String reason;
  final List<String> evidenceImageUrls;
  final DisputeStatus status;
  final String? adminNote;
  final String? resolution;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? artisanResponseText;
  final List<String> artisanEvidenceUrls;
  final DateTime? artisanRespondedAt;

  const DisputeModel({
    required this.id,
    required this.jobId,
    required this.raisedBy,
    required this.againstUserId,
    required this.reason,
    this.evidenceImageUrls = const [],
    this.status = DisputeStatus.open,
    this.adminNote,
    this.resolution,
    required this.createdAt,
    this.resolvedAt,
    this.artisanResponseText,
    this.artisanEvidenceUrls = const [],
    this.artisanRespondedAt,
  });

  factory DisputeModel.fromJson(Map<String, dynamic> json) {
    DateTime toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v as String? ?? '') ?? DateTime.now();
    }

    DateTime? toDateNullable(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v as String? ?? '');
    }

    return DisputeModel(
      id: json['id'] as String,
      jobId: json['jobId'] as String,
      raisedBy: json['raisedBy'] as String,
      againstUserId: json['againstUserId'] as String,
      reason: json['reason'] as String,
      evidenceImageUrls: List<String>.from(json['evidenceImageUrls'] ?? []),
      status: DisputeStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DisputeStatus.open,
      ),
      adminNote: json['adminNote'] as String?,
      resolution: json['resolution'] as String?,
      createdAt: toDate(json['createdAt']),
      resolvedAt: toDateNullable(json['resolvedAt']),
      artisanResponseText: json['artisanResponseText'] as String?,
      artisanEvidenceUrls: List<String>.from(json['artisanEvidenceUrls'] ?? []),
      artisanRespondedAt: toDateNullable(json['artisanRespondedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'raisedBy': raisedBy,
        'againstUserId': againstUserId,
        'reason': reason,
        'evidenceImageUrls': evidenceImageUrls,
        'status': status.name,
        if (adminNote != null) 'adminNote': adminNote,
        if (resolution != null) 'resolution': resolution,
        'createdAt': Timestamp.fromDate(createdAt),
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
        if (artisanResponseText != null) 'artisanResponseText': artisanResponseText,
        'artisanEvidenceUrls': artisanEvidenceUrls,
        if (artisanRespondedAt != null)
          'artisanRespondedAt': Timestamp.fromDate(artisanRespondedAt!),
      };
}
