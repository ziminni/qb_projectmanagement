import '../models/app_role.dart';
import '../models/equipment_borrow.dart';
import '../services/business_rule_exception.dart';
import 'equipment_repository.dart';
import 'labor_repository.dart';
import 'schedule_repository.dart';
import 'user_repository.dart';

class _EquipmentRuleException extends BusinessRuleException {
  const _EquipmentRuleException(super.message);
}

class MockEquipmentRepository implements EquipmentRepository {
  MockEquipmentRepository({
    UserRepository? users,
    ScheduleRepository? schedule,
    LaborRepository? labor,
  }) : _users = users,
       _schedule = schedule,
       _labor = labor;

  final UserRepository? _users;
  final ScheduleRepository? _schedule;
  final LaborRepository? _labor;

  final List<EquipmentBorrow> _items = [];
  int _nextId = 1;

  Future<String?> _userName(int id) async {
    if (_users == null) return null;
    final list = await _users.getUsers();
    return list.where((u) => u.id == id).firstOrNull?.fullName;
  }

  @override
  Future<List<EquipmentBorrow>> getBorrows({
    int? projectId,
    List<int>? projectIds,
    EquipmentBorrowStatus? status,
  }) async {
    return _items.where((b) {
      if (projectId != null && b.projectId != projectId) return false;
      if (projectIds != null && !projectIds.contains(b.projectId)) return false;
      if (status != null && b.status != status) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  @override
  Future<EquipmentBorrow> createBorrow(
    EquipmentBorrowDraft draft, {
    required int userId,
    required AppRole role,
  }) async {
    final name = draft.equipmentName.trim();
    if (name.isEmpty) {
      throw const _EquipmentRuleException('Choose or enter an equipment name.');
    }
    if (draft.quantity < 1) {
      throw const _EquipmentRuleException('Quantity must be at least 1.');
    }
    if (draft.expectedReturnDate != null &&
        draft.expectedReturnDate!.isBefore(draft.neededDate)) {
      throw const _EquipmentRuleException(
        'Expected return date cannot be earlier than the needed date.',
      );
    }

    String? categoryName;
    if (draft.categoryId != null && _schedule != null) {
      final cats = await _schedule.getCategories(draft.projectId);
      categoryName = cats
          .where((c) => c.id == draft.categoryId)
          .firstOrNull
          ?.name;
    }

    var borrowerName = draft.borrowerName.trim();
    String? borrowerTrade;
    if (draft.borrowerWorkerId != null && _labor != null) {
      final workers = await _labor.getWorkers();
      final w = workers
          .where((x) => x.id == draft.borrowerWorkerId)
          .firstOrNull;
      if (w != null) {
        if (borrowerName.isEmpty) borrowerName = w.fullName;
        borrowerTrade = w.trade;
      }
    }

    final requesterName = await _userName(userId);
    final isPm = role == AppRole.owner;

    final created = EquipmentBorrow(
      id: _nextId++,
      projectId: draft.projectId,
      categoryId: draft.categoryId,
      categoryName: categoryName,
      equipmentItemId: draft.equipmentItemId,
      source: draft.source,
      equipmentName: name,
      quantity: draft.quantity,
      borrowerWorkerId: draft.borrowerWorkerId,
      borrowerName: borrowerName,
      borrowerTrade: borrowerTrade,
      rentalSupplier: draft.rentalSupplier.trim(),
      rentalRate: isPm ? draft.rentalRate : null,
      rateUnit: draft.rateUnit,
      neededDate: draft.neededDate,
      expectedReturnDate: draft.expectedReturnDate,
      status: isPm
          ? EquipmentBorrowStatus.borrowed
          : EquipmentBorrowStatus.pending,
      requestedById: userId,
      requestedByName: requesterName,
      reviewedById: isPm ? userId : null,
      reviewedByName: isPm ? requesterName : null,
      notes: draft.notes.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<EquipmentBorrow> approveBorrow(
    int id, {
    required int userId,
    double? rentalRate,
  }) async {
    final idx = _items.indexWhere((b) => b.id == id);
    if (idx < 0) {
      throw const _EquipmentRuleException('Equipment request not found.');
    }
    final current = _items[idx];
    if (current.status != EquipmentBorrowStatus.pending) {
      throw const _EquipmentRuleException(
        'This equipment request has already been reviewed.',
      );
    }
    final reviewer = await _userName(userId);
    final updated = current.copyWith(
      status: EquipmentBorrowStatus.borrowed,
      rentalRate: rentalRate ?? current.rentalRate,
      reviewedById: userId,
      reviewedByName: reviewer,
    );
    _items[idx] = updated;
    return updated;
  }

  @override
  Future<EquipmentBorrow> rejectBorrow(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const _EquipmentRuleException(
        'Enter a reason for rejecting this equipment request.',
      );
    }
    final idx = _items.indexWhere((b) => b.id == id);
    if (idx < 0) {
      throw const _EquipmentRuleException('Equipment request not found.');
    }
    final current = _items[idx];
    if (current.status != EquipmentBorrowStatus.pending) {
      throw const _EquipmentRuleException(
        'This equipment request has already been reviewed.',
      );
    }
    final reviewer = await _userName(userId);
    final updated = current.copyWith(
      status: EquipmentBorrowStatus.rejected,
      reviewedById: userId,
      reviewedByName: reviewer,
      rejectionReason: trimmed,
    );
    _items[idx] = updated;
    return updated;
  }

  @override
  Future<EquipmentBorrow> markReturned(
    int id, {
    required int userId,
    required EquipmentReturnCondition condition,
    String notes = '',
  }) async {
    final idx = _items.indexWhere((b) => b.id == id);
    if (idx < 0) {
      throw const _EquipmentRuleException('Equipment record not found.');
    }
    final current = _items[idx];
    if (current.status != EquipmentBorrowStatus.borrowed) {
      throw const _EquipmentRuleException(
        'Only active on-site equipment can be marked returned.',
      );
    }
    final returner = await _userName(userId);
    final updated = current.copyWith(
      status: EquipmentBorrowStatus.returned,
      returnCondition: condition,
      returnNotes: notes.trim(),
      returnedAt: DateTime.now(),
      returnedById: userId,
      returnedByName: returner,
    );
    _items[idx] = updated;
    return updated;
  }
}
