import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_notification.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/session_service.dart';

class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel({
    required SessionService session,
    required NotificationRepository notifications,
    required NotificationService service,
  }) : _session = session,
       _repo = notifications,
       _service = service;

  final SessionService _session;
  final NotificationRepository _repo;
  final NotificationService _service;

  bool _loading = true;
  List<AppNotification> _items = const [];

  bool get isLoading => _loading;
  List<AppNotification> get items => _items;
  bool get hasUnread => _items.any((n) => !n.isRead);

  Future<void> load() async {
    _items = await _repo.getFor(_session.user!.id);
    _loading = false;
    notifyListeners();
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    await _service.markRead(n.id);
    await load();
  }

  Future<void> markAllRead() async {
    await _service.markAllRead(_session.user!.id);
    await load();
  }
}
