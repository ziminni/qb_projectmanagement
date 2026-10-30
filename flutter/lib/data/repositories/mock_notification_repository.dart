import '../models/app_notification.dart';
import 'notification_repository.dart';

class MockNotificationRepository implements NotificationRepository {
  final _items = <AppNotification>[
    AppNotification(
      id: 1,
      userId: 1,
      type: 'pcab_expiry',
      message: 'The PCAB license expires on Dec 15, 2026. Start the renewal.',
      link: '/admin/company',
      createdAt: DateTime(2026, 10, 16, 8),
    ),
    AppNotification(
      id: 2,
      userId: 3,
      type: 'pcab_expiry',
      message: 'The PCAB license expires on Dec 15, 2026. Start the renewal.',
      createdAt: DateTime(2026, 10, 16, 8),
    ),
    AppNotification(
      id: 3,
      userId: 3,
      type: 'todo_done',
      message:
          'Ana Bautista marked "Second-floor column rebar" done on '
          'QB-2026-014. Verify it.',
      link: '/todo-verification',
      createdAt: DateTime(2026, 10, 15, 17),
    ),
  ];

  @override
  Future<List<AppNotification>> getFor(int userId) async =>
      _items.where((n) => n.userId == userId).toList()..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );

  @override
  Future<AppNotification> create({
    required int userId,
    required String type,
    required String message,
    String? link,
  }) async {
    final n = AppNotification(
      id: _items.fold(0, (m, n) => n.id > m ? n.id : m) + 1,
      userId: userId,
      type: type,
      message: message,
      link: link,
      createdAt: DateTime.now(),
    );
    _items.add(n);
    return n;
  }

  @override
  Future<void> markRead(int id) async {
    final i = _items.indexWhere((n) => n.id == id);
    if (i >= 0) _items[i] = _items[i].copyWith(isRead: true);
  }

  @override
  Future<void> markAllRead(int userId) async {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].userId == userId) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
    }
  }
}
