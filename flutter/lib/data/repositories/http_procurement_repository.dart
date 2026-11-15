import '../models/store_balance.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/photo_file_name.dart';
import '../models/app_role.dart';
import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/json_utils.dart';
import '../models/material_request.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/site_count.dart';
import '../models/supplier_payment.dart';
import '../services/business_rule_exception.dart';
import '../services/inventory_calculator.dart';
import '../services/procurement_rules.dart';
import 'procurement_repository.dart';

/// Procurement against the CPMS backend (Phase 3, 3.1a routes).
///
/// Scope, role and redaction are the server's: the active role (sent as
/// `X-Active-Role`) decides which projects and rows come back and which peso
/// keys exist, so the `userId`s/`role`s in the interface are never sent as a
/// claim. Status, totals, `po_no`, actors and timestamps are server-owned. Rule
/// refusals arrive as the server's own `detail` text and surface as
/// `BusinessRuleException` unchanged.
class HttpProcurementRepository implements ProcurementRepository {
  HttpProcurementRepository(this._client);

  final ApiClient _client;

  /// Payables and supplier payments are financially blocked (3.1a decision
  /// 10): the server sends an empty `payments` list, so a screen that showed
  /// "Paid ₱0.00" would be inventing a figure.
  @override
  bool get supportsPayments => false;

  @override
  bool get supportsPosStatus => true;

  @override
  Future<StoreBalance?> getStoreBalance(int projectId) async =>
      StoreBalance.fromJson(
        jsonObject(await _client.get('projects/$projectId/pos-payables/')),
      );

  @override
  Future<List<StorePaymentReceipt>> getStorePaymentReceipts(
    int projectId,
  ) async => [
    for (final row in await _client.getRows(
      'projects/$projectId/pos-payment-receipts/',
    ))
      StorePaymentReceipt.fromJson(row),
  ];

  @override
  Future<StorePaymentReceipt> submitStorePaymentReceipt(
    int projectId, {
    required double amount,
    required String referenceNo,
    String paymentMethod = 'BANK_TRANSFER',
    String notes = '',
  }) async => StorePaymentReceipt.fromJson(
    jsonObject(
      await _client.post(
        'projects/$projectId/pos-payment-receipts/',
        body: {
          'amount': amount.toStringAsFixed(2),
          'reference_no': referenceNo.trim(),
          'payment_method': paymentMethod,
          'notes': notes.trim(),
        },
      ),
    ),
  );

  @override
  Future<PosStatus> getPosStatus(int id) async => PosStatus.fromJson(
    jsonObject(await _client.get('purchase-orders/$id/pos-status/')),
  );

  @override
  Future<PosStatus> retryPosSync(int id) async => PosStatus.fromJson(
    jsonObject(await _client.post('purchase-orders/$id/pos-sync/')),
  );

  // ---- Requests

  @override
  Future<List<MaterialRequest>> getRequests({
    List<int>? projectIds,
    List<MaterialRequestStatus>? statuses,
  }) async {
    final rows = await _client.getRows(
      'material-requests/',
      query: {
        ..._projectQuery(projectIds),
        // The route filters one status; a longer list is filtered here.
        if (statuses != null && statuses.length == 1)
          'status': statuses.single.apiValue,
      },
    );
    return [
      for (final row in rows)
        if (statuses == null ||
            statuses.any((s) => s.apiValue == row['status']))
          MaterialRequest.fromJson(row),
    ];
  }

  @override
  Future<MaterialRequestDetail?> getRequest(int id) async {
    final data = await _client.get(
      'material-requests/$id/',
      notFoundAsNull: true,
    );
    if (data == null) return null;
    final detail = jsonObject(data);
    return MaterialRequestDetail(
      MaterialRequest.fromJson(jsonObject(detail['request'])),
      _rows(detail['items'], MaterialRequestItem.fromJson),
      _rows(detail['counts'], SiteCount.fromJson),
    );
  }

  @override
  Future<BudgetCheck> checkBudget(int categoryId, double amount) async {
    final data = jsonObject(
      await _client.get(
        'categories/$categoryId/procurement-budget/',
        // A 2-place decimal string, never a binary float.
        query: {'amount': amount.toStringAsFixed(2)},
      ),
    );
    return BudgetCheck(
      budget: JsonUtils.toDoubleOrNull(data['budget']),
      committed: JsonUtils.toDouble(data['committed']),
      requestCost: JsonUtils.toDouble(data['request_cost']),
    );
  }

