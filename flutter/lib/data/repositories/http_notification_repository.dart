import '../../core/network/api_client.dart';
import '../models/app_notification.dart';
import 'notification_repository.dart';

/// The server creates notifications (contract: notifications are created by
/// the server), so [create] never POSTs one.
class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this._client);

  final ApiClient _client;

  /// Reads only the caller's own rows; the server scopes them to the access
  /// token, so [userId] is not sent.
  @override
  Future<List<AppNotification>> getFor(int userId) async => [
    for (final row in await _client.getRows('notifications/'))
      AppNotification.fromJson(row),
  ];

  /// Deliberately no request: a client-made notification would let anyone
  /// write to another user's inbox. Returns the unsaved row so a caller
  /// awaiting one keeps working.
  @override
  Future<AppNotification> create({
    required int userId,
    required String type,
    required String message,
    String? link,
  }) async => AppNotification(
    id: 0,
    userId: userId,
    type: type,
    message: message,
    link: link,
    createdAt: DateTime.now(),
  );

  @override
  Future<void> markRead(int id) async {
    await _client.post('notifications/$id/read/');
  }

  @override
  Future<void> markAllRead(int userId) async {
    await _client.post('notifications/read-all/');
  }
}
