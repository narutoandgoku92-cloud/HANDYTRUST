import 'package:cloud_firestore/cloud_firestore.dart';

enum JobStatus {
  requested,
  matched,
  inChat,
  paymentPending,
  escrowLocked,
  inProgress,
  submitted,
  completed,
  disputed,
  resolved,
  cancelled;

  static JobStatus fromString(String s) {
    // "paid_escrow" is written by DemoEscrowService; map it to escrowLocked
    if (s == 'paid_escrow') return JobStatus.escrowLocked;
    return JobStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => JobStatus.requested,
    );
  }

  String get label => switch (this) {
        JobStatus.requested => 'Requested',
        JobStatus.matched => 'Matched',
        JobStatus.inChat => 'In Chat',
        JobStatus.paymentPending => 'Payment Pending',
        JobStatus.escrowLocked => 'Escrow Locked',
        JobStatus.inProgress => 'In Progress',
        JobStatus.submitted => 'Submitted',
        JobStatus.completed => 'Completed',
        JobStatus.disputed => 'Disputed',
        JobStatus.resolved => 'Resolved',
        JobStatus.cancelled => 'Cancelled',
      };

  bool get isTerminal =>
      this == JobStatus.completed ||
      this == JobStatus.resolved ||
      this == JobStatus.cancelled;

  bool get isActive =>
      this == JobStatus.escrowLocked || this == JobStatus.inProgress || this == JobStatus.submitted;
}

class JobModel {
  final String id;
  final String customerId;
  final String artisanId;
  final String category;
  final String description;
  final List<String> imageUrls;
  final List<String> completionImageUrls;
  final JobStatus status;
  final double? agreedAmount;
  final String? paymentReference;
  final String? disputeReason;
  final String? disputeResolution;
  final DateTime? disputeWindowEndsAt;
  final String? artisanNotes;
  final double? customerLat;
  final double? customerLng;
  final String? customerAddress;
  final double? budgetMin;
  final double? budgetMax;
  /// 'asap' | 'scheduled'
  final String urgency;
  final DateTime? scheduledDate;
  final DateTime createdAt;
  final DateTime? matchedAt;
  final DateTime? escrowLockedAt;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? completedAt;
  final DateTime? autoReleaseAt;

  /// Set only when the customer accepted the AI job-improvement suggestion
  /// at creation time: {category, confidence, enhancedDescription}.
  final Map<String, dynamic>? aiSuggestion;

  // ─── Consistency / audit fields (server-written by JobService) ───────────
  /// Firestore server timestamp of the last mutation — set by JobService only.
  final DateTime? lastUpdatedAt;
  /// Role or UID of the last writer: 'customer' | 'artisan' | 'system' | 'admin'
  final String? lastUpdatedBy;
  /// Monotonically incrementing counter. Incremented inside every transaction.
  /// Useful for debugging concurrent write issues.
  final int updateVersion;

