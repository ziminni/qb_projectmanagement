import '../models/app_role.dart';
import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/material_request.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/site_count.dart';
import '../models/supplier_payment.dart';
import '../services/inventory_calculator.dart';
import '../services/procurement_rules.dart';

class MaterialRequestDetail {
  const MaterialRequestDetail(this.request, this.items, this.counts);

  final MaterialRequest request;
  final List<MaterialRequestItem> items;

  /// The site count taken before the request.
  final List<SiteCount> counts;
}

typedef RequestLine = ({String description, String unit, double quantity});

typedef CountLine = ({
  int? materialId,
  String name,
  String unit,
  double expected,
  double counted,
});

class MaterialRequestDraft {
  const MaterialRequestDraft({
    required this.projectId,
    required this.neededBy,
    required this.items,
    required this.counts,
  });

  final int projectId;
  final DateTime neededBy;
  final List<RequestLine> items;

  /// One count per material currently on site.
  final List<CountLine> counts;
}

typedef OrderLine = ({
  int? materialId,
  String description,
  String unit,
  double quantity,
  double unitPrice,
});

/// The owner's answer to a request: an own-store order delivered to
/// [deliveryAddress], or a purchase already paid at another store.
class OrderDraft {
  const OrderDraft.ownStore({
    required this.requestId,
    required this.categoryId,
    required this.lines,
    this.coversItemIds = const [],
    required String this.deliveryAddress,
  }) : source = MaterialSource.ownStore,
       storeName = null,
       orNumber = null,
       receiptPhotoUrl = null;

  const OrderDraft.otherStore({
    required this.requestId,
    required this.categoryId,
    required this.lines,
    this.coversItemIds = const [],
    required String this.storeName,
    required String this.orNumber,
    required String this.receiptPhotoUrl,
  }) : source = MaterialSource.external,
       deliveryAddress = null;

  final int requestId;

  /// The budget category the order is charged to.
  final int categoryId;
  final MaterialSource source;
  final List<OrderLine> lines;

  /// The requested items this order covers.
  final List<int> coversItemIds;
  final String? deliveryAddress;
  final String? storeName;
  final String? orNumber;
  final String? receiptPhotoUrl;
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

  /// Checks an order of [amount] against the category's remaining budget.
  Future<BudgetCheck> checkBudget(int categoryId, double amount);

  Future<MaterialRequest> createRequest(
    MaterialRequestDraft draft, {
    required int userId,
  });

  /// Owner turns down a pending request.
  Future<MaterialRequest> rejectRequest(
    int id, {
    required int userId,
    required AppRole role,
    required String reason,
  });

  /// Owner orders from the own store or logs another store's purchase. A
  /// request can be answered with several orders.
  Future<PurchaseOrder> placeOrder(OrderDraft draft, {required int userId});

  Future<List<PurchaseOrder>> getPurchaseOrders({
    List<int>? projectIds,
    List<PurchaseOrderStatus>? statuses,
  });

  Future<PurchaseOrderDetail?> getPurchaseOrder(int id);

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
