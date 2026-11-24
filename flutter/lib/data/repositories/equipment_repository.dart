import '../models/app_role.dart';
import '../models/equipment_borrow.dart';

class EquipmentBorrowDraft {
  const EquipmentBorrowDraft({
    required this.projectId,
    this.categoryId,
    this.equipmentItemId,
    required this.source,
    required this.equipmentName,
    this.quantity = 1,
    this.borrowerWorkerId,
    this.borrowerName = '',
    this.rentalSupplier = '',
    this.rentalRate,
    this.rateUnit = 'day',
    required this.neededDate,
    this.expectedReturnDate,
    this.notes = '',
  });

  final int projectId;
  final int? categoryId;
  final int? equipmentItemId;
  final EquipmentBorrowSource source;
  final String equipmentName;
  final int quantity;
  final int? borrowerWorkerId;
  final String borrowerName;
  final String rentalSupplier;
  final double? rentalRate;
  final String rateUnit;
  final DateTime neededDate;
  final DateTime? expectedReturnDate;
  final String notes;
}

abstract interface class EquipmentRepository {
  Future<List<EquipmentBorrow>> getBorrows({
    int? projectId,
    List<int>? projectIds,
    EquipmentBorrowStatus? status,
  });

  Future<EquipmentBorrow> createBorrow(
    EquipmentBorrowDraft draft, {
    required int userId,
    required AppRole role,
  });

  Future<EquipmentBorrow> approveBorrow(
    int id, {
    required int userId,
    double? rentalRate,
  });

  Future<EquipmentBorrow> rejectBorrow(
    int id, {
    required int userId,
    required String reason,
  });

  Future<EquipmentBorrow> markReturned(
    int id, {
    required int userId,
    required EquipmentReturnCondition condition,
    String notes = '',
  });
}