  const JobModel({
    required this.id,
    required this.customerId,
    this.artisanId = '',
    required this.category,
    required this.description,
    this.imageUrls = const [],
    this.completionImageUrls = const [],
    this.status = JobStatus.requested,
    this.agreedAmount,
    this.paymentReference,
    this.disputeReason,
    this.disputeResolution,
    this.disputeWindowEndsAt,
    this.artisanNotes,
    this.customerLat,
    this.customerLng,
    this.customerAddress,
    this.budgetMin,
    this.budgetMax,
    this.urgency = 'asap',
    this.scheduledDate,
    required this.createdAt,
    this.matchedAt,
    this.escrowLockedAt,
    this.startedAt,
    this.submittedAt,
    this.completedAt,
    this.autoReleaseAt,
    this.aiSuggestion,
    this.lastUpdatedAt,
    this.lastUpdatedBy,
    this.updateVersion = 0,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        // customerId/category/description are required by Firestore rules
        // on every job this app creates, but defaulting them here means a
        // malformed/manually-edited doc degrades gracefully instead of
        // throwing and crashing the entire list it's read from.
        customerId: json['customerId'] as String? ?? '',
        artisanId: json['artisanId'] as String? ?? '',
        category: json['category'] as String? ?? 'Other',
        description: json['description'] as String? ?? '',
        imageUrls: List<String>.from(json['imageUrls'] ?? []),
        completionImageUrls: List<String>.from(json['completionImageUrls'] ?? []),
        status: JobStatus.fromString(json['status'] as String? ?? 'requested'),
        agreedAmount: (json['agreedAmount'] as num?)?.toDouble(),
        paymentReference: json['paymentReference'] as String?,
        disputeReason: json['disputeReason'] as String?,
        disputeResolution: json['disputeResolution'] as String?,
        disputeWindowEndsAt: _toDateNullable(json['disputeWindowEndsAt']),
        artisanNotes: json['artisanNotes'] as String?,
        customerLat: (json['customerLat'] as num?)?.toDouble(),
        customerLng: (json['customerLng'] as num?)?.toDouble(),
        customerAddress: json['customerAddress'] as String?,
        budgetMin: (json['budgetMin'] as num?)?.toDouble(),
        budgetMax: (json['budgetMax'] as num?)?.toDouble(),
        urgency: json['urgency'] as String? ?? 'asap',
        scheduledDate: _toDateNullable(json['scheduledDate']),
        createdAt: _toDate(json['createdAt']),
        matchedAt: _toDateNullable(json['matchedAt']),
        escrowLockedAt: _toDateNullable(json['escrowLockedAt']),
        startedAt: _toDateNullable(json['startedAt']),
        submittedAt: _toDateNullable(json['submittedAt']),
        completedAt: _toDateNullable(json['completedAt']),
        autoReleaseAt: _toDateNullable(json['autoReleaseAt']),
        aiSuggestion: json['aiSuggestion'] as Map<String, dynamic>?,
        lastUpdatedAt: _toDateNullable(json['lastUpdatedAt']),
        lastUpdatedBy: json['lastUpdatedBy'] as String?,
        updateVersion: (json['updateVersion'] as int?) ?? 0,
      );

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static DateTime? _toDateNullable(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'artisanId': artisanId,
        'category': category,
        'description': description,
        'imageUrls': imageUrls,
        'completionImageUrls': completionImageUrls,
        'status': status.name,
        if (agreedAmount != null) 'agreedAmount': agreedAmount,
        if (paymentReference != null) 'paymentReference': paymentReference,
        if (disputeReason != null) 'disputeReason': disputeReason,
        if (disputeResolution != null) 'disputeResolution': disputeResolution,
        if (disputeWindowEndsAt != null)
          'disputeWindowEndsAt': Timestamp.fromDate(disputeWindowEndsAt!),
        if (artisanNotes != null) 'artisanNotes': artisanNotes,
        if (customerLat != null) 'customerLat': customerLat,
        if (customerLng != null) 'customerLng': customerLng,
        if (customerAddress != null) 'customerAddress': customerAddress,
        if (budgetMin != null) 'budgetMin': budgetMin,
        if (budgetMax != null) 'budgetMax': budgetMax,
        'urgency': urgency,
        if (scheduledDate != null) 'scheduledDate': Timestamp.fromDate(scheduledDate!),
        'createdAt': Timestamp.fromDate(createdAt),
        if (matchedAt != null) 'matchedAt': Timestamp.fromDate(matchedAt!),
        if (escrowLockedAt != null) 'escrowLockedAt': Timestamp.fromDate(escrowLockedAt!),
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        if (autoReleaseAt != null) 'autoReleaseAt': Timestamp.fromDate(autoReleaseAt!),
        if (aiSuggestion != null) 'aiSuggestion': aiSuggestion,
        if (lastUpdatedAt != null) 'lastUpdatedAt': Timestamp.fromDate(lastUpdatedAt!),
        if (lastUpdatedBy != null) 'lastUpdatedBy': lastUpdatedBy,
        'updateVersion': updateVersion,
      };

  JobModel copyWith({
    String? artisanId,
    JobStatus? status,
    List<String>? completionImageUrls,
    double? agreedAmount,
    String? paymentReference,
    String? disputeReason,
    String? artisanNotes,
    DateTime? matchedAt,
    DateTime? escrowLockedAt,
    DateTime? startedAt,
    DateTime? submittedAt,
    DateTime? completedAt,
    DateTime? autoReleaseAt,
  }) =>
      JobModel(
        id: id,
        customerId: customerId,
        artisanId: artisanId ?? this.artisanId,
        category: category,
        description: description,
        imageUrls: imageUrls,
        completionImageUrls: completionImageUrls ?? this.completionImageUrls,
        status: status ?? this.status,
        agreedAmount: agreedAmount ?? this.agreedAmount,
        paymentReference: paymentReference ?? this.paymentReference,
        disputeReason: disputeReason ?? this.disputeReason,
        artisanNotes: artisanNotes ?? this.artisanNotes,
        customerLat: customerLat,
        customerLng: customerLng,
        customerAddress: customerAddress,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        urgency: urgency,
        scheduledDate: scheduledDate,
        createdAt: createdAt,
        matchedAt: matchedAt ?? this.matchedAt,
        escrowLockedAt: escrowLockedAt ?? this.escrowLockedAt,
        startedAt: startedAt ?? this.startedAt,
        submittedAt: submittedAt ?? this.submittedAt,
        completedAt: completedAt ?? this.completedAt,
        autoReleaseAt: autoReleaseAt ?? this.autoReleaseAt,
      );
}
