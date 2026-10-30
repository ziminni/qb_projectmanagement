import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/category.dart';
import '../models/delivery.dart';
import '../models/delivery_item.dart';
import '../models/material_request.dart';
import '../models/material_request_item.dart';
import '../models/material_source.dart';
import '../models/payment_method.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
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

  final _requests = [...MockProcurementData.requests];
  final _requestItems = [...MockProcurementData.requestItems];
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
    );
  }

  Future<Map<int, double>> _defaultCosts() async => {
    for (final m in await _masterData.getMaterials()) m.id: m.defaultUnitCost,
  };

  /// Approved and ordered material cost for [categoryId]: PO prices where
  /// ordered, default unit costs otherwise.
  Future<double> _committed(int categoryId, {int? excludingRequestId}) async {
    final costs = await _defaultCosts();
    var total = 0.0;
    for (final r in _requests) {
      if (r.categoryId != categoryId || r.id == excludingRequestId) continue;
      if (r.status != MaterialRequestStatus.approved &&
          r.status != MaterialRequestStatus.ordered) {
        continue;
      }
      for (final item in _requestItems.where(
        (x) => x.materialRequestId == r.id,
      )) {
        final ordered = _orderItems.where(
          (o) =>
              o.materialRequestItemId == item.id &&
              _orderById(o.purchaseOrderId).status !=
                  PurchaseOrderStatus.cancelled,
        );
        total += ordered.isNotEmpty
            ? ordered.fold(0.0, (s, o) => s + o.amount)
            : item.quantity * (costs[item.materialId] ?? 0);
      }
    }
    return total;
  }

  @override
  Future<BudgetCheck> checkBudget(
    int categoryId,
    List<({int materialId, double quantity})> items, {
    int? excludingRequestId,
  }) async {
    final costs = await _defaultCosts();
    final category = await _categoryById(categoryId);
    return BudgetCheck(
      budget: category != null && category.hasBudget ? category.budget : null,
      committed: await _committed(
        categoryId,
        excludingRequestId: excludingRequestId,
      ),
      requestCost: items.fold(
        0.0,
        (s, i) => s + i.quantity * (costs[i.materialId] ?? 0),
      ),
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
    final categories = await _schedule.getCategories(draft.projectId);
    if (!categories.any((c) => c.id == draft.categoryId)) {
      throw const BusinessRuleException('Choose a category of this project.');
    }
    ProcurementRules.enforce(
      ProcurementRules.validateNeededBy(draft.neededBy, _clock()),
    );
    if (draft.items.isEmpty) {
      throw const BusinessRuleException('Add at least one item.');
    }
    for (final i in draft.items) {
      ProcurementRules.enforce(ProcurementRules.validateQuantity(i.quantity));
    }
    final now = _clock();
    final request = MaterialRequest(
      id: _next(_requests.map((r) => r.id)),
      projectId: draft.projectId,
      categoryId: draft.categoryId,
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
          materialId: i.materialId,
          quantity: i.quantity,
        ),
      );
    }
    await _notifications?.notifyProjectRole(
      draft.projectId,
      AppRole.owner,
      type: 'material_request',
      message: '${request.number} for ${project.code} needs your approval.',
      link: AppRoutes.materialRequest(request.id),
    );
    return request;
  }

  @override
  Future<MaterialRequest> approveRequest(
    int id, {
    required int userId,
    required AppRole role,
  }) async {
    final i = _requestIndex(id);
    final r = _requests[i];
    if (r.status != MaterialRequestStatus.pending || role != AppRole.owner) {
      throw BusinessRuleException(
        'This request is ${r.status.label.toLowerCase()} and cannot be '
        'approved by a ${role.label.toLowerCase()}.',
      );
    }
    await _requirePm(r.projectId, userId);
    final updated = r.copyWith(
      status: MaterialRequestStatus.approved,
      approvedBy: () => userId,
      updatedAt: _clock(),
    );
    _requests[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'material_request_approved',
      entity: 'material_request',
      entityId: id,
    );
    await _notifications?.notify(
      [r.requestedBy],
      type: 'material_request',
      message: 'Your ${r.number} was approved.',
      link: AppRoutes.materialRequest(id),
    );
    return updated;
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

  // ---- Purchase orders

  @override
  Future<List<PurchaseOrder>> createPurchaseOrders(
    int requestId,
    List<OrderLine> lines, {
    required int userId,
  }) async {
    final ri = _requestIndex(requestId);
    final request = _requests[ri];
    if (request.status != MaterialRequestStatus.approved) {
      throw const BusinessRuleException(
        'Only approved requests can be turned into purchase orders.',
      );
    }
    await _requirePm(request.projectId, userId);
    final suppliers = {
      for (final s in await _masterData.getSuppliers()) s.id: s,
    };
    final openItems = {
      for (final x in _requestItems)
        if (x.materialRequestId == requestId &&
            x.status == MaterialRequestItemStatus.pending)
          x.id: x,
    };
    if (lines.isEmpty) {
      throw const BusinessRuleException('Choose at least one item to order.');
    }
    for (final l in lines) {
      final item = openItems[l.requestItemId];
      if (item == null) {
        throw const BusinessRuleException('An item is already ordered.');
      }
      final supplier = suppliers[l.supplierId];
      if (supplier == null) {
        throw const BusinessRuleException('Choose a supplier for every item.');
      }
      if (supplier.isOwnStore != (l.source == MaterialSource.ownStore)) {
        throw BusinessRuleException(
          l.source == MaterialSource.ownStore
              ? 'Own-store items must be ordered from the own store.'
              : '${supplier.name} is the own store; tag the item Own store.',
        );
      }
      ProcurementRules.enforce(ProcurementRules.validateUnitPrice(l.unitPrice));
    }

    final now = _clock();
    final created = <PurchaseOrder>[];
    final bySupplier = <int, List<OrderLine>>{};
    for (final l in lines) {
      bySupplier.putIfAbsent(l.supplierId, () => []).add(l);
    }
    for (final entry in bySupplier.entries) {
      final id = _next(_orders.map((o) => o.id));
      final total = entry.value.fold(
        0.0,
        (s, l) => s + openItems[l.requestItemId]!.quantity * l.unitPrice,
      );
      final order = PurchaseOrder(
        id: id,
        poNo: 'PO-${now.year}-${id.toString().padLeft(4, '0')}',
        projectId: request.projectId,
        supplierId: entry.key,
        source: entry.value.first.source,
        status: PurchaseOrderStatus.released,
        totalAmount: total,
        approvedBy: userId,
        createdAt: now,
        updatedAt: now,
      );
      _orders.add(order);
      for (final l in entry.value) {
        final item = openItems[l.requestItemId]!;
        _orderItems.add(
          PurchaseOrderItem(
            id: _next(_orderItems.map((o) => o.id)),
            purchaseOrderId: id,
            materialRequestItemId: item.id,
            materialId: item.materialId,
            quantity: item.quantity,
            unitPrice: l.unitPrice,
          ),
        );
        final ii = _requestItems.indexWhere((x) => x.id == item.id);
        _requestItems[ii] = item.copyWith(
          source: l.source,
          status: MaterialRequestItemStatus.ordered,
        );
      }
      created.add(order);
      await _auditLog.record(
        userId: userId,
        action: 'purchase_order_created',
        entity: 'purchase_order',
        entityId: id,
        details: {'request_id': requestId, 'total': total},
      );
      await _notifyDelivery(order);
    }
    if (!_requestItems.any(
      (x) =>
          x.materialRequestId == requestId &&
          x.status == MaterialRequestItemStatus.pending,
    )) {
      _requests[ri] = request.copyWith(
        status: MaterialRequestStatus.ordered,
        updatedAt: now,
      );
    }
    return created;
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
    final requestItemIds = items.map((o) => o.materialRequestItemId).toSet();
    final requestId = _requestItems
        .where((x) => requestItemIds.contains(x.id))
        .map((x) => x.materialRequestId)
        .firstOrNull;
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
      requestId: requestId,
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
    final updated = o.copyWith(status: PurchaseOrderStatus.cancelled);
    _orders[i] = updated;
    // Free the request items so purchasing can reorder them.
    for (final oi in _orderItems.where((x) => x.purchaseOrderId == id)) {
      final ii = _requestItems.indexWhere(
        (x) => x.id == oi.materialRequestItemId,
      );
      final item = _requestItems[ii];
      _requestItems[ii] = item.copyWith(
        status: MaterialRequestItemStatus.pending,
      );
      final ri = _requestIndex(item.materialRequestId);
      if (_requests[ri].status == MaterialRequestStatus.ordered) {
        _requests[ri] = _requests[ri].copyWith(
          status: MaterialRequestStatus.approved,
        );
      }
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
    final requestCategory = {
      for (final r in _requests)
        if (r.projectId == projectId) r.id: r.categoryId,
    };
    final itemCategory = {
      for (final x in _requestItems)
        if (requestCategory.containsKey(x.materialRequestId))
          x.id: requestCategory[x.materialRequestId]!,
    };
    final orderItemCategory = {
      for (final o in _orderItems)
        if (itemCategory.containsKey(o.materialRequestItemId))
          o.id: (itemCategory[o.materialRequestItemId]!, o.unitPrice),
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
        message: '${order.poNo} is released. Confirm the delivery on arrival.',
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
