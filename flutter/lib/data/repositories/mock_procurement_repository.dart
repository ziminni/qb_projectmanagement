import 'dart:typed_data';

import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/category.dart';
import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/material_request.dart';
import '../models/material_item.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/site_count.dart';
import '../models/supplier_payment.dart';
import '../services/business_rule_exception.dart';
import '../services/inventory_calculator.dart';
import '../services/notification_service.dart';
import '../services/procurement_rules.dart';
import '../services/project_rules.dart';
import 'audit_log_repository.dart';
import 'daily_report_repository.dart';
import 'master_data_repository.dart';
import 'mock_procurement_data.dart';
import 'procurement_repository.dart';
import 'project_repository.dart';
import 'schedule_repository.dart';
import 'user_repository.dart';

class MockProcurementRepository implements ProcurementRepository {
  MockProcurementRepository({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required MasterDataRepository masterData,
    required DailyReportRepository reports,
    required UserRepository users,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
    DateTime Function()? clock,
  }) : _projects = projects,
       _schedule = schedule,
       _masterData = masterData,
       _reports = reports,
       _users = users,
       _auditLog = auditLog,
       _notifications = notifications,
       _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final MasterDataRepository _masterData;
  final DailyReportRepository _reports;
  final UserRepository _users;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final DateTime Function() _clock;

  /// The demo records supplier payments itself, so the screens keep showing
  /// paid amounts and the Pay button.
  @override
  bool get supportsPayments => true;

  @override
  bool get supportsPosStatus => false;

  @override
  Future<PosStatus> getPosStatus(int id) async =>
      throw UnsupportedError('Store sync status is unavailable in demo mode.');

  @override
  Future<PosStatus> retryPosSync(int id) async =>
      throw UnsupportedError('Store sync is unavailable in demo mode.');

  final _requests = [...MockProcurementData.requests];
  final _requestItems = [...MockProcurementData.requestItems];
  final _counts = <SiteCount>[];
  final _orders = [...MockProcurementData.orders];
  final _orderItems = [...MockProcurementData.orderItems];
  final _deliveries = [...MockProcurementData.deliveries];
  final _deliveryItems = [...MockProcurementData.deliveryItems];
  final _payments = [...MockProcurementData.payments];

  static int _next(Iterable<int> ids) =>
      ids.fold(0, (m, id) => id > m ? id : m) + 1;

  // ---- Requests

