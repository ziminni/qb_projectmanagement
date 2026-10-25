import 'json_utils.dart';

/// A row in `notifications`. Named `AppNotification` to avoid clashing with
/// Flutter's `Notification` class.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    this.link,
    this.isRead = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;

  /// Event type, e.g. `todo_done`, `report_returned`, `billing_pending`.
  final String type;
  final String message;

  /// In-app route to open, if any.
  final String? link;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    type: type,
    message: message,
    link: link,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        userId: json['user_id'] as int,
        type: json['type'] as String,
        message: json['message'] as String,
        link: json['link'] as String?,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'message': message,
    'link': link,
    'is_read': isRead,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
