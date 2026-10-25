import 'json_utils.dart';

/// A row in `suppliers`. The company's own hardware store is a supplier with
/// [isOwnStore] set.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.address,
    this.isOwnStore = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? address;
  final bool isOwnStore;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Supplier copyWith({
    int? id,
    String? name,
    String? Function()? contactPerson,
    String? Function()? phone,
    String? Function()? address,
    bool? isOwnStore,
    DateTime? updatedAt,
  }) => Supplier(
    id: id ?? this.id,
    name: name ?? this.name,
    contactPerson: contactPerson != null ? contactPerson() : this.contactPerson,
    phone: phone != null ? phone() : this.phone,
    address: address != null ? address() : this.address,
    isOwnStore: isOwnStore ?? this.isOwnStore,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as int,
    name: json['name'] as String,
    contactPerson: json['contact_person'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    isOwnStore: json['is_own_store'] as bool? ?? false,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contact_person': contactPerson,
    'phone': phone,
    'address': address,
    'is_own_store': isOwnStore,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
