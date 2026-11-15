import 'json_utils.dart';

/// A row in `users`. `password_hash` is never sent to the client, so it is
/// not part of this model.
class User {
  const User({
    required this.id,
    required this.companyId,
    required this.fullName,
    required this.email,
    this.phone,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int companyId;
  final String fullName;
  final String email;
  final String? phone;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    companyId: json['company_id'] as int,
    fullName: json['full_name'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'is_active': isActive,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
