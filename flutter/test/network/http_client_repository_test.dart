import 'package:buildpro_frontend/data/models/client.dart';
import 'package:buildpro_frontend/data/repositories/http_client_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// A client row as the server sends it (`clients/`, read-only in 2.1).
Map<String, dynamic> clientRow({
  int id = 1,
  String name = 'San Miguel Foods',
  int? userId,
}) => {
  'id': id,
  'name': name,
  'contact_person': 'Rosa Lim',
  'email': 'rosa@example.ph',
  'phone': '+63 917 000 0000',
  'address': 'Lipa City',
  'user_id': userId,
  'created_at': '2026-07-01T02:00:00Z',
  'updated_at': '2026-07-01T02:00:00Z',
};

void main() {
  group('http client repository', () {
    test('reads the client records from the server', () async {
      final api = FakeApi(
        (options) => json([
          clientRow(id: 1, userId: 9),
          clientRow(id: 2, name: 'Batangas Agri Co.'),
        ]),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final clients = await repo.getClients();

      expect(api.last('clients/').method, 'GET');
      expect(clients.map((c) => c.name), [
        'San Miguel Foods',
        'Batangas Agri Co.',
      ]);
      expect(clients.first.userId, 9);
      expect(clients.first.contactPerson, 'Rosa Lim');
    });

    test('reads one client', () async {
      final api = FakeApi((options) => json(clientRow(id: 3)));
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final client = await repo.getClient(3);

      expect(api.last('clients/3/').method, 'GET');
      expect(client!.name, 'San Miguel Foods');
      expect(client.userId, isNull);
    });

    test('returns null for a client outside the caller scope', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.getClient(99), isNull);
    });

    test('finds the client record linked to a portal login', () async {
      final api = FakeApi(
        (options) => json([
          clientRow(id: 1),
          clientRow(id: 2, name: 'Batangas Agri Co.', userId: 12),
        ]),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final client = await repo.getClientForUser(12);

      // Derived from `clients/`: the server has no per-user client route.
      expect(api.paths, ['clients/']);
      expect(client!.id, 2);
      expect(await repo.getClientForUser(404), isNull);
    });

    test('can link a portal login (5.3 writes the route)', () {
      final repo = HttpClientRepository(
        testClient(api: FakeApi((o) => json(clientRow())), tokens: InMemoryTokenStore()),
      );

      expect(repo.canLinkUsers, isTrue);
    });

    test('creates a client and keeps the server id', () async {
      final api = FakeApi(
        (options) => json(clientRow(id: 7, name: 'New Client'), status: 201),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveClient(
        const Client(
          id: 0,
          name: '  New Client  ',
          contactPerson: ' Rosa Lim ',
          userId: 9,
        ),
      );

      expect(api.last('clients/').method, 'POST');
      final body = sentBody(api.last('clients/'));
      expect(body, {
        'name': 'New Client',
        'contact_person': 'Rosa Lim',
        'email': '',
        'phone': '',
        'address': '',
      });
      // The login is linked by its own route, never by create/update.
      expect(body.containsKey('user_id'), isFalse);
      expect(saved.id, 7);
    });

    test('updates an existing client by id', () async {
      final api = FakeApi((options) => json(clientRow(id: 4)));
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveClient(
        const Client(id: 4, name: 'San Miguel Foods', email: 'ap@example.ph'),
      );

      expect(api.last('clients/4/').method, 'PATCH');
      expect(sentBody(api.last('clients/4/'))['email'], 'ap@example.ph');
      expect(saved.id, 4);
    });

    test('a server refusal reaches the caller', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'A client with this name already exists.',
        }, status: 400),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.saveClient(const Client(id: 0, name: 'San Miguel Foods')),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'A client with this name already exists.',
          ),
        ),
      );
    });

    test('links a portal login to the chosen client', () async {
      final api = FakeApi((options) => json(clientRow(id: 4, userId: 9)));
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.linkUser(9, 4);

      expect(api.paths, ['clients/4/link-user/']);
      expect(sentBody(api.last('clients/4/link-user/')), {'user_id': 9});
    });

    test('unlinks the login from whichever client holds it', () async {
      final api = FakeApi(
        (options) => options.method == 'POST'
            ? json(clientRow(id: 4, userId: null))
            : json([clientRow(id: 4, userId: 9)]),
      );
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.linkUser(9, null);

      expect(api.paths, ['clients/', 'clients/4/unlink-user/']);
      expect(api.last('clients/4/unlink-user/').method, 'POST');
    });

    test('unlinking an unlinked login writes nothing', () async {
      final api = FakeApi((options) => json([clientRow(id: 4)]));
      final repo = HttpClientRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.linkUser(9, null);

      expect(api.paths, ['clients/']);
    });
  });
}
