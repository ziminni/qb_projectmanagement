import 'json_utils.dart';

enum EquipmentBorrowSource implements JsonEnum {
  owned('owned', 'Queen Builders owned'),
  rented('rented', 'External rental');

  const EquipmentBorrowSource(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static EquipmentBorrowSource fromJson(Object? raw) =>
      enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum EquipmentBorrowStatus implements JsonEnum {
  pending('pending', 'Pending PM approval'),
  borrowed('borrowed', 'On site (borrowed)'),
  returned('returned', 'Returned'),
  rejected('rejected', 'Rejected');

  const EquipmentBorrowStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static EquipmentBorrowStatus fromJson(Object? raw) =>
      enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum EquipmentReturnCondition implements JsonEnum {
  good('good', 'Good'),
  damaged('damaged', 'Damaged'),
  maintenance('maintenance', 'Needs maintenance');

  const EquipmentReturnCondition(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static EquipmentReturnCondition? fromJsonOrNull(Object? raw) {
    final s = (raw as String?)?.trim() ?? '';
    if (s.isEmpty) return null;
    for (final v in values) {
      if (v.apiValue == s) return v;
    }
    return null;
  }

  String toJson() => apiValue;
}

/// A borrowed Queen Builders equipment item or externally rented equipment
/// assigned to a project (and optionally to a specific laborer on site).
class EquipmentBorrow {
  const EquipmentBorrow({
    required this.id,
    required this.projectId,
    this.categoryId,
    this.categoryName,
    this.equipmentItemId,
    required this.source,
    required this.equipmentName,
    required this.quantity,
    this.borrowerWorkerId,
    this.borrowerName = '',
    this.borrowerTrade,
    this.rentalSupplier = '',
    this.rentalRate,
    this.rateUnit = 'day',
    required this.neededDate,
    this.expectedReturnDate,
    required this.status,
    this.returnCondition,
    this.returnNotes = '',
    this.returnedAt,
    this.returnedById,
    this.returnedByName,
    required this.requestedById,
    this.requestedByName,
    this.reviewedById,
    this.reviewedByName,
    this.rejectionReason = '',
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int? categoryId;
  final String? categoryName;
  final int? equipmentItemId;
  final EquipmentBorrowSource source;
  final String equipmentName;
  final int quantity;
  final int? borrowerWorkerId;
  final String borrowerName;
  final String? borrowerTrade;
  final String rentalSupplier;
  final double? rentalRate;
  final String rateUnit;
  final DateTime neededDate;
  final DateTime? expectedReturnDate;
  final EquipmentBorrowStatus status;
  final EquipmentReturnCondition? returnCondition;
  final String returnNotes;
  final DateTime? returnedAt;
  final int? returnedById;
  final String? returnedByName;
  final int requestedById;
  final String? requestedByName;
  final int? reviewedById;
  final String? reviewedByName;
  final String rejectionReason;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOverdue =>
      status == EquipmentBorrowStatus.borrowed &&
      expectedReturnDate != null &&
      DateTime.now().isAfter(
        DateTime(
          expectedReturnDate!.year,
          expectedReturnDate!.month,
          expectedReturnDate!.day,
          23,
          59,
        ),
      );

  bool get hasBorrower => borrowerName.trim().isNotEmpty;

  EquipmentBorrow copyWith({
    EquipmentBorrowStatus? status,
    double? rentalRate,
    EquipmentReturnCondition? returnCondition,
    String? returnNotes,
    DateTime? returnedAt,
    int? returnedById,
    String? returnedByName,
    int? reviewedById,
    String? reviewedByName,
    String? rejectionReason,
  }) => EquipmentBorrow(
    id: id,
    projectId: projectId,
    categoryId: categoryId,
    categoryName: categoryName,
    equipmentItemId: equipmentItemId,
    source: source,
    equipmentName: equipmentName,
    quantity: quantity,
    borrowerWorkerId: borrowerWorkerId,
    borrowerName: borrowerName,
    borrowerTrade: borrowerTrade,
    rentalSupplier: rentalSupplier,
    rentalRate: rentalRate ?? this.rentalRate,
    rateUnit: rateUnit,
    neededDate: neededDate,
    expectedReturnDate: expectedReturnDate,
    status: status ?? this.status,
    returnCondition: returnCondition ?? this.returnCondition,
    returnNotes: returnNotes ?? this.returnNotes,
    returnedAt: returnedAt ?? this.returnedAt,
    returnedById: returnedById ?? this.returnedById,
    returnedByName: returnedByName ?? this.returnedByName,
    requestedById: requestedById,
    requestedByName: requestedByName,
    reviewedById: reviewedById ?? this.reviewedById,
    reviewedByName: reviewedByName ?? this.reviewedByName,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    notes: notes,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory EquipmentBorrow.fromJson(Map<String, dynamic> json) =>
      EquipmentBorrow(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        categoryId: json['category_id'] as int?,
        categoryName: json['category_name'] as String?,
        equipmentItemId: json['equipment_item_id'] as int?,
        source: EquipmentBorrowSource.fromJson(json['source']),
        equipmentName: json['equipment_name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        borrowerWorkerId: json['borrower_worker_id'] as int?,
        borrowerName: json['borrower_name'] as String? ?? '',
        borrowerTrade: json['borrower_trade'] as String?,
        rentalSupplier: json['rental_supplier'] as String? ?? '',
        rentalRate: json['rental_rate'] == null
            ? null
            : JsonUtils.toDouble(json['rental_rate']),
        rateUnit: json['rate_unit'] as String? ?? 'day',
        neededDate: JsonUtils.toDate(json['needed_date']),
        expectedReturnDate: JsonUtils.toDateOrNull(
          json['expected_return_date'],
        ),
        status: EquipmentBorrowStatus.fromJson(json['status']),
        returnCondition: EquipmentReturnCondition.fromJsonOrNull(
          json['return_condition'],
        ),
        returnNotes: json['return_notes'] as String? ?? '',
        returnedAt: JsonUtils.toDateOrNull(json['returned_at']),
        returnedById: json['returned_by_id'] as int?,
        returnedByName: json['returned_by_name'] as String?,
        requestedById: json['requested_by_id'] as int,
        requestedByName: json['requested_by_name'] as String?,
        reviewedById: json['reviewed_by_id'] as int?,
        reviewedByName: json['reviewed_by_name'] as String?,
        rejectionReason: json['rejection_reason'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );
}