  @override
  Future<MaterialRequest> createRequest(
    MaterialRequestDraft draft, {
    required int userId,
  }) async => MaterialRequest.fromJson(
    jsonObject(
      await _client.post(
        'material-requests/',
        body: {
          'project_id': draft.projectId,
          'needed_by': JsonUtils.fromDate(draft.neededBy),
          'items': [
            for (final i in draft.items)
              {
                'description': i.description.trim(),
                'unit': i.unit.trim(),
                'quantity': i.quantity,
              },
          ],
          'counts': [
            for (final c in draft.counts)
              {
                'material_id': c.materialId,
                'name': c.name,
                'unit': c.unit,
                'expected': c.expected,
                'counted': c.counted,
              },
          ],
        },
      ),
    ),
  );

  @override
  Future<MaterialRequest> rejectRequest(
    int id, {
    required int userId,
    required AppRole role,
    required String reason,
  }) async => MaterialRequest.fromJson(
    jsonObject(
      await _client.post(
        'material-requests/$id/reject/',
        body: {'reason': reason.trim()},
      ),
    ),
  );

  // ---- Orders

  @override
  Future<PurchaseOrder> placeOrder(
    OrderDraft draft, {
    required int userId,
  }) async => _order(
    jsonObject(await _client.post('purchase-orders/', body: _orderBody(draft))),
  );

  /// An own-store order is plain JSON; an other-store one is multipart because
  /// the receipt evidence is the uploaded file, never a URL (3.1a decision 2).
  Object _orderBody(OrderDraft draft) {
    final lines = [
      for (final l in draft.lines)
        {
          'material_id': l.materialId,
          'description': l.description.trim(),
          'unit': l.unit.trim(),
          'quantity': l.quantity,
          'unit_price': l.unitPrice,
        },
    ];
    if (draft.source == MaterialSource.ownStore) {
      return {
        'request_id': draft.requestId,
        'category_id': draft.categoryId,
        'source': draft.source.apiValue,
        'lines': lines,
        'covers_item_ids': draft.coversItemIds,
        'delivery_address': draft.deliveryAddress?.trim(),
      };
    }
    final bytes = draft.receiptPhotoBytes;
    if (bytes == null || bytes.isEmpty) {
      // The demo's file path is not a file: refuse like the server does.
      throw const BusinessRuleException('Attach a photo of the receipt.');
    }
    return FormData.fromMap({
      'request_id': draft.requestId,
      'category_id': draft.categoryId,
      'source': draft.source.apiValue,
      // Multipart fields are text: the nested lists travel as JSON.
      'lines': jsonEncode(lines),
      'covers_item_ids': jsonEncode(draft.coversItemIds),
      'store_name': draft.storeName?.trim(),
      'or_number': draft.orNumber?.trim(),
      'receipt_photo': MultipartFile.fromBytes(
        bytes,
        filename: photoFileName(bytes),
      ),
    });
  }

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders({
    List<int>? projectIds,
    List<PurchaseOrderStatus>? statuses,
  }) async {
    final rows = await _client.getRows(
      'purchase-orders/',
      query: {
        ..._projectQuery(projectIds),
        if (statuses != null && statuses.length == 1)
          'status': statuses.single.apiValue,
      },
    );
    return [
      for (final row in rows)
        if (statuses == null ||
            statuses.any((s) => s.apiValue == row['status']))
          _order(row),
    ];
  }

  @override
  Future<PurchaseOrderDetail?> getPurchaseOrder(int id) async {
    final data = await _client.get(
      'purchase-orders/$id/',
      notFoundAsNull: true,
    );
    if (data == null) return null;
    final detail = jsonObject(data);
    return PurchaseOrderDetail(
      order: _order(jsonObject(detail['order'])),
      items: _rows(detail['items'], _orderItem),
      deliveries: [
        for (final row in _rawRows(detail['deliveries']))
          DeliveryDetail(
            Delivery.fromJson(jsonObject(row['delivery'])),
            _rows(row['items'], DeliveryItem.fromJson),
          ),
      ],
      // Payables are financially blocked (3.1a decision 10): the key is empty.
      payments: _rows(detail['payments'], SupplierPayment.fromJson),
      requestId: detail['request_id'] as int?,
    );
  }

