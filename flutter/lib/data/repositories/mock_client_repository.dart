import '../models/client.dart';
import '../services/business_rule_exception.dart';
import '../services/master_data_rules.dart';
import 'client_repository.dart';
import 'mock_company_data.dart';

class MockClientRepository implements ClientRepository {
  final _clients = [...MockCompanyData.clients];

  @override
  Future<List<Client>> getClients() async =>
      [..._clients]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Client?> getClient(int id) async {
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Client?> getClientForUser(int userId) async {
    for (final c in _clients) {
      if (c.userId == userId) return c;
    }
    return null;
  }

  @override
  Future<Client> saveClient(Client client) async {
    MasterDataRules.enforce(
      MasterDataRules.required(client.name, 'client name'),
    );
    MasterDataRules.enforce(
      MasterDataRules.validateOptionalEmail(client.email),
    );
    final saved = client.copyWith(
      id: client.id == 0
          ? _clients.fold(0, (m, c) => c.id > m ? c.id : m) + 1
          : null,
      name: client.name.trim(),
      updatedAt: DateTime.now(),
    );
    final i = _clients.indexWhere((c) => c.id == saved.id);
    if (i < 0) {
      _clients.add(saved);
    } else {
      _clients[i] = saved;
    }
    return saved;
  }

  @override
  Future<void> linkUser(int userId, int? clientId) async {
    if (clientId != null &&
        _clients.any(
          (c) => c.userId != null && c.userId != userId && c.id == clientId,
        )) {
      throw const BusinessRuleException(
        'That client already has a portal login linked.',
      );
    }
    for (var i = 0; i < _clients.length; i++) {
      final c = _clients[i];
      if (c.userId == userId && c.id != clientId) {
        _clients[i] = c.copyWith(userId: () => null);
      } else if (c.id == clientId) {
        _clients[i] = c.copyWith(userId: () => userId);
      }
    }
  }
}
