import 'json_utils.dart';

/// A row in `clients`. [userId] links the client's portal login.
class Client {
  const Client({
    required this.id,
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.userId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final int? userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Client copyWith({
    int? id,
    String? name,
    String? Function()? contactPerson,
    String? Function()? email,
    String? Function()? phone,
    String? Function()? address,
    int? Function()? userId,
    DateTime? updatedAt,
  }) => Client(
    id: id ?? this.id,
    name: name ?? this.name,
    contactPerson: contactPerson != null ? contactPerson() : this.contactPerson,
    email: email != null ? email() : this.email,
    phone: phone != null ? phone() : this.phone,
    address: address != null ? address() : this.address,
    userId: userId != null ? userId() : this.userId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Client.fromJson(Map<String, dynamic> json) => Client(
    id: json['id'] as int,
    name: json['name'] as String,
    contactPerson: json['contact_person'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    userId: json['user_id'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contact_person': contactPerson,
    'email': email,
    'phone': phone,
    'address': address,
    'user_id': userId,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