  @override
  Future<PurchaseOrder> cancelPurchaseOrder(
    int id, {
    required int userId,
  }) async =>
      _order(jsonObject(await _client.post('purchase-orders/$id/cancel/')));

  // ---- Deliveries and inventory

  @override
  Future<Delivery> confirmDelivery(
    int purchaseOrderId,
    List<({int poItemId, double received, double damaged})> lines, {
    required int userId,
    String? receiptPhotoUrl,
    Uint8List? receiptPhotoBytes,
  }) async {
    final rows = [
      for (final l in lines)
        {
          'po_item_id': l.poItemId,
          'received': l.received,
          'damaged': l.damaged,
        },
    ];
    final bytes = receiptPhotoBytes;
    final Object body = bytes == null || bytes.isEmpty
        ? {'lines': rows}
        : FormData.fromMap({
            'lines': jsonEncode(rows),
            'receipt_photo': MultipartFile.fromBytes(
              bytes,
              filename: photoFileName(bytes),
            ),
          });
    return Delivery.fromJson(
      jsonObject(
        await _client.post(
          'purchase-orders/$purchaseOrderId/deliveries/',
          body: body,
        ),
      ),
    );
  }

  @override
  Future<List<({DeliveryDetail delivery, PurchaseOrder order})>> getDeliveries({
    List<int>? projectIds,
  }) async {
    final rows = await _client.getRows(
      'deliveries/',
      query: _projectQuery(projectIds),
    );
    return [
      for (final row in rows)
        (
          delivery: DeliveryDetail(
            Delivery.fromJson(
              jsonObject(jsonObject(row['delivery'])['delivery']),
            ),
            _rows(jsonObject(row['delivery'])['items'], DeliveryItem.fromJson),
          ),
          order: _order(jsonObject(row['order'])),
        ),
    ];
  }

  @override
  Future<List<InventoryLine>> getSiteInventory(int projectId) async => [
    for (final row in await _client.getRows(
      'projects/$projectId/site-inventory/',
    ))
      InventoryLine(
        materialId: row['material_id'] as int?,
        name: row['name'] as String,
        unit: row['unit'] as String? ?? '',
        received: JsonUtils.toDouble(row['received']),
        damaged: JsonUtils.toDouble(row['damaged']),
        used: JsonUtils.toDouble(row['used']),
      ),
  ];

  // ---- Financially blocked (phase-3 contract, blockers 1 and 2)

  @override
  Future<List<Payable>> getPayables({List<int>? projectIds}) async =>
      throw UnsupportedError(
        'Supplier payables are blocked: a per-PO delivered value cannot '
        'represent POS project debt, and which ledger owns that debt is not '
        'decided yet (phase-3 contract, blocker 2).',
      );

  @override
  Future<SupplierPayment> recordPayment(
    int purchaseOrderId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async => throw UnsupportedError(
    'Supplier payments are blocked until the ledger that owns POS debt is '
    'decided; the POS service cannot post payments either (phase-3 contract, '
    'blocker 2).',
  );

  @override
  Future<Map<int, double>> deliveredValueByCategory(int projectId) async {
    // Outside-store goods only: own-store goods are the store's charge.
    final data = jsonObject(
      await _client.get('projects/$projectId/external-materials-cost/'),
    );
    return {
      for (final e in jsonObject(data['by_category']).entries)
        int.parse(e.key): JsonUtils.toDouble(e.value),
    };
  }

  // ---- Helpers

  /// `?project=1,2`; the server intersects it with the caller's scope.
  static Map<String, dynamic> _projectQuery(List<int>? ids) =>
      ids == null || ids.isEmpty ? const {} : {'project': ids.join(',')};

  /// A purchase order, told whether this role is sent the finance keys: an
  /// omitted `total_amount` is a zero only for a redacted role (decision 06,
  /// ruling 1), never for a finance one.
  PurchaseOrder _order(Map<String, dynamic> row) =>
      PurchaseOrder.fromJson(row, financeKeysOmitted: !_client.seesFinance);

  PurchaseOrderItem _orderItem(Map<String, dynamic> row) =>
      PurchaseOrderItem.fromJson(row, financeKeysOmitted: !_client.seesFinance);

  static List<Map<String, dynamic>> _rawRows(Object? raw) => [
    for (final row in (raw as List<dynamic>? ?? const []))
      (row as Map).cast<String, dynamic>(),
  ];

  static List<T> _rows<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
  ) => [for (final row in _rawRows(raw)) parse(row)];
}
