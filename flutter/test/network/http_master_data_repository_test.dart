import 'package:buildpro_frontend/data/models/equipment.dart';
import 'package:buildpro_frontend/data/models/material_item.dart';
import 'package:buildpro_frontend/data/models/supplier.dart';
import 'package:buildpro_frontend/data/models/trade.dart';
import 'package:buildpro_frontend/data/repositories/http_master_data_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, dynamic> materialRow(int id, {num cost = 250}) => {
  'id': id,
  'name': 'Cement $id',
  'unit': 'bag',
  'default_unit_cost': cost,
  'store_sku': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};

Map<String, dynamic> supplierRow(int id) => {
  'id': id,
  'name': 'Supplier $id',
  'contact_person': 'Ana',
  'phone': '0917',
  'address': 'Cebu',
  'is_own_store': false,
  'pos_payer_id': null,
};

Map<String, dynamic> tradeRow(int id) => {
  'id': id,
  'name': 'Trade $id',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};

Map<String, dynamic> equipmentRow(int id) => {
  'id': id,
  'name': 'Mixer $id',
  'ownership': 'owned',
  'rate': 1500,
  'rate_unit': 'day',
};

void main() {
  group('http master data repository', () {
    test('reads every page of materials from master-data', () async {
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second
              ? null
              : 'http://cpms.test/api/v1/master-data/materials/?page=2',
          'results': [if (!second) materialRow(1), if (second) materialRow(2)],
        });
      });
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final materials = await repo.getMaterials();

      expect(materials.map((m) => m.id), [1, 2]);
      expect(api.paths, [
        'master-data/materials/',
        'http://cpms.test/api/v1/master-data/materials/?page=2',
      ]);
      expect(materials.first.defaultUnitCost, 250);
    });

    test('creates a material without an id and blanks a missing SKU', () async {
      final api = FakeApi((options) => json(materialRow(9), status: 201));
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveMaterial(
        const MaterialItem(
          id: 0,
          name: 'Cement',
          unit: 'bag',
          defaultUnitCost: 250,
          storeSku: '   ',
        ),
      );

      final request = api.last('master-data/materials/');
      final sent = sentBody(request);
      expect(request.method, 'POST');
      expect(sent['name'], 'Cement');
      expect(sent['unit'], 'bag');
      expect(sent['default_unit_cost'], 250);
      expect(sent['store_sku'], isNull);
      expect(saved.id, 9);
    });

    test(
      'patches an existing material and keeps the price it was given',
      () async {
        final api = FakeApi((options) => json(materialRow(4, cost: 0)));
        final repo = HttpMasterDataRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        final saved = await repo.saveMaterial(
          const MaterialItem(
            id: 4,
            name: 'Cement',
            unit: 'bag',
            defaultUnitCost: 0,
            storeSku: 'SKU-1',
          ),
        );

        final request = api.last('master-data/materials/4/');
        expect(request.method, 'PATCH');
        // A redacted price arrives as 0; the client sends back what it has and
        // never guesses a real figure (contract: finance redaction).
        expect(sentBody(request)['default_unit_cost'], 0);
        expect(sentBody(request)['store_sku'], 'SKU-1');
        expect(saved.defaultUnitCost, 0);
      },
    );

    test('refuses a duplicate material name with the server text', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'A material with this name already exists.',
        }, status: 400),
      );
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await expectLater(
        repo.saveMaterial(
          const MaterialItem(
            id: 0,
            name: 'Cement',
            unit: 'bag',
            defaultUnitCost: 250,
          ),
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'A material with this name already exists.',
          ),
        ),
      );
    });

    test(
      'reads suppliers and creates one through the master-data path',
      () async {
        final api = FakeApi(
          (options) => options.method == 'GET'
              ? json([supplierRow(1)])
              : json(supplierRow(2), status: 201),
        );
        final repo = HttpMasterDataRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        expect((await repo.getSuppliers()).single.id, 1);

        final saved = await repo.saveSupplier(
          const Supplier(id: 0, name: 'Hardware Hub', isOwnStore: true),
        );

        final sent = sentBody(api.last('master-data/suppliers/'));
        expect(sent['name'], 'Hardware Hub');
        expect(sent['is_own_store'], isTrue);
        expect(sent['contact_person'], isNull);
        expect(saved.id, 2);
      },
    );

    test('patches an existing supplier', () async {
      final api = FakeApi((options) => json(supplierRow(5)));
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.saveSupplier(
        const Supplier(
          id: 5,
          name: 'Supplier 5',
          contactPerson: 'Ana',
          phone: '0917',
          address: 'Cebu',
        ),
      );

      final request = api.last('master-data/suppliers/5/');
      expect(request.method, 'PATCH');
      expect(sentBody(request)['contact_person'], 'Ana');
    });

    test('reads trades and saves a new one', () async {
      final api = FakeApi(
        (options) => options.method == 'GET'
            ? json([tradeRow(1), tradeRow(2)])
            : json(tradeRow(7), status: 201),
      );
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect((await repo.getTrades()).map((t) => t.name), [
        'Trade 1',
        'Trade 2',
      ]);

      final saved = await repo.saveTrade(const Trade(id: 0, name: 'Masonry'));

      expect(api.last('master-data/trades/').method, 'POST');
      expect(sentBody(api.last('master-data/trades/'))['name'], 'Masonry');
      expect(saved.id, 7);
    });

    test('deletes a trade with a DELETE on its own row', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.deleteTrade(12);

      final request = api.last('master-data/trades/12/');
      expect(request.method, 'DELETE');
    });

    test('reads equipment and saves its ownership, rate and unit', () async {
      final api = FakeApi(
        (options) => options.method == 'GET'
            ? json([equipmentRow(1)])
            : json(equipmentRow(3), status: 201),
      );
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final equipment = await repo.getEquipment();
      expect(equipment.single.ownership, EquipmentOwnership.owned);
      expect(equipment.single.rate, 1500);

      final saved = await repo.saveEquipment(
        const Equipment(
          id: 0,
          name: 'Backhoe',
          ownership: EquipmentOwnership.rented,
          rate: 2500,
          rateUnit: RateUnit.hour,
        ),
      );

      final sent = sentBody(api.last('master-data/equipment/'));
      expect(sent['name'], 'Backhoe');
      expect(sent['ownership'], 'rented');
      expect(sent['rate'], 2500);
      expect(sent['rate_unit'], 'hour');
      expect(saved.id, 3);
    });

    test('refuses a write for a role that may not write', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Project Manager or Admin role required.',
        }, status: 403),
      );
      final repo = HttpMasterDataRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await expectLater(
        repo.saveTrade(const Trade(id: 0, name: 'Masonry')),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Project Manager or Admin role required.',
          ),
        ),
      );
    });
  });
}
