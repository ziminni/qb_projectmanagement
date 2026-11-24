import '../../core/network/api_client.dart';
import '../models/app_role.dart';
import '../models/equipment_borrow.dart';
import '../models/json_utils.dart';
import 'equipment_repository.dart';

class HttpEquipmentRepository implements EquipmentRepository {
  HttpEquipmentRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<EquipmentBorrow>> getBorrows({
    int? projectId,
    List<int>? projectIds,
    EquipmentBorrowStatus? status,
  }) async {
    final rows = await _client.getRows(
      'project-equipment-borrows/',
      query: {
        if (projectId != null) 'project': '$projectId',
        if (status != null) 'status': status.apiValue,
      },
    );
    final items = [for (final r in rows) EquipmentBorrow.fromJson(r)];
    if (projectIds != null) {
      final allowed = projectIds.toSet();
      return items.where((b) => allowed.contains(b.projectId)).toList();
    }
    return items;
  }

  @override
  Future<EquipmentBorrow> createBorrow(
    EquipmentBorrowDraft draft, {
    required int userId,
    required AppRole role,
  }) async {
    final data = await _client.post(
      'project-equipment-borrows/',
      body: {
        'project_id': draft.projectId,
        if (draft.categoryId != null) 'category_id': draft.categoryId,
        if (draft.equipmentItemId != null)
          'equipment_item_id': draft.equipmentItemId,
        'source': draft.source.apiValue,
        'equipment_name': draft.equipmentName,
        'quantity': draft.quantity,
        if (draft.borrowerWorkerId != null)
          'borrower_worker_id': draft.borrowerWorkerId,
        'borrower_name': draft.borrowerName,
        'rental_supplier': draft.rentalSupplier,
        if (draft.rentalRate != null) 'rental_rate': draft.rentalRate,
        'rate_unit': draft.rateUnit,
        'needed_date': JsonUtils.fromDate(draft.neededDate),
        if (draft.expectedReturnDate != null)
          'expected_return_date': JsonUtils.fromDate(draft.expectedReturnDate!),
        'notes': draft.notes,
      },
    );
    return EquipmentBorrow.fromJson(jsonObject(data));
  }

  @override
  Future<EquipmentBorrow> approveBorrow(
    int id, {
    required int userId,
    double? rentalRate,
  }) async {
    final data = await _client.post(
      'project-equipment-borrows/$id/approve/',
      body: {'rental_rate': ?rentalRate},
    );
    return EquipmentBorrow.fromJson(jsonObject(data));
  }

  @override
  Future<EquipmentBorrow> rejectBorrow(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final data = await _client.post(
      'project-equipment-borrows/$id/reject/',
      body: {'reason': reason},
    );
    return EquipmentBorrow.fromJson(jsonObject(data));
  }

  @override
  Future<EquipmentBorrow> markReturned(
    int id, {
    required int userId,
    required EquipmentReturnCondition condition,
    String notes = '',
  }) async {
    final data = await _client.post(
      'project-equipment-borrows/$id/mark-returned/',
      body: {
        'condition': condition.apiValue,
        'notes': notes,
      },
    );
    return EquipmentBorrow.fromJson(jsonObject(data));
  }
}
