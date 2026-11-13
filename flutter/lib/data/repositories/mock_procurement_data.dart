import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/material_request.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/supplier_payment.dart';

/// Seed requests, POs, deliveries and supplier payments for projects 1–2.
abstract final class MockProcurementData {
  static const _own = MaterialSource.ownStore;
  static const _ext = MaterialSource.external;

  static final requests = [
    MaterialRequest(
      id: 1,
      projectId: 1,
      categoryId: 1,
      requestedBy: 4,
      neededBy: DateTime(2026, 8, 4),
      status: MaterialRequestStatus.ordered,
      approvedBy: 3,
      createdAt: DateTime(2026, 7, 30),
    ),
    MaterialRequest(
      id: 2,
      projectId: 1,
      categoryId: 2,
      requestedBy: 4,
      neededBy: DateTime(2026, 9, 2),
      status: MaterialRequestStatus.ordered,
      approvedBy: 3,
      createdAt: DateTime(2026, 8, 28),
    ),
    MaterialRequest(
      id: 3,
      projectId: 1,
      categoryId: 2,
      requestedBy: 4,
      neededBy: DateTime(2026, 10, 28),
      status: MaterialRequestStatus.pending,
      createdAt: DateTime(2026, 10, 22, 16),
    ),
    MaterialRequest(
      id: 4,
      projectId: 1,
      categoryId: 3,
      requestedBy: 4,
      neededBy: DateTime(2026, 11, 10),
      status: MaterialRequestStatus.pending,
      createdAt: DateTime(2026, 10, 21, 9),
    ),
    // Over the Site preparation budget; the owner sees a warning.
    MaterialRequest(
      id: 5,
      projectId: 2,
      categoryId: 5,
      requestedBy: 8,
      neededBy: DateTime(2026, 11, 3),
      status: MaterialRequestStatus.pending,
      createdAt: DateTime(2026, 10, 23, 11),
    ),
  ];

  static const requestItems = [
    MaterialRequestItem(
      id: 1,
      materialRequestId: 1,
      description: 'Cement',
      unit: 'bags',
      quantity: 120,
      purchaseOrderId: 1,
    ),
    MaterialRequestItem(
      id: 2,
      materialRequestId: 1,
      description: '10 mm rebar',
      unit: 'pcs',
      quantity: 150,
      purchaseOrderId: 2,
    ),
    MaterialRequestItem(
      id: 3,
      materialRequestId: 1,
      description: 'Washed sand',
      unit: 'cu.m',
      quantity: 10,
      purchaseOrderId: 3,
    ),
    MaterialRequestItem(
      id: 4,
      materialRequestId: 1,
      description: 'Gravel 3/4',
      unit: 'cu.m',
      quantity: 12,
      purchaseOrderId: 3,
    ),
    MaterialRequestItem(
      id: 5,
      materialRequestId: 2,
      description: '12 mm rebar',
      unit: 'pcs',
      quantity: 120,
      purchaseOrderId: 4,
    ),
    MaterialRequestItem(
      id: 6,
      materialRequestId: 2,
      description: 'Tie wire',
      unit: 'kg',
      quantity: 30,
      purchaseOrderId: 5,
    ),
    MaterialRequestItem(
      id: 7,
      materialRequestId: 2,
      description: 'Marine plywood 1/2',
      unit: 'sheets',
      quantity: 40,
      purchaseOrderId: 5,
    ),
    MaterialRequestItem(
      id: 8,
      materialRequestId: 2,
      description: 'Cement',
      unit: 'bags',
      quantity: 80,
      purchaseOrderId: 5,
    ),
    MaterialRequestItem(
      id: 9,
      materialRequestId: 3,
      description: 'Cement for slab',
      unit: 'bags',
      quantity: 60,
    ),
    MaterialRequestItem(
      id: 10,
      materialRequestId: 3,
      description: 'Plywood for forms',
      unit: 'sheets',
      quantity: 20,
    ),
    MaterialRequestItem(
      id: 11,
      materialRequestId: 4,
      description: 'Roof sheets (long span)',
      unit: 'lin.m',
      quantity: 220,
    ),
    MaterialRequestItem(
      id: 12,
      materialRequestId: 4,
      description: 'Tie wire',
      unit: 'kg',
      quantity: 10,
    ),
    MaterialRequestItem(
      id: 13,
      materialRequestId: 5,
      description: 'Gravel for fill',
      unit: 'cu.m',
      quantity: 300,
    ),
  ];

  static final orders = [
    PurchaseOrder(
      id: 1,
      poNo: 'PO-2026-0001',
      projectId: 1,
      materialRequestId: 1,
      categoryId: 1,
      supplierId: 1,
      source: _own,
      status: PurchaseOrderStatus.delivered,
      totalAmount: 31200,
      createdAt: DateTime(2026, 7, 31),
    ),
    PurchaseOrder(
      id: 2,
      poNo: 'PO-2026-0002',
      projectId: 1,
      materialRequestId: 1,
      categoryId: 1,
      supplierId: 2,
      source: _ext,
      status: PurchaseOrderStatus.delivered,
      totalAmount: 35250,
      createdAt: DateTime(2026, 7, 31),
    ),
    PurchaseOrder(
      id: 3,
      poNo: 'PO-2026-0003',
      projectId: 1,
      materialRequestId: 1,
      categoryId: 1,
      supplierId: 3,
      source: _ext,
      status: PurchaseOrderStatus.delivered,
      totalAmount: 31000,
      createdAt: DateTime(2026, 7, 31),
    ),
    PurchaseOrder(
      id: 4,
      poNo: 'PO-2026-0004',
      projectId: 1,
      materialRequestId: 2,
      categoryId: 2,
      supplierId: 2,
      source: _ext,
      status: PurchaseOrderStatus.delivered,
      totalAmount: 40200,
      createdAt: DateTime(2026, 8, 29),
    ),
    PurchaseOrder(
      id: 5,
      poNo: 'PO-2026-0005',
      projectId: 1,
      materialRequestId: 2,
      categoryId: 2,
      supplierId: 1,
      source: _own,
      status: PurchaseOrderStatus.partiallyDelivered,
      totalAmount: 53650,
      approvedBy: 3,
      createdAt: DateTime(2026, 8, 29),
    ),
  ];