  @override
  Future<List<MaterialRequest>> getRequests({
    List<int>? projectIds,
    List<MaterialRequestStatus>? statuses,
  }) async =>
      _requests
          .where(
            (r) =>
                (projectIds == null || projectIds.contains(r.projectId)) &&
                (statuses == null || statuses.contains(r.status)),
          )
          .toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );

  @override
  Future<MaterialRequestDetail?> getRequest(int id) async {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    return MaterialRequestDetail(
      _requests[i],
      _requestItems.where((x) => x.materialRequestId == id).toList(),
      _counts.where((c) => c.materialRequestId == id).toList(),
    );
  }

  /// Ordered or bought material for [categoryId], excluding cancelled
  /// orders.
  double _committed(int categoryId) => _orders
      .where(
        (o) =>
            o.categoryId == categoryId &&
            o.status != PurchaseOrderStatus.cancelled,
      )
      .fold(0.0, (s, o) => s + o.totalAmount);

  @override
  Future<BudgetCheck> checkBudget(int categoryId, double amount) async {
    final category = await _categoryById(categoryId);
    return BudgetCheck(
      budget: category != null && category.hasBudget ? category.budget : null,
      committed: _committed(categoryId),
      requestCost: amount,
    );
  }

  Future<Category?> _categoryById(int categoryId) async {
    for (final p in await _projects.getProjects()) {
      for (final c in await _schedule.getCategories(p.id)) {
        if (c.id == categoryId) return c;
      }
    }
    return null;
  }

  @override
  Future<MaterialRequest> createRequest(
    MaterialRequestDraft draft, {
    required int userId,
  }) async {
    final project = await _projects.getProject(draft.projectId);
    if (project == null) {
      throw const BusinessRuleException('Project not found.');
    }
    ProjectRules.enforce(
      ProjectRules.requireOngoing(project, 'Material requests'),
    );
    if (!await _projects.isAssigned(
      draft.projectId,
      userId,
      AppRole.siteEngineer,
    )) {
      throw const BusinessRuleException(
        'Only the site engineer assigned to this project can request materials.',
      );
    }
    ProcurementRules.enforce(
      ProcurementRules.validateNeededBy(draft.neededBy, _clock()),
    );
    if (draft.items.isEmpty) {
      throw const BusinessRuleException('Add at least one item.');
    }
    for (final i in draft.items) {
      ProcurementRules.enforce(
        ProcurementRules.validateRequired(i.description, 'item'),
      );
      ProcurementRules.enforce(ProcurementRules.validateQuantity(i.quantity));
    }
    // Forced compliance: every material on site is counted first.
    final counted = {
      for (final c in draft.counts) inventoryKey(c.materialId, c.name): c,
    };
    for (final line in await getSiteInventory(draft.projectId)) {
      if (!line.needsCount) continue;
      final c = counted[line.key];
      if (c == null) {
        throw BusinessRuleException(
          'Count the ${line.name} on site before requesting more.',
        );
      }
      ProcurementRules.enforce(ProcurementRules.validateCount(c.counted));
    }
    final now = _clock();
    final request = MaterialRequest(
      id: _next(_requests.map((r) => r.id)),
      projectId: draft.projectId,
      requestedBy: userId,
      neededBy: DateTime(
        draft.neededBy.year,
        draft.neededBy.month,
        draft.neededBy.day,
      ),
      status: MaterialRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    _requests.add(request);
    for (final i in draft.items) {
      _requestItems.add(
        MaterialRequestItem(
          id: _next(_requestItems.map((x) => x.id)),
          materialRequestId: request.id,
          description: i.description.trim(),
          unit: i.unit.trim(),
          quantity: i.quantity,
          createdAt: now,
        ),
      );
    }
    for (final c in draft.counts) {
      _counts.add(
        SiteCount(
          id: _next(_counts.map((x) => x.id)),
          materialRequestId: request.id,
          materialId: c.materialId,
          name: c.name,
          unit: c.unit,
          expected: c.expected,
          counted: c.counted,
        ),
      );
    }
    await _auditLog.record(
      userId: userId,
      action: 'material_request_created',
      entity: 'material_request',
      entityId: request.id,
      details: {'items': draft.items.length, 'counted': draft.counts.length},
    );
    await _notifications?.notifyProjectRole(
      draft.projectId,
      AppRole.owner,
      type: 'material_request',
      message: '${request.number} for ${project.code} is waiting for you.',
      link: AppRoutes.materialRequest(request.id),
    );
    return request;
  }

  @override
  Future<MaterialRequest> rejectRequest(
    int id, {
    required int userId,
    required AppRole role,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const BusinessRuleException('Give a reason for rejecting.');
    }
    final i = _requestIndex(id);
    final r = _requests[i];
    if (r.status != MaterialRequestStatus.pending || role != AppRole.owner) {
      throw BusinessRuleException(
        'This request is ${r.status.label.toLowerCase()} and cannot be '
        'rejected by a ${role.label.toLowerCase()}.',
      );
    }
    await _requirePm(r.projectId, userId);
    final updated = r.copyWith(
      status: MaterialRequestStatus.rejected,
      updatedAt: _clock(),
    );
    _requests[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'material_request_rejected',
      entity: 'material_request',
      entityId: id,
      details: {'reason': reason.trim()},
    );
    await _notifications?.notify(
      [r.requestedBy],
      type: 'material_request',
      message: 'Your ${r.number} was rejected: ${reason.trim()}',
      link: AppRoutes.materialRequest(id),
    );
    return updated;
  }

  // ---- Orders

  /// A typed name that matches the price list counts as that material.
  Future<int?> _matchMaterial(String name) async {
    final n = name.trim().toLowerCase();
    for (final MaterialItem m in await _masterData.getMaterials()) {
      if (m.name.toLowerCase() == n) return m.id;
    }
    return null;
  }

  @override
  Future<PurchaseOrder> placeOrder(
    OrderDraft draft, {
    required int userId,
  }) async {
    final ri = _requestIndex(draft.requestId);
    final request = _requests[ri];
    if (request.status == MaterialRequestStatus.rejected) {
      throw const BusinessRuleException('This request was rejected.');
    }
    await _requirePm(request.projectId, userId);
    final categories = await _schedule.getCategories(request.projectId);
    if (!categories.any((c) => c.id == draft.categoryId)) {
      throw const BusinessRuleException(
        'Choose the budget category of this project.',
      );
    }
    if (draft.lines.isEmpty) {
      throw const BusinessRuleException('Add at least one material.');
    }
    for (final id in draft.coversItemIds) {
      final item = _requestItems.where((x) => x.id == id).firstOrNull;
      if (item == null || item.materialRequestId != request.id) {
        throw const BusinessRuleException('An item is not on this request.');
      }
      if (item.isCovered) {
        throw BusinessRuleException(
          '${item.description} is already covered by another order.',
        );
      }
    }
    for (final l in draft.lines) {
      ProcurementRules.enforce(
        ProcurementRules.validateRequired(l.description, 'material'),
      );
      ProcurementRules.enforce(ProcurementRules.validateQuantity(l.quantity));
      ProcurementRules.enforce(ProcurementRules.validateUnitPrice(l.unitPrice));
    }
    final own = draft.source == MaterialSource.ownStore;
    int? supplierId;
    if (own) {
      ProcurementRules.enforce(
        ProcurementRules.validateRequired(
          draft.deliveryAddress,
          'delivery address',
        ),
      );
      if (draft.lines.any((l) => l.materialId == null)) {
        throw const BusinessRuleException(
          'Pick own-store materials from the store catalog.',
        );
      }
      supplierId = (await _masterData.getSuppliers())
          .where((s) => s.isOwnStore)
          .firstOrNull
          ?.id;
      if (supplierId == null) {
        throw const BusinessRuleException(
          'Set up the own store in the supplier list first.',
        );
      }
    } else {
      ProcurementRules.enforce(
        ProcurementRules.validateRequired(draft.storeName, 'store name'),
      );
      ProcurementRules.enforce(
        ProcurementRules.validateRequired(draft.orNumber, 'OR number'),
      );
      if (draft.receiptPhotoUrl == null || draft.receiptPhotoUrl!.isEmpty) {
        throw const BusinessRuleException('Attach a photo of the receipt.');
      }
    }

    final now = _clock();
    final id = _next(_orders.map((o) => o.id));
    final total = draft.lines.fold(0.0, (s, l) => s + l.quantity * l.unitPrice);
    final order = PurchaseOrder(
      id: id,
      poNo: 'PO-${now.year}-${id.toString().padLeft(4, '0')}',
      projectId: request.projectId,
      materialRequestId: request.id,
      categoryId: draft.categoryId,
      supplierId: supplierId,
      storeName: own ? null : draft.storeName!.trim(),
      source: draft.source,
      status: own
          ? PurchaseOrderStatus.released
          : PurchaseOrderStatus.purchased,
      totalAmount: total,
      deliveryAddress: draft.deliveryAddress?.trim(),
      orNumber: draft.orNumber?.trim(),
      receiptPhotoUrl: draft.receiptPhotoUrl,
      approvedBy: userId,
      createdAt: now,
      updatedAt: now,
    );
    _orders.add(order);
    for (final l in draft.lines) {
      _orderItems.add(
        PurchaseOrderItem(
          id: _next(_orderItems.map((o) => o.id)),
          purchaseOrderId: id,
          materialId: l.materialId ?? await _matchMaterial(l.description),
          description: l.description.trim(),
          unit: l.unit.trim(),
          quantity: l.quantity,
          unitPrice: l.unitPrice,
          createdAt: now,
        ),
      );
    }
    for (final itemId in draft.coversItemIds) {
      final ii = _requestItems.indexWhere((x) => x.id == itemId);
      _requestItems[ii] = _requestItems[ii].coveredBy(id);
    }
    _requests[ri] = request.copyWith(
      status: MaterialRequestStatus.ordered,
      approvedBy: () => request.approvedBy ?? userId,
      updatedAt: now,
    );
    await _auditLog.record(
      userId: userId,
      action: own ? 'purchase_order_created' : 'purchase_logged',
      entity: 'purchase_order',
      entityId: id,
      details: {
        'request_id': request.id,
        'total': total,
        if (!own) 'or_number': draft.orNumber!.trim(),
      },
    );
    await _notifications?.notify(
      [request.requestedBy],
      type: 'material_request',
      message: own
          ? 'Your ${request.number} was ordered from the own store.'
          : 'Your ${request.number} was bought at ${order.storeName}.',
      link: AppRoutes.materialRequest(request.id),
    );
    await _notifyDelivery(order);
    return order;
  }

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders({
    List<int>? projectIds,
    List<PurchaseOrderStatus>? statuses,
  }) async =>
      _orders
          .where(
            (o) =>
                (projectIds == null || projectIds.contains(o.projectId)) &&
                (statuses == null || statuses.contains(o.status)),
          )
          .toList()
        ..sort((a, b) => b.poNo.compareTo(a.poNo));

  @override
  Future<PurchaseOrderDetail?> getPurchaseOrder(int id) async {
    final i = _orders.indexWhere((o) => o.id == id);
    if (i < 0) return null;
    final items = _orderItems.where((o) => o.purchaseOrderId == id).toList();
    return PurchaseOrderDetail(
      order: _orders[i],
      items: items,
      deliveries: [
        for (final d in _deliveries)
          if (d.purchaseOrderId == id)
            DeliveryDetail(
              d,
              _deliveryItems.where((x) => x.deliveryId == d.id).toList(),
            ),
      ],
      payments: _payments.where((p) => p.purchaseOrderId == id).toList(),
      requestId: _orders[i].materialRequestId,
    );
  }

  @override
  Future<PurchaseOrder> cancelPurchaseOrder(
    int id, {
    required int userId,
  }) async {
    final i = _orderIndex(id);
    final o = _orders[i];
    if (_deliveries.any((d) => d.purchaseOrderId == id)) {
      throw const BusinessRuleException(
        'A PO with deliveries cannot be cancelled.',
      );
    }
    if (o.status == PurchaseOrderStatus.cancelled) return o;
    if (o.paidOnPurchase) {
      throw const BusinessRuleException(
        'A purchase already paid at the store cannot be cancelled.',
      );
    }
    final updated = o.copyWith(status: PurchaseOrderStatus.cancelled);
    _orders[i] = updated;
    // Its items are open again for another order.
    for (var j = 0; j < _requestItems.length; j++) {
      if (_requestItems[j].purchaseOrderId == id) {
        _requestItems[j] = _requestItems[j].coveredBy(null);
      }
    }
    // A request left with no live order goes back to the owner's queue.
    final requestId = o.materialRequestId;
    if (requestId != null &&
        !_orders.any(
          (x) =>
              x.materialRequestId == requestId &&
              x.status != PurchaseOrderStatus.cancelled,
        )) {
      final ri = _requestIndex(requestId);
      _requests[ri] = _requests[ri].copyWith(
        status: MaterialRequestStatus.pending,
      );
    }
    await _auditLog.record(
      userId: userId,
      action: 'purchase_order_cancelled',
      entity: 'purchase_order',
      entityId: id,
    );
    return updated;
  }

  // ---- Deliveries

  @override
  Future<Delivery> confirmDelivery(
    int purchaseOrderId,
    List<({int poItemId, double received, double damaged})> lines, {
    required int userId,
    String? receiptPhotoUrl,
    Uint8List? receiptPhotoBytes,
  }) async {
    final oi = _orderIndex(purchaseOrderId);
    final order = _orders[oi];
    if (!order.status.awaitsDelivery) {
      throw BusinessRuleException(
        'This PO is ${order.status.label.toLowerCase()}; there is nothing to '
        'receive.',
      );
    }
    if (!await _projects.isAssigned(
      order.projectId,
      userId,
      AppRole.siteEngineer,
    )) {
      throw const BusinessRuleException(
        'Only the site engineer on this project confirms its deliveries.',
      );
    }
    final detail = (await getPurchaseOrder(purchaseOrderId))!;
    final items = {for (final i in detail.items) i.id: i};
    if (!lines.any((l) => l.received > 0)) {
      throw const BusinessRuleException('Enter the quantity received.');
    }
    for (final l in lines) {
      final item = items[l.poItemId];
      if (item == null) {
        throw const BusinessRuleException('Unknown PO line.');
      }
      ProcurementRules.enforce(
        ProcurementRules.validateReceipt(
          ordered: item.quantity,
          alreadyReceived: detail.receivedFor(item.id),
          received: l.received,
          damaged: l.damaged,
        ),
      );
    }
    final now = _clock();
    final delivery = Delivery(
      id: _next(_deliveries.map((d) => d.id)),
      purchaseOrderId: purchaseOrderId,
      receivedBy: userId,
      receivedAt: now,
      receiptPhotoUrl: receiptPhotoUrl,
      createdAt: now,
    );
    _deliveries.add(delivery);
    for (final l in lines.where((l) => l.received > 0)) {
      _deliveryItems.add(
        DeliveryItem(
          id: _next(_deliveryItems.map((d) => d.id)),
          deliveryId: delivery.id,
          purchaseOrderItemId: l.poItemId,
          qtyReceived: l.received,
          qtyDamaged: l.damaged,
        ),
      );
    }
    final after = (await getPurchaseOrder(purchaseOrderId))!;
    final complete = after.items.every(
      (i) => after.receivedFor(i.id) >= i.quantity,
    );
    _orders[oi] = order.copyWith(
      status: complete
          ? PurchaseOrderStatus.delivered
          : PurchaseOrderStatus.partiallyDelivered,
    );
    await _auditLog.record(
      userId: userId,
      action: 'delivery_confirmed',
      entity: 'purchase_order',
      entityId: purchaseOrderId,
      details: {'delivery_id': delivery.id},
    );
    final damaged = lines.any((l) => l.damaged > 0);
    final message =
        'Delivery received for ${order.poNo}'
        '${damaged ? ' with damaged items' : ''}.';
    await _notifications?.notifyProjectRole(
      order.projectId,
      AppRole.owner,
      type: 'delivery',
      message: message,
      link: AppRoutes.purchaseOrder(purchaseOrderId),
    );
    await _notifyRole(
      AppRole.accountant,
      'delivery',
      message,
      AppRoutes.purchaseOrder(purchaseOrderId),
    );
    return delivery;
  }

  @override
  Future<List<({DeliveryDetail delivery, PurchaseOrder order})>> getDeliveries({
    List<int>? projectIds,
  }) async =>
      [
        for (final d in _deliveries)
          if (projectIds == null ||
              projectIds.contains(_orderById(d.purchaseOrderId).projectId))
            (
              delivery: DeliveryDetail(
                d,
                _deliveryItems.where((x) => x.deliveryId == d.id).toList(),
              ),
              order: _orderById(d.purchaseOrderId),
            ),
      ]..sort(
        (a, b) => b.delivery.delivery.receivedAt.compareTo(
          a.delivery.delivery.receivedAt,
        ),
      );

  // ---- Inventory, payables, costs

  @override
  Future<List<InventoryLine>> getSiteInventory(int projectId) async {
    final orderIds = {
      for (final o in _orders)
        if (o.projectId == projectId) o.id,
    };
    final items = _orderItems
        .where((i) => orderIds.contains(i.purchaseOrderId))
        .toList();
    final deliveryIds = {
      for (final d in _deliveries)
        if (orderIds.contains(d.purchaseOrderId)) d.id,
    };
    return computeSiteInventory(
      orderItems: items,
      deliveryItems: _deliveryItems
          .where((d) => deliveryIds.contains(d.deliveryId))
          .toList(),
      usage: await _reports.getApprovedMaterialUsage(projectId),
      materials: {for (final m in await _masterData.getMaterials()) m.id: m},
    );
  }

  double _deliveredValue(int orderId) {
    final prices = {
      for (final i in _orderItems)
        if (i.purchaseOrderId == orderId) i.id: i.unitPrice,
    };
    final deliveryIds = {
      for (final d in _deliveries)
        if (d.purchaseOrderId == orderId) d.id,
    };
    return _deliveryItems
        .where((d) => deliveryIds.contains(d.deliveryId))
        .fold(
          0.0,
          (s, d) => s + d.qtyGood * (prices[d.purchaseOrderItemId] ?? 0),
        );
  }

  @override
  Future<List<Payable>> getPayables({List<int>? projectIds}) async => [
    for (final o in _orders)
      if (o.status != PurchaseOrderStatus.cancelled &&
          !o.paidOnPurchase &&
          (projectIds == null || projectIds.contains(o.projectId)))
        Payable(
          order: o,
          deliveredValue: _deliveredValue(o.id),
          paid: _payments
              .where((p) => p.purchaseOrderId == o.id)
              .fold(0.0, (s, p) => s + p.amount),
        ),
  ];

  @override
  Future<SupplierPayment> recordPayment(
    int purchaseOrderId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async {
    final payable = (await getPayables()).firstWhere(
      (p) => p.order.id == purchaseOrderId,
      orElse: () => throw const BusinessRuleException('PO not found.'),
    );
    ProcurementRules.enforce(
      ProcurementRules.validatePayment(amount, payable.balance),
    );
    final payment = SupplierPayment(
      id: _next(_payments.map((p) => p.id)),
      purchaseOrderId: purchaseOrderId,
      amount: amount,
      paidOn: paidOn,
      method: method,
      referenceNo: referenceNo,
      createdAt: _clock(),
    );
    _payments.add(payment);
    await _auditLog.record(
      userId: userId,
      action: 'supplier_payment_recorded',
      entity: 'purchase_order',
      entityId: purchaseOrderId,
      details: {'amount': amount},
    );
    return payment;
  }

  @override
  Future<Map<int, double>> deliveredValueByCategory(int projectId) async {
    final orderCategory = {
      for (final o in _orders)
        if (o.projectId == projectId && o.categoryId != null)
          o.id: o.categoryId!,
    };
    final orderItemCategory = {
      for (final o in _orderItems)
        if (orderCategory.containsKey(o.purchaseOrderId))
          o.id: (orderCategory[o.purchaseOrderId]!, o.unitPrice),
    };
    final result = <int, double>{};
    for (final d in _deliveryItems) {
      final entry = orderItemCategory[d.purchaseOrderItemId];
      if (entry == null) continue;
      result[entry.$1] = (result[entry.$1] ?? 0) + d.qtyGood * entry.$2;
    }
    return result;
  }

  // ---- Helpers

  Future<void> _requirePm(int projectId, int userId) async {
    if (!await _projects.isAssigned(projectId, userId, AppRole.owner)) {
      throw const BusinessRuleException(
        'Only the owner running this project can approve this.',
      );
    }
  }

  Future<void> _notifyRole(
    AppRole role,
    String type,
    String message,
    String link,
  ) async {
    final users = await _users.getUsersWithRole(role);
    await _notifications?.notify(
      users.map((u) => u.id),
      type: type,
      message: message,
      link: link,
    );
  }

  Future<void> _notifyDelivery(PurchaseOrder order) =>
      _notifications?.notifyProjectRole(
        order.projectId,
        AppRole.siteEngineer,
        type: 'purchase_order',
        message: order.paidOnPurchase
            ? '${order.poNo} was bought at ${order.storeName}. Confirm the '
                  'delivery on arrival.'
            : '${order.poNo} is released to the own store. Confirm the '
                  'delivery on arrival.',
        link: AppRoutes.deliveryConfirm(order.id),
      ) ??
      Future.value();

  PurchaseOrder _orderById(int id) => _orders.firstWhere((o) => o.id == id);

  int _requestIndex(int id) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i < 0) throw const BusinessRuleException('Request not found.');
    return i;
  }

  int _orderIndex(int id) {
    final i = _orders.indexWhere((o) => o.id == id);
    if (i < 0) throw const BusinessRuleException('Purchase order not found.');
    return i;
  }
}
