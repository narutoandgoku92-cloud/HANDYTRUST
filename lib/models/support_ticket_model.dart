import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer/artisan-submitted support ticket, reviewed by admins.
/// 'open' | 'resolved'
class SupportTicketModel {
  final String id;
  final String userId;
  final String userName;
  final String subject;
  final String message;
  final String status;
  final DateTime createdAt;
  final String? adminResponse;
  final DateTime? resolvedAt;

  const SupportTicketModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.subject,
    required this.message,
    this.status = 'open',
    required this.createdAt,
    this.adminResponse,
    this.resolvedAt,
  });

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    return SupportTicketModel(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? 'User',
      subject: json['subject'] as String? ?? '',
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      createdAt: _parseDate(json['createdAt']),
      adminResponse: json['adminResponse'] as String?,
      resolvedAt: json['resolvedAt'] != null ? _parseDate(json['resolvedAt']) : null,
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'subject': subject,
        'message': message,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        if (adminResponse != null) 'adminResponse': adminResponse,
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
      };
}
