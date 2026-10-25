import '../models/app_role.dart';
import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/material_request.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/supplier_payment.dart';
import '../services/inventory_calculator.dart';
import '../services/procurement_rules.dart';

class MaterialRequestDetail {
  const MaterialRequestDetail(this.request, this.items);

  final MaterialRequest request;
  final List<MaterialRequestItem> items;
}

class MaterialRequestDraft {
  const MaterialRequestDraft({
    required this.projectId,
    required this.categoryId,
    required this.neededBy,
    required this.items,
  });

  final int projectId;
  final int categoryId;
  final DateTime neededBy;
  final List<({int materialId, double quantity})> items;
}

/// Purchasing's choice for one request item.
class OrderLine {
  const OrderLine({
    required this.requestItemId,
    required this.source,
    required this.supplierId,
    required this.unitPrice,
  });

  final int requestItemId;
  final MaterialSource source;
  final int supplierId;
  final double unitPrice;
}

class DeliveryDetail {
  const DeliveryDetail(this.delivery, this.items);

  final Delivery delivery;
  final List<DeliveryItem> items;
}

class PurchaseOrderDetail {
  const PurchaseOrderDetail({
    required this.order,
    required this.items,
    required this.deliveries,
    required this.payments,
    required this.requestId,
  });

  final PurchaseOrder order;
  final List<PurchaseOrderItem> items;
  final List<DeliveryDetail> deliveries;
  final List<SupplierPayment> payments;
  final int? requestId;

  /// Quantity received so far per PO item.
  double receivedFor(int poItemId) => deliveries
      .expand((d) => d.items)
      .where((i) => i.purchaseOrderItemId == poItemId)
      .fold(0, (s, i) => s + i.qtyReceived);
}

/// What the company owes a supplier on one PO.
class Payable {
  const Payable({
    required this.order,
    required this.deliveredValue,
    required this.paid,
  });

  final PurchaseOrder order;

  /// Good (undamaged) quantity received × unit price.
  final double deliveredValue;
  final double paid;

  double get balance => deliveredValue - paid;
}

abstract interface class ProcurementRepository {
  Future<List<MaterialRequest>> getRequests({
    List<int>? projectIds,
    List<MaterialRequestStatus>? statuses,
  });

  Future<MaterialRequestDetail?> getRequest(int id);

  /// Checks [items] against the category's remaining budget.
  Future<BudgetCheck> checkBudget(
    int categoryId,
    List<({int materialId, double quantity})> items, {
    int? excludingRequestId,
  });

  Future<MaterialRequest> createRequest(
    MaterialRequestDraft draft, {
    required int userId,
  });

  /// PM approval sends over-budget requests on to the owner; owner approval
  /// approves them.
  Future<MaterialRequest> approveRequest(
    int id, {
    required int userId,
    required AppRole role,
  });

  Future<MaterialRequest> rejectRequest(
    int id, {
    required int userId,
    required AppRole role,
    required String reason,
  });

  /// Turns an approved request into one PO per supplier. POs above the
  /// approval threshold wait for the owner.
  Future<List<PurchaseOrder>> createPurchaseOrders(
    int requestId,
    List<OrderLine> lines, {
    required int userId,
  });

  Future<List<PurchaseOrder>> getPurchaseOrders({
    List<int>? projectIds,
    List<PurchaseOrderStatus>? statuses,
  });

  Future<PurchaseOrderDetail?> getPurchaseOrder(int id);

  Future<PurchaseOrder> approvePurchaseOrder(int id, {required int userId});

  Future<PurchaseOrder> cancelPurchaseOrder(int id, {required int userId});

  /// Site engineer confirms a delivery receipt.
  Future<Delivery> confirmDelivery(
    int purchaseOrderId,
    List<({int poItemId, double received, double damaged})> lines, {
    required int userId,
    String? receiptPhotoUrl,
  });

  /// Newest first, with the PO each belongs to.
  Future<List<({DeliveryDetail delivery, PurchaseOrder order})>> getDeliveries({
    List<int>? projectIds,
  });

  Future<List<InventoryLine>> getSiteInventory(int projectId);

  Future<List<Payable>> getPayables({List<int>? projectIds});

  Future<SupplierPayment> recordPayment(
    int purchaseOrderId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  });

  /// Delivered material value per category, for budget vs. actual.
  Future<Map<int, double>> deliveredValueByCategory(int projectId);
}
