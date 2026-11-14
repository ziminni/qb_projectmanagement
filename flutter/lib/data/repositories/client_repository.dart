import '../models/client.dart';

abstract interface class ClientRepository {
  Future<List<Client>> getClients();

  Future<Client?> getClient(int id);

  /// The client record a portal user is linked to, if any.
  Future<Client?> getClientForUser(int userId);

  /// Creates the client when its id is 0. A portal user can be linked to at
  /// most one client.
  Future<Client> saveClient(Client client);

  /// Links [userId] to [clientId], or unlinks the user when [clientId] is null.
  Future<void> linkUser(int userId, int? clientId);

  /// Whether this backend can link a portal login to a client record at all.
  /// The server exposes `clients/` read-only in Phase 2, so a screen must not
  /// half-save a user and then fail on the link.
  bool get canLinkUsers;
}
