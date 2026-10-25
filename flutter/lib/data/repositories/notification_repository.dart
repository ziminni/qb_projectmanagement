import '../models/app_notification.dart';

abstract interface class NotificationRepository {
  /// Newest first.
  Future<List<AppNotification>> getFor(int userId);

  Future<AppNotification> create({
    required int userId,
    required String type,
    required String message,
    String? link,
  });

  Future<void> markRead(int id);

  Future<void> markAllRead(int userId);
}
