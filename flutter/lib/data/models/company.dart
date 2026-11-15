import 'json_utils.dart';

/// A row in `companies`.
class Company {
  const Company({
    required this.id,
    required this.name,
    required this.address,
    required this.tin,
    required this.pcabLicenseNo,
    required this.pcabLicenseExpiry,
    this.logoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String address;
  final String tin;
  final String pcabLicenseNo;
  final DateTime pcabLicenseExpiry;
  final String? logoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Company copyWith({
    String? name,
    String? address,
    String? tin,
    String? pcabLicenseNo,
    DateTime? pcabLicenseExpiry,
    String? Function()? logoUrl,
    DateTime? updatedAt,
  }) => Company(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    tin: tin ?? this.tin,
    pcabLicenseNo: pcabLicenseNo ?? this.pcabLicenseNo,
    pcabLicenseExpiry: pcabLicenseExpiry ?? this.pcabLicenseExpiry,
    logoUrl: logoUrl != null ? logoUrl() : this.logoUrl,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as int,
    name: json['name'] as String,
    address: json['address'] as String,
    tin: json['tin'] as String,
    pcabLicenseNo: json['pcab_license_no'] as String,
    pcabLicenseExpiry: JsonUtils.toDate(json['pcab_license_expiry']),
    logoUrl: json['logo_url'] as String?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'tin': tin,
    'pcab_license_no': pcabLicenseNo,
    'pcab_license_expiry': JsonUtils.fromDate(pcabLicenseExpiry),
    'logo_url': logoUrl,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