  static const orderItems = [
    PurchaseOrderItem(
      id: 1,
      purchaseOrderId: 1,
      materialId: 1,
      description: 'Portland cement 40 kg',
      unit: 'bag',
      quantity: 120,
      unitPrice: 260,
    ),
    PurchaseOrderItem(
      id: 2,
      purchaseOrderId: 2,
      materialId: 2,
      description: 'Deformed bar 10 mm × 6 m',
      unit: 'pc',
      quantity: 150,
      unitPrice: 235,
    ),
    PurchaseOrderItem(
      id: 3,
      purchaseOrderId: 3,
      materialId: 4,
      description: 'Washed sand',
      unit: 'cu.m',
      quantity: 10,
      unitPrice: 1300,
    ),
    PurchaseOrderItem(
      id: 4,
      purchaseOrderId: 3,
      materialId: 5,
      description: 'Gravel 3/4"',
      unit: 'cu.m',
      quantity: 12,
      unitPrice: 1500,
    ),
    PurchaseOrderItem(
      id: 5,
      purchaseOrderId: 4,
      materialId: 3,
      description: 'Deformed bar 12 mm × 6 m',
      unit: 'pc',
      quantity: 120,
      unitPrice: 335,
    ),
    PurchaseOrderItem(
      id: 6,
      purchaseOrderId: 5,
      materialId: 9,
      description: 'Tie wire #16',
      unit: 'kg',
      quantity: 30,
      unitPrice: 95,
    ),
    PurchaseOrderItem(
      id: 7,
      purchaseOrderId: 5,
      materialId: 7,
      description: 'Marine plywood 1/2"',
      unit: 'sheet',
      quantity: 40,
      unitPrice: 750,
    ),
    PurchaseOrderItem(
      id: 8,
      purchaseOrderId: 5,
      materialId: 1,
      description: 'Portland cement 40 kg',
      unit: 'bag',
      quantity: 80,
      unitPrice: 260,
    ),
  ];

  static final deliveries = [
    Delivery(
      id: 1,
      purchaseOrderId: 1,
      receivedBy: 4,
      receivedAt: DateTime(2026, 8, 3, 10),
    ),
    Delivery(
      id: 2,
      purchaseOrderId: 2,
      receivedBy: 4,
      receivedAt: DateTime(2026, 8, 8, 14),
    ),
    Delivery(
      id: 3,
      purchaseOrderId: 3,
      receivedBy: 4,
      receivedAt: DateTime(2026, 8, 3, 15),
    ),
    Delivery(
      id: 4,
      purchaseOrderId: 4,
      receivedBy: 4,
      receivedAt: DateTime(2026, 9, 2, 9),
    ),
    Delivery(
      id: 5,
      purchaseOrderId: 5,
      receivedBy: 4,
      receivedAt: DateTime(2026, 10, 18, 11),
    ),
  ];

  static const deliveryItems = [
    DeliveryItem(
      id: 1,
      deliveryId: 1,
      purchaseOrderItemId: 1,
      qtyReceived: 120,
    ),
    DeliveryItem(
      id: 2,
      deliveryId: 2,
      purchaseOrderItemId: 2,
      qtyReceived: 150,
    ),
    DeliveryItem(id: 3, deliveryId: 3, purchaseOrderItemId: 3, qtyReceived: 10),
    DeliveryItem(id: 4, deliveryId: 3, purchaseOrderItemId: 4, qtyReceived: 12),
    DeliveryItem(
      id: 5,
      deliveryId: 4,
      purchaseOrderItemId: 5,
      qtyReceived: 120,
      qtyDamaged: 2,
    ),
    DeliveryItem(id: 6, deliveryId: 5, purchaseOrderItemId: 6, qtyReceived: 30),
    DeliveryItem(id: 7, deliveryId: 5, purchaseOrderItemId: 7, qtyReceived: 40),
  ];

  static final payments = [
    SupplierPayment(
      id: 1,
      purchaseOrderId: 1,
      amount: 31200,
      paidOn: DateTime(2026, 8, 15),
      method: PaymentMethod.bankTransfer,
      referenceNo: 'BT-0815-01',
    ),
    SupplierPayment(
      id: 2,
      purchaseOrderId: 2,
      amount: 35250,
      paidOn: DateTime(2026, 8, 20),
      method: PaymentMethod.check,
      referenceNo: 'CHK 004512',
    ),
    SupplierPayment(
      id: 3,
      purchaseOrderId: 3,
      amount: 20000,
      paidOn: DateTime(2026, 8, 20),
      method: PaymentMethod.cash,
    ),
  ];
}
