import '../../core/network/api_client.dart';
import '../models/client.dart';
import '../services/business_rule_exception.dart';
import 'client_repository.dart';

/// Client records, read from the CPMS backend.
///
/// Phase 2.1 exposes `clients/` read-only (staff roles) so the project form
/// can pick `client_id`; there is no client write route yet, so the two write
/// methods refuse with a clear message instead of pretending to save.
class HttpClientRepository implements ClientRepository {
  HttpClientRepository(this._client);

  final ApiClient _client;

  static const _readOnly = BusinessRuleException(
    'Client records are read-only on the server for now.',
  );

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

  /// Phase 2.1 exposes no route that links a portal login to a `clients` row.
  @override
  bool get canLinkUsers => false;

  @override
  Future<Client> saveClient(Client client) async => throw _readOnly;

  @override
  Future<void> linkUser(int userId, int? clientId) async => throw _readOnly;
}
