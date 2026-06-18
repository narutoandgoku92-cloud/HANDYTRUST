import 'package:cloud_firestore/cloud_firestore.dart';

/// A user can hold multiple roles simultaneously (customer + artisan).
/// [activeRole] tracks which dashboard they're currently viewing.
enum UserRole { customer, artisan }

class UserModel {
  final String uid;
  final String name;
  final String? email;
  final String? phoneNumber;
  /// All roles this account holds. At least one element always present.
  final List<String> roles;
  /// Which role the user is currently operating as.
  final String activeRole;
  final String? category;
  final String? location;
  final DateTime createdAt;
  final bool emailVerified;
  final bool notificationsEnabled;
  /// 'active' | 'suspended' — admin-only field, see [isSuspended].
  final String accountStatus;

  UserModel({
    required this.uid,
    required this.name,
    this.email,
    this.phoneNumber,
    List<String>? roles,
    String? activeRole,
    this.category,
    this.location,
    DateTime? createdAt,
    this.emailVerified = false,
    this.notificationsEnabled = true,
    this.accountStatus = 'active',
  })  : roles = roles ?? const ['customer'],
        activeRole = activeRole ?? (roles?.first ?? 'customer'),
        createdAt = createdAt ?? DateTime.now();

  bool get isSuspended => accountStatus == 'suspended';

  /// Legacy accessor — returns the primary role as enum.
  UserRole get role {
    if (activeRole == 'artisan' || (roles.contains('artisan') && !roles.contains('customer'))) {
      return UserRole.artisan;
    }
    return UserRole.customer;
  }

  bool get isArtisan => roles.contains('artisan');
  bool get isCustomer => roles.contains('customer');
  bool get isAdmin => roles.contains('admin');

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    List<String> roles;
    if (rawRoles is List) {
      roles = List<String>.from(rawRoles);
    } else {
      // Legacy migration: single 'role' field
      final legacyRole = json['role'] as String?;
      roles = legacyRole != null ? [legacyRole] : ['customer'];
    }

    return UserModel(
      uid: json['uid'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      roles: roles,
      activeRole: json['activeRole'] as String? ?? roles.first,
      category: json['category'] as String?,
      location: json['location'] as String?,
      createdAt: _parseDate(json['createdAt']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      accountStatus: json['accountStatus'] as String? ?? 'active',
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'roles': roles,
      'activeRole': activeRole,
      'category': category,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
      'emailVerified': emailVerified,
      'notificationsEnabled': notificationsEnabled,
      'accountStatus': accountStatus,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    List<String>? roles,
    String? activeRole,
    String? category,
    String? location,
    bool? emailVerified,
    bool? notificationsEnabled,
    String? accountStatus,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      roles: roles ?? this.roles,
      activeRole: activeRole ?? this.activeRole,
      category: category ?? this.category,
      location: location ?? this.location,
      createdAt: createdAt,
      emailVerified: emailVerified ?? this.emailVerified,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      accountStatus: accountStatus ?? this.accountStatus,
    );
  }
}
