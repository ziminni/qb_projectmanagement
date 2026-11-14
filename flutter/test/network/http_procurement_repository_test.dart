import 'dart:convert';
import 'dart:typed_data';

import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/material_request.dart';
import 'package:buildpro_frontend/data/models/material_source.dart';
import 'package:buildpro_frontend/data/models/payment_method.dart';
import 'package:buildpro_frontend/data/models/purchase_order.dart';
import 'package:buildpro_frontend/data/repositories/http_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

// Wire shapes from the 3.1a build: `finance: false` is what an admin or a site
// engineer receives — `total_amount`, `unit_price`, `or_number` and
// `receipt_photo_url` are omitted, never zero-filled.

Map<String, dynamic> requestRow({
  int id = 7,
  int projectId = 1,
  String status = 'pending',
}) => {
  'id': id,
  'project_id': projectId,
  'category_id': null,
  'requested_by': 4,
  'needed_by': '2026-11-05',
  'status': status,
  'approved_by': null,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> requestItemRow({int id = 11, int requestId = 7}) => {
  'id': id,
  'material_request_id': requestId,
  'description': 'Cement 40 kg',
  'unit': 'bag',
  'quantity': '80.00',
  'purchase_order_id': null,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> countRow({int id = 21, int requestId = 7}) => {
  'id': id,
  'material_request_id': requestId,
  'material_id': 1,
  'name': 'Cement 40 kg',
  'unit': 'bag',
  'expected': '70.00',
  'counted': '68.00',
};

Map<String, dynamic> orderRow({
  int id = 5,
  bool finance = true,
  String status = 'released',
  String source = 'own_store',
}) => {
  'id': id,
  'po_no': 'PO-2026-0005',
  'project_id': 1,
  'material_request_id': 4,
  'category_id': 3,
  'supplier_id': 2,
  'store_name': null,
  'source': source,
  'status': status,
  if (finance) 'total_amount': '99000.00',
  'delivery_address': 'Lipa City',
  if (finance) 'or_number': null,
  if (finance) 'receipt_photo_url': null,
  'approved_by': 3,
  'created_at': '2026-10-21T09:00:00Z',
  'updated_at': '2026-10-21T09:00:00Z',
};

Map<String, dynamic> orderItemRow({
  int id = 9,
  int orderId = 5,
  bool finance = true,
}) => {
  'id': id,
  'purchase_order_id': orderId,
  'material_id': 10,
  'description': 'Long-span roof sheet',
  'unit': 'pc',
  'quantity': '220.00',
  if (finance) 'unit_price': '450.00',
  'created_at': '2026-10-21T09:00:00Z',
  'updated_at': '2026-10-21T09:00:00Z',
};

Map<String, dynamic> deliveryRow({int id = 31, int orderId = 5}) => {
  'id': id,
  'purchase_order_id': orderId,
  'received_by': 4,
  'received_at': '2026-10-23T09:00:00Z',
  'receipt_photo_url': null,
  'created_at': '2026-10-23T09:00:00Z',
  'updated_at': '2026-10-23T09:00:00Z',
};

Map<String, dynamic> deliveryItemRow({int id = 41, int poItemId = 9}) => {
  'id': id,
  'delivery_id': 31,
  'purchase_order_item_id': poItemId,
  'qty_received': '50.00',
  'qty_damaged': '2.00',
  'created_at': '2026-10-23T09:00:00Z',
  'updated_at': '2026-10-23T09:00:00Z',
};

Map<String, dynamic> inventoryRow({int? materialId = 1}) => {
  'material_id': materialId,
  'name': materialId == null ? 'Roof screws' : 'Cement 40 kg',
  'unit': 'bag',
  'received': '120.00',
  'damaged': '2.00',
  'used': '50.00',
};

Map<String, dynamic> orderDetailRow({bool finance = true}) => {
  'order': orderRow(finance: finance),
  'items': [orderItemRow(finance: finance)],
  'deliveries': [
    {
      'delivery': deliveryRow(),
      'items': [deliveryItemRow()],
    },
  ],
  // Payables are financially blocked: the key stays an empty list.
  'payments': <Map<String, dynamic>>[],
  'request_id': 4,
};

/// The bytes a PNG starts with, so the upload name follows the content.
final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

HttpProcurementRepository repoFor(
  FakeApi api, {
  AppRole active = AppRole.owner,
}) => HttpProcurementRepository(
  testClient(
    api: api,
    tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
    session: signedInSession(active: active),
  ),
);

const requestLine = (description: 'Cement 40 kg', unit: 'bag', quantity: 80.0);

void main() {
  group('material requests', () {
    test('reads the scoped requests and filters a multi-status list', () async {
      final api = FakeApi(
        (options) =>
            json([requestRow(id: 7), requestRow(id: 8, status: 'ordered')]),
      );
      final repo = repoFor(api, active: AppRole.siteEngineer);

      final rows = await repo.getRequests(
        projectIds: [1, 2],
        statuses: [
          MaterialRequestStatus.pending,
          MaterialRequestStatus.rejected,
        ],
      );

      final request = api.last('material-requests/');
      expect(request.method, 'GET');
      expect(request.uri.queryParameters['project'], '1,2');
      // The route filters one status; a longer list is filtered here.
      expect(request.uri.queryParameters.containsKey('status'), isFalse);
      expect(rows.map((r) => r.id), [7]);
    });

    test('follows DRF pagination and sends a single status', () async {
      final nextPageUrl = '$apiBaseUrl/material-requests/?page=2';
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second ? null : nextPageUrl,
          'previous': null,
          'results': [requestRow(id: second ? 8 : 7)],
        });
      });
      final repo = repoFor(api);

      final rows = await repo.getRequests(
        statuses: [MaterialRequestStatus.pending],
      );

      expect(rows.map((r) => r.id), [7, 8]);
      expect(
        api.last('material-requests/').uri.queryParameters['status'],
        'pending',
      );
      expect(api.requests.last.uri.queryParameters['page'], '2');
    });

    test('reads one request with its items and counts', () async {
      final api = FakeApi(
        (options) => json({
          'request': requestRow(),
          'items': [requestItemRow()],
          'counts': [countRow()],
        }),
      );
      final repo = repoFor(api);

      final detail = await repo.getRequest(7);

      expect(detail!.request.number, 'MR-0007');
      expect(detail.items.single.quantity, 80);
      expect(detail.counts.single.difference, -2);
      // No actor claim travels: the server answers for the caller.
      expect(api.last('material-requests/7/').method, 'GET');
    });

    test('answers null for a request outside the caller scope', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );

      expect(await repoFor(api).getRequest(7), isNull);
    });

    test('checks a budget with a two-place amount', () async {
      final api = FakeApi(
        (options) => json({
          'budget': '500000.00',
          'committed': '120000.00',
          'request_cost': '99000.00',
        }),
      );

      final check = await repoFor(api).checkBudget(3, 99000);

      final request = api.last('categories/3/procurement-budget/');
      expect(request.uri.queryParameters['amount'], '99000.00');
      expect(check.budget, 500000);
      expect(check.remaining, 380000);
      expect(check.exceedsBudget, isFalse);
    });

    test('an unbudgeted category stays null', () async {
      final api = FakeApi(
        (options) => json({
          'budget': null,
          'committed': '0.00',
          'request_cost': '10.00',
        }),
      );

      final check = await repoFor(api).checkBudget(3, 10);

      expect(check.budget, isNull);
      expect(check.exceedsBudget, isFalse);
    });

    test('creates a request without claiming the actor', () async {
      final api = FakeApi((options) => json(requestRow(), status: 201));
      final repo = repoFor(api, active: AppRole.siteEngineer);

      final saved = await repo.createRequest(
        MaterialRequestDraft(
          projectId: 1,
          neededBy: DateTime(2026, 11, 5),
          items: const [requestLine],
          counts: const [
            (
              materialId: 1,
              name: 'Cement 40 kg',
              unit: 'bag',
              expected: 70.0,
              counted: 68.0,
            ),
          ],
        ),
        userId: 4,
      );

      final request = api.last('material-requests/');
      expect(request.method, 'POST');
      final body = sentBody(request);
      expect(body['project_id'], 1);
      expect(body['needed_by'], '2026-11-05');
      expect(body['items'], [
        {'description': 'Cement 40 kg', 'unit': 'bag', 'quantity': 80.0},
      ]);
      expect((body['counts'] as List).single, {
        'material_id': 1,
        'name': 'Cement 40 kg',
        'unit': 'bag',
        'expected': 70.0,
        'counted': 68.0,
      });
      expect(body.containsKey('user_id'), isFalse);
      expect(body.containsKey('requested_by'), isFalse);
      expect(saved.id, 7);
    });

    test('rejects with the reason only, and keeps the server text', () async {
      final api = FakeApi(
        (options) => json({
          'detail':
              'This request is ordered and cannot be rejected by a owner / '
              'project manager.',
        }, status: 400),
      );

      expect(
        repoFor(api).rejectRequest(
          7,
          userId: 3,
          role: AppRole.owner,
          reason: '  Budget is spent.  ',
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'This request is ordered and cannot be rejected by a owner / '
                'project manager.',
          ),
        ),
      );
    });

    test('a successful rejection sends the trimmed reason', () async {
      final api = FakeApi((options) => json(requestRow(status: 'rejected')));

      final rejected = await repoFor(api).rejectRequest(
        7,
        userId: 3,
        role: AppRole.owner,
        reason: '  Budget is spent.  ',
      );

      final request = api.last('material-requests/7/reject/');
      expect(request.method, 'POST');
      expect(sentBody(request), {'reason': 'Budget is spent.'});
      expect(rejected.status, MaterialRequestStatus.rejected);
    });
  });

  group('purchase orders', () {
    test('places an own-store order as JSON with no upload', () async {
      final api = FakeApi((options) => json(orderRow(), status: 201));

      final order = await repoFor(api).placeOrder(
        OrderDraft.ownStore(
          requestId: 4,
          categoryId: 3,
          lines: const [
            (
              materialId: 10,
              description: 'Long-span roof sheet',
              unit: 'pc',
              quantity: 220.0,
              unitPrice: 450.0,
            ),
          ],
          coversItemIds: const [11],
          deliveryAddress: ' Lipa City ',
        ),
        userId: 3,
      );

      final request = api.last('purchase-orders/');
      expect(request.method, 'POST');
      expect(
        request.headers[Headers.contentTypeHeader],
        Headers.jsonContentType,
      );
      final body = sentBody(request);
      expect(body['request_id'], 4);
      expect(body['category_id'], 3);
      expect(body['source'], 'own_store');
      expect(body['delivery_address'], 'Lipa City');
      expect((body['lines'] as List).single, {
        'material_id': 10,
        'description': 'Long-span roof sheet',
        'unit': 'pc',
        'quantity': 220.0,
        'unit_price': 450.0,
      });
      expect(body['covers_item_ids'], [11]);
      expect(body.containsKey('receipt_photo'), isFalse);
      expect(order.poNo, 'PO-2026-0005');
      expect(order.totalAmount, 99000);
    });

    test('uploads an other-store receipt photo as a private file', () async {
      final api = FakeApi(
        (options) => json(
          orderRow(source: 'external', status: 'purchased'),
          status: 201,
        ),
      );

      final order = await repoFor(api).placeOrder(
        OrderDraft.otherStore(
          requestId: 4,
          categoryId: 3,
          lines: const [
            (
              materialId: null,
              description: 'Roof screws',
              unit: 'pc',
              quantity: 500.0,
              unitPrice: 2.0,
            ),
          ],
          storeName: ' Ace Hardware ',
          orNumber: ' OR 7 ',
          receiptPhotoUrl: '/tmp/r.jpg',
          receiptPhotoBytes: pngBytes,
        ),
        userId: 3,
      );

      final request = api.last('purchase-orders/');
      expect(
        request.headers[Headers.contentTypeHeader],
        startsWith('multipart/form-data'),
      );
      final form = request.data as FormData;
      String field(String key) =>
          form.fields.firstWhere((f) => f.key == key).value;
      expect(field('source'), 'external');
      expect(field('store_name'), 'Ace Hardware');
      expect(field('or_number'), 'OR 7');
      expect(jsonDecode(field('lines')), [
        {
          'material_id': null,
          'description': 'Roof screws',
          'unit': 'pc',
          'quantity': 500.0,
          'unit_price': 2.0,
        },
      ]);
      // The body URL is ignored: the server stores the uploaded file only.
      expect(form.fields.any((f) => f.key == 'receipt_photo_url'), isFalse);
      expect(form.files.single.key, 'receipt_photo');
      expect(form.files.single.value.filename, 'photo.png');
      expect(form.files.single.value.length, pngBytes.length);
      expect(order.source, MaterialSource.external);
    });

    test('refuses an other-store order with no receipt bytes', () async {
      final api = FakeApi((options) => json(orderRow(), status: 201));

      expect(
        repoFor(api).placeOrder(
          OrderDraft.otherStore(
            requestId: 4,
            categoryId: 3,
            lines: const [
              (
                materialId: null,
                description: 'Roof screws',
                unit: 'pc',
                quantity: 500.0,
                unitPrice: 2.0,
              ),
            ],
            storeName: 'Ace Hardware',
            orNumber: 'OR 7',
            receiptPhotoUrl: '/tmp/r.jpg',
          ),
          userId: 3,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Attach a photo of the receipt.',
          ),
        ),
      );
      expect(api.requests, isEmpty);
    });

    test('lists orders by project and status', () async {
      final api = FakeApi(
        (options) => json([orderRow(), orderRow(id: 6, status: 'delivered')]),
      );

      final rows = await repoFor(api).getPurchaseOrders(
        projectIds: [1],
        statuses: [PurchaseOrderStatus.released],
      );

      final request = api.last('purchase-orders/');
      expect(request.uri.queryParameters['project'], '1');
      expect(request.uri.queryParameters['status'], 'released');
      expect(rows.map((o) => o.id), [5]);
    });

    test('reads one order with deliveries and no payments', () async {
      final api = FakeApi((options) => json(orderDetailRow()));

      final detail = await repoFor(api).getPurchaseOrder(5);

      expect(detail!.requestId, 4);
      expect(detail.items.single.amount, 99000);
      expect(detail.deliveries.single.items.single.qtyGood, 48);
      expect(detail.receivedFor(9), 50);
      expect(detail.payments, isEmpty);
    });

    test('answers null for an order outside the caller scope', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );

      expect(await repoFor(api).getPurchaseOrder(5), isNull);
    });

    test('cancels through its own route', () async {
      final api = FakeApi((options) => json(orderRow(status: 'cancelled')));

      final order = await repoFor(api).cancelPurchaseOrder(5, userId: 3);

      final request = api.last('purchase-orders/5/cancel/');
      expect(request.method, 'POST');
      expect(request.data, isNull);
      expect(order.status, PurchaseOrderStatus.cancelled);
    });

    test('confirms a delivery as JSON when no photo is attached', () async {
      final api = FakeApi((options) => json(deliveryRow(), status: 201));

      final delivery = await repoFor(api, active: AppRole.siteEngineer)
          .confirmDelivery(5, const [
            (poItemId: 9, received: 50.0, damaged: 2.0),
          ], userId: 4);

      final request = api.last('purchase-orders/5/deliveries/');
      expect(
        request.headers[Headers.contentTypeHeader],
        Headers.jsonContentType,
      );
      expect(sentBody(request), {
        'lines': [
          {'po_item_id': 9, 'received': 50.0, 'damaged': 2.0},
        ],
      });
      expect(delivery.receivedBy, 4);
    });

    test('uploads the delivery receipt photo as a private file', () async {
      final api = FakeApi((options) => json(deliveryRow(), status: 201));

      await repoFor(api, active: AppRole.siteEngineer).confirmDelivery(
        5,
        const [(poItemId: 9, received: 50.0, damaged: 0.0)],
        userId: 4,
        receiptPhotoBytes: pngBytes,
      );

      final form = api.last('purchase-orders/5/deliveries/').data as FormData;
      String field(String key) =>
          form.fields.firstWhere((f) => f.key == key).value;
      expect(jsonDecode(field('lines')), [
        {'po_item_id': 9, 'received': 50.0, 'damaged': 0.0},
      ]);
      expect(form.files.single.key, 'receipt_photo');
      expect(form.files.single.value.filename, 'photo.png');
    });

    test('keeps a delivery refusal text unchanged', () async {
      final api = FakeApi(
        (options) =>
            json({'detail': 'Damaged cannot exceed received.'}, status: 400),
      );

      expect(
        repoFor(api, active: AppRole.siteEngineer).confirmDelivery(5, const [
          (poItemId: 9, received: 5.0, damaged: 6.0),
        ], userId: 4),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Damaged cannot exceed received.',
          ),
        ),
      );
    });

    test('reads deliveries newest first with their order', () async {
      final api = FakeApi(
        (options) => json([
          {
            'delivery': {
              'delivery': deliveryRow(),
              'items': [deliveryItemRow()],
            },
            'order': orderRow(),
          },
        ]),
      );

      final rows = await repoFor(api).getDeliveries(projectIds: [1]);

      expect(api.last('deliveries/').uri.queryParameters['project'], '1');
      expect(rows.single.delivery.delivery.id, 31);
      expect(rows.single.delivery.items.single.qtyDamaged, 2);
      expect(rows.single.order.poNo, 'PO-2026-0005');
    });
  });

  group('site inventory', () {
    test('reads the derived stock lines', () async {
      final api = FakeApi(
        (options) => json([inventoryRow(), inventoryRow(materialId: null)]),
      );

      final lines = await repoFor(api).getSiteInventory(1);

      expect(api.last('projects/1/site-inventory/').method, 'GET');
      expect(lines.first.onHand, 68);
      expect(lines.first.key, 'm1');
      expect(lines.last.materialId, isNull);
      expect(lines.last.key, 'n:roof screws');
      expect(lines.last.onHand, 68);
    });
  });

  group('finance redaction', () {
    test('a non-finance order decodes the omitted keys as zero', () async {
      final api = FakeApi((options) => json(orderDetailRow(finance: false)));

      final detail = await repoFor(
        api,
        active: AppRole.siteEngineer,
      ).getPurchaseOrder(5);

      // Omitted, never zero-filled by the server: the screens that would show
      // these run only for finance roles (purchase_order_detail_page, the PO
      // tile, the order slip).
      expect(detail!.order.totalAmount, 0);
      expect(detail.order.orNumber, isNull);
      expect(detail.items.single.unitPrice, 0);
    });

    test('a finance order keeps the real amounts', () async {
      final api = FakeApi((options) => json(orderDetailRow()));

      final detail = await repoFor(
        api,
        active: AppRole.owner,
      ).getPurchaseOrder(5);

      expect(detail!.order.totalAmount, 99000);
      expect(detail.items.single.unitPrice, 450);
    });

    test('an external order is paid on purchase even when redacted', () {
      // `or_number` is finance-only, so it cannot carry the signal for an
      // admin or site engineer; the source is never redacted.
      final order = PurchaseOrder.fromJson(
        orderRow(finance: false, source: 'external'),
        financeKeysOmitted: true,
      );
      expect(order.orNumber, isNull);
      expect(order.paidOnPurchase, isTrue);
    });

    test('an external order with an OR number is paid at the counter', () {
      final order = PurchaseOrder.fromJson({
        ...orderRow(finance: true, source: 'external'),
        'or_number': 'OR-0012',
      });
      expect(order.paidOnPurchase, isTrue);
    });

    test('the demo answer stays: own store or no OR number is not paid', () {
      expect(PurchaseOrder.fromJson(orderRow()).paidOnPurchase, isFalse);
      expect(
        PurchaseOrder.fromJson(orderRow(source: 'external')).paidOnPurchase,
        isFalse,
      );
    });

    test('a finance answer without the money key is a parse error', () async {
      final row = orderRow()..remove('total_amount');
      final api = FakeApi(
        (options) => json({
          'order': row,
          'items': [orderItemRow()],
          'deliveries': <Map<String, dynamic>>[],
          'payments': <Map<String, dynamic>>[],
          'request_id': 4,
        }),
      );

      // A finance role is always sent the key; its absence is a broken
      // response, not a zero the UI may show as accounting truth.
      expect(
        repoFor(api, active: AppRole.accountant).getPurchaseOrder(5),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('finance-blocked methods', () {
    test('payables, payments and delivered value are not faked', () async {
      final api = FakeApi((options) => json(const <Object>[]));
      final repo = repoFor(api, active: AppRole.accountant);

      expect(
        repo.getPayables(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('POS project debt'),
          ),
        ),
      );
      expect(
        repo.recordPayment(
          5,
          amount: 1000,
          paidOn: DateTime(2026, 10, 24),
          method: PaymentMethod.cash,
          userId: 3,
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('POS debt'),
          ),
        ),
      );
      expect(
        repo.deliveredValueByCategory(1),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('per-line'),
          ),
        ),
      );
      expect(api.requests, isEmpty);
    });
  });

  group('repository switch', () {
    test('mocks stay the default until USE_API is set', () async {
      expect(useApi, isFalse);
      setupServiceLocator();
      expect(getIt<ProcurementRepository>(), isA<MockProcurementRepository>());
    });
  });
}
