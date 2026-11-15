import '../../core/network/api_client.dart';
import '../models/client.dart';
import 'client_repository.dart';

/// Client records on the CPMS backend.
///
/// `clients/` reads are staff-only and feed the project form; create/update and
/// the portal-login link are the Admin/Owner active role's (`POST clients/`,
/// `PATCH clients/{id}/`, `POST clients/{id}/link-user/|unlink-user/`). The
/// server owns ids, so a saved client carries the real `clients.id` the project
/// form then stores in `Project.clientId`.
class HttpClientRepository implements ClientRepository {
  HttpClientRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Client>> getClients() async => [
    for (final row in await _client.getRows('clients/')) Client.fromJson(row),
  ];

  @override
  Future<Client?> getClient(int id) async {
    final data = await _client.get('clients/$id/', notFoundAsNull: true);
    return data == null ? null : Client.fromJson(jsonObject(data));
  }

  /// The linked record is found in `clients/`: the contract has no per-user
  /// client route, and it does send `user_id` on every row.
  @override
  Future<Client?> getClientForUser(int userId) async {
    for (final client in await getClients()) {
      if (client.userId == userId) return client;
    }
    return null;
  }

  /// Id 0 creates; any other id updates. Only the editable columns are sent —
  /// the login is linked by its own route and the ids/timestamps are the
  /// server's.
  @override
  Future<Client> saveClient(Client client) async {
    final body = <String, dynamic>{
      'name': client.name.trim(),
      'contact_person': client.contactPerson?.trim() ?? '',
      'email': client.email?.trim() ?? '',
      'phone': client.phone?.trim() ?? '',
      'address': client.address?.trim() ?? '',
    };
    final data = client.id == 0
        ? await _client.post('clients/', body: body)
        : await _client.patch('clients/${client.id}/', body: body);
    return Client.fromJson(jsonObject(data));
  }

  /// `clientId` null unlinks: the route is per client, so the record holding
  /// this login is looked up first. A login already unlinked writes nothing.
  @override
  Future<void> linkUser(int userId, int? clientId) async {
    if (clientId != null) {
      await _client.post(
        'clients/$clientId/link-user/',
        body: {'user_id': userId},
      );
      return;
    }
    final current = await getClientForUser(userId);
    if (current == null) return;
    await _client.post('clients/${current.id}/unlink-user/');
  }
}
