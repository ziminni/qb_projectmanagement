import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/models/material_source.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/pdf/pdf_report.dart';
import 'procurement_lookups.dart';

class PurchaseOrderDetailViewModel extends ChangeNotifier with ActionRunner {
  PurchaseOrderDetailViewModel({
    required this.orderId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int orderId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  PurchaseOrderDetail? _detail;
  MaterialRequestDetail? _request;

  bool get isLoading => _loading;
  String? get error => _error;
  PurchaseOrderDetail? get detail => _detail;
  PurchaseOrder? get order => _detail?.order;
  AppRole get role => _session.activeRole!;

  double get paid =>
      _detail?.payments.fold<double>(0, (s, p) => s + p.amount) ?? 0;

  /// Whether supplier payments exist here at all; the API blocks them, so a
  /// paid amount would be a fabricated zero.
  bool get supportsPayments => _procurement.supportsPayments;

  PosStatus? _posStatus;
  PosStatus? get posStatus => _posStatus;
  bool posBusy = false;
  bool posQueued = false;
  String? posError;

  bool get supportsPosStatus =>
      _procurement.supportsPosStatus &&
      order?.source == MaterialSource.ownStore &&
      _error == null;

  bool get canRetryStoreSync =>
      supportsPosStatus &&
      role == AppRole.owner &&
      (order?.status != PurchaseOrderStatus.cancelled ||
          (_posStatus?.closeNeedsReview ?? false));

  Future<void> refreshPosStatus() => _readPosStatus(queue: false);
  Future<void> retryStoreSync() => _readPosStatus(queue: true);

  Future<void> _readPosStatus({required bool queue}) async {
    if (!supportsPosStatus ||
        posBusy ||
        isBusy ||
        (queue && !canRetryStoreSync)) {
      return;
    }
    posBusy = true;
    posError = null;
    posQueued = false;
    notifyListeners();
    try {
      _posStatus = queue
          ? await _procurement.retryPosSync(orderId)
          : await _procurement.getPosStatus(orderId);
      posQueued = queue;
    } on BusinessRuleException catch (e) {
      posError = e.message;
    } catch (_) {
      posError = 'Could not load store sync status. Try again.';
    } finally {
      posBusy = false;
      notifyListeners();
    }
  }

  bool get canCancel =>
      role == AppRole.owner &&
      _detail != null &&
      _detail!.deliveries.isEmpty &&
      !order!.paidOnPurchase &&
      order!.status != PurchaseOrderStatus.cancelled;

  bool get canReceive =>
      role == AppRole.siteEngineer && (order?.status.awaitsDelivery ?? false);

  Future<void> load() async {
    _error = null;
    try {
      await lookups.load(_session.user!.id, role);
      _detail = await _procurement.getPurchaseOrder(orderId);
      final requestId = _detail?.requestId;
      if (requestId != null) {
        _request = await _procurement.getRequest(requestId);
      }
      if (_detail == null) {
        _error = 'Purchase order not found.';
      } else if (!lookups.projects.containsKey(_detail!.order.projectId)) {
        _error = 'You cannot see this purchase order.';
      }
    } catch (e) {
      _error = 'Could not load the purchase order. $e';
    } finally {
      _loading = false;
      notifyListeners();
      if (supportsPosStatus) await refreshPosStatus();
    }
  }

  Future<String?> cancel() async {
    if (isBusy || posBusy) return null;
    final error = await runAction(() async {
      await _procurement.cancelPurchaseOrder(
        orderId,
        userId: _session.user!.id,
      );
      _detail = await _procurement.getPurchaseOrder(orderId);
    });
    if (error == null) await refreshPosStatus();
    return error;
  }

  /// The order slip: what the site asked for and what was ordered or
  /// bought. Prices only for roles that see finances.
  PdfReport pdfReport() {
    final d = _detail!;
    final o = d.order;
    final finance = role.seesFinance;
    String q(double v) => InputParsers.amountText(v);
    final r = _request;
    return PdfReport(
      title: o.paidOnPurchase ? 'Purchase record' : 'Material order slip',
      fileName: o.poNo,
      subtitle: '${o.poNo} · ${lookups.projectCode(o.projectId)}',
      info: [
        ('Store', lookups.storeName(o)),
        ('Source', o.source.label),
        ('Status', o.statusLabel),
        if (o.createdAt != null) ('Date', Formatters.date(o.createdAt!)),
        ('Ordered by', lookups.userName(o.approvedBy)),
        if (o.deliveryAddress != null) ('Deliver to', o.deliveryAddress!),
        if (o.orNumber != null) ('OR number', o.orNumber!),
        if (r != null) ...[
          ('Request', r.request.number),
          ('Requested by', lookups.userName(r.request.requestedBy)),
          ('Needed by', Formatters.date(r.request.neededBy)),
        ],
      ],
      tables: [
        if (r != null)
          PdfTable(
            title: 'Requested by the site engineer',
            headers: const ['Item', 'Quantity'],
            rows: [
              for (final i in r.items)
                [i.description, '${q(i.quantity)} ${i.unit}'],
            ],
            numeric: const {1},
          ),
        PdfTable(
          title: o.paidOnPurchase ? 'Bought' : 'Ordered',
          headers: [
            'Material',
            'Quantity',
            'Received',
            if (finance) ...['Unit price', 'Amount'],
          ],
          rows: [
            for (final i in d.items)
              [
                i.description,
                '${q(i.quantity)} ${i.unit}',
                q(d.receivedFor(i.id)),
                if (finance) ...[
                  Formatters.peso(i.unitPrice),
                  Formatters.peso(i.amount),
                ],
              ],
          ],
          numeric: finance ? const {1, 2, 3, 4} : const {1, 2},
          totals: finance
              ? ['Total', '', '', '', Formatters.peso(o.totalAmount)]
              : null,
        ),
      ],
      signatures: o.paidOnPurchase
          ? const ['Bought by (owner)', 'Received on site by']
          : const [
              'Ordered by (owner)',
              'Released by (store)',
              'Received on site by',
            ],
    );
  }
}
